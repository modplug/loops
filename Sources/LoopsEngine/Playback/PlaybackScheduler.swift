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

    /// Optional input monitor for auto-suppressing monitoring during playback.
    public var inputMonitor: InputMonitor?

    /// Per-container audio subgraph.
    private struct ContainerSubgraph {
        let playerNode: AVAudioPlayerNode
        let instrumentUnit: AVAudioUnit?
        let effectUnits: [AVAudioUnit]
        let trackMixer: AVAudioMixerNode
    }

    /// Track-level mixer nodes (one per track, routes to master mixer or mainMixerNode).
    private var trackMixers: [ID<Track>: AVAudioMixerNode] = [:]

    /// Master track mixer node and effect chain.
    private var masterMixerNode: AVAudioMixerNode?
    private var masterEffectUnits: [AVAudioUnit] = []

    /// Per-track effect chains (non-master tracks with insertEffects).
    private var trackEffectUnits: [ID<Track>: [AVAudioUnit]] = [:]

    /// All active container subgraphs, keyed by container ID.
    private var containerSubgraphs: [ID<Container>: ContainerSubgraph] = [:]

    /// Containers currently playing, for firing exit actions on stop.
    private var activeContainers: [Container] = []

    /// Maps container IDs to the track they belong to, for monitoring suppression.
    private var containerToTrack: [ID<Container>: ID<Track>] = [:]

    /// Tracks that have at least one active container playing.
    private var tracksWithActiveContainers: Set<ID<Track>> = []

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
    /// Master track effects are loaded and all track mixers route through them.
    public func prepare(song: Song, sourceRecordings: [ID<SourceRecording>: SourceRecording]) async {
        cleanup()

        let allContainers = song.tracks.flatMap(\.containers)

        // Load audio files
        for (id, recording) in sourceRecordings {
            let fileURL = audioDirURL.appendingPathComponent(recording.filename)
            if let file = try? AVAudioFile(forReading: fileURL) {
                audioFiles[id] = file
            }
        }

        // Build master track effect chain: masterMixer → [effects] → mainMixerNode
        let masterTrack = song.masterTrack
        let outputTarget: AVAudioNode
        if let master = masterTrack {
            let masterMixer = AVAudioMixerNode()
            engine.attach(masterMixer)
            masterMixer.volume = master.volume
            masterMixer.pan = master.pan
            masterMixerNode = masterMixer

            // Load master effects
            if !master.isEffectChainBypassed {
                for effect in master.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                    guard !effect.isBypassed else { continue }
                    if let unit = try? await audioUnitHost.loadAudioUnit(component: effect.component) {
                        engine.attach(unit)
                        if let presetData = effect.presetData {
                            try? audioUnitHost.restoreState(audioUnit: unit, data: presetData)
                        }
                        masterEffectUnits.append(unit)
                    }
                }
            }

            // Connect: masterMixer → [effects] → mainMixerNode
            if masterEffectUnits.isEmpty {
                engine.connect(masterMixer, to: engine.mainMixerNode, format: nil)
            } else {
                engine.connect(masterMixer, to: masterEffectUnits[0], format: nil)
                for i in 0..<(masterEffectUnits.count - 1) {
                    engine.connect(masterEffectUnits[i], to: masterEffectUnits[i + 1], format: nil)
                }
                engine.connect(masterEffectUnits[masterEffectUnits.count - 1], to: engine.mainMixerNode, format: nil)
            }

            outputTarget = masterMixer
        } else {
            outputTarget = engine.mainMixerNode
        }

        // Create a mixer node per track, connected through track effects to master mixer (or mainMixer)
        for track in song.tracks {
            // Skip master track — it has its own mixer
            if track.kind == .master { continue }

            let trackMixer = AVAudioMixerNode()
            engine.attach(trackMixer)
            trackMixer.volume = track.isMuted ? 0.0 : track.volume
            trackMixer.pan = track.pan
            trackMixers[track.id] = trackMixer

            // Load track-level insert effects
            var tEffectUnits: [AVAudioUnit] = []
            if !track.isEffectChainBypassed {
                for effect in track.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                    guard !effect.isBypassed else { continue }
                    if let unit = try? await audioUnitHost.loadAudioUnit(component: effect.component) {
                        engine.attach(unit)
                        if let presetData = effect.presetData {
                            try? audioUnitHost.restoreState(audioUnit: unit, data: presetData)
                        }
                        tEffectUnits.append(unit)
                    }
                }
            }
            trackEffectUnits[track.id] = tEffectUnits

            // Route: trackMixer → [track effects] → outputTarget
            if tEffectUnits.isEmpty {
                engine.connect(trackMixer, to: outputTarget, format: nil)
            } else {
                engine.connect(trackMixer, to: tEffectUnits[0], format: nil)
                for i in 0..<(tEffectUnits.count - 1) {
                    engine.connect(tEffectUnits[i], to: tEffectUnits[i + 1], format: nil)
                }
                engine.connect(tEffectUnits[tEffectUnits.count - 1], to: outputTarget, format: nil)
            }

            // Pre-instantiate per-container subgraphs (resolve clone fields)
            for container in track.containers {
                let resolved = container.resolved { id in allContainers.first(where: { $0.id == id }) }
                guard resolved.sourceRecordingID != nil else { continue }
                await buildContainerSubgraph(container: resolved, trackMixer: trackMixer)
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

        let allContainers = song.tracks.flatMap(\.containers)

        // Build container → track mapping for monitoring suppression
        for track in song.tracks {
            for container in track.containers {
                containerToTrack[container.id] = track.id
            }
        }

        for track in song.tracks {
            if track.isMuted { continue }
            // Master track has no playable containers
            if track.kind == .master { continue }

            // Schedule each container that has a recording (resolve clone fields)
            for container in track.containers {
                let resolved = container.resolved { id in allContainers.first(where: { $0.id == id }) }
                scheduleContainer(
                    container: resolved,
                    fromBar: fromBar,
                    samplesPerBar: samplesPerBar
                )
            }
        }

        // Suppress input monitoring on tracks that have active containers
        for trackID in tracksWithActiveContainers {
            inputMonitor?.suppressMonitoring(trackID: trackID)
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
        // Unsuppress monitoring on tracks that had active containers
        for trackID in tracksWithActiveContainers {
            inputMonitor?.unsuppressMonitoring(trackID: trackID)
        }
        activeContainers.removeAll()
        tracksWithActiveContainers.removeAll()
        containerToTrack.removeAll()
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
        tracksWithActiveContainers.removeAll()
        containerToTrack.removeAll()

        for (_, units) in trackEffectUnits {
            for unit in units {
                engine.disconnectNodeOutput(unit)
                engine.detach(unit)
            }
        }
        trackEffectUnits.removeAll()

        for (_, mixer) in trackMixers {
            engine.disconnectNodeOutput(mixer)
            engine.detach(mixer)
        }
        trackMixers.removeAll()

        // Cleanup master mixer and effects
        for unit in masterEffectUnits {
            engine.disconnectNodeOutput(unit)
            engine.detach(unit)
        }
        masterEffectUnits.removeAll()
        if let masterMixer = masterMixerNode {
            engine.disconnectNodeOutput(masterMixer)
            engine.detach(masterMixer)
            masterMixerNode = nil
        }

        audioFiles.removeAll()
        currentSong = nil
    }

    /// Updates track mix parameters (volume, pan, mute).
    public func updateTrackMix(trackID: ID<Track>, volume: Float, pan: Float, isMuted: Bool) {
        guard let mixer = trackMixers[trackID] else {
            // Check if this is the master track
            if let masterMixer = masterMixerNode {
                masterMixer.volume = volume
                masterMixer.pan = pan
            }
            return
        }
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
        if let trackID = containerToTrack[container.id] {
            tracksWithActiveContainers.insert(trackID)
        }
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
        // Collect all containers with automation (resolve clone fields)
        let allContainers = song.tracks.flatMap(\.containers)
        let containersWithAutomation = allContainers
            .map { $0.resolved { id in allContainers.first(where: { $0.id == id }) } }
            .filter { !$0.automationLanes.isEmpty }

        // Collect tracks with track-level automation
        let tracksWithAutomation = song.tracks.filter { !$0.trackAutomationLanes.isEmpty }

        guard !containersWithAutomation.isEmpty || !tracksWithAutomation.isEmpty else { return }

        playbackStartBar = fromBar
        playbackStartTime = Date()

        let secondsPerBeat = 60.0 / bpm
        let beatsPerBar = Double(timeSignature.beatsPerBar)
        let secondsPerBar = beatsPerBar * secondsPerBeat

        // Capture track mixers for track-level automation
        let capturedTrackMixers = self.trackMixers
        let capturedMasterMixer = self.masterMixerNode

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        // Evaluate at ~60 Hz (every ~16ms) for smooth parameter updates
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            guard let self, let startTime = self.playbackStartTime else { return }
            let elapsed = Date().timeIntervalSince(startTime)
            let currentBar = self.playbackStartBar + elapsed / secondsPerBar

            // Evaluate container-level automation
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

            // Evaluate track-level automation (positions are 0-based from bar 1)
            let absoluteBarOffset = currentBar - 1.0
            for track in tracksWithAutomation {
                for lane in track.trackAutomationLanes {
                    guard let value = lane.interpolatedValue(atBar: absoluteBarOffset) else { continue }
                    if lane.targetPath.isTrackVolume {
                        if track.kind == .master {
                            capturedMasterMixer?.volume = value * 2.0
                        } else {
                            capturedTrackMixers[track.id]?.volume = track.isMuted ? 0.0 : value * 2.0
                        }
                    } else if lane.targetPath.isTrackPan {
                        let panValue = value * 2.0 - 1.0 // 0..1 → -1..+1
                        if track.kind == .master {
                            capturedMasterMixer?.pan = panValue
                        } else {
                            capturedTrackMixers[track.id]?.pan = panValue
                        }
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
            // Track-level effect
            guard let units = trackEffectUnits[path.trackID] else { return false }
            guard path.effectIndex >= 0, path.effectIndex < units.count else { return false }
            let unit = units[path.effectIndex]
            guard let param = unit.auAudioUnit.parameterTree?.parameter(
                withAddress: AUParameterAddress(path.parameterAddress)
            ) else { return false }
            param.value = value
            return true
        }
    }
}

// MARK: - ContainerTriggerDelegate

extension PlaybackScheduler: ContainerTriggerDelegate {
    public func triggerStart(containerID: ID<Container>) {
        guard let song = currentSong else { return }
        let allContainers = song.tracks.flatMap(\.containers)
        for track in song.tracks {
            guard let container = track.containers.first(where: { $0.id == containerID }) else { continue }
            // Skip if already active
            guard !activeContainers.contains(where: { $0.id == containerID }) else { return }
            let resolved = container.resolved { id in allContainers.first(where: { $0.id == id }) }
            let spb = samplesPerBar(bpm: currentBPM, timeSignature: currentTimeSignature, sampleRate: currentSampleRate)
            scheduleContainer(
                container: resolved,
                fromBar: Double(resolved.startBar),
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

            // If no more active containers on this track, unsuppress monitoring
            if let trackID = containerToTrack[containerID] {
                let hasOtherActive = activeContainers.contains { containerToTrack[$0.id] == trackID }
                if !hasOtherActive {
                    tracksWithActiveContainers.remove(trackID)
                    inputMonitor?.unsuppressMonitoring(trackID: trackID)
                }
            }
        }
    }

    public func setRecordArmed(containerID: ID<Container>, armed: Bool) {
        onRecordArmedChanged?(containerID, armed)
    }
}
