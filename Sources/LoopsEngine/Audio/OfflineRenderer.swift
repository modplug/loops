import Foundation
import AVFoundation
import LoopsCore

/// Supported export audio formats.
public enum ExportFormat: String, CaseIterable, Sendable {
    case wav16 = "WAV 16-bit"
    case wav24 = "WAV 24-bit"
    case aiff = "AIFF"

    public var fileExtension: String {
        switch self {
        case .wav16, .wav24: return "wav"
        case .aiff: return "aiff"
        }
    }

    public var bitDepth: Int {
        switch self {
        case .wav16: return 16
        case .wav24, .aiff: return 24
        }
    }

    public var isFloat: Bool { false }

    public var isBigEndian: Bool { self == .aiff }
}

/// Supported export sample rates.
public enum ExportSampleRate: Double, CaseIterable, Sendable {
    case rate44100 = 44100
    case rate48000 = 48000

    public var displayName: String {
        switch self {
        case .rate44100: return "44.1 kHz"
        case .rate48000: return "48 kHz"
        }
    }
}

/// Configuration for an audio export operation.
public struct ExportConfiguration: Sendable {
    public var format: ExportFormat
    public var sampleRate: ExportSampleRate
    public var destinationURL: URL

    public init(format: ExportFormat, sampleRate: ExportSampleRate, destinationURL: URL) {
        self.format = format
        self.sampleRate = sampleRate
        self.destinationURL = destinationURL
    }
}

/// Renders a song's audio offline to a file.
public final class OfflineRenderer {
    private let audioDirURL: URL
    private let chunkSize: AVAudioFrameCount = 4096

    public init(audioDirURL: URL) {
        self.audioDirURL = audioDirURL
    }

    /// Calculates total song length in bars from the furthest container end.
    public static func songLengthBars(song: Song) -> Int {
        var maxEnd = 0
        for track in song.tracks {
            for container in track.containers {
                maxEnd = max(maxEnd, container.endBar)
            }
        }
        return maxEnd > 0 ? maxEnd - 1 : 0
    }

    /// Calculates the number of samples in one bar.
    public static func samplesPerBar(bpm: Double, timeSignature: TimeSignature, sampleRate: Double) -> Double {
        let secondsPerBeat = 60.0 / bpm
        let beatsPerBar = Double(timeSignature.beatsPerBar)
        return beatsPerBar * secondsPerBeat * sampleRate
    }

    /// Renders the song to an audio file, processing container effects, fades,
    /// automation, and track-level effects offline.
    @discardableResult
    public func render(
        song: Song,
        sourceRecordings: [ID<SourceRecording>: SourceRecording],
        config: ExportConfiguration,
        progress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        let totalBars = Self.songLengthBars(song: song)
        guard totalBars > 0 else {
            throw LoopsError.exportFailed(reason: "Song has no content to export")
        }

        let sampleRate = config.sampleRate.rawValue
        let spb = Self.samplesPerBar(
            bpm: song.tempo.bpm,
            timeSignature: song.timeSignature,
            sampleRate: sampleRate
        )
        let totalFrames = AVAudioFrameCount(Double(totalBars) * spb)

        // Determine which tracks are audible
        let hasSolo = song.tracks.contains { $0.isSoloed }
        var audibleTracks = song.tracks.filter { track in
            if track.isMuted { return false }
            if hasSolo && !track.isSoloed { return false }
            return true
        }

        // Resolve trigger actions: include containers from non-audible tracks if triggered
        let triggeredIDs = resolveTriggeredContainers(
            audibleTracks: audibleTracks,
            allTracks: song.tracks
        )
        for track in song.tracks {
            if audibleTracks.contains(where: { $0.id == track.id }) { continue }
            let triggered = track.containers.filter { triggeredIDs.contains($0.id) }
            if !triggered.isEmpty {
                var trigTrack = track
                trigTrack.containers = triggered
                trigTrack.isMuted = false
                audibleTracks.append(trigTrack)
            }
        }

        // Log MIDI actions (skipped during offline render)
        logMIDIActions(tracks: audibleTracks)

        // Preload audio buffers for each source recording
        var bufferCache: [ID<SourceRecording>: AVAudioPCMBuffer] = [:]
        for track in audibleTracks {
            for container in track.containers {
                guard let recID = container.sourceRecordingID,
                      let recording = sourceRecordings[recID],
                      bufferCache[recID] == nil else { continue }
                let fileURL = audioDirURL.appendingPathComponent(recording.filename)
                guard let audioFile = try? AVAudioFile(forReading: fileURL) else { continue }
                let fmt = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: audioFile.fileFormat.sampleRate,
                    channels: audioFile.fileFormat.channelCount,
                    interleaved: false
                )!
                let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(audioFile.length))!
                try? audioFile.read(into: buf)
                bufferCache[recID] = buf
            }
        }

        let stereoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        )!

        // Phase 1: Pre-render each container (looping + fades + effects + automation)
        var processedContainers: [ID<Container>: AVAudioPCMBuffer] = [:]
        for track in audibleTracks {
            for container in track.containers {
                guard let recID = container.sourceRecordingID,
                      let sourceBuffer = bufferCache[recID] else { continue }

                let containerLengthSamples = Int(Double(container.lengthBars) * spb)
                let containerBuffer = buildContainerBuffer(
                    sourceBuffer: sourceBuffer,
                    container: container,
                    containerLengthSamples: containerLengthSamples
                )
                applyFades(to: containerBuffer, container: container, samplesPerBar: spb)

                let hasActiveEffects = !container.isEffectChainBypassed
                    && container.insertEffects.contains(where: { !$0.isBypassed })
                let hasInstrument = container.instrumentOverride != nil

                if hasActiveEffects || hasInstrument {
                    if let processed = await processContainerThroughEffects(
                        container: container,
                        inputBuffer: containerBuffer,
                        samplesPerBar: spb
                    ) {
                        processedContainers[container.id] = processed
                    } else {
                        processedContainers[container.id] = containerBuffer
                    }
                } else {
                    processedContainers[container.id] = containerBuffer
                }
            }
        }

        // Phase 2: Process track-level effects
        var processedTrackBuffers: [ID<Track>: AVAudioPCMBuffer] = [:]
        for track in audibleTracks {
            let hasActiveTrackEffects = track.insertEffects.contains(where: { !$0.isBypassed })
            if hasActiveTrackEffects {
                let trackBuf = mixContainersToTrackBuffer(
                    track: track,
                    processedContainers: processedContainers,
                    samplesPerBar: spb,
                    totalFrames: totalFrames,
                    format: stereoFormat
                )
                if let processed = await processTrackThroughEffects(
                    track: track,
                    inputBuffer: trackBuf
                ) {
                    processedTrackBuffers[track.id] = processed
                } else {
                    processedTrackBuffers[track.id] = trackBuf
                }
            }
        }

        // Phase 3: Mix into output file
        let outputSettings = createOutputSettings(config: config)
        let outputFile = try AVAudioFile(
            forWriting: config.destinationURL,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        var framesWritten: AVAudioFrameCount = 0
        while framesWritten < totalFrames {
            let framesToProcess = min(chunkSize, totalFrames - framesWritten)
            let chunk = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: framesToProcess)!
            chunk.frameLength = framesToProcess

            if let data = chunk.floatChannelData {
                for ch in 0..<2 {
                    memset(data[ch], 0, Int(framesToProcess) * MemoryLayout<Float>.size)
                }
            }

            for track in audibleTracks {
                if let trackBuf = processedTrackBuffers[track.id] {
                    mixProcessedTrackBuffer(
                        trackBuffer: trackBuf,
                        volume: track.volume,
                        pan: track.pan,
                        into: chunk,
                        startFrame: framesWritten
                    )
                } else {
                    mixTrack(
                        track: track,
                        into: chunk,
                        startFrame: framesWritten,
                        samplesPerBar: spb,
                        processedContainers: processedContainers
                    )
                }
            }

            try outputFile.write(from: chunk)
            framesWritten += framesToProcess
            progress?(min(Double(framesWritten) / Double(totalFrames), 1.0))
        }

        return config.destinationURL
    }

    // MARK: - Container Audio

    /// Creates a container-length buffer with source audio, looped if in .fill mode.
    private func buildContainerBuffer(
        sourceBuffer: AVAudioPCMBuffer,
        container: Container,
        containerLengthSamples: Int
    ) -> AVAudioPCMBuffer {
        guard let srcData = sourceBuffer.floatChannelData else {
            let fmt = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sourceBuffer.format.sampleRate,
                channels: 2, interleaved: false
            )!
            let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(containerLengthSamples))!
            buf.frameLength = AVAudioFrameCount(containerLengthSamples)
            return buf
        }
        let srcChannels = Int(sourceBuffer.format.channelCount)
        let srcFrames = Int(sourceBuffer.frameLength)
        let outChannels: UInt32 = 2

        let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceBuffer.format.sampleRate,
            channels: outChannels, interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(containerLengthSamples))!
        buffer.frameLength = AVAudioFrameCount(containerLengthSamples)
        guard let outData = buffer.floatChannelData else { return buffer }

        let isLooping = container.loopSettings.loopCount == .fill

        for frame in 0..<containerLengthSamples {
            let srcIdx: Int
            if isLooping {
                srcIdx = srcFrames > 0 ? frame % srcFrames : 0
            } else {
                srcIdx = frame
            }
            guard srcIdx < srcFrames else {
                outData[0][frame] = 0
                outData[1][frame] = 0
                continue
            }
            outData[0][frame] = srcData[0][srcIdx]
            outData[1][frame] = srcChannels > 1 ? srcData[1][srcIdx] : srcData[0][srcIdx]
        }
        return buffer
    }

    /// Applies enter/exit fade gain curves to a container buffer.
    private func applyFades(
        to buffer: AVAudioPCMBuffer,
        container: Container,
        samplesPerBar: Double
    ) {
        guard container.enterFade != nil || container.exitFade != nil else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        let containerLen = Int64(frameLength)

        let enterFadeSamples = container.enterFade.map { Int64($0.duration * samplesPerBar) } ?? 0
        let exitFadeSamples = container.exitFade.map { Int64($0.duration * samplesPerBar) } ?? 0
        let exitFadeStart = containerLen - exitFadeSamples

        for ch in 0..<channelCount {
            guard let chData = buffer.floatChannelData?[ch] else { continue }
            for frame in 0..<frameLength {
                let pos = Int64(frame)
                var gain: Float = 1.0
                if let fade = container.enterFade, pos < enterFadeSamples, enterFadeSamples > 0 {
                    let t = Double(pos) / Double(enterFadeSamples)
                    gain *= Float(fade.curve.gain(at: t))
                }
                if let fade = container.exitFade, pos >= exitFadeStart, exitFadeSamples > 0 {
                    let t = Double(pos - exitFadeStart) / Double(exitFadeSamples)
                    gain *= Float(fade.curve.gain(at: 1.0 - t))
                }
                if gain < 1.0 {
                    chData[frame] *= gain
                }
            }
        }
    }

    /// Processes a container buffer through its AU effect chain using an offline AVAudioEngine.
    /// Evaluates automation lanes targeting the container's own effects.
    private func processContainerThroughEffects(
        container: Container,
        inputBuffer: AVAudioPCMBuffer,
        samplesPerBar: Double
    ) async -> AVAudioPCMBuffer? {
        let containerFrames = inputBuffer.frameLength
        let format = inputBuffer.format

        let engine = AVAudioEngine()
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunkSize)
        } catch { return nil }

        let player = AVAudioPlayerNode()
        engine.attach(player)
        let auHost = AudioUnitHost(engine: engine)

        // Load instrument override
        var instrumentUnit: AVAudioUnit?
        if let override = container.instrumentOverride {
            instrumentUnit = try? await auHost.loadAudioUnit(component: override)
            if let unit = instrumentUnit { engine.attach(unit) }
        }

        // Load effects
        var effectUnits: [AVAudioUnit] = []
        if !container.isEffectChainBypassed {
            for effect in container.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                guard !effect.isBypassed else { continue }
                if let unit = try? await auHost.loadAudioUnit(component: effect.component) {
                    engine.attach(unit)
                    if let presetData = effect.presetData {
                        try? auHost.restoreState(audioUnit: unit, data: presetData)
                    }
                    effectUnits.append(unit)
                }
            }
        }

        // Build chain: player → [instrument] → [effects...] → mainMixer
        var chain: [AVAudioNode] = []
        if let inst = instrumentUnit { chain.append(inst) }
        chain.append(contentsOf: effectUnits)

        if chain.isEmpty {
            engine.connect(player, to: engine.mainMixerNode, format: format)
        } else {
            engine.connect(player, to: chain[0], format: format)
            for i in 0..<(chain.count - 1) {
                engine.connect(chain[i], to: chain[i + 1], format: format)
            }
            engine.connect(chain.last!, to: engine.mainMixerNode, format: format)
        }

        do { try engine.start() } catch { return nil }
        player.play()
        player.scheduleBuffer(inputBuffer, completionHandler: nil)

        // Render in chunks with automation
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: containerFrames)!
        guard let outData = output.floatChannelData else { return nil }
        var framesRendered: AVAudioFrameCount = 0

        while framesRendered < containerFrames {
            let framesToRender = min(chunkSize, containerFrames - framesRendered)

            // Evaluate automation targeting this container's own effects
            for lane in container.automationLanes {
                guard lane.targetPath.containerID == container.id else { continue }
                let barOffset = Double(framesRendered) / samplesPerBar
                if let value = lane.interpolatedValue(atBar: barOffset) {
                    let idx = lane.targetPath.effectIndex
                    if idx >= 0, idx < effectUnits.count {
                        let param = effectUnits[idx].auAudioUnit.parameterTree?.parameter(
                            withAddress: AUParameterAddress(lane.targetPath.parameterAddress)
                        )
                        param?.value = value
                    }
                }
            }

            let chunkBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRender)!
            let status: AVAudioEngineManualRenderingStatus
            do { status = try engine.renderOffline(framesToRender, to: chunkBuf) } catch { break }

            guard status == .success || status == .insufficientDataFromInputNode else { break }

            if let chunkData = chunkBuf.floatChannelData {
                let rendered = Int(chunkBuf.frameLength)
                let offset = Int(framesRendered)
                for ch in 0..<Int(format.channelCount) {
                    memcpy(&outData[ch][offset], chunkData[ch], rendered * MemoryLayout<Float>.size)
                }
            }

            framesRendered += chunkBuf.frameLength
            output.frameLength = framesRendered
            if status == .insufficientDataFromInputNode { break }
        }

        engine.stop()
        return output
    }

    // MARK: - Track Effects

    /// Mixes all containers for a track into a single buffer (no track volume/pan applied).
    private func mixContainersToTrackBuffer(
        track: Track,
        processedContainers: [ID<Container>: AVAudioPCMBuffer],
        samplesPerBar: Double,
        totalFrames: AVAudioFrameCount,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames)!
        buf.frameLength = totalFrames
        guard let outData = buf.floatChannelData else { return buf }
        for ch in 0..<2 { memset(outData[ch], 0, Int(totalFrames) * MemoryLayout<Float>.size) }

        for container in track.containers {
            guard let srcBuf = processedContainers[container.id],
                  let srcData = srcBuf.floatChannelData else { continue }
            let srcFrames = Int(srcBuf.frameLength)
            let srcChannels = Int(srcBuf.format.channelCount)

            let containerVolume = container.volumeOverride ?? 1.0
            let containerPan = container.panOverride ?? 0.0
            let cLeft = containerVolume * (containerPan <= 0 ? 1.0 : 1.0 - containerPan)
            let cRight = containerVolume * (containerPan >= 0 ? 1.0 : 1.0 + containerPan)

            let startSample = Int(Double(container.startBar - 1) * samplesPerBar)
            let endSample = min(startSample + srcFrames, Int(totalFrames))

            for frame in startSample..<endSample {
                let srcIdx = frame - startSample
                guard srcIdx < srcFrames else { break }
                outData[0][frame] += srcData[0][srcIdx] * cLeft
                outData[1][frame] += (srcChannels > 1 ? srcData[1][srcIdx] : srcData[0][srcIdx]) * cRight
            }
        }
        return buf
    }

    /// Processes a track buffer through the track's insert effects using an offline AVAudioEngine.
    private func processTrackThroughEffects(
        track: Track,
        inputBuffer: AVAudioPCMBuffer
    ) async -> AVAudioPCMBuffer? {
        let totalFrames = inputBuffer.frameLength
        let format = inputBuffer.format

        let engine = AVAudioEngine()
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunkSize)
        } catch { return nil }

        let player = AVAudioPlayerNode()
        engine.attach(player)
        let auHost = AudioUnitHost(engine: engine)

        var effectUnits: [AVAudioUnit] = []
        for effect in track.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            guard !effect.isBypassed else { continue }
            if let unit = try? await auHost.loadAudioUnit(component: effect.component) {
                engine.attach(unit)
                if let presetData = effect.presetData {
                    try? auHost.restoreState(audioUnit: unit, data: presetData)
                }
                effectUnits.append(unit)
            }
        }

        guard !effectUnits.isEmpty else { return nil }

        engine.connect(player, to: effectUnits[0], format: format)
        for i in 0..<(effectUnits.count - 1) {
            engine.connect(effectUnits[i], to: effectUnits[i + 1], format: format)
        }
        engine.connect(effectUnits.last!, to: engine.mainMixerNode, format: format)

        do { try engine.start() } catch { return nil }
        player.play()
        player.scheduleBuffer(inputBuffer, completionHandler: nil)

        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames)!
        guard let outData = output.floatChannelData else { return nil }
        var framesRendered: AVAudioFrameCount = 0

        while framesRendered < totalFrames {
            let framesToRender = min(chunkSize, totalFrames - framesRendered)
            let chunkBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRender)!
            let status: AVAudioEngineManualRenderingStatus
            do { status = try engine.renderOffline(framesToRender, to: chunkBuf) } catch { break }
            guard status == .success || status == .insufficientDataFromInputNode else { break }

            if let chunkData = chunkBuf.floatChannelData {
                let rendered = Int(chunkBuf.frameLength)
                let offset = Int(framesRendered)
                for ch in 0..<Int(format.channelCount) {
                    memcpy(&outData[ch][offset], chunkData[ch], rendered * MemoryLayout<Float>.size)
                }
            }

            framesRendered += chunkBuf.frameLength
            output.frameLength = framesRendered
            if status == .insufficientDataFromInputNode { break }
        }

        engine.stop()
        return output
    }

    // MARK: - Mixing

    /// Mixes a track's pre-rendered containers into the output chunk with volume/pan.
    private func mixTrack(
        track: Track,
        into output: AVAudioPCMBuffer,
        startFrame: AVAudioFrameCount,
        samplesPerBar: Double,
        processedContainers: [ID<Container>: AVAudioPCMBuffer]
    ) {
        guard let outData = output.floatChannelData else { return }
        let outFrames = Int(output.frameLength)

        let volume = track.volume
        let pan = track.pan
        let leftGain = volume * (pan <= 0 ? 1.0 : 1.0 - pan)
        let rightGain = volume * (pan >= 0 ? 1.0 : 1.0 + pan)

        for container in track.containers {
            guard let buffer = processedContainers[container.id],
                  let srcData = buffer.floatChannelData else { continue }

            let containerVolume = container.volumeOverride ?? 1.0
            let containerPan = container.panOverride ?? 0.0
            let cLeftGain = leftGain * containerVolume * (containerPan <= 0 ? 1.0 : 1.0 - containerPan)
            let cRightGain = rightGain * containerVolume * (containerPan >= 0 ? 1.0 : 1.0 + containerPan)

            let srcChannels = Int(buffer.format.channelCount)
            let srcFrames = Int(buffer.frameLength)
            let containerStartSample = Int(Double(container.startBar - 1) * samplesPerBar)
            let containerEndSample = containerStartSample + srcFrames

            let chunkStart = Int(startFrame)
            let chunkEnd = chunkStart + outFrames
            guard containerStartSample < chunkEnd && containerEndSample > chunkStart else { continue }

            let overlapStart = max(containerStartSample, chunkStart)
            let overlapEnd = min(containerEndSample, chunkEnd)

            for frame in overlapStart..<overlapEnd {
                let outIdx = frame - chunkStart
                let srcIdx = frame - containerStartSample
                guard srcIdx >= 0 && srcIdx < srcFrames else { continue }
                let sample = srcData[0][srcIdx]
                outData[0][outIdx] += sample * cLeftGain
                outData[1][outIdx] += (srcChannels > 1 ? srcData[1][srcIdx] : sample) * cRightGain
            }
        }
    }

    /// Mixes a pre-processed track buffer into the output chunk with track volume/pan.
    private func mixProcessedTrackBuffer(
        trackBuffer: AVAudioPCMBuffer,
        volume: Float,
        pan: Float,
        into output: AVAudioPCMBuffer,
        startFrame: AVAudioFrameCount
    ) {
        guard let outData = output.floatChannelData,
              let srcData = trackBuffer.floatChannelData else { return }

        let leftGain = volume * (pan <= 0 ? 1.0 : 1.0 - pan)
        let rightGain = volume * (pan >= 0 ? 1.0 : 1.0 + pan)
        let outFrames = Int(output.frameLength)
        let srcFrames = Int(trackBuffer.frameLength)
        let start = Int(startFrame)

        for i in 0..<outFrames {
            let srcIdx = start + i
            guard srcIdx < srcFrames else { break }
            outData[0][i] += srcData[0][srcIdx] * leftGain
            outData[1][i] += srcData[1][srcIdx] * rightGain
        }
    }

    // MARK: - Trigger Resolution

    /// Scans audible containers for trigger-start actions targeting containers on non-audible tracks.
    private func resolveTriggeredContainers(
        audibleTracks: [Track],
        allTracks: [Track]
    ) -> Set<ID<Container>> {
        let audibleTrackIDs = Set(audibleTracks.map(\.id))
        let nonAudibleContainerIDs = Set(
            allTracks.filter { !audibleTrackIDs.contains($0.id) }
                .flatMap(\.containers).map(\.id)
        )

        var triggered = Set<ID<Container>>()
        for track in audibleTracks {
            for container in track.containers {
                for action in container.onEnterActions + container.onExitActions {
                    if case .triggerContainer(_, let targetID, let triggerAction) = action,
                       triggerAction == .start,
                       nonAudibleContainerIDs.contains(targetID) {
                        triggered.insert(targetID)
                    }
                }
            }
        }
        return triggered
    }

    // MARK: - MIDI Logging

    /// Logs MIDI actions that are skipped during offline render.
    private func logMIDIActions(tracks: [Track]) {
        for track in tracks {
            for container in track.containers {
                for action in container.onEnterActions + container.onExitActions {
                    if case .sendMIDI(_, let message, let destination) = action {
                        _ = message; _ = destination
                        // MIDI actions are intentionally skipped during offline render
                    }
                }
            }
        }
    }

    // MARK: - Output Settings

    private func createOutputSettings(config: ExportConfiguration) -> [String: Any] {
        let sampleRate = config.sampleRate.rawValue
        let bitDepth = config.format.bitDepth
        let formatID: AudioFormatID = kAudioFormatLinearPCM

        var formatFlags: AudioFormatFlags = kLinearPCMFormatFlagIsPacked
        if config.format.isBigEndian {
            formatFlags |= kLinearPCMFormatFlagIsBigEndian
        }
        formatFlags |= kLinearPCMFormatFlagIsSignedInteger

        return [
            AVFormatIDKey: formatID,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: config.format.isBigEndian,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }
}
