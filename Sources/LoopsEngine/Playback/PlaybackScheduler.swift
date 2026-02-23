import Foundation
import AVFoundation
import CoreFoundation
import LoopsCore
import ObjCHelpers

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
    /// File URLs for recordings, used to create per-container file handles.
    private var recordingFileURLs: [ID<SourceRecording>: URL] = [:]
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

    /// Callback for per-track level meter updates.
    /// Called on the audio render thread; dispatch to main for UI updates.
    /// Parameters: trackID, peak level (0.0-1.0).
    public var onTrackLevelUpdate: ((ID<Track>, Float) -> Void)?

    /// Track IDs that currently have level taps installed.
    private var trackLevelTapIDs: Set<ID<Track>> = []

    /// Per-container audio subgraph.
    private struct ContainerSubgraph {
        let playerNode: AVAudioPlayerNode
        let instrumentUnit: AVAudioUnit?
        let effectUnits: [AVAudioUnit]
        let trackMixer: AVAudioMixerNode
        /// Per-container audio file handle. Each container gets its own
        /// AVAudioFile instance even when sharing a recording, because
        /// AVAudioFile's internal read cursor is not thread-safe.
        var audioFile: AVAudioFile?
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

    /// MIDI notes currently sounding (for sending note-off on stop).
    private var activeMIDINotes: [(trackID: ID<Track>, note: UInt8, channel: UInt8)] = []

    // MARK: - Graph Fingerprinting (for incremental updates)

    /// Fingerprint of an effect slot — captures what determines the audio graph shape.
    /// Preset data changes don't require graph rebuild (applied live), so not included.
    private struct EffectShapeFingerprint: Equatable {
        let component: AudioComponentInfo
    }

    /// Fingerprint of a container's graph shape — determines when the per-container
    /// subgraph (player → instrument → effects → mixer) needs rebuilding.
    private struct ContainerGraphFingerprint: Equatable {
        let id: ID<Container>
        let sourceRecordingID: ID<SourceRecording>?
        let effects: [EffectShapeFingerprint]
        let instrumentOverride: AudioComponentInfo?
        let parentContainerID: ID<Container>?
    }

    /// Fingerprint of a track's graph shape — determines when the per-track
    /// subgraph (track mixer → track effects → output target) needs rebuilding.
    private struct TrackGraphFingerprint: Equatable {
        let kind: TrackKind
        let effects: [EffectShapeFingerprint]
        let isEffectChainBypassed: Bool
        let containers: [ContainerGraphFingerprint]
        let instrumentComponent: AudioComponentInfo?

        static func from(_ track: Track, allContainers: [Container]) -> TrackGraphFingerprint {
            let effects: [EffectShapeFingerprint] = track.isEffectChainBypassed ? [] :
                track.insertEffects
                    .sorted(by: { $0.orderIndex < $1.orderIndex })
                    .filter { !$0.isBypassed }
                    .map { EffectShapeFingerprint(component: $0.component) }

            let containers = track.containers.map { container -> ContainerGraphFingerprint in
                let resolved = container.resolved { id in allContainers.first(where: { $0.id == id }) }
                let cEffects: [EffectShapeFingerprint] = resolved.isEffectChainBypassed ? [] :
                    resolved.insertEffects
                        .sorted(by: { $0.orderIndex < $1.orderIndex })
                        .filter { !$0.isBypassed }
                        .map { EffectShapeFingerprint(component: $0.component) }
                return ContainerGraphFingerprint(
                    id: container.id,
                    sourceRecordingID: resolved.sourceRecordingID,
                    effects: cEffects,
                    instrumentOverride: resolved.instrumentOverride,
                    parentContainerID: container.parentContainerID
                )
            }

            return TrackGraphFingerprint(
                kind: track.kind,
                effects: effects,
                isEffectChainBypassed: track.isEffectChainBypassed,
                containers: containers,
                instrumentComponent: track.instrumentComponent
            )
        }
    }

    /// Stored graph fingerprints from the last prepare() — used to diff and
    /// skip rebuilding unchanged tracks during incremental updates.
    private var preparedTrackFingerprints: [ID<Track>: TrackGraphFingerprint] = [:]
    private var preparedMasterFingerprint: TrackGraphFingerprint?

    /// Container IDs whose effect chains failed to connect during the last prepare.
    /// The UI uses this to show a red indicator on broken effects.
    private var _failedContainerIDs: Set<ID<Container>> = []

    /// Returns the set of container IDs whose effect chains failed to connect.
    public var failedContainerIDs: Set<ID<Container>> {
        lock.lock()
        defer { lock.unlock() }
        return _failedContainerIDs
    }

    /// Callback fired after `prepare`/`prepareIncremental` finishes, delivering
    /// the set of container IDs whose effect chains failed to connect.
    /// Called on the main actor.
    public var onEffectChainStatusChanged: ((Set<ID<Container>>) -> Void)?

    /// Whether playback is active (has been scheduled and not stopped).
    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return playbackStartTime != nil
    }

    /// Invalidates the prepared graph fingerprints, forcing the next
    /// `needsPrepare()` call to return `true`. Use after operations that
    /// may corrupt the engine topology (e.g. input monitoring toggles).
    public func invalidatePreparedState() {
        lock.lock()
        preparedTrackFingerprints.removeAll()
        preparedMasterFingerprint = nil
        lock.unlock()
    }

    /// Returns `true` when the audio graph needs rebuilding for this song.
    /// Compares graph-shape fingerprints (effects, instruments, container audio
    /// assignments) — cosmetic changes like renaming, volume, pan, or moving
    /// containers do NOT require a re-prepare.
    public func needsPrepare(song: Song, recordingIDs: Set<ID<SourceRecording>>) -> Bool {
        let allContainers = song.tracks.flatMap(\.containers)
        var newFingerprints: [ID<Track>: TrackGraphFingerprint] = [:]
        for track in song.tracks where track.kind != .master {
            newFingerprints[track.id] = TrackGraphFingerprint.from(track, allContainers: allContainers)
        }
        let newMasterFP = song.masterTrack.map { TrackGraphFingerprint.from($0, allContainers: allContainers) }

        lock.lock()
        let oldFingerprints = preparedTrackFingerprints
        let oldMasterFP = preparedMasterFingerprint
        let oldRecordingIDs = Set(audioFiles.keys)
        lock.unlock()

        if oldFingerprints.isEmpty && oldMasterFP == nil {
            return true // never prepared
        }
        if recordingIDs != oldRecordingIDs { return true }
        if newMasterFP != oldMasterFP { return true }
        if newFingerprints != oldFingerprints { return true }
        return false
    }

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
        let prepareStart = CFAbsoluteTimeGetCurrent()
        let allContainers = song.tracks.flatMap(\.containers)

        // ── Phase 1: Load files and audio units (async, engine keeps running) ──

        // Map recording IDs to file URLs for per-container file handle creation.
        // Each container gets its own AVAudioFile instance because AVAudioFile's
        // internal read cursor is not thread-safe across concurrent player nodes.
        var recordingFileURLs: [ID<SourceRecording>: URL] = [:]
        var loadedFiles: [ID<SourceRecording>: AVAudioFile] = [:]
        for (id, recording) in sourceRecordings {
            let fileURL = audioDirURL.appendingPathComponent(recording.filename)
            if let file = try? AVAudioFile(forReading: fileURL) {
                loadedFiles[id] = file
                recordingFileURLs[id] = fileURL
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
                } else {
                    print("[WARN] Failed to load AU: \(effect.displayName)")
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
                    } else {
                        print("[WARN] Failed to load AU: \(effect.displayName)")
                    }
                }
            }

            var preloadedContainers: [PreloadedContainer] = []
            for container in track.containers {
                guard !Task.isCancelled else { return }
                let resolved = container.resolved { id in allContainers.first(where: { $0.id == id }) }
                let hasAudio = resolved.sourceRecordingID != nil
                let hasMIDI = resolved.midiSequence != nil
                let isLinkedClone = container.parentContainerID != nil
                let needsInstrument = track.instrumentComponent != nil || resolved.instrumentOverride != nil

                // Skip containers without audio or MIDI unless they are linked clones
                // (linked clones get pre-allocated subgraphs so audio can be
                // registered mid-session when the parent finishes recording)
                // or the track has an instrument (MIDI tracks that need subgraphs).
                guard hasAudio || hasMIDI || isLinkedClone || needsInstrument else { continue }

                let fileFormat: AVAudioFormat?
                if let recID = resolved.sourceRecordingID {
                    fileFormat = loadedFiles[recID]?.processingFormat
                } else {
                    fileFormat = nil
                }

                var instrumentUnit: AVAudioUnit?
                if let override = resolved.instrumentOverride {
                    instrumentUnit = try? await audioUnitHost.loadAudioUnit(component: override)
                } else if let trackInstrument = track.instrumentComponent {
                    instrumentUnit = try? await audioUnitHost.loadAudioUnit(component: trackInstrument)
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
                        } else {
                            print("[WARN] Failed to load AU: \(effect.displayName)")
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

        // Install host musical context blocks on all preloaded AUs so
        // tempo-synced plugins can query BPM, time signature, and beat position.
        for unit in preloadedMasterEffects {
            installMusicalContext(on: unit)
        }
        for pt in preloadedTracks {
            for unit in pt.effects { installMusicalContext(on: unit) }
            for pc in pt.containers {
                if let inst = pc.instrument { installMusicalContext(on: inst) }
                for unit in pc.effects { installMusicalContext(on: unit) }
            }
        }

        // ── Phase 2: Stop engine, rebuild graph synchronously, restart ──
        // engine.connect() silently fails on a running engine, so we must
        // stop it for the attach/connect pass. This phase is fast (no awaits).

        let totalContainers = preloadedTracks.flatMap(\.containers).count
        let phase1Ms = (CFAbsoluteTimeGetCurrent() - prepareStart) * 1000
        print("[PERF] prepare phase1 (AU load): \(String(format: "%.1f", phase1Ms))ms — \(loadedFiles.count) files, \(preloadedTracks.count) tracks, \(totalContainers) containers")
        for pt in preloadedTracks {
            for pc in pt.containers {
                print("[PLAY]   container '\(pc.container.name)' id=\(pc.container.id) hasFormat=\(pc.audioFormat != nil) recID=\(pc.container.sourceRecordingID.map { "\($0)" } ?? "none")")
            }
        }

        let phase2Start = CFAbsoluteTimeGetCurrent()
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        defer { if wasRunning { try? engine.start() } }

        cleanup()

        lock.lock()
        audioFiles = loadedFiles
        self.recordingFileURLs = recordingFileURLs
        lock.unlock()

        var newFailedContainerIDs = Set<ID<Container>>()

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
                var chainConnected = true
                if chain.isEmpty {
                    engine.connect(player, to: trackMixer, format: playerFormat)
                } else {
                    // Use nil format for effect chain connections to let AU
                    // nodes auto-negotiate formats. Passing playerFormat here
                    // crashes (-10868) when a plugin doesn't support that
                    // format/channel-count. Wrap in ObjC try/catch since
                    // engine.connect() raises NSExceptions on failure.
                    var connectError: NSError?
                    let success = ObjCTryCatch({
                        self.engine.connect(player, to: chain[0], format: nil)
                        for i in 0..<(chain.count - 1) {
                            self.engine.connect(chain[i], to: chain[i + 1], format: nil)
                        }
                        self.engine.connect(chain[chain.count - 1], to: trackMixer, format: nil)
                    }, &connectError)
                    if !success {
                        print("[WARN] Effect chain connection failed for '\(pc.container.name)': \(connectError?.localizedDescription ?? "unknown")")
                        for node in chain { engine.detach(node) }
                        engine.connect(player, to: trackMixer, format: playerFormat)
                        chainConnected = false
                        newFailedContainerIDs.insert(pc.container.id)
                    }
                }

                // When the fallback fired, chain nodes were detached from the engine.
                // Store empty arrays so cleanup() doesn't try to disconnect them.
                let actualEffects = chainConnected ? pc.effects : []
                let actualInstrument = chainConnected ? pc.instrument : nil

                // Create a per-container AVAudioFile handle so player nodes
                // don't share a read cursor on the render thread.
                let containerAudioFile: AVAudioFile?
                if let recID = pc.container.sourceRecordingID,
                   let url = recordingFileURLs[recID] {
                    containerAudioFile = try? AVAudioFile(forReading: url)
                } else {
                    containerAudioFile = nil
                }

                lock.lock()
                containerSubgraphs[pc.container.id] = ContainerSubgraph(
                    playerNode: player,
                    instrumentUnit: actualInstrument,
                    effectUnits: actualEffects,
                    trackMixer: trackMixer,
                    audioFile: containerAudioFile
                )
                lock.unlock()
            }
        }

        lock.lock()
        _failedContainerIDs = newFailedContainerIDs
        lock.unlock()
        onEffectChainStatusChanged?(newFailedContainerIDs)

        // Store graph fingerprints for incremental comparison
        var newFingerprints: [ID<Track>: TrackGraphFingerprint] = [:]
        for track in song.tracks where track.kind != .master {
            newFingerprints[track.id] = TrackGraphFingerprint.from(track, allContainers: allContainers)
        }
        let masterFP = song.masterTrack.map { TrackGraphFingerprint.from($0, allContainers: allContainers) }
        lock.lock()
        preparedTrackFingerprints = newFingerprints
        preparedMasterFingerprint = masterFP
        lock.unlock()

        let phase2Ms = (CFAbsoluteTimeGetCurrent() - phase2Start) * 1000
        let totalMs = (CFAbsoluteTimeGetCurrent() - prepareStart) * 1000
        print("[PERF] prepare phase2 (engine rebuild): \(String(format: "%.1f", phase2Ms))ms — total: \(String(format: "%.1f", totalMs))ms")
    }

    /// Incrementally updates the audio graph, rebuilding only tracks whose
    /// effects, instruments, or containers have changed since the last prepare().
    /// Unchanged tracks continue playing without interruption.
    ///
    /// Returns the set of track IDs whose subgraphs were rebuilt.
    /// Empty set means nothing changed (no engine restart needed).
    @MainActor
    public func prepareIncremental(
        song: Song,
        sourceRecordings: [ID<SourceRecording>: SourceRecording]
    ) async -> Set<ID<Track>> {
        let allContainers = song.tracks.flatMap(\.containers)

        // Compute new fingerprints
        var newFingerprints: [ID<Track>: TrackGraphFingerprint] = [:]
        for track in song.tracks where track.kind != .master {
            newFingerprints[track.id] = TrackGraphFingerprint.from(track, allContainers: allContainers)
        }
        let newMasterFP = song.masterTrack.map { TrackGraphFingerprint.from($0, allContainers: allContainers) }

        // Compare against stored fingerprints
        lock.lock()
        let oldFingerprints = preparedTrackFingerprints
        let oldMasterFP = preparedMasterFingerprint
        lock.unlock()

        // If no previous fingerprints, fall back to full prepare
        guard !oldFingerprints.isEmpty else {
            await prepare(song: song, sourceRecordings: sourceRecordings)
            return Set(song.tracks.filter { $0.kind != .master }.map(\.id))
        }

        // Identify changed, added, and removed tracks
        var changedTrackIDs = Set<ID<Track>>()
        for (trackID, newFP) in newFingerprints {
            if oldFingerprints[trackID] != newFP {
                changedTrackIDs.insert(trackID)
            }
        }
        // Tracks in old but not in new = removed
        let removedTrackIDs = Set(oldFingerprints.keys).subtracting(Set(newFingerprints.keys))
        let masterChanged = newMasterFP != oldMasterFP

        let hasGraphChanges = !changedTrackIDs.isEmpty || !removedTrackIDs.isEmpty || masterChanged
        guard hasGraphChanges else {
            // Nothing changed — just update files and recording URLs
            var updatedURLs: [ID<SourceRecording>: URL] = [:]
            var updatedFiles: [ID<SourceRecording>: AVAudioFile] = [:]
            for (id, recording) in sourceRecordings {
                let fileURL = audioDirURL.appendingPathComponent(recording.filename)
                if let file = try? AVAudioFile(forReading: fileURL) {
                    updatedFiles[id] = file
                    updatedURLs[id] = fileURL
                }
            }
            lock.lock()
            audioFiles = updatedFiles
            recordingFileURLs = updatedURLs
            lock.unlock()
            return []
        }

        // ── Phase 1: Pre-load AU units for changed tracks (async, engine keeps running) ──

        var preloadedMasterEffects: [AVAudioUnit] = []
        if masterChanged {
            let masterTrack = song.masterTrack
            if let master = masterTrack, !master.isEffectChainBypassed {
                for effect in master.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                    guard !effect.isBypassed else { continue }
                    guard !Task.isCancelled else { return [] }
                    if let unit = try? await audioUnitHost.loadAudioUnit(component: effect.component) {
                        if let presetData = effect.presetData {
                            try? audioUnitHost.restoreState(audioUnit: unit, data: presetData)
                        }
                        preloadedMasterEffects.append(unit)
                    } else {
                        print("[WARN] Failed to load AU: \(effect.displayName)")
                    }
                }
            }
        }

        guard !Task.isCancelled else { return [] }

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

        // Load audio files
        var loadedFiles: [ID<SourceRecording>: AVAudioFile] = [:]
        var newRecordingFileURLs: [ID<SourceRecording>: URL] = [:]
        for (id, recording) in sourceRecordings {
            let fileURL = audioDirURL.appendingPathComponent(recording.filename)
            if let file = try? AVAudioFile(forReading: fileURL) {
                loadedFiles[id] = file
                newRecordingFileURLs[id] = fileURL
            }
        }

        guard !Task.isCancelled else { return [] }

        var preloadedChangedTracks: [PreloadedTrack] = []
        for track in song.tracks {
            if track.kind == .master { continue }
            guard changedTrackIDs.contains(track.id) else { continue }
            guard !Task.isCancelled else { return [] }

            var trackEffects: [AVAudioUnit] = []
            if !track.isEffectChainBypassed {
                for effect in track.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                    guard !effect.isBypassed else { continue }
                    if let unit = try? await audioUnitHost.loadAudioUnit(component: effect.component) {
                        if let presetData = effect.presetData {
                            try? audioUnitHost.restoreState(audioUnit: unit, data: presetData)
                        }
                        trackEffects.append(unit)
                    } else {
                        print("[WARN] Failed to load AU: \(effect.displayName)")
                    }
                }
            }

            var preloadedContainers: [PreloadedContainer] = []
            for container in track.containers {
                guard !Task.isCancelled else { return [] }
                let resolved = container.resolved { id in allContainers.first(where: { $0.id == id }) }
                let hasAudio = resolved.sourceRecordingID != nil
                let hasMIDI = resolved.midiSequence != nil
                let isLinkedClone = container.parentContainerID != nil
                let needsInstrument = track.instrumentComponent != nil || resolved.instrumentOverride != nil
                guard hasAudio || hasMIDI || isLinkedClone || needsInstrument else { continue }

                let fileFormat: AVAudioFormat?
                if let recID = resolved.sourceRecordingID {
                    fileFormat = loadedFiles[recID]?.processingFormat
                } else {
                    fileFormat = nil
                }

                var instrumentUnit: AVAudioUnit?
                if let override = resolved.instrumentOverride {
                    instrumentUnit = try? await audioUnitHost.loadAudioUnit(component: override)
                } else if let trackInstrument = track.instrumentComponent {
                    instrumentUnit = try? await audioUnitHost.loadAudioUnit(component: trackInstrument)
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
                        } else {
                            print("[WARN] Failed to load AU: \(effect.displayName)")
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

            preloadedChangedTracks.append(PreloadedTrack(
                track: track,
                effects: trackEffects,
                containers: preloadedContainers
            ))
        }

        guard !Task.isCancelled else { return [] }

        // Install host musical context blocks on all preloaded AUs
        for unit in preloadedMasterEffects {
            installMusicalContext(on: unit)
        }
        for pt in preloadedChangedTracks {
            for unit in pt.effects { installMusicalContext(on: unit) }
            for pc in pt.containers {
                if let inst = pc.instrument { installMusicalContext(on: inst) }
                for unit in pc.effects { installMusicalContext(on: unit) }
            }
        }

        // ── Phase 2: Stop engine, selectively rebuild graph, restart ──

        print("[PLAY] prepareIncremental: \(changedTrackIDs.count) changed, \(removedTrackIDs.count) removed, master=\(masterChanged)")

        // Capture current AU state from containers being rebuilt so preset
        // changes made via the plugin UI are preserved across graph rebuilds.
        // Keyed by component info so reordering matches the right plugin.
        lock.lock()
        var capturedAUStates: [ID<Container>: [(AudioComponentInfo, Data)]] = [:]
        for trackID in changedTrackIDs {
            for (containerID, subgraph) in containerSubgraphs where containerToTrack[containerID] == trackID {
                var states: [(AudioComponentInfo, Data)] = []
                for unit in subgraph.effectUnits {
                    let d = unit.audioComponentDescription
                    let info = AudioComponentInfo(
                        componentType: d.componentType,
                        componentSubType: d.componentSubType,
                        componentManufacturer: d.componentManufacturer
                    )
                    if let state = unit.auAudioUnit.fullState,
                       let data = try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0) {
                        states.append((info, data))
                    }
                }
                if !states.isEmpty {
                    capturedAUStates[containerID] = states
                }
            }
        }
        lock.unlock()

        // Keep failures from unchanged containers, clear for rebuilt ones
        lock.lock()
        var newFailedContainerIDs = _failedContainerIDs
        let rebuildTrackIDs = changedTrackIDs.union(removedTrackIDs)
        for (containerID, _) in containerSubgraphs {
            if let trackID = containerToTrack[containerID], rebuildTrackIDs.contains(trackID) {
                newFailedContainerIDs.remove(containerID)
            }
        }
        lock.unlock()

        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        defer { if wasRunning { try? engine.start() } }

        // Clean up removed tracks
        for trackID in removedTrackIDs {
            cleanupTrackSubgraph(trackID: trackID)
        }

        // Clean up changed tracks
        for trackID in changedTrackIDs {
            cleanupTrackSubgraph(trackID: trackID)
        }

        // Update files
        lock.lock()
        audioFiles = loadedFiles
        recordingFileURLs = newRecordingFileURLs
        lock.unlock()

        // Determine output target
        let outputTarget: AVAudioNode
        if masterChanged {
            cleanupMasterChain()

            if let master = song.masterTrack {
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

                // Reconnect unchanged track mixers to new master output
                lock.lock()
                let unchangedMixers = trackMixers.filter { !changedTrackIDs.contains($0.key) && !removedTrackIDs.contains($0.key) }
                let unchangedEffects = trackEffectUnits.filter { !changedTrackIDs.contains($0.key) && !removedTrackIDs.contains($0.key) }
                lock.unlock()

                for (trackID, mixer) in unchangedMixers {
                    if let effects = unchangedEffects[trackID], !effects.isEmpty {
                        // Reconnect last effect to new output target
                        engine.disconnectNodeOutput(effects[effects.count - 1])
                        engine.connect(effects[effects.count - 1], to: outputTarget, format: nil)
                    } else {
                        engine.disconnectNodeOutput(mixer)
                        engine.connect(mixer, to: outputTarget, format: nil)
                    }
                }
            } else {
                outputTarget = engine.mainMixerNode
            }
        } else {
            lock.lock()
            outputTarget = masterMixerNode ?? engine.mainMixerNode
            lock.unlock()
        }

        // Build changed track subgraphs
        let hasSolo = song.tracks.contains { $0.isSoloed }
        for preloaded in preloadedChangedTracks {
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
                var chainConnected = true
                if chain.isEmpty {
                    engine.connect(player, to: trackMixer, format: playerFormat)
                } else {
                    // Use nil format for effect chain connections (same as prepare())
                    var connectError: NSError?
                    let success = ObjCTryCatch({
                        self.engine.connect(player, to: chain[0], format: nil)
                        for i in 0..<(chain.count - 1) {
                            self.engine.connect(chain[i], to: chain[i + 1], format: nil)
                        }
                        self.engine.connect(chain[chain.count - 1], to: trackMixer, format: nil)
                    }, &connectError)
                    if !success {
                        print("[WARN] Effect chain connection failed for '\(pc.container.name)': \(connectError?.localizedDescription ?? "unknown")")
                        for node in chain { engine.detach(node) }
                        engine.connect(player, to: trackMixer, format: playerFormat)
                        chainConnected = false
                        newFailedContainerIDs.insert(pc.container.id)
                    }
                }

                let actualEffects = chainConnected ? pc.effects : []
                let actualInstrument = chainConnected ? pc.instrument : nil

                // Restore captured AU state from the previous graph, matching by
                // AudioComponentInfo so reordering preserves the right preset on each
                // plugin. This preserves preset changes made via the plugin UI that
                // weren't saved to the model.
                if chainConnected, var captured = capturedAUStates[pc.container.id] {
                    for unit in actualEffects {
                        let d = unit.audioComponentDescription
                        let info = AudioComponentInfo(
                            componentType: d.componentType,
                            componentSubType: d.componentSubType,
                            componentManufacturer: d.componentManufacturer
                        )
                        if let idx = captured.firstIndex(where: { $0.0 == info }) {
                            let data = captured[idx].1
                            if let state = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                                unit.auAudioUnit.fullState = state
                            }
                            captured.remove(at: idx)
                        }
                    }
                }

                let containerAudioFile: AVAudioFile?
                if let recID = pc.container.sourceRecordingID,
                   let url = newRecordingFileURLs[recID] {
                    containerAudioFile = try? AVAudioFile(forReading: url)
                } else {
                    containerAudioFile = nil
                }

                lock.lock()
                containerSubgraphs[pc.container.id] = ContainerSubgraph(
                    playerNode: player,
                    instrumentUnit: actualInstrument,
                    effectUnits: actualEffects,
                    trackMixer: trackMixer,
                    audioFile: containerAudioFile
                )
                containerToTrack[pc.container.id] = preloaded.track.id
                lock.unlock()
            }
        }

        lock.lock()
        _failedContainerIDs = newFailedContainerIDs
        lock.unlock()
        onEffectChainStatusChanged?(newFailedContainerIDs)

        // Store updated fingerprints
        lock.lock()
        preparedTrackFingerprints = newFingerprints
        preparedMasterFingerprint = newMasterFP
        lock.unlock()

        return changedTrackIDs.union(removedTrackIDs)
    }

    /// Reschedules containers on specific tracks from the given bar position.
    /// Used after prepareIncremental() to start audio on rebuilt tracks while
    /// unchanged tracks continue playing uninterrupted.
    public func playChangedTracks(
        _ changedTrackIDs: Set<ID<Track>>,
        song: Song,
        fromBar: Double,
        bpm: Double,
        timeSignature: TimeSignature,
        sampleRate: Double
    ) {
        let samplesPerBar = self.samplesPerBar(bpm: bpm, timeSignature: timeSignature, sampleRate: sampleRate)
        let allContainers = song.tracks.flatMap(\.containers)

        lock.lock()
        currentSong = song
        currentBPM = bpm
        currentTimeSignature = timeSignature
        currentSampleRate = sampleRate
        // Rebuild container → track mapping for ALL tracks
        containerToTrack.removeAll()
        for track in song.tracks {
            for container in track.containers {
                containerToTrack[container.id] = track.id
            }
        }
        lock.unlock()

        // Schedule containers only on changed tracks
        for track in song.tracks {
            if track.kind == .master { continue }
            guard changedTrackIDs.contains(track.id) else { continue }

            for container in track.containers {
                let resolved = container.resolved { id in allContainers.first(where: { $0.id == id }) }
                if resolved.hasMIDI && resolved.sourceRecordingID == nil {
                    let containerEndBar = Double(resolved.endBar)
                    let containerStartBar = Double(resolved.startBar)
                    if fromBar < containerEndBar && fromBar >= containerStartBar - 1 {
                        lock.lock()
                        activeContainers.append(resolved)
                        tracksWithActiveContainers.insert(track.id)
                        lock.unlock()
                        actionDispatcher?.containerDidEnter(resolved)
                    }
                    continue
                }
                scheduleContainer(container: resolved, fromBar: fromBar, samplesPerBar: samplesPerBar)
            }
        }

        // Restart automation timer with updated song data to pick up new track effects
        restartAutomationTimer(song: song, fromBar: fromBar, bpm: bpm, timeSignature: timeSignature)
    }

    /// Returns the current playback position in bars, or nil if not playing.
    /// Uses the automation timer's wall-clock reference for position calculation.
    public func currentPlaybackBar() -> Double? {
        lock.lock()
        guard let startTime = playbackStartTime else {
            lock.unlock()
            return nil
        }
        let startBar = playbackStartBar
        let bpm = currentBPM
        let ts = currentTimeSignature
        lock.unlock()

        let elapsed = Date().timeIntervalSince(startTime)
        let secondsPerBeat = 60.0 / bpm
        let secondsPerBar = Double(ts.beatsPerBar) * secondsPerBeat
        return startBar + elapsed / secondsPerBar
    }

    /// Updates tempo and/or time signature during live playback without rebuilding
    /// the audio graph. Adjusts the playback start reference so that the current
    /// beat position remains continuous across the tempo change. The musical context
    /// block will immediately reflect the new values on its next render-thread poll.
    public func updateTempo(bpm: Double, timeSignature: TimeSignature) {
        lock.lock()
        let oldBPM = currentBPM
        let oldTS = currentTimeSignature
        let oldStartTime = playbackStartTime
        let oldStartBar = playbackStartBar

        // Calculate current bar position under the old tempo
        let currentBar: Double
        if let startTime = oldStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            let secondsPerBeat = 60.0 / oldBPM
            let secondsPerBar = Double(oldTS.beatsPerBar) * secondsPerBeat
            currentBar = oldStartBar + elapsed / secondsPerBar
        } else {
            currentBar = oldStartBar
        }

        // Re-anchor: new start reference = now at the current bar, with new tempo
        currentBPM = bpm
        currentTimeSignature = timeSignature
        if oldStartTime != nil {
            playbackStartTime = Date()
            playbackStartBar = currentBar
        }
        lock.unlock()
    }

    /// Schedules and starts playback from the given bar position.
    public func play(
        song: Song,
        fromBar: Double,
        bpm: Double,
        timeSignature: TimeSignature,
        sampleRate: Double
    ) {
        let playStart = CFAbsoluteTimeGetCurrent()
        let samplesPerBar = self.samplesPerBar(bpm: bpm, timeSignature: timeSignature, sampleRate: sampleRate)
        let allContainers = song.tracks.flatMap(\.containers)

        lock.lock()
        // Store playback state for trigger-based scheduling and position tracking
        currentSong = song
        currentBPM = bpm
        currentTimeSignature = timeSignature
        currentSampleRate = sampleRate
        playbackStartTime = Date()
        playbackStartBar = fromBar

        // Build container → track mapping for monitoring suppression
        for track in song.tracks {
            for container in track.containers {
                containerToTrack[container.id] = track.id
            }
        }
        lock.unlock()

        print("[PLAY] play() fromBar=\(fromBar) subgraphs=\(containerSubgraphs.count) audioFiles=\(audioFiles.count)")
        for track in song.tracks {
            // Master track has no playable containers
            if track.kind == .master { continue }

            // Schedule all containers regardless of mute/solo — muting is
            // handled by mixer volumes so tracks can be unmuted during playback.
            for container in track.containers {
                let resolved = container.resolved { id in allContainers.first(where: { $0.id == id }) }

                // MIDI containers are scheduled via the automation/MIDI timer, not audio scheduling.
                // Register them as active so they fire enter/exit actions and suppress monitoring.
                if resolved.hasMIDI && resolved.sourceRecordingID == nil {
                    let containerEndBar = Double(resolved.endBar)
                    let containerStartBar = Double(resolved.startBar)
                    if fromBar < containerEndBar && fromBar >= containerStartBar - 1 {
                        lock.lock()
                        activeContainers.append(resolved)
                        tracksWithActiveContainers.insert(track.id)
                        lock.unlock()
                        actionDispatcher?.containerDidEnter(resolved)
                    }
                    continue
                }

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

        let playMs = (CFAbsoluteTimeGetCurrent() - playStart) * 1000
        print("[PERF] play(): \(String(format: "%.1f", playMs))ms — \(song.tracks.flatMap(\.containers).count) containers from bar \(fromBar)")
    }

    /// Stops all playback.
    /// - Parameter skipDeclick: When `true`, stops player nodes immediately without
    ///   the ~8ms fade-out ramp. Use this for seeks where playback restarts immediately.
    public func stop(skipDeclick: Bool = false) {
        let stopStart = CFAbsoluteTimeGetCurrent()
        stopAutomationTimer()

        // Copy state under lock, then operate on copies
        lock.lock()
        let subgraphs = containerSubgraphs
        let containers = activeContainers
        let tracks = tracksWithActiveContainers
        let midiNotes = activeMIDINotes
        activeContainers.removeAll()
        tracksWithActiveContainers.removeAll()
        containerToTrack.removeAll()
        activeMIDINotes.removeAll()
        currentSong = nil
        lock.unlock()

        // Send note-off for all active MIDI notes
        for midiNote in midiNotes {
            sendMIDINoteToTrack(midiNote.trackID, message: .noteOff(channel: midiNote.channel, note: midiNote.note, velocity: 0))
        }

        if !subgraphs.isEmpty {
            if skipDeclick {
                // Immediate stop — no fade, playback is about to restart
                for (_, subgraph) in subgraphs {
                    subgraph.playerNode.stop()
                }
            } else {
                // Declick fade-out: ramp main mixer output volume to zero over ~8ms
                // so the render thread picks up intermediate values before we stop nodes.
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
        }

        for container in containers {
            actionDispatcher?.containerDidExit(container)
        }
        // Unsuppress monitoring on tracks that had active containers
        for trackID in tracks {
            inputMonitor?.unsuppressMonitoring(trackID: trackID)
        }

        let stopMs = (CFAbsoluteTimeGetCurrent() - stopStart) * 1000
        print("[PERF] stop(skipDeclick=\(skipDeclick)): \(String(format: "%.1f", stopMs))ms — \(subgraphs.count) subgraphs, \(midiNotes.count) MIDI notes")
    }

    /// Safely disconnects a node's output, catching NSExceptions from nodes
    /// that were already detached (e.g. after a failed effect chain connection).
    private func safeDisconnect(_ node: AVAudioNode) {
        var error: NSError?
        ObjCTryCatch({ self.engine.disconnectNodeOutput(node) }, &error)
    }

    /// Installs host musical context and transport state blocks on an Audio Unit
    /// so tempo-synced plugins (e.g. OneKnob Pumper, delay with tempo sync) can
    /// query the current BPM, time signature, beat position, and transport state.
    private func installMusicalContext(on audioUnit: AVAudioUnit) {
        let au = audioUnit.auAudioUnit

        au.musicalContextBlock = { [weak self] tempo, timeSignatureNumerator, timeSignatureDenominator, currentBeatPosition, sampleOffsetToNextBeat, currentMeasureDownbeatPosition in
            guard let self else { return false }
            self.lock.lock()
            let bpm = self.currentBPM
            let ts = self.currentTimeSignature
            let startTime = self.playbackStartTime
            let startBar = self.playbackStartBar
            let sampleRate = self.currentSampleRate
            self.lock.unlock()

            tempo?.pointee = bpm
            timeSignatureNumerator?.pointee = Double(ts.beatsPerBar)
            timeSignatureDenominator?.pointee = Int(ts.beatUnit)

            // Calculate current beat position from wall-clock elapsed time
            let secondsPerBeat = 60.0 / bpm
            if let startTime {
                let elapsed = Date().timeIntervalSince(startTime)
                let beatsElapsed = elapsed / secondsPerBeat
                let startBeat = (startBar - 1.0) * Double(ts.beatsPerBar)
                let currentBeat = startBeat + beatsElapsed
                currentBeatPosition?.pointee = currentBeat

                // Downbeat of current measure
                let beatsPerBar = Double(ts.beatsPerBar)
                let currentMeasureBeat = floor(currentBeat / beatsPerBar) * beatsPerBar
                currentMeasureDownbeatPosition?.pointee = currentMeasureBeat

                // Samples to next beat boundary
                let beatFraction = currentBeat - floor(currentBeat)
                let secondsToNextBeat = (1.0 - beatFraction) * secondsPerBeat
                sampleOffsetToNextBeat?.pointee = Int(secondsToNextBeat * sampleRate)
            } else {
                currentBeatPosition?.pointee = 0
                currentMeasureDownbeatPosition?.pointee = 0
                sampleOffsetToNextBeat?.pointee = 0
            }

            return true
        }

        au.transportStateBlock = { [weak self] transportStateFlags, currentSamplePosition, cycleStartBeatPosition, cycleEndBeatPosition in
            guard let self else { return false }
            self.lock.lock()
            let isPlaying = self.playbackStartTime != nil
            let startTime = self.playbackStartTime
            let sampleRate = self.currentSampleRate
            self.lock.unlock()

            var flags: AUHostTransportStateFlags = []
            if isPlaying {
                flags.insert(.moving)
            }
            flags.insert(.changed)
            transportStateFlags?.pointee = flags

            if let startTime {
                let elapsed = Date().timeIntervalSince(startTime)
                currentSamplePosition?.pointee = elapsed * sampleRate
            } else {
                currentSamplePosition?.pointee = 0
            }

            // No looping support yet
            cycleStartBeatPosition?.pointee = 0
            cycleEndBeatPosition?.pointee = 0

            return true
        }
    }

    /// Cleans up all nodes and audio files.
    ///
    /// Must run on the main actor — AVAudioEngine topology operations (disconnect,
    /// detach) can silently fail from background threads.
    @MainActor
    public func cleanup() {
        stopAutomationTimer()

        // Remove level taps before tearing down nodes
        removeTrackLevelTaps()

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
        recordingFileURLs.removeAll()
        currentSong = nil
        preparedTrackFingerprints.removeAll()
        preparedMasterFingerprint = nil
        lock.unlock()

        // Engine operations on local copies — no lock needed
        for (_, subgraph) in subgraphs {
            subgraph.playerNode.stop()
            safeDisconnect(subgraph.playerNode)
            engine.detach(subgraph.playerNode)
            if let inst = subgraph.instrumentUnit {
                safeDisconnect(inst)
                engine.detach(inst)
            }
            for unit in subgraph.effectUnits {
                safeDisconnect(unit)
                engine.detach(unit)
            }
        }

        for (_, units) in tEffectUnits {
            for unit in units {
                safeDisconnect(unit)
                engine.detach(unit)
            }
        }

        for (_, mixer) in tMixers {
            safeDisconnect(mixer)
            engine.detach(mixer)
        }

        // Cleanup master mixer and effects
        for unit in mEffectUnits {
            safeDisconnect(unit)
            engine.detach(unit)
        }
        if let masterMixer = mMixer {
            safeDisconnect(masterMixer)
            engine.detach(masterMixer)
        }
    }

    // MARK: - Per-Track Level Metering

    /// Installs audio taps on all track mixer nodes to read peak levels.
    /// Safe to call multiple times — only installs on tracks that don't already have taps.
    public func installTrackLevelTaps() {
        lock.lock()
        let mixers = trackMixers
        lock.unlock()

        for (trackID, mixer) in mixers {
            lock.lock()
            let alreadyInstalled = trackLevelTapIDs.contains(trackID)
            lock.unlock()
            guard !alreadyInstalled else { continue }

            let format = mixer.outputFormat(forBus: 0)
            guard format.channelCount > 0 else { continue }
            let bufferSize: AVAudioFrameCount = 4096
            let capturedTrackID = trackID
            mixer.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                let peak = AudioEngineManager.peakLevel(from: buffer)
                self.onTrackLevelUpdate?(capturedTrackID, peak)
            }
            lock.lock()
            trackLevelTapIDs.insert(trackID)
            lock.unlock()
        }
    }

    /// Removes all per-track level taps.
    public func removeTrackLevelTaps() {
        lock.lock()
        let tapIDs = trackLevelTapIDs
        let mixers = trackMixers
        trackLevelTapIDs.removeAll()
        lock.unlock()

        for trackID in tapIDs {
            if let mixer = mixers[trackID] {
                mixer.removeTap(onBus: 0)
            }
        }
    }

    /// Tears down a single track's subgraph (containers, effects, mixer) from the engine.
    /// Must be called while the engine is stopped.
    @MainActor
    private func cleanupTrackSubgraph(trackID: ID<Track>) {
        // Remove level tap for this track before tearing down
        lock.lock()
        let hadTap = trackLevelTapIDs.remove(trackID) != nil
        lock.unlock()
        if hadTap, let mixer = trackMixers[trackID] {
            mixer.removeTap(onBus: 0)
        }

        lock.lock()
        // Find and remove container subgraphs belonging to this track
        let trackMixer = trackMixers.removeValue(forKey: trackID)
        let effects = trackEffectUnits.removeValue(forKey: trackID)
        var removedSubgraphs: [ContainerSubgraph] = []
        for (containerID, subgraph) in containerSubgraphs {
            if subgraph.trackMixer === trackMixer {
                removedSubgraphs.append(subgraph)
                containerSubgraphs.removeValue(forKey: containerID)
                containerToTrack.removeValue(forKey: containerID)
                activeContainers.removeAll { $0.id == containerID }
            }
        }
        tracksWithActiveContainers.remove(trackID)
        lock.unlock()

        // Detach nodes from engine
        for subgraph in removedSubgraphs {
            subgraph.playerNode.stop()
            safeDisconnect(subgraph.playerNode)
            engine.detach(subgraph.playerNode)
            if let inst = subgraph.instrumentUnit {
                safeDisconnect(inst)
                engine.detach(inst)
            }
            for unit in subgraph.effectUnits {
                safeDisconnect(unit)
                engine.detach(unit)
            }
        }

        if let effects {
            for unit in effects {
                safeDisconnect(unit)
                engine.detach(unit)
            }
        }

        if let mixer = trackMixer {
            safeDisconnect(mixer)
            engine.detach(mixer)
        }
    }

    /// Tears down only the master mixer chain (master mixer node + master effects).
    /// Must be called while the engine is stopped.
    @MainActor
    private func cleanupMasterChain() {
        lock.lock()
        let mEffects = masterEffectUnits
        masterEffectUnits.removeAll()
        let mMixer = masterMixerNode
        masterMixerNode = nil
        lock.unlock()

        for unit in mEffects {
            safeDisconnect(unit)
            engine.detach(unit)
        }
        if let masterMixer = mMixer {
            safeDisconnect(masterMixer)
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

    /// Registers an audio file for a recording that completed mid-session.
    /// This makes the audio available for scheduling linked containers.
    public func registerRecording(id: ID<SourceRecording>, file: AVAudioFile) {
        lock.lock()
        audioFiles[id] = file
        recordingFileURLs[id] = file.url
        lock.unlock()
    }

    /// Schedules a linked container for playback mid-session, using the current
    /// playback state. Called after a recording is propagated to a linked clone.
    public func scheduleLinkedContainer(container: Container) {
        lock.lock()
        let bpm = currentBPM
        let ts = currentTimeSignature
        let sr = currentSampleRate
        let song = currentSong

        // Reconnect the player node with the audio file's format so the
        // channel count matches the buffer that will be scheduled.
        if let recID = container.sourceRecordingID,
           let file = audioFiles[recID],
           var subgraph = containerSubgraphs[container.id] {
            let fileFormat = file.processingFormat

            // Give this container its own AVAudioFile handle
            if subgraph.audioFile == nil, let url = recordingFileURLs[recID] {
                subgraph.audioFile = try? AVAudioFile(forReading: url)
                containerSubgraphs[container.id] = subgraph
            }

            lock.unlock()

            // Reconnect player → first chain node (or trackMixer) with the file format
            engine.disconnectNodeOutput(subgraph.playerNode)
            let firstDownstream: AVAudioNode
            if let inst = subgraph.instrumentUnit {
                firstDownstream = inst
            } else if let firstEffect = subgraph.effectUnits.first {
                firstDownstream = firstEffect
            } else {
                firstDownstream = subgraph.trackMixer
            }
            engine.connect(subgraph.playerNode, to: firstDownstream, format: fileFormat)
        } else {
            lock.unlock()
        }

        guard song != nil else { return }
        let spb = samplesPerBar(bpm: bpm, timeSignature: ts, sampleRate: sr)
        scheduleContainer(
            container: container,
            fromBar: Double(container.startBar),
            samplesPerBar: spb
        )
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
            let sg = containerSubgraphs[container.id]
            // Prefer per-container audio file; fall back to shared file
            audioFile = sg?.audioFile ?? audioFiles[recordingID]
            subgraph = sg
            if audioFile == nil || subgraph == nil {
                print("[PLAY] scheduleContainer '\(container.name)' id=\(container.id) MISSING audioFile=\(audioFile != nil) subgraph=\(subgraph != nil) recID=\(recordingID)")
            }
        } else {
            audioFile = nil
            subgraph = nil
            print("[PLAY] scheduleContainer '\(container.name)' id=\(container.id) NO sourceRecordingID")
        }
        lock.unlock()

        guard let audioFile, let subgraph else { return }

        // scheduleSegment interprets startingFrame/frameCount in the audio file's
        // native sample rate.  The caller computed samplesPerBar using the engine's
        // output rate, so rescale when the file rate differs.
        let fileRate = audioFile.fileFormat.sampleRate
        let fileSPB: Double
        if fileRate > 0, fileRate != currentSampleRate, currentSampleRate > 0 {
            fileSPB = samplesPerBar * (fileRate / currentSampleRate)
        } else {
            fileSPB = samplesPerBar
        }

        let audioOffsetSamples = Int64(container.audioStartOffset * fileSPB)

        print("[PLAY] scheduleContainer '\(container.name)' id=\(container.id) bars=\(container.startBar)-\(container.endBar) fileLen=\(audioFile.length) audioOffset=\(audioOffsetSamples) fileRate=\(fileRate) engineRate=\(currentSampleRate) parent=\(container.parentContainerID.map { "\($0)" } ?? "none")")

        let containerStartSample = Int64(Double(container.startBar - 1) * fileSPB)
        let containerEndSample = Int64(Double(container.endBar - 1) * fileSPB)
        let playheadSample = Int64((fromBar - 1.0) * fileSPB)

        // Skip containers that end before the playhead
        if containerEndSample <= playheadSample {
            print("[PLAY]   skipping '\(container.name)' — ends before playhead")
            return
        }

        let startOffset: AVAudioFramePosition
        let frameCount: AVAudioFrameCount

        // For future containers, compute the delay in frames so audio starts
        // at the correct bar position instead of immediately.
        let futureDelayFrames: AVAudioFramePosition
        if playheadSample >= containerStartSample {
            // Playhead is inside this container
            let positionInContainer = playheadSample - containerStartSample
            startOffset = AVAudioFramePosition(positionInContainer + audioOffsetSamples)
            let remaining = containerEndSample - playheadSample
            let fileFrames = audioFile.length - startOffset
            frameCount = AVAudioFrameCount(min(remaining, max(fileFrames, 0)))
            futureDelayFrames = 0
        } else {
            // Container starts in the future — schedule with delay
            startOffset = AVAudioFramePosition(audioOffsetSamples)
            let containerLength = containerEndSample - containerStartSample
            let fileFrames = audioFile.length - audioOffsetSamples
            frameCount = AVAudioFrameCount(min(containerLength, max(fileFrames, 0)))
            futureDelayFrames = AVAudioFramePosition(containerStartSample - playheadSample)
        }

        guard frameCount > 0 else {
            print("[PLAY]   '\(container.name)' frameCount=0, skipping")
            return
        }

        // Build AVAudioTime for future containers (nil = play immediately)
        // futureDelayFrames is in file-rate frames, so the rate matches.
        let scheduleTime: AVAudioTime?
        if futureDelayFrames > 0 {
            scheduleTime = AVAudioTime(sampleTime: futureDelayFrames, atRate: fileRate)
            print("[PLAY]   '\(container.name)' scheduling frameCount=\(frameCount) delay=\(futureDelayFrames) frames")
        } else {
            scheduleTime = nil
            print("[PLAY]   '\(container.name)' scheduling frameCount=\(frameCount) startOffset=\(startOffset)")
        }

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
                    samplesPerBar: fileSPB,
                    audioOffsetSamples: audioOffsetSamples,
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
                    samplesPerBar: fileSPB,
                    audioOffsetSamples: audioOffsetSamples
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
                    samplesPerBar: fileSPB,
                    enterFade: container.enterFade,
                    exitFade: container.exitFade,
                    at: scheduleTime
                )
            } else {
                scheduleDeclickedSegment(
                    player: subgraph.playerNode,
                    audioFile: audioFile,
                    startingFrame: startOffset,
                    frameCount: frameCount,
                    at: scheduleTime
                )
            }
        }

        // Guard against concurrent cleanup detaching the node from the engine
        guard subgraph.playerNode.engine != nil else {
            print("[PLAY]   '\(container.name)' player NOT attached to engine!")
            return
        }
        subgraph.playerNode.play()
        print("[PLAY]   '\(container.name)' player.play() called, isPlaying=\(subgraph.playerNode.isPlaying)")

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
        frameCount: AVAudioFrameCount,
        at when: AVAudioTime? = nil
    ) {
        // For future containers (scheduled with a delay), skip the declick
        // fade-in since the silence gap naturally prevents clicks.
        if when != nil {
            player.scheduleSegment(audioFile, startingFrame: startingFrame, frameCount: frameCount, at: when)
            return
        }

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
        samplesPerBar: Double,
        audioOffsetSamples: Int64 = 0
    ) {
        let containerLengthSamples = containerEndSample - containerStartSample
        let effectiveFileLength = audioFile.length - audioOffsetSamples

        guard effectiveFileLength > 0, containerLengthSamples > 0 else { return }

        var position = max(playheadSample, containerStartSample) - containerStartSample
        let endPosition = containerLengthSamples
        var isFirst = true

        while position < endPosition {
            let positionInLoop = (position % effectiveFileLength) + audioOffsetSamples
            let remainingInLoop = effectiveFileLength - (position % effectiveFileLength)
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
    /// For large containers, only reads the fade regions into buffers and uses
    /// scheduleSegment (no file I/O) for the unfaded middle portion.
    private func scheduleFadingPlayback(
        player: AVAudioPlayerNode,
        audioFile: AVAudioFile,
        startOffset: AVAudioFramePosition,
        frameCount: AVAudioFrameCount,
        containerPosition: Int64,
        containerLengthSamples: Int64,
        samplesPerBar: Double,
        enterFade: FadeSettings?,
        exitFade: FadeSettings?,
        at when: AVAudioTime? = nil
    ) {
        let format = audioFile.processingFormat
        let enterFadeSamples = enterFade.map { Int64($0.duration * samplesPerBar) } ?? 0
        let exitFadeSamples = exitFade.map { Int64($0.duration * samplesPerBar) } ?? 0
        let exitFadeStart = containerLengthSamples - exitFadeSamples

        // For short containers or containers entirely within fade regions,
        // use the simple single-buffer approach (overhead of splitting not worthwhile)
        let totalFadeSamples = enterFadeSamples + exitFadeSamples
        if Int64(frameCount) <= totalFadeSamples || frameCount <= 88200 {
            scheduleFadingPlaybackSimple(
                player: player, audioFile: audioFile, format: format,
                startOffset: startOffset, frameCount: frameCount,
                containerPosition: containerPosition,
                containerLengthSamples: containerLengthSamples,
                samplesPerBar: samplesPerBar,
                enterFade: enterFade, exitFade: exitFade,
                enterFadeSamples: enterFadeSamples, at: when
            )
            return
        }

        // Split into up to 3 segments: enter fade buffer + unfaded segment + exit fade buffer
        var pos = containerPosition
        var fileOffset = startOffset
        var remaining = Int64(frameCount)
        var isFirst = true
        let endPos = containerPosition + Int64(frameCount)

        // Part 1: Enter fade region (buffer with fade applied)
        if pos < enterFadeSamples, enterFade != nil {
            let fadeEnd = min(enterFadeSamples, endPos)
            let fadeFrames = AVAudioFrameCount(fadeEnd - pos)
            if let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: fadeFrames) {
                audioFile.framePosition = fileOffset
                do { try audioFile.read(into: buf, frameCount: fadeFrames) } catch { return }
                applyContainerFades(
                    to: buf, containerPosition: pos,
                    containerLengthSamples: containerLengthSamples,
                    samplesPerBar: samplesPerBar,
                    enterFade: enterFade,
                    exitFade: (fadeEnd > exitFadeStart) ? exitFade : nil
                )
                player.scheduleBuffer(buf, at: when)
                fileOffset += AVAudioFramePosition(fadeFrames)
                pos += Int64(fadeFrames)
                remaining -= Int64(fadeFrames)
                isFirst = false
            }
        } else if when == nil, pos >= enterFadeSamples {
            // Past the enter fade — apply declick ramp on first 256 frames
            let declickFrames = min(Self.declickFrameCount, AVAudioFrameCount(remaining))
            if let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: declickFrames) {
                audioFile.framePosition = fileOffset
                do { try audioFile.read(into: buf, frameCount: declickFrames) } catch { return }
                Self.applyDeclickFadeIn(to: buf)
                player.scheduleBuffer(buf, at: nil)
                fileOffset += AVAudioFramePosition(declickFrames)
                pos += Int64(declickFrames)
                remaining -= Int64(declickFrames)
                isFirst = false
            }
        }

        // Part 2: Unfaded middle (scheduleSegment — no file I/O)
        let middleEnd = min(exitFadeStart, endPos)
        let middleFrames = max(Int64(0), middleEnd - pos)
        if middleFrames > 0 {
            player.scheduleSegment(
                audioFile,
                startingFrame: fileOffset,
                frameCount: AVAudioFrameCount(middleFrames),
                at: isFirst ? when : nil
            )
            fileOffset += AVAudioFramePosition(middleFrames)
            pos += middleFrames
            remaining -= middleFrames
            isFirst = false
        }

        // Part 3: Exit fade region (buffer with fade applied)
        if remaining > 0, exitFade != nil, pos >= exitFadeStart {
            let fadeFrames = AVAudioFrameCount(remaining)
            if let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: fadeFrames) {
                audioFile.framePosition = fileOffset
                do { try audioFile.read(into: buf, frameCount: fadeFrames) } catch { return }
                applyContainerFades(
                    to: buf, containerPosition: pos,
                    containerLengthSamples: containerLengthSamples,
                    samplesPerBar: samplesPerBar,
                    enterFade: nil, exitFade: exitFade
                )
                player.scheduleBuffer(buf)
            }
        } else if remaining > 0 {
            // No exit fade for this tail — just schedule the segment
            player.scheduleSegment(
                audioFile,
                startingFrame: fileOffset,
                frameCount: AVAudioFrameCount(remaining),
                at: isFirst ? when : nil
            )
        }
    }

    /// Simple single-buffer fading path for short containers.
    private func scheduleFadingPlaybackSimple(
        player: AVAudioPlayerNode,
        audioFile: AVAudioFile,
        format: AVAudioFormat,
        startOffset: AVAudioFramePosition,
        frameCount: AVAudioFrameCount,
        containerPosition: Int64,
        containerLengthSamples: Int64,
        samplesPerBar: Double,
        enterFade: FadeSettings?,
        exitFade: FadeSettings?,
        enterFadeSamples: Int64,
        at when: AVAudioTime? = nil
    ) {
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
        if containerPosition >= enterFadeSamples {
            Self.applyDeclickFadeIn(to: buffer)
        }
        player.scheduleBuffer(buffer, at: when)
    }

    /// Schedules looping playback with enter/exit fades applied at container boundaries.
    private func scheduleFadingLoopPlayback(
        player: AVAudioPlayerNode,
        audioFile: AVAudioFile,
        containerStartSample: Int64,
        containerEndSample: Int64,
        playheadSample: Int64,
        samplesPerBar: Double,
        audioOffsetSamples: Int64 = 0,
        enterFade: FadeSettings?,
        exitFade: FadeSettings?
    ) {
        let containerLengthSamples = containerEndSample - containerStartSample
        let effectiveFileLength = audioFile.length - audioOffsetSamples

        guard effectiveFileLength > 0, containerLengthSamples > 0 else { return }

        let enterFadeSamples = enterFade.map { Int64($0.duration * samplesPerBar) } ?? 0
        let exitFadeSamples = exitFade.map { Int64($0.duration * samplesPerBar) } ?? 0
        let exitFadeStart = containerLengthSamples - exitFadeSamples

        var position = max(playheadSample, containerStartSample) - containerStartSample
        let endPosition = containerLengthSamples
        let format = audioFile.processingFormat
        var isFirst = true

        while position < endPosition {
            let positionInLoop = (position % effectiveFileLength) + audioOffsetSamples
            let remainingInLoop = effectiveFileLength - (position % effectiveFileLength)
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

        // Collect MIDI containers for note scheduling
        struct MIDIContainerInfo {
            let container: Container
            let trackID: ID<Track>
            let notes: [MIDINoteEvent]
        }
        var midiContainers: [MIDIContainerInfo] = []
        for track in song.tracks {
            guard track.kind == .midi else { continue }
            for container in track.containers {
                let resolved = container.resolved { id in allContainers.first(where: { $0.id == id }) }
                if let sequence = resolved.midiSequence, !sequence.notes.isEmpty {
                    midiContainers.append(MIDIContainerInfo(
                        container: resolved,
                        trackID: track.id,
                        notes: sequence.notes
                    ))
                }
            }
        }

        guard !containersWithAutomation.isEmpty || !tracksWithAutomation.isEmpty || !midiContainers.isEmpty else { return }

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

        // MIDI note tracking: notes currently sounding (for note-off on timer tick)
        // Protected by the timer's serial queue — no additional locking needed.
        struct ActiveMIDINote: Hashable {
            let containerID: ID<Container>
            let noteID: ID<MIDINoteEvent>
        }
        var activeNotes = Set<ActiveMIDINote>()
        // Weak reference to self for MIDI note sending
        weak var weakSelf = self

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        // Evaluate at ~60 Hz (every ~16ms) for smooth parameter updates and MIDI scheduling
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler {
            let elapsed = Date().timeIntervalSince(startTime)
            let currentBar = startBar + elapsed / secondsPerBar

            // ── MIDI note scheduling ──
            for midiInfo in midiContainers {
                let containerStartBar = Double(midiInfo.container.startBar)
                let containerEndBar = Double(midiInfo.container.endBar)

                // Skip containers outside playback range
                guard currentBar >= containerStartBar - 0.1 && currentBar < containerEndBar + 0.1 else {
                    // Send note-off for any active notes from this container that's out of range
                    for active in activeNotes where active.containerID == midiInfo.container.id {
                        if let note = midiInfo.notes.first(where: { $0.id == active.noteID }) {
                            weakSelf?.sendMIDINoteToTrack(midiInfo.trackID, message: .noteOff(channel: note.channel, note: note.pitch, velocity: 0))
                        }
                    }
                    activeNotes = activeNotes.filter { $0.containerID != midiInfo.container.id }
                    continue
                }

                // Current position in beats within the container
                let beatOffset = (currentBar - containerStartBar) * beatsPerBar

                for note in midiInfo.notes {
                    let key = ActiveMIDINote(containerID: midiInfo.container.id, noteID: note.id)

                    if beatOffset >= note.startBeat && beatOffset < note.endBeat {
                        // Note should be on
                        if !activeNotes.contains(key) {
                            activeNotes.insert(key)
                            weakSelf?.sendMIDINoteToTrack(midiInfo.trackID, message: .noteOn(channel: note.channel, note: note.pitch, velocity: note.velocity))
                        }
                    } else {
                        // Note should be off
                        if activeNotes.contains(key) {
                            activeNotes.remove(key)
                            weakSelf?.sendMIDINoteToTrack(midiInfo.trackID, message: .noteOff(channel: note.channel, note: note.pitch, velocity: 0))
                        }
                    }
                }
            }

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

    /// Restarts the automation timer with updated song data, preserving
    /// the current playback position. Used after incremental graph updates
    /// to pick up new track effects and automation lanes.
    private func restartAutomationTimer(
        song: Song,
        fromBar: Double,
        bpm: Double,
        timeSignature: TimeSignature
    ) {
        // Capture the current playback position before stopping the old timer
        lock.lock()
        let oldStartTime = playbackStartTime
        let oldStartBar = playbackStartBar
        let oldBPM = currentBPM
        let oldTS = currentTimeSignature
        lock.unlock()

        // Calculate where we are now in the playback
        let currentBar: Double
        if let startTime = oldStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            let secondsPerBeat = 60.0 / oldBPM
            let secondsPerBar = Double(oldTS.beatsPerBar) * secondsPerBeat
            currentBar = oldStartBar + elapsed / secondsPerBar
        } else {
            currentBar = fromBar
        }

        stopAutomationTimer()
        startAutomationTimer(song: song, fromBar: currentBar, bpm: bpm, timeSignature: timeSignature)
    }
}

// MARK: - Live AU Instance Access

extension PlaybackScheduler {
    /// Returns the live AVAudioUnit for a container-level effect at the given index.
    public func liveEffectUnit(containerID: ID<Container>, effectIndex: Int) -> AVAudioUnit? {
        lock.lock()
        defer { lock.unlock() }
        guard let subgraph = containerSubgraphs[containerID] else { return nil }
        guard effectIndex >= 0, effectIndex < subgraph.effectUnits.count else { return nil }
        return subgraph.effectUnits[effectIndex]
    }

    /// Returns the live AVAudioUnit for a track-level effect at the given index.
    public func liveTrackEffectUnit(trackID: ID<Track>, effectIndex: Int) -> AVAudioUnit? {
        lock.lock()
        defer { lock.unlock() }
        guard let units = trackEffectUnits[trackID] else { return nil }
        guard effectIndex >= 0, effectIndex < units.count else { return nil }
        return units[effectIndex]
    }

    /// Returns the live AVAudioUnit for a master track effect at the given index.
    public func liveMasterEffectUnit(effectIndex: Int) -> AVAudioUnit? {
        lock.lock()
        defer { lock.unlock() }
        guard effectIndex >= 0, effectIndex < masterEffectUnits.count else { return nil }
        return masterEffectUnits[effectIndex]
    }
    /// Sends a MIDI message to the first instrument unit found on the given track.
    /// Used by the virtual keyboard to trigger notes on instrument tracks.
    /// No-op when no instrument subgraphs exist for the track (e.g. transport stopped).
    public func sendMIDINoteToTrack(_ trackID: ID<Track>, message: MIDIActionMessage) {
        lock.lock()
        let trackMixer = trackMixers[trackID]
        var instrumentUnit: AVAudioUnit?
        if trackMixer != nil {
            for (_, subgraph) in containerSubgraphs {
                if subgraph.trackMixer === trackMixer, let inst = subgraph.instrumentUnit {
                    instrumentUnit = inst
                    break
                }
            }
        }
        lock.unlock()

        guard let instrumentUnit else { return }
        let bytes = message.midiBytes
        instrumentUnit.auAudioUnit.scheduleMIDIEventBlock?(AUEventSampleTimeImmediate, 0, bytes.count, bytes)
    }

    /// Forwards raw MIDI input from external devices to matching instrument tracks.
    /// Filters events by device ID and channel based on track routing settings.
    /// Called from the MIDI input callback on an arbitrary thread.
    public func forwardExternalMIDI(word: UInt32, deviceID: String?) {
        let status = UInt8((word >> 16) & 0xF0)
        let channel = UInt8((word >> 16) & 0x0F)
        let data1 = UInt8((word >> 8) & 0xFF)
        let data2 = UInt8(word & 0xFF)

        // Only forward note on/off, CC, and pitch bend
        guard status == 0x80 || status == 0x90 || status == 0xB0 || status == 0xE0 else { return }

        lock.lock()
        let song = currentSong
        lock.unlock()
        guard let song else { return }

        for track in song.tracks where track.kind == .midi {
            // Filter by device ID (nil = all devices)
            if let trackDevice = track.midiInputDeviceID, trackDevice != deviceID {
                continue
            }
            // Filter by channel (nil = omni)
            if let trackChannel = track.midiInputChannel, trackChannel != channel + 1 {
                continue
            }

            let message: MIDIActionMessage
            switch status {
            case 0x90: message = .noteOn(channel: channel, note: data1, velocity: data2)
            case 0x80: message = .noteOff(channel: channel, note: data1, velocity: data2)
            case 0xB0: message = .controlChange(channel: channel, controller: data1, value: data2)
            default: continue
            }
            sendMIDINoteToTrack(track.id, message: message)
        }
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
