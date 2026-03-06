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
        let bufferQueue: RecordBufferQueue
        let filename: String
        var peaks: [Float]
        var extrema: [WaveformExtrema]
        var rms: [Float]
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
        let startBar: Double
        let endBar: Double
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
    public var onWaveformUpdated: ((ID<Container>, [Float], [WaveformExtrema], [Float]) -> Void)?

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
        armedContainers: [(containerID: ID<Container>, trackID: ID<Track>, startBar: Double, endBar: Double)],
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

        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        lock.lock()
        inputChannelCount = format.channelCount
        sampleRate = format.sampleRate
        samplesPerPeak = max(1, Int(format.sampleRate) / WaveformGenerator.peaksPerSecond)
        lock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }
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

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        lock.lock()
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

        // Find which armed container (if any) the playhead is in
        var targetArmed: ArmedContainer?
        for ac in armed {
            if currentBar >= ac.startBar && currentBar < ac.endBar {
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
                    bufferQueue: RecordBufferQueue(
                        writer: writer,
                        label: "com.loops.containerRecorder.\(filename)"
                    ),
                    filename: filename,
                    peaks: [],
                    extrema: [],
                    rms: [],
                    pendingSamples: []
                )
                activeRecording = recording
            } catch {
            }
        }

        // Write samples to active recording
        guard var rec = recording else {
            lock.unlock()
            return
        }

        lock.unlock()

        // Write the buffer to the file
        if let copiedBuffer = Self.copy(buffer: buffer) {
            _ = rec.bufferQueue.enqueue(copiedBuffer)
        }

        // Extract signed mono-ish samples for waveform calculation.
        if let channelData = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            for i in 0..<frameCount {
                var positive: Float = 0
                var negative: Float = 0
                for ch in 0..<channelCount {
                    let sample = channelData[ch][i]
                    positive = max(positive, sample)
                    negative = min(negative, sample)
                }
                let signedSample: Float
                if abs(positive) >= abs(negative) {
                    signedSample = positive
                } else {
                    signedSample = negative
                }
                rec.pendingSamples.append(signedSample)
            }
        }

        // Generate peaks from accumulated samples
        lock.lock()
        let spp = samplesPerPeak
        lock.unlock()

        var newPeaks: [Float] = []
        var newExtrema: [WaveformExtrema] = []
        var newRMS: [Float] = []
        while rec.pendingSamples.count >= spp {
            let bucket = Array(rec.pendingSamples.prefix(spp))
            bucket.withUnsafeBufferPointer { samples in
                let extrema = WaveformGenerator.extremaFromSamples(samples, samplesPerBucket: samples.count)
                let rms = WaveformGenerator.rmsFromSamples(samples, samplesPerBucket: samples.count)
                if let first = extrema.first {
                    newExtrema.append(first)
                    newPeaks.append(min(max(abs(first.minimum), abs(first.maximum)), 1.0))
                }
                if let first = rms.first {
                    newRMS.append(first)
                }
            }
            rec.pendingSamples.removeFirst(spp)
        }

        if !newPeaks.isEmpty {
            rec.peaks.append(contentsOf: newPeaks)
            rec.extrema.append(contentsOf: newExtrema)
            rec.rms.append(contentsOf: newRMS)
            let containerID = rec.containerID
            let currentPeaks = rec.peaks
            let currentExtrema = rec.extrema
            let currentRMS = rec.rms

            lock.lock()
            activeRecording = rec
            lock.unlock()

            // Notify UI about peak updates on main thread
            let callback = onPeaksUpdated
            let waveformCallback = onWaveformUpdated
            DispatchQueue.main.async {
                callback?(containerID, currentPeaks)
                waveformCallback?(containerID, currentPeaks, currentExtrema, currentRMS)
            }
        } else {
            lock.lock()
            activeRecording = rec
            lock.unlock()
        }
    }

    private func finalizeRecording(_ recording: ActiveRecording) {
        let sampleCount = recording.bufferQueue.finish()

        // Generate final peak from any remaining pending samples
        var finalPeaks = recording.peaks
        var finalExtrema = recording.extrema
        var finalRMS = recording.rms
        if !recording.pendingSamples.isEmpty {
            recording.pendingSamples.withUnsafeBufferPointer { samples in
                let extrema = WaveformGenerator.extremaFromSamples(samples, samplesPerBucket: samples.count)
                let rms = WaveformGenerator.rmsFromSamples(samples, samplesPerBucket: samples.count)
                if let first = extrema.first {
                    finalExtrema.append(first)
                    finalPeaks.append(min(max(abs(first.minimum), abs(first.maximum)), 1.0))
                }
                if let first = rms.first {
                    finalRMS.append(first)
                }
            }
        }

        let sourceRecording = SourceRecording(
            filename: recording.filename,
            sampleRate: sampleRate,
            sampleCount: sampleCount,
            waveformPeaks: finalPeaks,
            waveformExtrema: finalExtrema,
            waveformRMS: finalRMS
        )

        let trackID = recording.trackID
        let containerID = recording.containerID
        let callback = onRecordingComplete
        DispatchQueue.main.async {
            callback?(trackID, containerID, sourceRecording)
        }
    }

    private static func copy(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copied = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copied.frameLength = buffer.frameLength

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        for channel in 0..<channelCount {
            guard let src = buffer.floatChannelData?[channel],
                  let dst = copied.floatChannelData?[channel] else { continue }
            dst.update(from: src, count: frameCount)
        }
        return copied
    }
}
