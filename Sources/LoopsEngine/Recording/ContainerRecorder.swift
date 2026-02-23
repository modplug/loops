import Foundation
import AVFoundation
import LoopsCore

/// Records audio from the engine's input node into armed containers.
///
/// When the playhead enters an armed container's bar range, a new CAF file
/// is created and input audio is captured. Recording stops when the playhead
/// leaves the range or transport stops. Waveform peaks are generated
/// incrementally from captured samples.
public final class ContainerRecorder: @unchecked Sendable {
    private let engine: AVAudioEngine
    private let audioDirURL: URL
    private let lock = NSLock()

    /// Active recording session for a single container.
    private struct ActiveRecording {
        let containerID: ID<Container>
        let trackID: ID<Track>
        let writer: CAFWriter
        let filename: String
        var peaks: [Float]
        /// Accumulates raw samples between peak calculations.
        var pendingSamples: [Float]
    }

    private var activeRecording: ActiveRecording?
    private var isTapInstalled: Bool = false

    /// Armed containers to monitor, keyed by container ID.
    /// Each entry stores the track ID, start bar, and end bar.
    private struct ArmedContainer {
        let containerID: ID<Container>
        let trackID: ID<Track>
        let startBar: Int
        let endBar: Int
    }

    private var armedContainers: [ArmedContainer] = []
    private var sampleRate: Double = 44100.0
    private var inputChannelCount: UInt32 = 1
    private var samplesPerBar: Double = 0
    private var playbackStartBar: Double = 1.0

    /// Accumulated sample count since tap was installed, used to calculate
    /// current bar position from the audio thread.
    private var tapSampleCount: Int64 = 0

    /// Number of samples per waveform peak (100 peaks/sec default).
    private var samplesPerPeak: Int = 441

    /// Called on the main thread when peaks are updated during recording.
    /// Parameters: containerID, peaks array.
    public var onPeaksUpdated: ((ID<Container>, [Float]) -> Void)?

    /// Called on the main thread when recording completes for a container.
    /// Parameters: trackID, containerID, SourceRecording.
    public var onRecordingComplete: ((ID<Track>, ID<Container>, SourceRecording) -> Void)?

    public init(engine: AVAudioEngine, audioDirURL: URL) {
        self.engine = engine
        self.audioDirURL = audioDirURL
    }

    /// Starts monitoring armed containers during playback.
    /// Installs an input tap and begins tracking bar position from sample count.
    public func startMonitoring(
        armedContainers: [(containerID: ID<Container>, trackID: ID<Track>, startBar: Int, endBar: Int)],
        fromBar: Double,
        bpm: Double,
        timeSignature: TimeSignature,
        sampleRate: Double
    ) {
        lock.lock()
        self.armedContainers = armedContainers.map {
            ArmedContainer(containerID: $0.containerID, trackID: $0.trackID, startBar: $0.startBar, endBar: $0.endBar)
        }
        self.sampleRate = sampleRate
        self.playbackStartBar = fromBar
        let secondsPerBeat = 60.0 / bpm
        let beatsPerBar = Double(timeSignature.beatsPerBar)
        let secondsPerBar = beatsPerBar * secondsPerBeat
        self.samplesPerBar = secondsPerBar * sampleRate
        self.samplesPerPeak = max(1, Int(sampleRate) / WaveformGenerator.peaksPerSecond)
        self.tapSampleCount = 0
        lock.unlock()

        guard !armedContainers.isEmpty else { return }

        installTapIfNeeded()
    }

    /// Stops all recording and removes the input tap.
    public func stopMonitoring() {
        removeTap()

        lock.lock()
        let recording = activeRecording
        activeRecording = nil
        armedContainers.removeAll()
        lock.unlock()

        if let recording {
            finalizeRecording(recording)
        }
    }

    // MARK: - Private

    private func installTapIfNeeded() {
        lock.lock()
        guard !isTapInstalled else {
            lock.unlock()
            return
        }
        isTapInstalled = true
        lock.unlock()

        print("[REC] Installing tap on inputNode...")
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        print("[REC] Input format: \(format.channelCount)ch, \(format.sampleRate)Hz")

        lock.lock()
        inputChannelCount = format.channelCount
        sampleRate = format.sampleRate
        samplesPerPeak = max(1, Int(format.sampleRate) / WaveformGenerator.peaksPerSecond)
        lock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }
        print("[REC] Tap installed successfully")
    }

    private func removeTap() {
        lock.lock()
        guard isTapInstalled else {
            lock.unlock()
            return
        }
        isTapInstalled = false
        lock.unlock()

        engine.inputNode.removeTap(onBus: 0)
    }

    private var bufferCount: Int = 0

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        lock.lock()
        bufferCount += 1
        let bc = bufferCount
        let armed = armedContainers
        let spb = samplesPerBar
        let startBar = playbackStartBar
        let sr = sampleRate
        let currentTapSamples = tapSampleCount

        // Calculate current bar from accumulated samples
        let currentBar: Double
        if spb > 0 {
            currentBar = startBar + Double(currentTapSamples) / spb
        } else {
            currentBar = startBar
        }

        tapSampleCount += Int64(frameCount)

        if bc == 1 {
            print("[REC] First buffer: bar=\(String(format: "%.2f", currentBar)) armed=\(armed.count) spb=\(spb)")
            for ac in armed {
                print("[REC]   armed container bars=\(ac.startBar)-\(ac.endBar)")
            }
        }

        // Find which armed container (if any) the playhead is in
        var targetArmed: ArmedContainer?
        for ac in armed {
            if currentBar >= Double(ac.startBar) && currentBar < Double(ac.endBar) {
                targetArmed = ac
                break
            }
        }

        var recording = activeRecording

        // If playhead left current recording's container, finalize it
        if let rec = recording, targetArmed?.containerID != rec.containerID {
            activeRecording = nil
            lock.unlock()
            finalizeRecording(rec)
            lock.lock()
            recording = nil
        }

        // Start new recording if entering an armed container
        if recording == nil, let target = targetArmed {
            let filename = UUID().uuidString + ".caf"
            let fileURL = audioDirURL.appendingPathComponent(filename)
            let channelCount = inputChannelCount
            do {
                let writer = try CAFWriter(url: fileURL, sampleRate: sr, channelCount: channelCount)
                recording = ActiveRecording(
                    containerID: target.containerID,
                    trackID: target.trackID,
                    writer: writer,
                    filename: filename,
                    peaks: [],
                    pendingSamples: []
                )
                activeRecording = recording
                print("[REC] Started recording to \(filename) (\(channelCount)ch, \(sr)Hz)")
            } catch {
                print("[REC] FAILED to create CAFWriter: \(error)")
            }
        }

        // Write samples to active recording
        guard var rec = recording else {
            lock.unlock()
            return
        }

        lock.unlock()

        // Write the buffer to the file
        do {
            try rec.writer.write(buffer)
        } catch {
            if bc <= 3 {
                print("[REC] Write FAILED: \(error) bufferFormat=\(buffer.format)")
            }
        }

        // Extract samples for peak calculation (mono mix)
        if let channelData = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            for i in 0..<frameCount {
                var sample: Float = 0
                for ch in 0..<channelCount {
                    sample = max(sample, abs(channelData[ch][i]))
                }
                rec.pendingSamples.append(sample)
            }
        }

        // Generate peaks from accumulated samples
        lock.lock()
        let spp = samplesPerPeak
        lock.unlock()

        var newPeaks: [Float] = []
        while rec.pendingSamples.count >= spp {
            var maxVal: Float = 0
            for i in 0..<spp {
                let absVal = rec.pendingSamples[i]
                if absVal > maxVal {
                    maxVal = absVal
                }
            }
            newPeaks.append(min(maxVal, 1.0))
            rec.pendingSamples.removeFirst(spp)
        }

        if !newPeaks.isEmpty {
            rec.peaks.append(contentsOf: newPeaks)
            let containerID = rec.containerID
            let currentPeaks = rec.peaks

            lock.lock()
            activeRecording = rec
            lock.unlock()

            // Notify UI about peak updates on main thread
            let callback = onPeaksUpdated
            DispatchQueue.main.async {
                callback?(containerID, currentPeaks)
            }
        } else {
            lock.lock()
            activeRecording = rec
            lock.unlock()
        }
    }

    private func finalizeRecording(_ recording: ActiveRecording) {
        let sampleCount = recording.writer.close()

        // Generate final peak from any remaining pending samples
        var finalPeaks = recording.peaks
        if !recording.pendingSamples.isEmpty {
            var maxVal: Float = 0
            for sample in recording.pendingSamples {
                if sample > maxVal {
                    maxVal = sample
                }
            }
            finalPeaks.append(min(maxVal, 1.0))
        }

        let sourceRecording = SourceRecording(
            filename: recording.filename,
            sampleRate: sampleRate,
            sampleCount: sampleCount,
            waveformPeaks: finalPeaks
        )

        let trackID = recording.trackID
        let containerID = recording.containerID
        let callback = onRecordingComplete
        DispatchQueue.main.async {
            callback?(trackID, containerID, sourceRecording)
        }
    }
}
