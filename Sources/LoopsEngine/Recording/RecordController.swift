import Foundation
import AVFoundation
import LoopsCore

/// Records the engine input into one or more armed audio containers at the same
/// time, keeping all sessions aligned to the same captured sample timeline.
public final class RecordController: @unchecked Sendable {
    private let engine: AVAudioEngine
    private let audioDirURL: URL
    private let lock = NSLock()
    private let maxPendingBuffersPerSession: Int
    private let recordWriteDelayNanoseconds: UInt64

    private struct ArmedContainer {
        let containerID: ID<Container>
        let trackID: ID<Track>
        let startBar: Double
        let endBar: Double
    }

    private struct ActiveRecording {
        let containerID: ID<Container>
        let trackID: ID<Track>
        let writer: CAFWriter
        let bufferQueue: RecordBufferQueue
        let filename: String
        let startBar: Double
        let startSampleOffset: Int64
        var sampleCount: Int64
        var peaks: [Float]
        var extrema: [WaveformExtrema]
        var rms: [Float]
        var pendingSamples: [Float]
    }

    private var armedContainers: [ArmedContainer] = []
    private var activeRecordings: [ID<Container>: ActiveRecording] = [:]
    private var isTapInstalled = false
    private var sampleRate: Double = 44100.0
    private var inputChannelCount: UInt32 = 1
    private var samplesPerBar: Double = 0
    private var playbackStartBar: Double = 1.0
    private var tapSampleCount: Int64 = 0
    private var samplesPerPeak: Int = 441

    public var onPeaksUpdated: ((ID<Container>, [Float]) -> Void)?
    public var onWaveformUpdated: ((ID<Container>, [Float], [WaveformExtrema], [Float]) -> Void)?
    public var onRecordingComplete: ((ID<Track>, ID<Container>, SourceRecording) -> Void)?
    public var onDiagnosticsUpdated: ((RecordControllerDiagnostics) -> Void)?

    public init(
        engine: AVAudioEngine,
        audioDirURL: URL,
        maxPendingBuffersPerSession: Int = 32,
        recordWriteDelayNanoseconds: UInt64 = 0
    ) {
        self.engine = engine
        self.audioDirURL = audioDirURL
        self.maxPendingBuffersPerSession = max(1, maxPendingBuffersPerSession)
        self.recordWriteDelayNanoseconds = recordWriteDelayNanoseconds
    }

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
        playbackStartBar = fromBar
        let secondsPerBeat = 60.0 / bpm
        let beatsPerBar = Double(timeSignature.beatsPerBar)
        let secondsPerBar = beatsPerBar * secondsPerBeat
        samplesPerBar = secondsPerBar * sampleRate
        samplesPerPeak = max(1, Int(sampleRate) / WaveformGenerator.peaksPerSecond)
        tapSampleCount = 0
        let diagnostics = makeDiagnosticsLocked()
        lock.unlock()

        guard !armedContainers.isEmpty else { return }
        installTapIfNeeded()
        emitDiagnostics(diagnostics)
    }

    public func stopMonitoring() {
        removeTap()

        lock.lock()
        let recordings = Array(activeRecordings.values)
        activeRecordings.removeAll()
        armedContainers.removeAll()
        let diagnostics = makeDiagnosticsLocked()
        lock.unlock()

        for recording in recordings {
            finalizeRecording(recording)
        }
        emitDiagnostics(diagnostics)
    }

    public func activeSessions() -> [TrackRecordSession] {
        lock.lock()
        let sessions = activeRecordings.values.map {
            TrackRecordSession(
                trackID: $0.trackID,
                containerID: $0.containerID,
                filename: $0.filename,
                startBar: $0.startBar,
                startSampleOffset: $0.startSampleOffset,
                sampleCount: $0.sampleCount,
                droppedBufferCount: $0.bufferQueue.droppedBufferCount,
                droppedSampleCount: $0.bufferQueue.droppedSampleCount
            )
        }
        lock.unlock()
        return sessions.sorted { $0.startSampleOffset < $1.startSampleOffset }
    }

    public func diagnostics() -> RecordControllerDiagnostics {
        lock.lock()
        let diagnostics = makeDiagnosticsLocked()
        lock.unlock()
        return diagnostics
    }

    func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        lock.lock()
        let armed = armedContainers
        let spb = samplesPerBar
        let startBar = playbackStartBar
        let sr = sampleRate
        let currentTapSamples = tapSampleCount
        let currentBar = spb > 0 ? startBar + Double(currentTapSamples) / spb : startBar
        tapSampleCount += Int64(frameCount)

        let targetContainers = armed.filter { currentBar >= $0.startBar && currentBar < $0.endBar }
        let targetIDs = Set(targetContainers.map(\.containerID))
        var sessionsChanged = false

        let finishedRecordings = activeRecordings.values.filter { !targetIDs.contains($0.containerID) }
        for finished in finishedRecordings {
            activeRecordings.removeValue(forKey: finished.containerID)
            sessionsChanged = true
        }

        for target in targetContainers where activeRecordings[target.containerID] == nil {
            let filename = UUID().uuidString + ".caf"
            let fileURL = audioDirURL.appendingPathComponent(filename)
            do {
                let writer = try CAFWriter(url: fileURL, sampleRate: sr, channelCount: inputChannelCount)
                activeRecordings[target.containerID] = ActiveRecording(
                    containerID: target.containerID,
                    trackID: target.trackID,
                    writer: writer,
                    bufferQueue: RecordBufferQueue(
                        writer: writer,
                        label: "com.loops.recordController.\(filename)",
                        maxPendingBuffers: maxPendingBuffersPerSession,
                        writeDelayNanoseconds: recordWriteDelayNanoseconds
                    ),
                    filename: filename,
                    startBar: target.startBar,
                    startSampleOffset: currentTapSamples,
                    sampleCount: 0,
                    peaks: [],
                    extrema: [],
                    rms: [],
                    pendingSamples: []
                )
                sessionsChanged = true
            } catch {
            }
        }

        let recordingIDs = Array(activeRecordings.keys)
        lock.unlock()

        for recording in finishedRecordings {
            finalizeRecording(recording)
        }

        guard !recordingIDs.isEmpty else { return }

        let monoSamples = Self.extractSignedSamples(from: buffer)
        let deliveredSamples = Int64(frameCount)
        var shouldEmitDiagnostics = false

        for containerID in recordingIDs {
            guard let copiedBuffer = Self.copy(buffer: buffer) else { continue }

            lock.lock()
            guard var recording = activeRecordings[containerID] else {
                lock.unlock()
                continue
            }
            lock.unlock()

            let accepted = recording.bufferQueue.enqueue(copiedBuffer)
            if accepted {
                recording.sampleCount += deliveredSamples
            } else {
                shouldEmitDiagnostics = true
            }
            recording.pendingSamples.append(contentsOf: monoSamples)
            flushWaveformBuckets(for: &recording)

            lock.lock()
            activeRecordings[containerID] = recording
            lock.unlock()
        }

        if sessionsChanged || shouldEmitDiagnostics {
            emitDiagnostics(diagnostics())
        }
    }

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
            self?.processInputBuffer(buffer)
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

    private func flushWaveformBuckets(for recording: inout ActiveRecording) {
        let spp: Int
        lock.lock()
        spp = samplesPerPeak
        lock.unlock()

        var newPeaks: [Float] = []
        var newExtrema: [WaveformExtrema] = []
        var newRMS: [Float] = []

        while recording.pendingSamples.count >= spp {
            let bucket = Array(recording.pendingSamples.prefix(spp))
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
            recording.pendingSamples.removeFirst(spp)
        }

        guard !newPeaks.isEmpty else { return }

        recording.peaks.append(contentsOf: newPeaks)
        recording.extrema.append(contentsOf: newExtrema)
        recording.rms.append(contentsOf: newRMS)
        let containerID = recording.containerID
        let callback = onPeaksUpdated
        let waveformCallback = onWaveformUpdated
        let peaks = recording.peaks
        let extrema = recording.extrema
        let rms = recording.rms
        DispatchQueue.main.async {
            callback?(containerID, peaks)
            waveformCallback?(containerID, peaks, extrema, rms)
        }
    }

    private func finalizeRecording(_ recording: ActiveRecording) {
        let sampleCount = recording.bufferQueue.finish()

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

        let callback = onRecordingComplete
        DispatchQueue.main.async {
            callback?(recording.trackID, recording.containerID, sourceRecording)
        }
    }

    private func makeDiagnosticsLocked() -> RecordControllerDiagnostics {
        let sessions = Array(activeRecordings.values)
        let totalRecordedSampleCount = sessions.reduce(into: Int64(0)) { partial, session in
            partial += session.sampleCount
        }
        let totalDroppedBufferCount = sessions.reduce(into: 0) { partial, session in
            partial += session.bufferQueue.droppedBufferCount
        }
        let totalDroppedSampleCount = sessions.reduce(into: Int64(0)) { partial, session in
            partial += session.bufferQueue.droppedSampleCount
        }
        let overloadedSessionCount = sessions.reduce(into: 0) { partial, session in
            if session.bufferQueue.droppedBufferCount > 0 {
                partial += 1
            }
        }

        return RecordControllerDiagnostics(
            activeSessionCount: sessions.count,
            totalRecordedSampleCount: totalRecordedSampleCount,
            totalDroppedBufferCount: totalDroppedBufferCount,
            totalDroppedSampleCount: totalDroppedSampleCount,
            overloadedSessionCount: overloadedSessionCount
        )
    }

    private func emitDiagnostics(_ diagnostics: RecordControllerDiagnostics) {
        guard let callback = onDiagnosticsUpdated else { return }
        DispatchQueue.main.async {
            callback(diagnostics)
        }
    }

    private static func extractSignedSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channelData = buffer.floatChannelData else { return [] }

        let channelCount = Int(buffer.format.channelCount)
        var samples: [Float] = []
        samples.reserveCapacity(frameCount)
        for i in 0..<frameCount {
            var positive: Float = 0
            var negative: Float = 0
            for channel in 0..<channelCount {
                let sample = channelData[channel][i]
                positive = max(positive, sample)
                negative = min(negative, sample)
            }
            samples.append(abs(positive) >= abs(negative) ? positive : negative)
        }
        return samples
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
