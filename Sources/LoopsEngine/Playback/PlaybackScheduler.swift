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

    /// Protects all mutable state from concurrent access.
    /// Methods called from arbitrary threads (MIDI callbacks, UI, cooperative pool)
    /// must acquire this lock before reading or writing any mutable property.
    private let lock = NSLock()

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

    deinit {
        lock.lock()
        let timer = automationTimer
        automationTimer = nil
        lock.unlock()
        timer?.cancel()
    }

    /// Prepares playback for a song by creating track mixers and loading audio files.
    /// AU effects for containers are pre-instantiated here.
    /// Master track effects are loaded and all track mixers route through them.
    ///
    /// Must run on the main actor — AVAudioEngine topology operations (attach,
    /// connect, disconnect, detach) can silently fail from background threads.
    ///
    /// Two-phase design: audio units are loaded asynchronously while the engine
    /// keeps running (no audible gap), then the engine is briefly stopped for
    /// the synchronous attach/connect pass.
    @MainActor
    public func prepare(song: Song, sourceRecordings: [ID<SourceRecording>: SourceRecording]) async {
        let allContainers = song.tracks.flatMap(\.containers)

        // ── Phase 1: Load files and audio units (async, engine keeps running) ──

        var loadedFiles: [ID<SourceRecording>: AVAudioFile] = [:]
        for (id, recording) in sourceRecordings {
            let fileURL = audioDirURL.appendingPathComponent(recording.filename)
            if let file = try? AVAudioFile(forReading: fileURL) {
                loadedFiles[id] = file
            }
        }

        guard !Task.isCancelled else { return }

        // Pre-load master effects
        let masterTrack = song.masterTrack
        var preloadedMasterEffects: [AVAudioUnit] = []
        if let master = masterTrack, !master.isEffectChainBypassed {
            for effect in master.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                guard !effect.isBypassed else { continue }
                guard !Task.isCancelled else { return }
                if let unit = try? await audioUnitHost.loadAudioUnit(component: effect.component) {
                    if let presetData = effect.presetData {
                        try? audioUnitHost.restoreState(audioUnit: unit, data: presetData)
                    }
                    preloadedMasterEffects.append(unit)
                }
            }
        }

        guard !Task.isCancelled else { return }

        // Pre-load track and container audio units
        struct PreloadedContainer {
            let container: Container
            let instrument: AVAudioUnit?
            let effects: [AVAudioUnit]
            let audioFormat: AVAudioFormat?
        }
        struct PreloadedTrack {
            let track: Track
            let effects: [AVAudioUnit]
            let containers: [PreloadedContainer]
        }

        var preloadedTracks: [PreloadedTrack] = []
        for track in song.tracks {
            if track.kind == .master { continue }
            guard !Task.isCancelled else { return }

            var trackEffects: [AVAudioUnit] = []
            if !track.isEffectChainBypassed {
                for effect in track.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                    guard !effect.isBypassed else { continue }
                    if let unit = try? await audioUnitHost.loadAudioUnit(component: effect.component) {
                        if let presetData = effect.presetData {
                            try? audioUnitHost.restoreState(audioUnit: unit, data: presetData)
                        }
                        trackEffects.append(unit)
                    }
                }
            }

            var preloadedContainers: [PreloadedContainer] = []
            for container in track.containers {
                guard !Task.isCancelled else { return }
                let resolved = container.resolved { id in allContainers.first(where: { $0.id == id }) }
                guard let recID = resolved.sourceRecordingID else { continue }
                let fileFormat = loadedFiles[recID]?.processingFormat

                var instrumentUnit: AVAudioUnit?
                if let override = resolved.instrumentOverride {
                    instrumentUnit = try? await audioUnitHost.loadAudioUnit(component: override)
                }

                var effectUnits: [AVAudioUnit] = []
                if !resolved.isEffectChainBypassed {
                    for effect in resolved.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                        guard !effect.isBypassed else { continue }
                        if let unit = try? await audioUnitHost.loadAudioUnit(component: effect.component) {
                            if let presetData = effect.presetData {
                                try? audioUnitHost.restoreState(audioUnit: unit, data: presetData)
                            }
                            effectUnits.append(unit)
                        }
                    }
                }

                preloadedContainers.append(PreloadedContainer(
                    container: resolved,
                    instrument: instrumentUnit,
                    effects: effectUnits,
                    audioFormat: fileFormat
                ))
            }

            preloadedTracks.append(PreloadedTrack(
                track: track,
                effects: trackEffects,
                containers: preloadedContainers
            ))
        }

        guard !Task.isCancelled else { return }

        // ── Phase 2: Stop engine, rebuild graph synchronously, restart ──
        // engine.connect() silently fails on a running engine, so we must
        // stop it for the attach/connect pass. This phase is fast (no awaits).

        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        defer { if wasRunning { try? engine.start() } }

        cleanup()

        lock.lock()
        audioFiles = loadedFiles
        lock.unlock()

        // Master mixer chain
        let outputTarget: AVAudioNode
        if let master = masterTrack {
            let masterMixer = AVAudioMixerNode()
            engine.attach(masterMixer)
            masterMixer.volume = master.volume
            masterMixer.pan = master.pan

            for unit in preloadedMasterEffects {
                engine.attach(unit)
            }

            lock.lock()
            masterMixerNode = masterMixer
            masterEffectUnits = preloadedMasterEffects
            lock.unlock()

            if preloadedMasterEffects.isEmpty {
                engine.connect(masterMixer, to: engine.mainMixerNode, format: nil)
            } else {
                engine.connect(masterMixer, to: preloadedMasterEffects[0], format: nil)
                for i in 0..<(preloadedMasterEffects.count - 1) {
                    engine.connect(preloadedMasterEffects[i], to: preloadedMasterEffects[i + 1], format: nil)
                }
                engine.connect(preloadedMasterEffects[preloadedMasterEffects.count - 1], to: engine.mainMixerNode, format: nil)
            }

            outputTarget = masterMixer
        } else {
            outputTarget = engine.mainMixerNode
        }

        // Track mixers and container subgraphs
        let hasSolo = preloadedTracks.contains { $0.track.isSoloed }
        for preloaded in preloadedTracks {
            let trackMixer = AVAudioMixerNode()
            engine.attach(trackMixer)
            let effectivelyMuted = preloaded.track.isMuted
                || (hasSolo && !preloaded.track.isSoloed)
            trackMixer.volume = effectivelyMuted ? 0.0 : preloaded.track.volume
            trackMixer.pan = preloaded.track.pan

            for unit in preloaded.effects {
                engine.attach(unit)
            }

            lock.lock()
            trackMixers[preloaded.track.id] = trackMixer
            trackEffectUnits[preloaded.track.id] = preloaded.effects
            lock.unlock()

            if preloaded.effects.isEmpty {
                engine.connect(trackMixer, to: outputTarget, format: nil)
            } else {
                engine.connect(trackMixer, to: preloaded.effects[0], format: nil)
                for i in 0..<(preloaded.effects.count - 1) {
                    engine.connect(preloaded.effects[i], to: preloaded.effects[i + 1], format: nil)
                }
                engine.connect(preloaded.effects[preloaded.effects.count - 1], to: outputTarget, format: nil)
            }

            for pc in preloaded.containers {
                let player = AVAudioPlayerNode()
                engine.attach(player)

                if let inst = pc.instrument {
                    engine.attach(inst)
                }
                for unit in pc.effects {
                    engine.attach(unit)
                }

                var chain: [AVAudioNode] = []
                if let inst = pc.instrument { chain.append(inst) }
                chain.append(contentsOf: pc.effects)

                let playerFormat = pc.audioFormat
                if chain.isEmpty {
                    engine.connect(player, to: trackMixer, format: playerFormat)
                } else {
                    engine.connect(player, to: chain[0], format: playerFormat)
                    for i in 0..<(chain.count - 1) {
                        engine.connect(chain[i], to: chain[i + 1], format: nil)
                    }
                    engine.connect(chain[chain.count - 1], to: trackMixer, format: nil)
                }

                lock.lock()
                containerSubgraphs[pc.container.id] = ContainerSubgraph(
                    playerNode: player,
                    instrumentUnit: pc.instrument,
                    effectUnits: pc.effects,
                    trackMixer: trackMixer
                )
                lock.unlock()
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
        let samplesPerBar = self.samplesPerBar(bpm: bpm, timeSignature: timeSignature, sampleRate: sampleRate)
        let allContainers = song.tracks.flatMap(\.containers)

        lock.lock()
        // Store playback state for trigger-based scheduling
        currentSong = song
        currentBPM = bpm
        currentTimeSignature = timeSignature
        currentSampleRate = sampleRate

        // Build container → track mapping for monitoring suppression
        for track in song.tracks {
            for container in track.containers {
                containerToTrack[container.id] = track.id
            }
        }
        lock.unlock()

        for track in song.tracks {
            // Master track has no playable containers
            if track.kind == .master { continue }

            // Schedule all containers regardless of mute/solo — muting is
            // handled by mixer volumes so tracks can be unmuted during playback.
            for container in track.containers {
                let resolved = container.resolved { id in allContainers.first(where: { $0.id == id }) }
                scheduleContainer(
                    container: resolved,
                    fromBar: fromBar,
                    samplesPerBar: samplesPerBar
                )
            }
        }

        lock.lock()
        let activeTrackIDs = tracksWithActiveContainers
        lock.unlock()

        // Suppress input monitoring on tracks that have active containers
        for trackID in activeTrackIDs {
            inputMonitor?.suppressMonitoring(trackID: trackID)
        }

        startAutomationTimer(song: song, fromBar: fromBar, bpm: bpm, timeSignature: timeSignature)
    }

    /// Stops all playback.
    public func stop() {
        stopAutomationTimer()

        // Copy state under lock, then operate on copies
        lock.lock()
        let subgraphs = containerSubgraphs
        let containers = activeContainers
        let tracks = tracksWithActiveContainers
        activeContainers.removeAll()
        tracksWithActiveContainers.removeAll()
        containerToTrack.removeAll()
        currentSong = nil
        lock.unlock()

        // Declick fade-out: ramp main mixer output volume to zero over ~8ms
        // so the render thread picks up intermediate values before we stop nodes.
        if !subgraphs.isEmpty {
            let savedVolume = engine.mainMixerNode.outputVolume
            let steps = 8
            for i in 1...steps {
                engine.mainMixerNode.outputVolume = savedVolume * Float(steps - i) / Float(steps)
                usleep(1000)
            }
            for (_, subgraph) in subgraphs {
                subgraph.playerNode.stop()
            }
            engine.mainMixerNode.outputVolume = savedVolume
        }

        for container in containers {
            actionDispatcher?.containerDidExit(container)
        }
        // Unsuppress monitoring on tracks that had active containers
        for trackID in tracks {
            inputMonitor?.unsuppressMonitoring(trackID: trackID)
        }
    }

    /// Cleans up all nodes and audio files.
    ///
    /// Must run on the main actor — AVAudioEngine topology operations (disconnect,
    /// detach) can silently fail from background threads.
    @MainActor
    public func cleanup() {
        stopAutomationTimer()

        // Copy and clear shared state under lock — non-@MainActor methods
        // (stop, updateTrackMix, scheduleContainer, etc.) also read these.
        lock.lock()
        let subgraphs = containerSubgraphs
        containerSubgraphs.removeAll()
        activeContainers.removeAll()
        tracksWithActiveContainers.removeAll()
        containerToTrack.removeAll()
        let tEffectUnits = trackEffectUnits
        trackEffectUnits.removeAll()
        let tMixers = trackMixers
        trackMixers.removeAll()
        let mEffectUnits = masterEffectUnits
        masterEffectUnits.removeAll()
        let mMixer = masterMixerNode
        masterMixerNode = nil
        audioFiles.removeAll()
        currentSong = nil
        lock.unlock()

        // Engine operations on local copies — no lock needed
        for (_, subgraph) in subgraphs {
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

        for (_, units) in tEffectUnits {
            for unit in units {
                engine.disconnectNodeOutput(unit)
                engine.detach(unit)
            }
        }

        for (_, mixer) in tMixers {
            engine.disconnectNodeOutput(mixer)
            engine.detach(mixer)
        }

        // Cleanup master mixer and effects
        for unit in mEffectUnits {
            engine.disconnectNodeOutput(unit)
            engine.detach(unit)
        }
        if let masterMixer = mMixer {
            engine.disconnectNodeOutput(masterMixer)
            engine.detach(masterMixer)
        }
    }

    /// Updates track mix parameters (volume, pan, mute).
    public func updateTrackMix(trackID: ID<Track>, volume: Float, pan: Float, isMuted: Bool) {
        lock.lock()
        let mixer = trackMixers[trackID]
        let masterMixer = masterMixerNode
        lock.unlock()

        guard let mixer else {
            // Check if this is the master track
            masterMixer?.volume = volume
            masterMixer?.pan = pan
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
        lock.lock()
        let audioFile: AVAudioFile?
        let subgraph: ContainerSubgraph?
        if let recordingID = container.sourceRecordingID {
            audioFile = audioFiles[recordingID]
            subgraph = containerSubgraphs[container.id]
        } else {
            audioFile = nil
            subgraph = nil
        }
        lock.unlock()

        guard let audioFile, let subgraph else { return }

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
                scheduleDeclickedSegment(
                    player: subgraph.playerNode,
                    audioFile: audioFile,
                    startingFrame: startOffset,
                    frameCount: frameCount
                )
            }
        }

        // Guard against concurrent cleanup detaching the node from the engine
        guard subgraph.playerNode.engine != nil else { return }
        subgraph.playerNode.play()

        lock.lock()
        activeContainers.append(container)
        if let trackID = containerToTrack[container.id] {
            tracksWithActiveContainers.insert(trackID)
        }
        lock.unlock()

        actionDispatcher?.containerDidEnter(container)
    }

    private func samplesPerBar(bpm: Double, timeSignature: TimeSignature, sampleRate: Double) -> Double {
        let beatsPerBar = Double(timeSignature.beatsPerBar)
        let secondsPerBeat = 60.0 / bpm
        return beatsPerBar * secondsPerBeat * sampleRate
    }

    // MARK: - Transport Declick

    /// Number of frames for the transport declick fade (linear ramp).
    /// ~256 samples ≈ 5.8 ms at 44.1 kHz — imperceptible but eliminates clicks.
    private static let declickFrameCount: AVAudioFrameCount = 256

    /// Applies a linear fade-in (0→1) over the first `declickFrameCount` frames of a buffer.
    private static func applyDeclickFadeIn(to buffer: AVAudioPCMBuffer) {
        let channelCount = Int(buffer.format.channelCount)
        let rampLength = min(Int(declickFrameCount), Int(buffer.frameLength))
        guard rampLength > 0 else { return }
        for channel in 0..<channelCount {
            guard let channelData = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<rampLength {
                channelData[frame] *= Float(frame) / Float(rampLength)
            }
        }
    }

    /// Schedules a segment with a declick fade-in on the first few frames.
    /// Reads the initial samples into a buffer, applies a linear ramp from 0→1,
    /// then schedules the remainder as a normal segment.
    private func scheduleDeclickedSegment(
        player: AVAudioPlayerNode,
        audioFile: AVAudioFile,
        startingFrame: AVAudioFramePosition,
        frameCount: AVAudioFrameCount
    ) {
        let declickFrames = min(Self.declickFrameCount, frameCount)
        let format = audioFile.processingFormat

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: declickFrames) else {
            player.scheduleSegment(audioFile, startingFrame: startingFrame, frameCount: frameCount, at: nil)
            return
        }

        audioFile.framePosition = startingFrame
        do {
            try audioFile.read(into: buffer, frameCount: declickFrames)
        } catch {
            player.scheduleSegment(audioFile, startingFrame: startingFrame, frameCount: frameCount, at: nil)
            return
        }

        Self.applyDeclickFadeIn(to: buffer)
        player.scheduleBuffer(buffer)

        let remainingFrames = frameCount - declickFrames
        if remainingFrames > 0 {
            player.scheduleSegment(
                audioFile,
                startingFrame: startingFrame + AVAudioFramePosition(declickFrames),
                frameCount: remainingFrames,
                at: nil
            )
        }
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
        var isFirst = true

        while position < endPosition {
            let positionInLoop = position % fileLengthSamples
            let remainingInLoop = fileLengthSamples - positionInLoop
            let remainingInContainer = endPosition - position
            let framesToPlay = min(remainingInLoop, remainingInContainer)

            guard framesToPlay > 0 else { break }

            if isFirst {
                scheduleDeclickedSegment(
                    player: player,
                    audioFile: audioFile,
                    startingFrame: AVAudioFramePosition(positionInLoop),
                    frameCount: AVAudioFrameCount(framesToPlay)
                )
                isFirst = false
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

        // Apply declick when starting outside the container's enter fade region
        let enterFadeSamples = enterFade.map { Int64($0.duration * samplesPerBar) } ?? 0
        if containerPosition >= enterFadeSamples {
            Self.applyDeclickFadeIn(to: buffer)
        }

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
        var isFirst = true

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

                // Declick when starting outside the enter fade region
                if isFirst && position >= enterFadeSamples {
                    Self.applyDeclickFadeIn(to: buffer)
                }

                player.scheduleBuffer(buffer)
            } else {
                if isFirst {
                    scheduleDeclickedSegment(
                        player: player,
                        audioFile: audioFile,
                        startingFrame: AVAudioFramePosition(positionInLoop),
                        frameCount: AVAudioFrameCount(framesToPlay)
                    )
                } else {
                    player.scheduleSegment(
                        audioFile,
                        startingFrame: AVAudioFramePosition(positionInLoop),
                        frameCount: AVAudioFrameCount(framesToPlay),
                        at: nil
                    )
                }
            }

            isFirst = false
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

        let startTime = Date()

        lock.lock()
        playbackStartBar = fromBar
        playbackStartTime = startTime
        lock.unlock()

        let secondsPerBeat = 60.0 / bpm
        let beatsPerBar = Double(timeSignature.beatsPerBar)
        let secondsPerBar = beatsPerBar * secondsPerBeat

        // Capture all state upfront — timer handler must not access self
        lock.lock()
        let capturedTrackMixers = self.trackMixers
        let capturedMasterMixer = self.masterMixerNode
        let capturedContainerSubgraphs = self.containerSubgraphs
        let capturedTrackEffectUnits = self.trackEffectUnits
        // Build per-track instrument unit list from container subgraphs
        var trackInstrumentUnits: [ID<Track>: [AVAudioUnit]] = [:]
        for track in song.tracks where track.kind == .midi {
            var units: [AVAudioUnit] = []
            for container in track.containers {
                if let subgraph = self.containerSubgraphs[container.id],
                   let instUnit = subgraph.instrumentUnit {
                    units.append(instUnit)
                }
            }
            if !units.isEmpty {
                trackInstrumentUnits[track.id] = units
            }
        }
        lock.unlock()
        let startBar = fromBar

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        // Evaluate at ~60 Hz (every ~16ms) for smooth parameter updates
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler {
            let elapsed = Date().timeIntervalSince(startTime)
            let currentBar = startBar + elapsed / secondsPerBar

            // Evaluate container-level automation
            for container in containersWithAutomation {
                let containerStartBar = Double(container.startBar)
                let containerEndBar = Double(container.endBar)

                // Only evaluate if current playback is within this container
                guard currentBar >= containerStartBar && currentBar < containerEndBar else { continue }

                let barOffset = currentBar - containerStartBar
                for lane in container.automationLanes {
                    if let value = lane.interpolatedValue(atBar: barOffset) {
                        // Inline parameter setting using captured state
                        if let containerID = lane.targetPath.containerID {
                            if let subgraph = capturedContainerSubgraphs[containerID] {
                                let units = subgraph.effectUnits
                                if lane.targetPath.effectIndex >= 0,
                                   lane.targetPath.effectIndex < units.count {
                                    let unit = units[lane.targetPath.effectIndex]
                                    unit.auAudioUnit.parameterTree?.parameter(
                                        withAddress: AUParameterAddress(lane.targetPath.parameterAddress)
                                    )?.value = value
                                }
                            }
                        } else {
                            if let units = capturedTrackEffectUnits[lane.targetPath.trackID] {
                                if lane.targetPath.effectIndex >= 0,
                                   lane.targetPath.effectIndex < units.count {
                                    let unit = units[lane.targetPath.effectIndex]
                                    unit.auAudioUnit.parameterTree?.parameter(
                                        withAddress: AUParameterAddress(lane.targetPath.parameterAddress)
                                    )?.value = value
                                }
                            }
                        }
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
                    } else if lane.targetPath.isTrackEffectParameter {
                        // Track-level effect parameter automation
                        if let units = capturedTrackEffectUnits[track.id] {
                            let idx = lane.targetPath.effectIndex
                            if idx >= 0 && idx < units.count {
                                units[idx].auAudioUnit.parameterTree?.parameter(
                                    withAddress: AUParameterAddress(lane.targetPath.parameterAddress)
                                )?.value = value
                            }
                        }
                    } else if lane.targetPath.isTrackInstrumentParameter {
                        // Track instrument parameter automation — apply to all container instrument units
                        if let units = trackInstrumentUnits[track.id] {
                            let addr = AUParameterAddress(lane.targetPath.parameterAddress)
                            for unit in units {
                                unit.auAudioUnit.parameterTree?.parameter(withAddress: addr)?.value = value
                            }
                        }
                    }
                }
            }
        }
        timer.resume()
        lock.lock()
        automationTimer = timer
        lock.unlock()
    }

    private func stopAutomationTimer() {
        lock.lock()
        let timer = automationTimer
        automationTimer = nil
        playbackStartTime = nil
        lock.unlock()
        timer?.cancel()
    }
}

// MARK: - ParameterResolver

extension PlaybackScheduler: ParameterResolver {
    public func setParameter(at path: EffectPath, value: Float) -> Bool {
        lock.lock()
        // Instrument parameter: apply to all container instrument units on the track
        if path.isTrackInstrumentParameter {
            var didSet = false
            let addr = AUParameterAddress(path.parameterAddress)
            for (_, subgraph) in containerSubgraphs {
                if subgraph.trackMixer == trackMixers[path.trackID],
                   let instUnit = subgraph.instrumentUnit,
                   let param = instUnit.auAudioUnit.parameterTree?.parameter(withAddress: addr) {
                    param.value = value
                    didSet = true
                }
            }
            lock.unlock()
            return didSet
        }

        let unit: AVAudioUnit?
        if let containerID = path.containerID {
            if let subgraph = containerSubgraphs[containerID] {
                let units = subgraph.effectUnits
                unit = (path.effectIndex >= 0 && path.effectIndex < units.count)
                    ? units[path.effectIndex] : nil
            } else {
                unit = nil
            }
        } else {
            if let units = trackEffectUnits[path.trackID] {
                unit = (path.effectIndex >= 0 && path.effectIndex < units.count)
                    ? units[path.effectIndex] : nil
            } else {
                unit = nil
            }
        }
        lock.unlock()

        guard let unit else { return false }
        guard let param = unit.auAudioUnit.parameterTree?.parameter(
            withAddress: AUParameterAddress(path.parameterAddress)
        ) else { return false }
        param.value = value
        return true
    }
}

// MARK: - ContainerTriggerDelegate

extension PlaybackScheduler: ContainerTriggerDelegate {
    public func triggerStart(containerID: ID<Container>) {
        lock.lock()
        let song = currentSong
        let alreadyActive = activeContainers.contains(where: { $0.id == containerID })
        let bpm = currentBPM
        let ts = currentTimeSignature
        let sr = currentSampleRate
        lock.unlock()

        guard let song, !alreadyActive else { return }
        let allContainers = song.tracks.flatMap(\.containers)
        for track in song.tracks {
            guard let container = track.containers.first(where: { $0.id == containerID }) else { continue }
            let resolved = container.resolved { id in allContainers.first(where: { $0.id == id }) }
            let spb = samplesPerBar(bpm: bpm, timeSignature: ts, sampleRate: sr)
            scheduleContainer(
                container: resolved,
                fromBar: Double(resolved.startBar),
                samplesPerBar: spb
            )
            return
        }
    }

    public func triggerStop(containerID: ID<Container>) {
        lock.lock()
        let subgraph = containerSubgraphs[containerID]
        let index = activeContainers.firstIndex(where: { $0.id == containerID })
        var container: Container?
        var trackIDToUnsuppress: ID<Track>?
        if let index {
            container = activeContainers[index]
            activeContainers.remove(at: index)

            if let trackID = containerToTrack[containerID] {
                let hasOtherActive = activeContainers.contains { containerToTrack[$0.id] == trackID }
                if !hasOtherActive {
                    tracksWithActiveContainers.remove(trackID)
                    trackIDToUnsuppress = trackID
                }
            }
        }
        lock.unlock()

        subgraph?.playerNode.stop()
        if let container {
            actionDispatcher?.containerDidExit(container)
        }
        if let trackID = trackIDToUnsuppress {
            inputMonitor?.unsuppressMonitoring(trackID: trackID)
        }
    }

    public func setRecordArmed(containerID: ID<Container>, armed: Bool) {
        onRecordArmedChanged?(containerID, armed)
    }
}
