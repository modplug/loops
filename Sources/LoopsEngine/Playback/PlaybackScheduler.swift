import Foundation
import AVFoundation
import LoopsCore

/// Schedules playback of recorded containers on AVAudioPlayerNodes,
/// synchronized to the timeline's bar/beat grid.
///
/// Architecture: each active container gets its own
/// `AVAudioPlayerNode → [AU Effects] → Track AVAudioMixerNode → mainMixerNode`.
/// When a container's effect chain is bypassed (or empty), the player routes
/// directly to the track mixer.
public final class PlaybackScheduler: @unchecked Sendable {
    private let engine: AVAudioEngine
    private let audioUnitHost: AudioUnitHost
    private var audioFiles: [ID<SourceRecording>: AVAudioFile] = [:]
    private let audioDirURL: URL

    /// Optional action dispatcher for container enter/exit MIDI actions.
    public var actionDispatcher: ActionDispatcher?

    /// Callback when a container trigger sets record-armed state.
    /// Parameters: containerID, armed.
    public var onRecordArmedChanged: ((ID<Container>, Bool) -> Void)?

    /// Per-container audio subgraph.
    private struct ContainerSubgraph {
        let playerNode: AVAudioPlayerNode
        let instrumentUnit: AVAudioUnit?
        let effectUnits: [AVAudioUnit]
        let trackMixer: AVAudioMixerNode
    }

    /// Track-level mixer nodes (one per track, routes to mainMixerNode).
    private var trackMixers: [ID<Track>: AVAudioMixerNode] = [:]

    /// All active container subgraphs, keyed by container ID.
    private var containerSubgraphs: [ID<Container>: ContainerSubgraph] = [:]

    /// Containers currently playing, for firing exit actions on stop.
    private var activeContainers: [Container] = []

    /// Stored playback state for trigger-based scheduling.
    private var currentSong: Song?
    private var currentBPM: Double = 120.0
    private var currentTimeSignature: TimeSignature = TimeSignature()
    private var currentSampleRate: Double = 44100.0

    /// Automation state: tracks playback start time and container offsets.
    private var automationTimer: DispatchSourceTimer?
    private var playbackStartTime: Date?
    private var playbackStartBar: Double = 1.0

    public init(engine: AVAudioEngine, audioDirURL: URL) {
        self.engine = engine
        self.audioUnitHost = AudioUnitHost(engine: engine)
        self.audioDirURL = audioDirURL
    }

    /// Prepares playback for a song by creating track mixers and loading audio files.
    /// AU effects for containers are pre-instantiated here.
    public func prepare(song: Song, sourceRecordings: [ID<SourceRecording>: SourceRecording]) async {
        cleanup()

        // Load audio files
        for (id, recording) in sourceRecordings {
            let fileURL = audioDirURL.appendingPathComponent(recording.filename)
            if let file = try? AVAudioFile(forReading: fileURL) {
                audioFiles[id] = file
            }
        }

        // Create a mixer node per track, connected to the main mixer
        for track in song.tracks {
            let trackMixer = AVAudioMixerNode()
            engine.attach(trackMixer)
            engine.connect(trackMixer, to: engine.mainMixerNode, format: nil)
            trackMixer.volume = track.isMuted ? 0.0 : track.volume
            trackMixer.pan = track.pan
            trackMixers[track.id] = trackMixer

            // Pre-instantiate per-container subgraphs
            for container in track.containers {
                guard container.sourceRecordingID != nil else { continue }
                await buildContainerSubgraph(container: container, trackMixer: trackMixer)
            }
        }
    }

    /// Schedules and starts playback from the given bar position.
    public func play(
        song: Song,
        fromBar: Double,
        bpm: Double,
        timeSignature: TimeSignature,
        sampleRate: Double
    ) {
        // Store playback state for trigger-based scheduling
        currentSong = song
        currentBPM = bpm
        currentTimeSignature = timeSignature
        currentSampleRate = sampleRate

        let samplesPerBar = self.samplesPerBar(bpm: bpm, timeSignature: timeSignature, sampleRate: sampleRate)

        for track in song.tracks {
            if track.isMuted { continue }

            // Schedule each container that has a recording
            for container in track.containers {
                scheduleContainer(
                    container: container,
                    fromBar: fromBar,
                    samplesPerBar: samplesPerBar
                )
            }
        }

        startAutomationTimer(song: song, fromBar: fromBar, bpm: bpm, timeSignature: timeSignature)
    }

    /// Stops all playback.
    public func stop() {
        stopAutomationTimer()
        for (_, subgraph) in containerSubgraphs {
            subgraph.playerNode.stop()
        }
        for container in activeContainers {
            actionDispatcher?.containerDidExit(container)
        }
        activeContainers.removeAll()
        currentSong = nil
    }

    /// Cleans up all nodes and audio files.
    public func cleanup() {
        stopAutomationTimer()
        for (_, subgraph) in containerSubgraphs {
            subgraph.playerNode.stop()
            engine.disconnectNodeOutput(subgraph.playerNode)
            engine.detach(subgraph.playerNode)
            if let inst = subgraph.instrumentUnit {
                engine.disconnectNodeOutput(inst)
                engine.detach(inst)
            }
            for unit in subgraph.effectUnits {
                engine.disconnectNodeOutput(unit)
                engine.detach(unit)
            }
        }
        containerSubgraphs.removeAll()
        activeContainers.removeAll()

        for (_, mixer) in trackMixers {
            engine.disconnectNodeOutput(mixer)
            engine.detach(mixer)
        }
        trackMixers.removeAll()

        audioFiles.removeAll()
        currentSong = nil
    }

    /// Updates track mix parameters (volume, pan, mute).
    public func updateTrackMix(trackID: ID<Track>, volume: Float, pan: Float, isMuted: Bool) {
        guard let mixer = trackMixers[trackID] else { return }
        mixer.volume = isMuted ? 0.0 : volume
        mixer.pan = pan
    }

    // MARK: - Private

    /// Schedules a single container for playback, handling fades and looping.
    private func scheduleContainer(
        container: Container,
        fromBar: Double,
        samplesPerBar: Double
    ) {
        guard let recordingID = container.sourceRecordingID,
              let audioFile = audioFiles[recordingID],
              let subgraph = containerSubgraphs[container.id] else { return }

        let containerStartSample = Int64(Double(container.startBar - 1) * samplesPerBar)
        let containerEndSample = Int64(Double(container.endBar - 1) * samplesPerBar)
        let playheadSample = Int64((fromBar - 1.0) * samplesPerBar)

        // Skip containers that end before the playhead
        if containerEndSample <= playheadSample { return }

        let startOffset: AVAudioFramePosition
        let frameCount: AVAudioFrameCount

        if playheadSample >= containerStartSample {
            // Playhead is inside this container
            startOffset = AVAudioFramePosition(playheadSample - containerStartSample)
            let remaining = containerEndSample - playheadSample
            let fileFrames = audioFile.length - startOffset
            frameCount = AVAudioFrameCount(min(remaining, fileFrames))
        } else {
            // Container starts in the future
            startOffset = 0
            let containerLength = containerEndSample - containerStartSample
            let fileFrames = audioFile.length
            frameCount = AVAudioFrameCount(min(containerLength, fileFrames))
        }

        guard frameCount > 0 else { return }

        let hasFades = container.enterFade != nil || container.exitFade != nil

        // For fill loop mode: schedule repeating segments
        if container.loopSettings.loopCount == .fill {
            if hasFades {
                scheduleFadingLoopPlayback(
                    player: subgraph.playerNode,
                    audioFile: audioFile,
                    containerStartSample: containerStartSample,
                    containerEndSample: containerEndSample,
                    playheadSample: playheadSample,
                    samplesPerBar: samplesPerBar,
                    enterFade: container.enterFade,
                    exitFade: container.exitFade
                )
            } else {
                scheduleLoopingPlayback(
                    player: subgraph.playerNode,
                    audioFile: audioFile,
                    containerStartSample: containerStartSample,
                    containerEndSample: containerEndSample,
                    playheadSample: playheadSample,
                    samplesPerBar: samplesPerBar
                )
            }
        } else {
            if hasFades {
                scheduleFadingPlayback(
                    player: subgraph.playerNode,
                    audioFile: audioFile,
                    startOffset: startOffset,
                    frameCount: frameCount,
                    containerPosition: playheadSample >= containerStartSample
                        ? playheadSample - containerStartSample : Int64(0),
                    containerLengthSamples: containerEndSample - containerStartSample,
                    samplesPerBar: samplesPerBar,
                    enterFade: container.enterFade,
                    exitFade: container.exitFade
                )
            } else {
                subgraph.playerNode.scheduleSegment(
                    audioFile,
                    startingFrame: startOffset,
                    frameCount: frameCount,
                    at: nil
                )
            }
        }

        subgraph.playerNode.play()
        activeContainers.append(container)
        actionDispatcher?.containerDidEnter(container)
    }

    /// Builds the per-container audio subgraph:
    /// `AVAudioPlayerNode → [Instrument Override] → [AU Effects (if not bypassed)] → trackMixer`
    private func buildContainerSubgraph(container: Container, trackMixer: AVAudioMixerNode) async {
        let player = AVAudioPlayerNode()
        engine.attach(player)

        // Load instrument override if present
        var instrumentUnit: AVAudioUnit?
        if let override = container.instrumentOverride {
            if let unit = try? await audioUnitHost.loadAudioUnit(component: override) {
                engine.attach(unit)
                instrumentUnit = unit
            }
        }

        var effectUnits: [AVAudioUnit] = []

        // Load AU effects if the chain is not bypassed
        if !container.isEffectChainBypassed {
            for effect in container.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                guard !effect.isBypassed else { continue }
                if let unit = try? await audioUnitHost.loadAudioUnit(component: effect.component) {
                    engine.attach(unit)
                    // Restore preset if available
                    if let presetData = effect.presetData {
                        try? audioUnitHost.restoreState(audioUnit: unit, data: presetData)
                    }
                    effectUnits.append(unit)
                }
            }
        }

        // Build the chain: player → [instrument] → [effects...] → trackMixer
        // Collect all processing nodes in order
        var chain: [AVAudioNode] = []
        if let inst = instrumentUnit { chain.append(inst) }
        chain.append(contentsOf: effectUnits)

        if chain.isEmpty {
            engine.connect(player, to: trackMixer, format: nil)
        } else {
            engine.connect(player, to: chain[0], format: nil)
            for i in 0..<(chain.count - 1) {
                engine.connect(chain[i], to: chain[i + 1], format: nil)
            }
            engine.connect(chain[chain.count - 1], to: trackMixer, format: nil)
        }

        containerSubgraphs[container.id] = ContainerSubgraph(
            playerNode: player,
            instrumentUnit: instrumentUnit,
            effectUnits: effectUnits,
            trackMixer: trackMixer
        )
    }

    private func samplesPerBar(bpm: Double, timeSignature: TimeSignature, sampleRate: Double) -> Double {
        let beatsPerBar = Double(timeSignature.beatsPerBar)
        let secondsPerBeat = 60.0 / bpm
        return beatsPerBar * secondsPerBeat * sampleRate
    }

    private func scheduleLoopingPlayback(
        player: AVAudioPlayerNode,
        audioFile: AVAudioFile,
        containerStartSample: Int64,
        containerEndSample: Int64,
        playheadSample: Int64,
        samplesPerBar: Double
    ) {
        let containerLengthSamples = containerEndSample - containerStartSample
        let fileLengthSamples = audioFile.length

        guard fileLengthSamples > 0, containerLengthSamples > 0 else { return }

        var position = max(playheadSample, containerStartSample) - containerStartSample
        let endPosition = containerLengthSamples

        while position < endPosition {
            let positionInLoop = position % fileLengthSamples
            let remainingInLoop = fileLengthSamples - positionInLoop
            let remainingInContainer = endPosition - position
            let framesToPlay = min(remainingInLoop, remainingInContainer)

            guard framesToPlay > 0 else { break }

            player.scheduleSegment(
                audioFile,
                startingFrame: AVAudioFramePosition(positionInLoop),
                frameCount: AVAudioFrameCount(framesToPlay),
                at: nil
            )

            position += framesToPlay
        }
    }

    // MARK: - Fade Scheduling

    /// Schedules a single (non-looping) segment with enter/exit fades applied.
    private func scheduleFadingPlayback(
        player: AVAudioPlayerNode,
        audioFile: AVAudioFile,
        startOffset: AVAudioFramePosition,
        frameCount: AVAudioFrameCount,
        containerPosition: Int64,
        containerLengthSamples: Int64,
        samplesPerBar: Double,
        enterFade: FadeSettings?,
        exitFade: FadeSettings?
    ) {
        let format = audioFile.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }

        audioFile.framePosition = startOffset
        do { try audioFile.read(into: buffer, frameCount: frameCount) } catch { return }

        applyContainerFades(
            to: buffer,
            containerPosition: containerPosition,
            containerLengthSamples: containerLengthSamples,
            samplesPerBar: samplesPerBar,
            enterFade: enterFade,
            exitFade: exitFade
        )

        player.scheduleBuffer(buffer)
    }

    /// Schedules looping playback with enter/exit fades applied at container boundaries.
    private func scheduleFadingLoopPlayback(
        player: AVAudioPlayerNode,
        audioFile: AVAudioFile,
        containerStartSample: Int64,
        containerEndSample: Int64,
        playheadSample: Int64,
        samplesPerBar: Double,
        enterFade: FadeSettings?,
        exitFade: FadeSettings?
    ) {
        let containerLengthSamples = containerEndSample - containerStartSample
        let fileLengthSamples = audioFile.length

        guard fileLengthSamples > 0, containerLengthSamples > 0 else { return }

        let enterFadeSamples = enterFade.map { Int64($0.duration * samplesPerBar) } ?? 0
        let exitFadeSamples = exitFade.map { Int64($0.duration * samplesPerBar) } ?? 0
        let exitFadeStart = containerLengthSamples - exitFadeSamples

        var position = max(playheadSample, containerStartSample) - containerStartSample
        let endPosition = containerLengthSamples
        let format = audioFile.processingFormat

        while position < endPosition {
            let positionInLoop = position % fileLengthSamples
            let remainingInLoop = fileLengthSamples - positionInLoop
            let remainingInContainer = endPosition - position
            let framesToPlay = min(remainingInLoop, remainingInContainer)

            guard framesToPlay > 0 else { break }

            let needsFade = (enterFade != nil && position < enterFadeSamples) ||
                            (exitFade != nil && position + framesToPlay > exitFadeStart)

            if needsFade {
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: AVAudioFrameCount(framesToPlay)
                ) else { break }

                audioFile.framePosition = AVAudioFramePosition(positionInLoop)
                do {
                    try audioFile.read(into: buffer, frameCount: AVAudioFrameCount(framesToPlay))
                } catch { break }

                applyContainerFades(
                    to: buffer,
                    containerPosition: position,
                    containerLengthSamples: containerLengthSamples,
                    samplesPerBar: samplesPerBar,
                    enterFade: enterFade,
                    exitFade: exitFade
                )

                player.scheduleBuffer(buffer)
            } else {
                player.scheduleSegment(
                    audioFile,
                    startingFrame: AVAudioFramePosition(positionInLoop),
                    frameCount: AVAudioFrameCount(framesToPlay),
                    at: nil
                )
            }

            position += framesToPlay
        }
    }

    /// Applies enter/exit fade gain envelopes to a buffer based on its position
    /// within the overall container timeline.
    private func applyContainerFades(
        to buffer: AVAudioPCMBuffer,
        containerPosition: Int64,
        containerLengthSamples: Int64,
        samplesPerBar: Double,
        enterFade: FadeSettings?,
        exitFade: FadeSettings?
    ) {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        let enterFadeSamples = enterFade.map { Int64($0.duration * samplesPerBar) } ?? 0
        let exitFadeSamples = exitFade.map { Int64($0.duration * samplesPerBar) } ?? 0
        let exitFadeStart = containerLengthSamples - exitFadeSamples

        for channel in 0..<channelCount {
            guard let channelData = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<frameLength {
                let pos = containerPosition + Int64(frame)
                var gain: Float = 1.0

                // Apply enter fade (gain ramp 0→1)
                if let fade = enterFade, pos < enterFadeSamples, enterFadeSamples > 0 {
                    let t = Double(pos) / Double(enterFadeSamples)
                    gain *= Float(fade.curve.gain(at: t))
                }

                // Apply exit fade (gain ramp 1→0)
                if let fade = exitFade, pos >= exitFadeStart, exitFadeSamples > 0 {
                    let t = Double(pos - exitFadeStart) / Double(exitFadeSamples)
                    gain *= Float(fade.curve.gain(at: 1.0 - t))
                }

                if gain < 1.0 {
                    channelData[frame] *= gain
                }
            }
        }
    }
    // MARK: - Automation

    /// Starts a timer that evaluates automation lanes at regular intervals.
    private func startAutomationTimer(
        song: Song,
        fromBar: Double,
        bpm: Double,
        timeSignature: TimeSignature
    ) {
        // Collect all containers with automation
        let containersWithAutomation = song.tracks.flatMap(\.containers)
            .filter { !$0.automationLanes.isEmpty }
        guard !containersWithAutomation.isEmpty else { return }

        playbackStartBar = fromBar
        playbackStartTime = Date()

        let secondsPerBeat = 60.0 / bpm
        let beatsPerBar = Double(timeSignature.beatsPerBar)
        let secondsPerBar = beatsPerBar * secondsPerBeat

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        // Evaluate at ~60 Hz (every ~16ms) for smooth parameter updates
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            guard let self, let startTime = self.playbackStartTime else { return }
            let elapsed = Date().timeIntervalSince(startTime)
            let currentBar = self.playbackStartBar + elapsed / secondsPerBar

            for container in containersWithAutomation {
                let containerStartBar = Double(container.startBar)
                let containerEndBar = Double(container.endBar)

                // Only evaluate if current playback is within this container
                guard currentBar >= containerStartBar && currentBar < containerEndBar else { continue }

                let barOffset = currentBar - containerStartBar
                for lane in container.automationLanes {
                    if let value = lane.interpolatedValue(atBar: barOffset) {
                        self.setParameter(at: lane.targetPath, value: value)
                    }
                }
            }
        }
        timer.resume()
        automationTimer = timer
    }

    private func stopAutomationTimer() {
        automationTimer?.cancel()
        automationTimer = nil
        playbackStartTime = nil
    }
}

// MARK: - ParameterResolver

extension PlaybackScheduler: ParameterResolver {
    public func setParameter(at path: EffectPath, value: Float) -> Bool {
        if let containerID = path.containerID {
            // Target is a container-level effect
            guard let subgraph = containerSubgraphs[containerID] else { return false }
            let units = subgraph.effectUnits
            guard path.effectIndex >= 0, path.effectIndex < units.count else { return false }
            let unit = units[path.effectIndex]
            guard let param = unit.auAudioUnit.parameterTree?.parameter(
                withAddress: AUParameterAddress(path.parameterAddress)
            ) else { return false }
            param.value = value
            return true
        } else {
            // Track-level effect — not yet wired (track effects managed outside PlaybackScheduler)
            return false
        }
    }
}

// MARK: - ContainerTriggerDelegate

extension PlaybackScheduler: ContainerTriggerDelegate {
    public func triggerStart(containerID: ID<Container>) {
        guard let song = currentSong else { return }
        for track in song.tracks {
            guard let container = track.containers.first(where: { $0.id == containerID }) else { continue }
            // Skip if already active
            guard !activeContainers.contains(where: { $0.id == containerID }) else { return }
            let spb = samplesPerBar(bpm: currentBPM, timeSignature: currentTimeSignature, sampleRate: currentSampleRate)
            scheduleContainer(
                container: container,
                fromBar: Double(container.startBar),
                samplesPerBar: spb
            )
            return
        }
    }

    public func triggerStop(containerID: ID<Container>) {
        guard let subgraph = containerSubgraphs[containerID] else { return }
        subgraph.playerNode.stop()
        if let index = activeContainers.firstIndex(where: { $0.id == containerID }) {
            let container = activeContainers[index]
            actionDispatcher?.containerDidExit(container)
            activeContainers.remove(at: index)
        }
    }

    public func setRecordArmed(containerID: ID<Container>, armed: Bool) {
        onRecordArmedChanged?(containerID, armed)
    }
}
