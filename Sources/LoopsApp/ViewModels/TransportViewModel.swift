import SwiftUI
import AVFoundation
import LoopsCore
import LoopsEngine

/// Bridges TransportManager state to the SwiftUI view layer.
@Observable
@MainActor
public final class TransportViewModel {
    public var isPlaying: Bool = false
    public var isRecordArmed: Bool = false
    public var isMetronomeEnabled: Bool = false
    public var playheadBar: Double = 1.0
    public var bpm: Double = 120.0
    public var timeSignature: TimeSignature = TimeSignature()
    public var countInBars: Int = 0
    public var isCountingIn: Bool = false
    public var countInBarsRemaining: Int = 0
    public var metronomeVolume: Float = 0.8
    public var metronomeSubdivision: MetronomeSubdivision = .quarter
    public var metronomeOutputPortID: String?

    /// Container IDs whose effect chains failed to connect during the last graph build.
    /// Updated after each `prepare`/`prepareIncremental` cycle.
    public var failedContainerIDs: Set<ID<Container>> = []

    /// When true, stop returns playhead to where play was last pressed.
    /// Persisted across sessions via UserDefaults.
    public var returnToStartEnabled: Bool = true {
        didSet { UserDefaults.standard.set(returnToStartEnabled, forKey: "returnToStartEnabled") }
    }

    /// Set by the view layer when the setlist is in perform mode.
    /// Return-to-start is bypassed during perform mode.
    public var isPerformMode: Bool = false

    private let transport: TransportManager
    private let engineManager: AudioEngineManager?
    /// Audio graph scheduler. Exposed as private(set) so the MIDI input
    /// callback can call forwardExternalMIDI() without hopping to MainActor.
    /// Writes are @MainActor-only; the scheduler's internal lock protects
    /// concurrent reads. PlaybackScheduler is @unchecked Sendable.
    private(set) var playbackScheduler: PlaybackScheduler?
    private var containerRecorder: ContainerRecorder?
    private var playbackGeneration = 0
    private var playbackTask: Task<Void, Never>?

    /// Closure to fetch the current song context for playback.
    /// Set by the view layer so play() always uses the latest data.
    public var songProvider: (() -> (song: Song, recordings: [ID<SourceRecording>: SourceRecording], audioDir: URL)?)?

    /// Direct callback for playhead changes. Avoids SwiftUI observation overhead
    /// by routing updates outside the view re-evaluation cycle.
    public var onPlayheadChanged: ((Double) -> Void)?

    /// Called when waveform peaks are updated during recording.
    /// Parameters: containerID, peaks array.
    public var onRecordingPeaksUpdated: ((ID<Container>, [Float]) -> Void)?

    /// Called when recording completes for a container.
    /// Parameters: trackID, containerID, SourceRecording.
    public var onRecordingComplete: ((ID<Track>, ID<Container>, SourceRecording) -> Void)?

    /// Called when a per-track level update is available.
    /// Dispatched from the audio render thread — callers should dispatch to main.
    public var onTrackLevelUpdate: ((ID<Track>, Float) -> Void)?

    public init(transport: TransportManager, engineManager: AudioEngineManager? = nil) {
        self.transport = transport
        self.engineManager = engineManager
        // Restore persisted return-to-start preference (defaults to true)
        if UserDefaults.standard.object(forKey: "returnToStartEnabled") != nil {
            self.returnToStartEnabled = UserDefaults.standard.bool(forKey: "returnToStartEnabled")
        }
        syncFromTransport()
        transport.onPositionUpdate = { [weak self] bar in
            Task { @MainActor [weak self] in
                self?.playheadBar = bar
                self?.onPlayheadChanged?(bar)
            }
        }
        transport.onCountInComplete = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isCountingIn = false
                self.countInBarsRemaining = 0

                // Hold playhead until audio is actually scheduled and playing
                self.transport.beginWaitForAudioSync()

                // Now start actual audio playback and recording
                if let engine = self.engineManager, let context = self.songProvider?() {
                    self.schedulePlayback(
                        scheduler: self.playbackScheduler,
                        song: context.song,
                        recordings: context.recordings,
                        fromBar: self.playheadBar,
                        bpm: self.bpm,
                        timeSignature: self.timeSignature,
                        sampleRate: engine.currentSampleRate
                    )
                } else {
                    // No engine — let playhead start immediately
                    self.transport.completeAudioSync()
                }
                self.syncFromTransport()
            }
        }
        transport.onCountInTick = { [weak self] remaining in
            Task { @MainActor [weak self] in
                self?.countInBarsRemaining = remaining
            }
        }
    }

    public func play() {
        playbackGeneration += 1
        transport.bpm = bpm
        transport.timeSignature = timeSignature
        transport.countInBars = countInBars

        // Start audio engine when playing (needed for metronome and future playback)
        if let engine = engineManager {
            if !engine.isRunning {
                try? engine.start()
            }
            // Update metronome parameters
            engine.metronome?.update(
                bpm: bpm,
                beatsPerBar: timeSignature.beatsPerBar,
                sampleRate: engine.currentSampleRate
            )
            engine.metronome?.setVolume(metronomeVolume)
            engine.metronome?.setSubdivision(activeSubdivision(atBar: playheadBar))
            engine.metronome?.reset()

            // If count-in is active, always enable metronome during count-in
            if isRecordArmed && countInBars > 0 {
                engine.metronome?.setEnabled(true)
            } else {
                engine.metronome?.setEnabled(isMetronomeEnabled)
            }

            // Only schedule audio playback immediately if NOT counting in
            if !(isRecordArmed && countInBars > 0) {
                if let context = songProvider?() {
                    if playbackScheduler == nil {
                        let scheduler = PlaybackScheduler(engine: engine.engine, audioDirURL: context.audioDir)
                        let dispatcher = ActionDispatcher(midiOutput: CoreMIDIOutput())
                        dispatcher.triggerDelegate = scheduler
                        dispatcher.parameterResolver = scheduler
                        scheduler.actionDispatcher = dispatcher
                        scheduler.inputMonitor = engine.inputMonitor
                        scheduler.onTrackLevelUpdate = onTrackLevelUpdate
                        scheduler.onEffectChainStatusChanged = { [weak self] failedIDs in
                            Task { @MainActor [weak self] in
                                self?.failedContainerIDs = failedIDs
                            }
                        }
                        playbackScheduler = scheduler
                    }
                    schedulePlayback(
                        scheduler: playbackScheduler,
                        song: context.song,
                        recordings: context.recordings,
                        fromBar: playheadBar,
                        bpm: bpm,
                        timeSignature: timeSignature,
                        sampleRate: engine.currentSampleRate
                    )
                    // Wait for audio sync — playhead holds until
                    // schedulePlayback task calls completeAudioSync
                    transport.play(waitForAudioSync: true)
                    syncFromTransport()
                    return
                }
            } else {
                // Ensure scheduler exists for when count-in completes
                if let context = songProvider?() {
                    if playbackScheduler == nil {
                        let scheduler = PlaybackScheduler(engine: engine.engine, audioDirURL: context.audioDir)
                        let dispatcher = ActionDispatcher(midiOutput: CoreMIDIOutput())
                        dispatcher.triggerDelegate = scheduler
                        dispatcher.parameterResolver = scheduler
                        scheduler.actionDispatcher = dispatcher
                        scheduler.inputMonitor = engine.inputMonitor
                        scheduler.onTrackLevelUpdate = onTrackLevelUpdate
                        scheduler.onEffectChainStatusChanged = { [weak self] failedIDs in
                            Task { @MainActor [weak self] in
                                self?.failedContainerIDs = failedIDs
                            }
                        }
                        playbackScheduler = scheduler
                    }
                }
            }
        }

        transport.play()
        syncFromTransport()
    }

    public func pause() {
        playbackGeneration += 1
        stopContainerRecording()
        playbackTask?.cancel()
        playbackTask = nil
        // Stop the scheduler synchronously — don't queue behind SwiftUI work.
        // The ~8ms declick fade is acceptable for a user-initiated pause.
        playbackScheduler?.stop()
        engineManager?.metronome?.setEnabled(false)
        transport.pause()
        syncFromTransport()
    }

    public func stop() {
        playbackGeneration += 1
        stopContainerRecording()
        playbackTask?.cancel()
        playbackTask = nil
        // Stop the scheduler synchronously for immediate audio silence.
        playbackScheduler?.stop()
        engineManager?.metronome?.setEnabled(false)
        engineManager?.metronome?.reset()
        // In perform mode, always return to bar 1 (bypass return-to-start)
        transport.returnToStartEnabled = returnToStartEnabled && !isPerformMode
        transport.stop()
        syncFromTransport()
    }

    /// Handles a song switch: resets playhead to bar 1 and, if playback was
    /// active, stops the current audio graph and restarts playback on the new song.
    public func handleSongChanged() {
        let wasPlaying = isPlaying || isCountingIn

        if wasPlaying {
            // Stop current playback and scheduler synchronously
            playbackGeneration += 1
            stopContainerRecording()
            playbackTask?.cancel()
            playbackTask = nil
            playbackScheduler?.stop()
            engineManager?.metronome?.setEnabled(false)
            engineManager?.metronome?.reset()
            transport.pause()
        }

        // Reset playhead to bar 1
        transport.setPlayheadPosition(1.0)
        // Invalidate the scheduler's graph so it rebuilds for the new song
        playbackScheduler?.invalidatePreparedState()
        syncFromTransport()

        if wasPlaying {
            // Restart playback on the new song from bar 1
            play()
        }
    }

    public func togglePlayPause() {
        if isPlaying || isCountingIn {
            pause()
        } else {
            play()
        }
    }

    public func toggleRecordArm() {
        transport.toggleRecordArm()
        syncFromTransport()
    }

    public func toggleMetronome() {
        transport.toggleMetronome()
        syncFromTransport()

        // If currently playing, immediately update metronome output
        if isPlaying {
            engineManager?.metronome?.setEnabled(isMetronomeEnabled)
        }
    }

    /// Sets the metronome volume (clamped 0.0–1.0).
    public func setMetronomeVolume(_ volume: Float) {
        metronomeVolume = min(max(volume, 0.0), 1.0)
        engineManager?.metronome?.setVolume(metronomeVolume)
    }

    /// Sets the default metronome subdivision.
    public func setMetronomeSubdivision(_ subdivision: MetronomeSubdivision) {
        metronomeSubdivision = subdivision
        engineManager?.metronome?.setSubdivision(subdivision)
    }

    /// Routes the metronome to a specific output port (nil = main mixer).
    public func setMetronomeOutputPort(_ portID: String?) {
        metronomeOutputPortID = portID
        engineManager?.setMetronomeOutputPort(portID)
    }

    /// Applies a MetronomeConfig to the transport (volume, subdivision, output routing).
    public func applyMetronomeConfig(_ config: MetronomeConfig) {
        setMetronomeVolume(config.volume)
        setMetronomeSubdivision(config.subdivision)
        setMetronomeOutputPort(config.outputPortID)
    }

    public func setPlayheadPosition(_ bar: Double) {
        let start = CFAbsoluteTimeGetCurrent()
        transport.setPlayheadPosition(bar)
        syncFromTransport()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("[PERF] setPlayheadPosition(\(bar)): \(String(format: "%.1f", ms))ms")
    }

    /// Updates a single track's volume/pan in the live audio graph without
    /// touching the model. Used during continuous slider gestures to avoid
    /// triggering full SwiftUI view re-evaluation.
    public func updateTrackMixLive(trackID: ID<Track>, volume: Float, pan: Float) {
        playbackScheduler?.updateTrackMix(trackID: trackID, volume: volume, pan: pan, isMuted: false)
    }

    /// Pushes current mute/solo state to the live audio graph.
    /// Call after toggling mute or solo on any track.
    public func updateMuteSoloState(tracks: [Track]) {
        guard let scheduler = playbackScheduler else { return }
        let hasSolo = tracks.contains { $0.isSoloed }
        for track in tracks {
            guard track.kind != .master else { continue }
            let effectivelyMuted = track.isMuted
                || (hasSolo && !track.isSoloed)
            scheduler.updateTrackMix(
                trackID: track.id,
                volume: track.volume,
                pan: track.pan,
                isMuted: effectivelyMuted
            )
        }
    }

    /// Seeks to a new bar position. If currently playing, stops and restarts
    /// playback from the new position so audio is rescheduled.
    public func seek(toBar bar: Double) {
        let seekStart = CFAbsoluteTimeGetCurrent()
        playbackGeneration += 1
        let wasPlaying = isPlaying
        if wasPlaying {
            stopContainerRecording()
            playbackTask?.cancel()
            playbackTask = nil
            // Stop synchronously with skipDeclick — we're about to restart playback
            playbackScheduler?.stop(skipDeclick: true)
            engineManager?.metronome?.reset()
            transport.pause()
        }

        transport.setPlayheadPosition(bar)
        syncFromTransport()

        if wasPlaying, let engine = engineManager, let context = songProvider?() {
            engine.metronome?.update(
                bpm: bpm,
                beatsPerBar: timeSignature.beatsPerBar,
                sampleRate: engine.currentSampleRate
            )
            engine.metronome?.setVolume(metronomeVolume)
            engine.metronome?.setSubdivision(activeSubdivision(atBar: playheadBar))
            engine.metronome?.reset()
            engine.metronome?.setEnabled(isMetronomeEnabled)

            schedulePlayback(
                scheduler: playbackScheduler,
                song: context.song,
                recordings: context.recordings,
                fromBar: playheadBar,
                bpm: bpm,
                timeSignature: timeSignature,
                sampleRate: engine.currentSampleRate
            )
            transport.play(waitForAudioSync: true)
            syncFromTransport()
        }
        let seekMs = (CFAbsoluteTimeGetCurrent() - seekStart) * 1000
        print("[PERF] seek(toBar: \(bar)): \(String(format: "%.1f", seekMs))ms wasPlaying=\(wasPlaying)")
    }

    public func updateBPM(_ newBPM: Double) {
        bpm = min(max(newBPM, 20.0), 300.0)
        transport.bpm = bpm
        // Live-update metronome BPM if playing
        if isPlaying {
            engineManager?.metronome?.update(
                bpm: bpm,
                beatsPerBar: timeSignature.beatsPerBar,
                sampleRate: engineManager?.currentSampleRate ?? 44100.0
            )
        }
    }

    /// Enables or disables input monitoring for a track through the audio engine.
    public func setInputMonitoring(track: Track, enabled: Bool) {
        // Only audio tracks use hardware input monitoring. MIDI tracks hear
        // their instrument directly — routing the mic input would double the signal.
        guard track.kind == .audio else { return }
        guard let engine = engineManager else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        guard let monitor = engine.inputMonitor else { return }

        // Monitoring modifies the engine graph on a running engine.
        // Invalidate the scheduler's graph fingerprints so the next play()
        // triggers a full prepare() (engine stop → graph rebuild → restart).
        playbackScheduler?.invalidatePreparedState()

        if enabled {
            Task {
                await monitor.enableMonitoring(
                    trackID: track.id,
                    insertEffects: track.insertEffects,
                    volume: track.volume,
                    pan: track.pan
                )
            }
        } else {
            monitor.disableMonitoring(trackID: track.id)
        }
    }

    /// Sends a MIDI note event to the instrument on the given track.
    /// Used by the virtual keyboard for live note input.
    public func sendVirtualNote(trackID: ID<Track>, message: MIDIActionMessage) {
        playbackScheduler?.sendMIDINoteToTrack(trackID, message: message)
    }

    /// Returns the active subdivision for a given bar position.
    /// Checks master track containers for MetronomeSettings overrides;
    /// falls back to the default metronome subdivision.
    private func activeSubdivision(atBar bar: Double) -> MetronomeSubdivision {
        guard let context = songProvider?() else { return metronomeSubdivision }
        let song = context.song
        guard let masterTrack = song.masterTrack else { return metronomeSubdivision }

        // Find the master track container at the current bar position
        let barInt = Int(bar)
        for container in masterTrack.containers {
            if container.startBar <= barInt && container.endBar > barInt,
               let settings = container.metronomeSettings {
                return settings.subdivision
            }
        }
        return metronomeSubdivision
    }

    /// Sets a parameter value on the active PlaybackScheduler's ParameterResolver.
    /// Used for real-time MIDI CC → parameter control.
    @discardableResult
    public func setParameter(at path: EffectPath, value: Float) -> Bool {
        return playbackScheduler?.setParameter(at: path, value: value) ?? false
    }

    /// Returns the engine's live AVAudioUnit for a container-level effect, if playback is prepared.
    public func liveEffectUnit(containerID: ID<Container>, effectIndex: Int) -> AVAudioUnit? {
        playbackScheduler?.liveEffectUnit(containerID: containerID, effectIndex: effectIndex)
    }

    /// Returns the engine's live AVAudioUnit for a track-level effect, if playback is prepared.
    public func liveTrackEffectUnit(trackID: ID<Track>, effectIndex: Int) -> AVAudioUnit? {
        playbackScheduler?.liveTrackEffectUnit(trackID: trackID, effectIndex: effectIndex)
    }

    /// Returns the engine's live AVAudioUnit for a master track effect, if playback is prepared.
    public func liveMasterEffectUnit(effectIndex: Int) -> AVAudioUnit? {
        playbackScheduler?.liveMasterEffectUnit(effectIndex: effectIndex)
    }

    /// Registers a newly completed recording with the running scheduler and
    /// schedules all linked containers that now have audio available.
    /// Called by ProjectViewModel.onRecordingPropagated after recording
    /// propagation updates the model.
    public func registerAndScheduleLinkedContainers(
        recordingID: ID<SourceRecording>,
        filename: String,
        linkedContainers: [Container]
    ) {
        guard let scheduler = playbackScheduler,
              let context = songProvider?() else { return }
        let fileURL = context.audioDir.appendingPathComponent(filename)
        guard let file = try? AVAudioFile(forReading: fileURL) else { return }
        scheduler.registerRecording(id: recordingID, file: file)
        for container in linkedContainers {
            scheduler.scheduleLinkedContainer(container: container)
        }
    }

    /// Incrementally updates the audio graph during playback when effects,
    /// instruments, or containers change. Only rebuilds the affected tracks'
    /// subgraphs — unchanged tracks continue playing without interruption.
    ///
    /// Call this after modifying a track's effects/instruments while playback
    /// is active. If not currently playing, marks the graph as stale so the
    /// next play() triggers a full prepare.
    public func refreshPlaybackGraph() {
        guard isPlaying, let scheduler = playbackScheduler,
              let engine = engineManager, let context = songProvider?() else {
            // Not playing — just invalidate the cache so next play() rebuilds
            playbackScheduler?.invalidatePreparedState()
            return
        }

        let gen = playbackGeneration
        let previousTask = playbackTask
        previousTask?.cancel()
        playbackTask = Task {
            _ = await previousTask?.value
            guard self.playbackGeneration == gen else { return }

            let currentBar = scheduler.currentPlaybackBar() ?? self.playheadBar
            let changedTracks = await scheduler.prepareIncremental(
                song: context.song,
                sourceRecordings: context.recordings
            )
            guard self.playbackGeneration == gen else { return }
            // Re-install taps on any newly created track mixers
            scheduler.installTrackLevelTaps()

            if !changedTracks.isEmpty {
                // Invalidate open plugin windows — the graph rebuild created
                // new AU instances, so any open window is pointing at a stale AU.
                PluginWindowManager.shared.invalidateAll()

                scheduler.playChangedTracks(
                    changedTracks,
                    song: context.song,
                    fromBar: currentBar,
                    bpm: self.bpm,
                    timeSignature: self.timeSignature,
                    sampleRate: engine.currentSampleRate
                )
            }
        }
    }

    /// Serializes playback Tasks so only one prepare() runs at a time.
    /// Each new Task awaits the previous one before starting, preventing
    /// concurrent cleanup/prepare races on the audio graph.
    ///
    /// Skips the expensive `prepare()` call (which stops/starts the engine)
    /// when the audio graph shape hasn't changed (effects, instruments,
    /// container audio assignments). Cosmetic changes like renaming, volume,
    /// pan, or container moves do NOT trigger a re-prepare.
    private func schedulePlayback(
        scheduler: PlaybackScheduler?,
        song: Song,
        recordings: [ID<SourceRecording>: SourceRecording],
        fromBar: Double,
        bpm: Double,
        timeSignature: TimeSignature,
        sampleRate: Double
    ) {
        let gen = playbackGeneration
        playbackTask?.cancel()
        // Use graph-shape fingerprints so cosmetic changes (rename, volume,
        // pan, container move) don't trigger a full audio-graph rebuild.
        let needsPrepare = scheduler?.needsPrepare(
            song: song,
            recordingIDs: Set(recordings.keys)
        ) ?? true
        let containerCount = song.tracks.flatMap(\.containers).count
        let recCount = recordings.count
        print("[PLAY] schedulePlayback: needsPrepare=\(needsPrepare) containers=\(containerCount) recordings=\(recCount)")
        let scheduleEnqueueTime = CFAbsoluteTimeGetCurrent()
        playbackTask = Task {
            let taskStart = CFAbsoluteTimeGetCurrent()
            let waitMs = (taskStart - scheduleEnqueueTime) * 1000
            guard self.playbackGeneration == gen else {
                print("[PERF] schedulePlayback: cancelled after \(String(format: "%.1f", waitMs))ms queued")
                return
            }
            if needsPrepare {
                print("[PLAY] calling prepare()")
                await scheduler?.prepare(song: song, sourceRecordings: recordings)
                guard self.playbackGeneration == gen else { return }
                // Install per-track level taps after graph is built
                scheduler?.installTrackLevelTaps()
            }
            // stop() was already called synchronously before this Task was created,
            // so we can proceed directly to play().
            guard self.playbackGeneration == gen else { return }
            scheduler?.play(
                song: song,
                fromBar: fromBar,
                bpm: bpm,
                timeSignature: timeSignature,
                sampleRate: sampleRate
            )

            // Start container recording after audio scheduling
            if let context = self.songProvider?() {
                self.startContainerRecordingIfNeeded(
                    song: context.song,
                    fromBar: fromBar,
                    bpm: bpm,
                    timeSignature: timeSignature,
                    sampleRate: sampleRate,
                    audioDir: context.audioDir
                )
            }

            // Audio player nodes are now started — calibrate the playhead
            // so it starts advancing in sync with audible output.
            let outputLatency = self.engineManager?.engine.outputNode.presentationLatency ?? 0
            self.transport.completeAudioSync(audioOutputLatency: outputLatency)
            self.syncFromTransport()

            let totalMs = (CFAbsoluteTimeGetCurrent() - taskStart) * 1000
            print("[PERF] schedulePlayback task: \(String(format: "%.1f", totalMs))ms (queued \(String(format: "%.1f", waitMs))ms, needsPrepare=\(needsPrepare))")
        }
    }

    /// Starts container recording if the transport is record-armed and the
    /// current song has armed containers on audio tracks.
    private func startContainerRecordingIfNeeded(
        song: Song,
        fromBar: Double,
        bpm: Double,
        timeSignature: TimeSignature,
        sampleRate: Double,
        audioDir: URL
    ) {
        print("[REC] startContainerRecordingIfNeeded called, isRecordArmed=\(isRecordArmed)")
        guard isRecordArmed else {
            print("[REC] BAIL: transport not record-armed")
            return
        }

        // Collect armed containers from audio tracks.
        // If individual containers are armed, use those.
        // Otherwise, if the track itself is armed, all its containers are candidates.
        var armed: [(containerID: ID<Container>, trackID: ID<Track>, startBar: Int, endBar: Int)] = []
        for track in song.tracks where track.kind == .audio {
            let containerArmed = track.containers.filter(\.isRecordArmed)
            if !containerArmed.isEmpty {
                for container in containerArmed {
                    print("[REC]   container '\(container.name)' armed (container-level) bars=\(container.startBar)-\(container.endBar)")
                    armed.append((container.id, track.id, container.startBar, container.endBar))
                }
            } else if track.isRecordArmed {
                for container in track.containers {
                    print("[REC]   container '\(container.name)' armed (track-level) bars=\(container.startBar)-\(container.endBar)")
                    armed.append((container.id, track.id, container.startBar, container.endBar))
                }
            }
        }
        guard !armed.isEmpty else {
            print("[REC] BAIL: no armed containers found")
            return
        }
        guard let engine = engineManager else {
            print("[REC] BAIL: no engine manager")
            return
        }

        print("[REC] Creating ContainerRecorder with \(armed.count) armed container(s), audioDir=\(audioDir.path)")
        let recorder = ContainerRecorder(engine: engine.engine, audioDirURL: audioDir)
        recorder.onPeaksUpdated = { [weak self] containerID, peaks in
            self?.onRecordingPeaksUpdated?(containerID, peaks)
        }
        recorder.onRecordingComplete = { [weak self] trackID, containerID, recording in
            self?.onRecordingComplete?(trackID, containerID, recording)
        }
        containerRecorder = recorder
        recorder.startMonitoring(
            armedContainers: armed,
            fromBar: fromBar,
            bpm: bpm,
            timeSignature: timeSignature,
            sampleRate: sampleRate
        )
    }

    /// Stops container recording if active.
    private func stopContainerRecording() {
        containerRecorder?.stopMonitoring()
        containerRecorder = nil
    }

    private func syncFromTransport() {
        let syncStart = CFAbsoluteTimeGetCurrent()
        isPlaying = transport.state == .playing || transport.state == .recording
        isCountingIn = transport.state == .countingIn
        isRecordArmed = transport.isRecordArmed
        isMetronomeEnabled = transport.isMetronomeEnabled
        let bar = transport.playheadBar
        playheadBar = bar
        onPlayheadChanged?(bar)
        countInBarsRemaining = transport.countInBarsRemaining
        let syncMs = (CFAbsoluteTimeGetCurrent() - syncStart) * 1000
        if syncMs > 1.0 {
            print("[PERF] syncFromTransport: \(String(format: "%.1f", syncMs))ms")
        }
    }
}
