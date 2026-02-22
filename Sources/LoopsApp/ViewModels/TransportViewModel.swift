import SwiftUI
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

    private let transport: TransportManager
    private let engineManager: AudioEngineManager?
    private var playbackScheduler: PlaybackScheduler?
    private var containerRecorder: ContainerRecorder?
    private var playbackGeneration = 0
    private var playbackTask: Task<Void, Never>?
    /// Tracks the last prepared song so we can skip re-preparing when unchanged.
    private var lastPreparedSong: Song?
    private var lastPreparedRecordingIDs: Set<ID<SourceRecording>> = []

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

    public init(transport: TransportManager, engineManager: AudioEngineManager? = nil) {
        self.transport = transport
        self.engineManager = engineManager
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
        let previousTask = playbackTask
        previousTask?.cancel()
        let scheduler = playbackScheduler
        playbackTask = Task {
            _ = await previousTask?.value
            scheduler?.stop()
        }
        engineManager?.metronome?.setEnabled(false)
        transport.pause()
        syncFromTransport()
    }

    public func stop() {
        playbackGeneration += 1
        stopContainerRecording()
        let previousTask = playbackTask
        previousTask?.cancel()
        let scheduler = playbackScheduler
        playbackTask = Task {
            _ = await previousTask?.value
            scheduler?.stop()
        }
        engineManager?.metronome?.setEnabled(false)
        engineManager?.metronome?.reset()
        transport.stop()
        syncFromTransport()
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
        transport.setPlayheadPosition(bar)
        syncFromTransport()
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
        playbackGeneration += 1
        let wasPlaying = isPlaying
        if wasPlaying {
            stopContainerRecording()
            let previousTask = playbackTask
            previousTask?.cancel()
            let scheduler = playbackScheduler
            playbackTask = Task {
                _ = await previousTask?.value
                scheduler?.stop()
            }
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

    /// Serializes playback Tasks so only one prepare() runs at a time.
    /// Each new Task awaits the previous one before starting, preventing
    /// concurrent cleanup/prepare races on the audio graph.
    ///
    /// Skips the expensive `prepare()` call (which stops/starts the engine)
    /// when the song and recordings haven't changed since the last prepare.
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
        let previousTask = playbackTask
        previousTask?.cancel()
        let needsPrepare = song != lastPreparedSong
            || Set(recordings.keys) != lastPreparedRecordingIDs
        playbackTask = Task {
            _ = await previousTask?.value
            guard self.playbackGeneration == gen else { return }
            if needsPrepare {
                await scheduler?.prepare(song: song, sourceRecordings: recordings)
                guard self.playbackGeneration == gen else { return }
                self.lastPreparedSong = song
                self.lastPreparedRecordingIDs = Set(recordings.keys)
            } else {
                scheduler?.stop()
            }
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
        guard isRecordArmed else { return }

        // Collect armed containers from audio tracks
        var armed: [(containerID: ID<Container>, trackID: ID<Track>, startBar: Int, endBar: Int)] = []
        for track in song.tracks where track.kind == .audio {
            for container in track.containers where container.isRecordArmed {
                armed.append((container.id, track.id, container.startBar, container.endBar))
            }
        }
        guard !armed.isEmpty, let engine = engineManager else { return }

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
        isPlaying = transport.state == .playing || transport.state == .recording
        isCountingIn = transport.state == .countingIn
        isRecordArmed = transport.isRecordArmed
        isMetronomeEnabled = transport.isMetronomeEnabled
        let bar = transport.playheadBar
        playheadBar = bar
        onPlayheadChanged?(bar)
        countInBarsRemaining = transport.countInBarsRemaining
    }
}
