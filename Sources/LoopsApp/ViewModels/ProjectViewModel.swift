import SwiftUI
import LoopsCore
import LoopsEngine

/// An entry in the container clipboard, storing a copied container and its source track ID.
public struct ClipboardContainerEntry: Equatable, Sendable {
    public let container: Container
    public let trackID: ID<Track>
}

/// An entry in the undo history panel, tracking action names and timestamps.
public struct UndoHistoryEntry: Identifiable, Equatable {
    public let id: UUID
    public let actionName: String
    public let timestamp: Date
    /// Whether this entry represents the current state (top of undo stack).
    public var isCurrent: Bool

    public init(actionName: String, timestamp: Date = Date(), isCurrent: Bool = true) {
        self.id = UUID()
        self.actionName = actionName
        self.timestamp = timestamp
        self.isCurrent = isCurrent
    }

    /// Relative time string (e.g. "just now", "2m ago").
    public var relativeTimeString: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 5 { return "just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }
}

/// Toast message shown briefly after undo/redo operations.
public struct UndoToastMessage: Equatable, Identifiable {
    public let id: UUID
    public let text: String

    public init(text: String) {
        self.id = UUID()
        self.text = text
    }
}

/// Manages the current project state and file operations.
@Observable
@MainActor
public final class ProjectViewModel {
    public var project: Project
    public var projectURL: URL?
    public var hasUnsavedChanges: Bool = false
    public var isExportSheetPresented: Bool = false
    public var undoManager: UndoManager?

    /// Clipboard for container copy/paste operations.
    public var clipboard: [ClipboardContainerEntry] = []
    /// The leftmost start bar of copied containers, used for offset calculation on paste.
    public var clipboardBaseBar: Int = 1
    /// Section region metadata copied with section copy operations.
    public var clipboardSectionRegion: SectionRegion?

    /// Live waveform peaks for containers currently being recorded.
    /// Cleared when recording completes and peaks are stored in the SourceRecording.
    public var liveRecordingPeaks: [ID<Container>: [Float]] = [:]

    /// Callback fired when a recording completes and needs to be registered with the
    /// running PlaybackScheduler. Parameters: recordingID, filename, linked containers
    /// that should be scheduled for playback.
    public var onRecordingPropagated: ((ID<SourceRecording>, String, [Container]) -> Void)?

    /// History of undo/redo actions for the undo history panel.
    public var undoHistory: [UndoHistoryEntry] = []
    /// The index in undoHistory pointing to the current state.
    /// Entries above this index are "undone" (available for redo).
    public var undoHistoryCursor: Int = -1

    /// Current toast message, set on undo/redo and auto-cleared.
    public var undoToastMessage: UndoToastMessage?

    private let persistence = ProjectPersistence()
    private var undoObservers: [NSObjectProtocol] = []

    public init(project: Project = Project()) {
        self.project = project
        let um = UndoManager()
        um.groupsByEvent = false
        self.undoManager = um
        setupUndoNotifications()
    }

    /// Observe undo/redo notifications to trigger toast messages.
    private func setupUndoNotifications() {
        let undoObserver = NotificationCenter.default.addObserver(
            forName: .NSUndoManagerDidUndoChange,
            object: undoManager,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleUndoNotification()
            }
        }
        let redoObserver = NotificationCenter.default.addObserver(
            forName: .NSUndoManagerDidRedoChange,
            object: undoManager,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleRedoNotification()
            }
        }
        undoObservers = [undoObserver, redoObserver]
    }

    private func handleUndoNotification() {
        if undoHistoryCursor >= 0 {
            undoHistoryCursor -= 1
            // Mark current entry
            for i in undoHistory.indices {
                undoHistory[i].isCurrent = (i == undoHistoryCursor)
            }
        }
        let actionName = undoManager?.redoActionName ?? ""
        undoToastMessage = UndoToastMessage(text: "Undo: \(actionName)")
    }

    private func handleRedoNotification() {
        if undoHistoryCursor < undoHistory.count - 1 {
            undoHistoryCursor += 1
            for i in undoHistory.indices {
                undoHistory[i].isCurrent = (i == undoHistoryCursor)
            }
        }
        let actionName = undoManager?.undoActionName ?? ""
        undoToastMessage = UndoToastMessage(text: "Redo: \(actionName)")
    }

    /// Registers an undo action that snapshots and restores the full project state.
    private func registerUndo(actionName: String) {
        let snapshot = project
        let wasUnsaved = hasUnsavedChanges
        let savedSongID = currentSongID
        undoManager?.beginUndoGrouping()
        undoManager?.registerUndo(withTarget: self) { target in
            let redoSnapshot = target.project
            let redoUnsaved = target.hasUnsavedChanges
            let redoSongID = target.currentSongID
            target.project = snapshot
            target.hasUnsavedChanges = wasUnsaved
            target.currentSongID = savedSongID
            target.undoManager?.beginUndoGrouping()
            target.undoManager?.registerUndo(withTarget: target) { target2 in
                target2.project = redoSnapshot
                target2.hasUnsavedChanges = redoUnsaved
                target2.currentSongID = redoSongID
            }
            target.undoManager?.setActionName(actionName)
            target.undoManager?.endUndoGrouping()
        }
        undoManager?.setActionName(actionName)
        undoManager?.endUndoGrouping()
        // Track in undo history panel
        appendToUndoHistory(actionName: actionName)
    }

    /// Adds an entry to the undo history, trimming any "future" entries above the cursor.
    private func appendToUndoHistory(actionName: String) {
        // Remove entries above the current cursor (they represent undone actions that are now invalidated)
        if undoHistoryCursor < undoHistory.count - 1 {
            undoHistory.removeSubrange((undoHistoryCursor + 1)...)
        }
        // Unmark previous current
        for i in undoHistory.indices {
            undoHistory[i].isCurrent = false
        }
        let entry = UndoHistoryEntry(actionName: actionName, isCurrent: true)
        undoHistory.append(entry)
        undoHistoryCursor = undoHistory.count - 1
    }

    /// Creates a new empty project with a default song (with master track).
    public func newProject() {
        var defaultSong = Song(name: "Song 1")
        defaultSong.ensureMasterTrack()
        project = Project(songs: [defaultSong])
        currentSongID = defaultSong.id
        projectURL = nil
        hasUnsavedChanges = false
        undoManager?.removeAllActions()
        clearUndoHistory()
    }

    /// Saves the project to the current URL, or prompts for a location.
    /// Returns true if saved successfully, false if no URL is set.
    public func save() throws -> Bool {
        guard let url = projectURL else {
            return false
        }
        try persistence.save(project, to: url)
        hasUnsavedChanges = false
        return true
    }

    /// Saves the project to a specific URL.
    public func save(to url: URL) throws {
        try persistence.save(project, to: url)
        projectURL = url
        hasUnsavedChanges = false
    }

    /// Loads a project from a bundle URL.
    public func open(from url: URL) throws {
        project = try persistence.load(from: url)
        // Auto-create master tracks for old projects that don't have them
        for i in project.songs.indices {
            project.songs[i].ensureMasterTrack()
        }
        currentSongID = project.songs.first?.id
        projectURL = url
        hasUnsavedChanges = false
        undoManager?.removeAllActions()
        clearUndoHistory()
    }

    /// Clears the undo history panel.
    public func clearUndoHistory() {
        undoHistory.removeAll()
        undoHistoryCursor = -1
    }

    // MARK: - Song Access

    /// ID of the currently selected song.
    public var currentSongID: ID<Song>?

    /// Index of the currently active song.
    public var currentSongIndex: Int {
        get {
            if let id = currentSongID,
               let index = project.songs.firstIndex(where: { $0.id == id }) {
                return index
            }
            return min(_currentSongIndex, max(project.songs.count - 1, 0))
        }
        set {
            _currentSongIndex = newValue
            if project.songs.indices.contains(newValue) {
                currentSongID = project.songs[newValue].id
            }
        }
    }
    private var _currentSongIndex: Int = 0

    /// The currently active song, if any.
    public var currentSong: Song? {
        guard !project.songs.isEmpty else { return nil }
        return project.songs[currentSongIndex]
    }

    // MARK: - Song Management

    /// Called when the active song changes (e.g. sidebar click or setlist navigation).
    /// The view layer wires this to TransportViewModel to reset the playhead
    /// and restart playback for the new song.
    public var onSongChanged: (() -> Void)?

    /// Selects a song by its ID.
    public func selectSong(id: ID<Song>) {
        guard project.songs.contains(where: { $0.id == id }) else { return }
        let previousSongID = currentSongID
        currentSongID = id
        selectedContainerID = nil
        if id != previousSongID {
            onSongChanged?()
        }
    }

    /// Adds a new song with default settings (including master track).
    public func addSong() {
        registerUndo(actionName: "Add Song")
        let existingCount = project.songs.count
        var song = Song(name: "Song \(existingCount + 1)")
        song.ensureMasterTrack()
        project.songs.append(song)
        currentSongID = song.id
        hasUnsavedChanges = true
    }

    /// Removes a song by ID. Will not remove the last remaining song.
    public func removeSong(id: ID<Song>) {
        guard project.songs.count > 1 else { return }
        guard let index = project.songs.firstIndex(where: { $0.id == id }) else { return }

        registerUndo(actionName: "Remove Song")
        let wasSelected = currentSongID == id
        project.songs.remove(at: index)

        if wasSelected {
            // Select the nearest song
            let newIndex = min(index, project.songs.count - 1)
            currentSongID = project.songs[newIndex].id
            selectedContainerID = nil
        }
        hasUnsavedChanges = true
    }

    /// Renames a song.
    public func renameSong(id: ID<Song>, newName: String) {
        guard let index = project.songs.firstIndex(where: { $0.id == id }) else { return }
        registerUndo(actionName: "Rename Song")
        project.songs[index].name = newName
        hasUnsavedChanges = true
    }

    /// Sets the metronome configuration for a song.
    public func setMetronomeConfig(songID: ID<Song>, config: MetronomeConfig) {
        guard let index = project.songs.firstIndex(where: { $0.id == songID }) else { return }
        guard project.songs[index].metronomeConfig != config else { return }
        registerUndo(actionName: "Set Metronome Config")
        project.songs[index].metronomeConfig = config
        hasUnsavedChanges = true
    }

    /// Sets the count-in bars for a song.
    public func setCountInBars(songID: ID<Song>, bars: Int) {
        guard let index = project.songs.firstIndex(where: { $0.id == songID }) else { return }
        guard project.songs[index].countInBars != bars else { return }
        registerUndo(actionName: "Set Count-In")
        project.songs[index].countInBars = bars
        hasUnsavedChanges = true
    }

    /// Sets the time signature for a song.
    /// Validates beatsPerBar (1–12) and beatUnit (2, 4, 8, or 16).
    public func setTimeSignature(songID: ID<Song>, beatsPerBar: Int, beatUnit: Int) {
        guard let index = project.songs.firstIndex(where: { $0.id == songID }) else { return }
        guard (1...12).contains(beatsPerBar) else { return }
        guard [2, 4, 8, 16].contains(beatUnit) else { return }
        let newTS = TimeSignature(beatsPerBar: beatsPerBar, beatUnit: beatUnit)
        guard project.songs[index].timeSignature != newTS else { return }
        registerUndo(actionName: "Set Time Signature")
        project.songs[index].timeSignature = newTS
        hasUnsavedChanges = true
    }

    /// Duplicates a song and selects the copy.
    public func duplicateSong(id: ID<Song>) {
        guard let index = project.songs.firstIndex(where: { $0.id == id }) else { return }
        registerUndo(actionName: "Duplicate Song")
        let original = project.songs[index]
        let copy = Song(
            name: original.name + " Copy",
            tempo: original.tempo,
            timeSignature: original.timeSignature,
            tracks: original.tracks.map { track in
                Track(
                    name: track.name,
                    kind: track.kind,
                    volume: track.volume,
                    pan: track.pan,
                    isMuted: track.isMuted,
                    isSoloed: track.isSoloed,
                    containers: track.containers.map { container in
                        Container(
                            name: container.name,
                            startBar: container.startBar,
                            lengthBars: container.lengthBars,
                            sourceRecordingID: container.sourceRecordingID,
                            linkGroupID: container.linkGroupID,
                            loopSettings: container.loopSettings,
                            parentContainerID: container.parentContainerID,
                            overriddenFields: container.overriddenFields,
                            metronomeSettings: container.metronomeSettings
                        )
                    },
                    insertEffects: track.insertEffects,
                    sendLevels: track.sendLevels,
                    instrumentComponent: track.instrumentComponent,
                    midiInputDeviceID: track.midiInputDeviceID,
                    midiInputChannel: track.midiInputChannel,
                    isRecordArmed: track.isRecordArmed,
                    isMonitoring: track.isMonitoring,
                    trackAutomationLanes: track.trackAutomationLanes,
                    expressionPedalCC: track.expressionPedalCC,
                    expressionPedalTarget: track.expressionPedalTarget,
                    orderIndex: track.orderIndex
                )
            },
            countInBars: original.countInBars,
            sections: original.sections.map { section in
                SectionRegion(
                    name: section.name,
                    startBar: section.startBar,
                    lengthBars: section.lengthBars,
                    color: section.color,
                    notes: section.notes
                )
            },
            metronomeConfig: original.metronomeConfig
        )
        project.songs.insert(copy, at: index + 1)
        currentSongID = copy.id
        hasUnsavedChanges = true
    }

    // MARK: - Track Management

    /// Adds a new track to the current song with auto-generated name.
    /// Master tracks cannot be added manually (they are auto-created).
    public func addTrack(kind: TrackKind) {
        guard !project.songs.isEmpty else { return }
        guard kind != .master else { return }
        registerUndo(actionName: "Add Track")
        let existingCount = project.songs[currentSongIndex].tracks
            .filter { $0.kind == kind }.count
        let name = "\(kind.displayName) \(existingCount + 1)"
        let orderIndex = project.songs[currentSongIndex].tracks.count
        let track = Track(name: name, kind: kind, orderIndex: orderIndex)
        project.songs[currentSongIndex].tracks.append(track)
        project.songs[currentSongIndex].ensureMasterTrackLast()
        reindexTracks()
        hasUnsavedChanges = true
    }

    /// Inserts a new track at a specific index in the current song.
    /// The track is inserted before the master track if atIndex >= master position.
    public func insertTrack(kind: TrackKind, atIndex index: Int) {
        guard !project.songs.isEmpty else { return }
        guard kind != .master else { return }
        registerUndo(actionName: "Insert Track")
        let existingCount = project.songs[currentSongIndex].tracks
            .filter { $0.kind == kind }.count
        let name = "\(kind.displayName) \(existingCount + 1)"
        let clampedIndex = min(index, project.songs[currentSongIndex].tracks.count)
        let track = Track(name: name, kind: kind, orderIndex: clampedIndex)
        project.songs[currentSongIndex].tracks.insert(track, at: clampedIndex)
        project.songs[currentSongIndex].ensureMasterTrackLast()
        reindexTracks()
        hasUnsavedChanges = true
    }

    /// Removes a track from the current song by ID.
    /// Master tracks cannot be deleted.
    public func removeTrack(id: ID<Track>) {
        guard !project.songs.isEmpty else { return }
        // Prevent deleting the master track
        if let track = project.songs[currentSongIndex].tracks.first(where: { $0.id == id }),
           track.kind == .master { return }
        registerUndo(actionName: "Remove Track")
        project.songs[currentSongIndex].tracks.removeAll { $0.id == id }
        reindexTracks()
        hasUnsavedChanges = true
    }

    /// Renames a track in the current song.
    public func renameTrack(id: ID<Track>, newName: String) {
        guard !project.songs.isEmpty else { return }
        guard let index = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == id }) else { return }
        registerUndo(actionName: "Rename Track")
        project.songs[currentSongIndex].tracks[index].name = newName
        hasUnsavedChanges = true
    }

    /// Moves a track from one index to another (reordering).
    /// Master track is pinned to the bottom and cannot be moved.
    public func moveTrack(from source: IndexSet, to destination: Int) {
        guard !project.songs.isEmpty else { return }
        // Prevent moving the master track
        let tracks = project.songs[currentSongIndex].tracks
        for idx in source {
            if tracks.indices.contains(idx) && tracks[idx].kind == .master { return }
        }
        registerUndo(actionName: "Reorder Tracks")
        project.songs[currentSongIndex].tracks.move(fromOffsets: source, toOffset: destination)
        project.songs[currentSongIndex].ensureMasterTrackLast()
        reindexTracks()
        hasUnsavedChanges = true
    }

    /// Toggles mute on a track.
    public func toggleMute(trackID: ID<Track>) {
        guard !project.songs.isEmpty else { return }
        guard let index = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        registerUndo(actionName: "Toggle Mute")
        project.songs[currentSongIndex].tracks[index].isMuted.toggle()
        hasUnsavedChanges = true
    }

    /// Toggles solo on a track.
    public func toggleSolo(trackID: ID<Track>) {
        guard !project.songs.isEmpty else { return }
        guard let index = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        registerUndo(actionName: "Toggle Solo")
        project.songs[currentSongIndex].tracks[index].isSoloed.toggle()
        hasUnsavedChanges = true
    }

    /// Sets the record-arm state on a track.
    public func setTrackRecordArmed(trackID: ID<Track>, armed: Bool) {
        guard !project.songs.isEmpty else { return }
        guard let index = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard project.songs[currentSongIndex].tracks[index].isRecordArmed != armed else { return }
        registerUndo(actionName: armed ? "Arm Track" : "Disarm Track")
        project.songs[currentSongIndex].tracks[index].isRecordArmed = armed
        hasUnsavedChanges = true
    }

    /// Sets the input monitoring state on a track.
    public func setTrackMonitoring(trackID: ID<Track>, monitoring: Bool) {
        guard !project.songs.isEmpty else { return }
        guard let index = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard project.songs[currentSongIndex].tracks[index].isMonitoring != monitoring else { return }
        registerUndo(actionName: monitoring ? "Enable Input Monitor" : "Disable Input Monitor")
        project.songs[currentSongIndex].tracks[index].isMonitoring = monitoring
        hasUnsavedChanges = true
    }

    /// Sets the volume on a track.
    public func setTrackVolume(trackID: ID<Track>, volume: Float) {
        guard !project.songs.isEmpty else { return }
        guard let index = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        registerUndo(actionName: "Adjust Volume")
        project.songs[currentSongIndex].tracks[index].volume = max(0, min(volume, 2.0))
        hasUnsavedChanges = true
    }

    /// Sets the input port for a track.
    public func setTrackInputPort(trackID: ID<Track>, portID: String?) {
        guard !project.songs.isEmpty else { return }
        guard let index = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        registerUndo(actionName: "Set Input Port")
        project.songs[currentSongIndex].tracks[index].inputPortID = portID
        hasUnsavedChanges = true
    }

    /// Sets the output port for a track.
    public func setTrackOutputPort(trackID: ID<Track>, portID: String?) {
        guard !project.songs.isEmpty else { return }
        guard let index = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        registerUndo(actionName: "Set Output Port")
        project.songs[currentSongIndex].tracks[index].outputPortID = portID
        hasUnsavedChanges = true
    }

    /// Sets the MIDI input device and channel for a track.
    public func setTrackMIDIInput(trackID: ID<Track>, deviceID: String?, channel: UInt8?) {
        guard !project.songs.isEmpty else { return }
        guard let index = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        registerUndo(actionName: "Set MIDI Input")
        project.songs[currentSongIndex].tracks[index].midiInputDeviceID = deviceID
        project.songs[currentSongIndex].tracks[index].midiInputChannel = channel
        hasUnsavedChanges = true
    }

    /// Sets the pan on a track.
    public func setTrackPan(trackID: ID<Track>, pan: Float) {
        guard !project.songs.isEmpty else { return }
        guard let index = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        registerUndo(actionName: "Adjust Pan")
        project.songs[currentSongIndex].tracks[index].pan = max(-1.0, min(pan, 1.0))
        hasUnsavedChanges = true
    }

    /// Sets a send level on a track.
    public func setTrackSendLevel(trackID: ID<Track>, sendIndex: Int, level: Float) {
        guard !project.songs.isEmpty else { return }
        guard let index = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard sendIndex < project.songs[currentSongIndex].tracks[index].sendLevels.count else { return }
        registerUndo(actionName: "Adjust Send Level")
        project.songs[currentSongIndex].tracks[index].sendLevels[sendIndex].level = max(0.0, min(level, 1.0))
        hasUnsavedChanges = true
    }

    private func reindexTracks() {
        guard !project.songs.isEmpty else { return }
        for i in project.songs[currentSongIndex].tracks.indices {
            project.songs[currentSongIndex].tracks[i].orderIndex = i
        }
    }

    // MARK: - Master Track Management

    /// Adds an insert effect to the master track.
    public func addMasterEffect(effect: InsertEffect) {
        guard !project.songs.isEmpty else { return }
        guard let masterIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.kind == .master }) else { return }
        registerUndo(actionName: "Add Master Effect")
        var newEffect = effect
        newEffect.orderIndex = project.songs[currentSongIndex].tracks[masterIndex].insertEffects.count
        project.songs[currentSongIndex].tracks[masterIndex].insertEffects.append(newEffect)
        hasUnsavedChanges = true
    }

    /// Removes an insert effect from the master track.
    public func removeMasterEffect(effectID: ID<InsertEffect>) {
        guard !project.songs.isEmpty else { return }
        guard let masterIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.kind == .master }) else { return }
        registerUndo(actionName: "Remove Master Effect")
        project.songs[currentSongIndex].tracks[masterIndex].insertEffects.removeAll { $0.id == effectID }
        for i in project.songs[currentSongIndex].tracks[masterIndex].insertEffects.indices {
            project.songs[currentSongIndex].tracks[masterIndex].insertEffects[i].orderIndex = i
        }
        hasUnsavedChanges = true
    }

    /// Toggles bypass on the master track's entire effect chain.
    public func toggleMasterEffectChainBypass() {
        guard !project.songs.isEmpty else { return }
        guard let masterIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.kind == .master }) else { return }
        registerUndo(actionName: "Toggle Master Effect Bypass")
        project.songs[currentSongIndex].tracks[masterIndex].isEffectChainBypassed.toggle()
        hasUnsavedChanges = true
    }

    /// Sets the output port on the master track.
    public func setMasterOutputPort(portID: String?) {
        guard !project.songs.isEmpty else { return }
        guard let masterIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.kind == .master }) else { return }
        registerUndo(actionName: "Set Master Output")
        project.songs[currentSongIndex].tracks[masterIndex].outputPortID = portID
        hasUnsavedChanges = true
    }

    // MARK: - Track Effect Management

    /// Adds an insert effect to a track.
    public func addTrackEffect(trackID: ID<Track>, effect: InsertEffect) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        registerUndo(actionName: "Add Track Effect")
        var newEffect = effect
        newEffect.orderIndex = project.songs[currentSongIndex].tracks[trackIndex].insertEffects.count
        project.songs[currentSongIndex].tracks[trackIndex].insertEffects.append(newEffect)
        hasUnsavedChanges = true
    }

    /// Removes an insert effect from a track.
    public func removeTrackEffect(trackID: ID<Track>, effectID: ID<InsertEffect>) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        registerUndo(actionName: "Remove Track Effect")
        project.songs[currentSongIndex].tracks[trackIndex].insertEffects.removeAll { $0.id == effectID }
        for i in project.songs[currentSongIndex].tracks[trackIndex].insertEffects.indices {
            project.songs[currentSongIndex].tracks[trackIndex].insertEffects[i].orderIndex = i
        }
        hasUnsavedChanges = true
    }

    /// Reorders a track's insert effects by moving from source indices to a destination index.
    public func reorderTrackEffects(trackID: ID<Track>, from source: IndexSet, to destination: Int) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        registerUndo(actionName: "Reorder Track Effects")
        project.songs[currentSongIndex].tracks[trackIndex].insertEffects.sort { $0.orderIndex < $1.orderIndex }
        project.songs[currentSongIndex].tracks[trackIndex].insertEffects.move(fromOffsets: source, toOffset: destination)
        for i in project.songs[currentSongIndex].tracks[trackIndex].insertEffects.indices {
            project.songs[currentSongIndex].tracks[trackIndex].insertEffects[i].orderIndex = i
        }
        hasUnsavedChanges = true
    }

    /// Toggles bypass on a single effect within a track.
    public func toggleTrackEffectBypass(trackID: ID<Track>, effectID: ID<InsertEffect>) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard let effectIndex = project.songs[currentSongIndex].tracks[trackIndex].insertEffects.firstIndex(where: { $0.id == effectID }) else { return }
        registerUndo(actionName: "Toggle Track Effect Bypass")
        project.songs[currentSongIndex].tracks[trackIndex].insertEffects[effectIndex].isBypassed.toggle()
        hasUnsavedChanges = true
    }

    /// Toggles bypass on a track's entire effect chain.
    public func toggleTrackEffectChainBypass(trackID: ID<Track>) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        registerUndo(actionName: "Toggle Track Effect Chain Bypass")
        project.songs[currentSongIndex].tracks[trackIndex].isEffectChainBypassed.toggle()
        hasUnsavedChanges = true
    }

    // MARK: - Selection State

    /// The currently selected single track ID (for keyboard operations like record arm).
    /// Setting this clears selectedContainerID for mutual exclusion.
    public var selectedTrackID: ID<Track>? {
        didSet {
            if selectedTrackID != nil {
                selectedContainerID = nil
                selectedContainerIDs = []
            }
        }
    }

    /// Set of all selected container IDs (populated by select-all; cleared on single-select or deselect).
    public var selectedContainerIDs: Set<ID<Container>> = []

    /// Selects all containers in the current song.
    public func selectAllContainers() {
        guard let song = currentSong else { return }
        let allIDs = Set(song.tracks.flatMap(\.containers).map(\.id))
        selectedContainerIDs = allIDs
        // Also set single selection to nil since multiple are selected
        selectedContainerID = nil
    }

    /// Clears all selection state (container, track, section, multi-select).
    public func deselectAll() {
        selectedContainerID = nil
        selectedContainerIDs = []
        selectedTrackID = nil
        selectedSectionID = nil
    }

    /// Selects a track by 0-based index in the current song.
    public func selectTrackByIndex(_ index: Int) {
        guard let song = currentSong, song.tracks.indices.contains(index) else { return }
        selectedTrackID = song.tracks[index].id
    }

    /// The last bar with content (containers or sections) in the current song. Returns 1 if empty.
    public var lastBarWithContent: Int {
        guard let song = currentSong else { return 1 }
        let containerMax = song.tracks.flatMap(\.containers).map(\.endBar).max() ?? 1
        let sectionMax = song.sections.map(\.endBar).max() ?? 1
        return max(containerMax, sectionMax, 1)
    }

    // MARK: - Container Management

    /// The currently selected container ID.
    /// Setting this clears selectedTrackID for mutual exclusion.
    public var selectedContainerID: ID<Container>? {
        didSet {
            if selectedContainerID != nil {
                selectedTrackID = nil
            }
        }
    }

    /// Adds a container to a track. Returns false if it would overlap an existing container.
    public func addContainer(trackID: ID<Track>, startBar: Int, lengthBars: Int) -> Bool {
        guard !project.songs.isEmpty else { return false }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return false }
        registerUndo(actionName: "Add Container")

        let newContainer = Container(
            name: "Container",
            startBar: max(startBar, 1),
            lengthBars: max(lengthBars, 1)
        )

        if hasOverlap(in: project.songs[currentSongIndex].tracks[trackIndex], with: newContainer) {
            return false
        }

        project.songs[currentSongIndex].tracks[trackIndex].containers.append(newContainer)
        selectedContainerID = newContainer.id
        hasUnsavedChanges = true
        return true
    }

    /// Removes a container from its track.
    public func removeContainer(trackID: ID<Track>, containerID: ID<Container>) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        registerUndo(actionName: "Remove Container")
        project.songs[currentSongIndex].tracks[trackIndex].containers.removeAll { $0.id == containerID }
        if selectedContainerID == containerID {
            selectedContainerID = nil
        }
        hasUnsavedChanges = true
    }

    /// Moves a container to a new start bar. Returns false if it would overlap.
    public func moveContainer(trackID: ID<Track>, containerID: ID<Container>, newStartBar: Int) -> Bool {
        guard !project.songs.isEmpty else { return false }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return false }
        guard let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) else { return false }
        registerUndo(actionName: "Move Container")

        let clampedStart = max(newStartBar, 1)
        var proposed = project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex]
        proposed.startBar = clampedStart

        if hasOverlap(in: project.songs[currentSongIndex].tracks[trackIndex], with: proposed, excluding: containerID) {
            return false
        }

        project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].startBar = clampedStart
        hasUnsavedChanges = true
        return true
    }

    /// Resizes a container. Returns false if it would overlap.
    public func resizeContainer(trackID: ID<Track>, containerID: ID<Container>, newStartBar: Int? = nil, newLengthBars: Int? = nil) -> Bool {
        guard !project.songs.isEmpty else { return false }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return false }
        guard let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) else { return false }
        registerUndo(actionName: "Resize Container")

        var proposed = project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex]
        if let start = newStartBar { proposed.startBar = max(start, 1) }
        if let length = newLengthBars { proposed.lengthBars = max(length, 1) }

        if hasOverlap(in: project.songs[currentSongIndex].tracks[trackIndex], with: proposed, excluding: containerID) {
            return false
        }

        if let start = newStartBar {
            project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].startBar = max(start, 1)
        }
        if let length = newLengthBars {
            project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].lengthBars = max(length, 1)
        }
        hasUnsavedChanges = true
        return true
    }

    /// Toggles record-arm on a container.
    public func toggleContainerRecordArm(trackID: ID<Track>, containerID: ID<Container>) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) else { return }
        registerUndo(actionName: "Toggle Record Arm")
        project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].isRecordArmed.toggle()
        hasUnsavedChanges = true
    }

    /// Updates the source recording for a container after recording completes.
    /// Propagates the recording to all linked containers (clones and link group members).
    public func setContainerRecording(trackID: ID<Track>, containerID: ID<Container>, recording: SourceRecording) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) else { return }

        registerUndo(actionName: "Set Recording")
        // Add recording to project
        project.sourceRecordings[recording.id] = recording
        // Update container reference
        project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].sourceRecordingID = recording.id
        project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].isRecordArmed = false

        // If recording into a clone, mark .sourceRecording as overridden
        if project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].parentContainerID != nil {
            project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].overriddenFields.insert(.sourceRecording)
        }

        // Propagate recording to linked containers:
        // 1. Clones of this container (parentContainerID == containerID) that don't override .sourceRecording
        // 2. Containers in the same linkGroupID that don't override .sourceRecording
        let recordedContainer = project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex]
        let allContainers = project.songs[currentSongIndex].tracks.flatMap(\.containers)
        var linkedContainersToSchedule: [Container] = []

        for ti in project.songs[currentSongIndex].tracks.indices {
            let track = project.songs[currentSongIndex].tracks[ti]
            if track.kind == .master { continue }
            for ci in track.containers.indices {
                let c = track.containers[ci]
                if c.id == containerID { continue }

                let isCloneOfRecorded = c.parentContainerID == containerID
                let sharesLinkGroup = recordedContainer.linkGroupID != nil
                    && c.linkGroupID == recordedContainer.linkGroupID
                let overridesRecording = c.overriddenFields.contains(.sourceRecording)

                if (isCloneOfRecorded || sharesLinkGroup) && !overridesRecording {
                    project.songs[currentSongIndex].tracks[ti].containers[ci].sourceRecordingID = recording.id
                    // Collect the resolved container for scheduling
                    let updated = project.songs[currentSongIndex].tracks[ti].containers[ci]
                    let resolved = updated.resolved { id in allContainers.first(where: { $0.id == id }) }
                    linkedContainersToSchedule.append(resolved)
                }
            }
        }

        // Clear live recording peaks now that final peaks are in the SourceRecording
        liveRecordingPeaks.removeValue(forKey: containerID)
        // Also clear live peaks from linked containers
        for linked in linkedContainersToSchedule {
            liveRecordingPeaks.removeValue(forKey: linked.id)
        }

        hasUnsavedChanges = true

        // Notify scheduler to register the audio file and schedule linked containers
        if !linkedContainersToSchedule.isEmpty {
            onRecordingPropagated?(recording.id, recording.filename, linkedContainersToSchedule)
        }
    }

    /// Updates the loop settings for a container.
    public func updateContainerLoopSettings(containerID: ID<Container>, settings: LoopSettings) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: "Change Loop Settings")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].loopSettings = settings
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .loopSettings)
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Updates the name of a container.
    public func updateContainerName(containerID: ID<Container>, name: String) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: "Rename Container")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].name = name
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .name)
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Links containers by setting the same linkGroupID.
    public func linkContainers(containerIDs: [ID<Container>]) {
        guard !project.songs.isEmpty, containerIDs.count >= 2 else { return }
        registerUndo(actionName: "Link Containers")
        let linkGroupID = ID<LinkGroup>()
        // Find the first container's source recording to share
        var sharedSourceID: ID<SourceRecording>?
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            for containerIndex in project.songs[currentSongIndex].tracks[trackIndex].containers.indices {
                let container = project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex]
                if containerIDs.contains(container.id) {
                    if sharedSourceID == nil {
                        sharedSourceID = container.sourceRecordingID
                    }
                    project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].linkGroupID = linkGroupID
                    if let srcID = sharedSourceID {
                        project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].sourceRecordingID = srcID
                    }
                }
            }
        }
        hasUnsavedChanges = true
    }

    /// Unlinks a container by clearing its linkGroupID.
    public func unlinkContainer(containerID: ID<Container>) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: "Unlink Container")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].linkGroupID = nil
                hasUnsavedChanges = true
                return
            }
        }
    }

    // MARK: - Container Effect Management

    /// Adds an insert effect to a container.
    public func addContainerEffect(containerID: ID<Container>, effect: InsertEffect) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: "Add Container Effect")
                var newEffect = effect
                newEffect.orderIndex = project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].insertEffects.count
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].insertEffects.append(newEffect)
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .effects)
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Removes an insert effect from a container.
    public func removeContainerEffect(containerID: ID<Container>, effectID: ID<InsertEffect>) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: "Remove Container Effect")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].insertEffects.removeAll { $0.id == effectID }
                for i in project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].insertEffects.indices {
                    project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].insertEffects[i].orderIndex = i
                }
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .effects)
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Toggles bypass on a container's entire effect chain.
    public func toggleContainerEffectChainBypass(containerID: ID<Container>) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: "Toggle Effect Chain Bypass")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].isEffectChainBypassed.toggle()
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .effects)
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Reorders a container's insert effects by moving from source indices to a destination index.
    public func reorderContainerEffects(containerID: ID<Container>, from source: IndexSet, to destination: Int) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: "Reorder Effects")
                // Sort effects by orderIndex before reordering
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].insertEffects.sort { $0.orderIndex < $1.orderIndex }
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].insertEffects.move(fromOffsets: source, toOffset: destination)
                for i in project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].insertEffects.indices {
                    project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].insertEffects[i].orderIndex = i
                }
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .effects)
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Toggles bypass on a single effect within a container.
    public func toggleContainerEffectBypass(containerID: ID<Container>, effectID: ID<InsertEffect>) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                if let effectIndex = project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].insertEffects.firstIndex(where: { $0.id == effectID }) {
                    registerUndo(actionName: "Toggle Effect Bypass")
                    project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].insertEffects[effectIndex].isBypassed.toggle()
                    markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .effects)
                    hasUnsavedChanges = true
                    return
                }
            }
        }
    }

    /// Updates the preset data for an insert effect within a container.
    public func updateContainerEffectPreset(containerID: ID<Container>, effectID: ID<InsertEffect>, presetData: Data?) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                if let effectIndex = project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].insertEffects.firstIndex(where: { $0.id == effectID }) {
                    registerUndo(actionName: "Update Effect Preset")
                    project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].insertEffects[effectIndex].presetData = presetData
                    markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .effects)
                    hasUnsavedChanges = true
                    return
                }
            }
        }
    }

    // MARK: - Container Instrument Override

    /// Sets or clears the instrument override on a container.
    public func setContainerInstrumentOverride(containerID: ID<Container>, override: AudioComponentInfo?) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: override != nil ? "Set Instrument Override" : "Remove Instrument Override")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].instrumentOverride = override
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .instrumentOverride)
                hasUnsavedChanges = true
                return
            }
        }
    }

    // MARK: - Container Fade Settings

    /// Sets or clears the enter fade on a container.
    public func setContainerEnterFade(containerID: ID<Container>, fade: FadeSettings?) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: fade != nil ? "Set Enter Fade" : "Remove Enter Fade")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].enterFade = fade
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .fades)
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Sets or clears the exit fade on a container.
    public func setContainerExitFade(containerID: ID<Container>, fade: FadeSettings?) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: fade != nil ? "Set Exit Fade" : "Remove Exit Fade")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].exitFade = fade
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .fades)
                hasUnsavedChanges = true
                return
            }
        }
    }

    // MARK: - Container Enter/Exit Actions

    /// Adds an action to a container's enter action list.
    public func addContainerEnterAction(containerID: ID<Container>, action: ContainerAction) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: "Add Enter Action")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].onEnterActions.append(action)
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .enterActions)
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Removes an action from a container's enter action list.
    public func removeContainerEnterAction(containerID: ID<Container>, actionID: ID<ContainerAction>) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: "Remove Enter Action")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].onEnterActions.removeAll { $0.id == actionID }
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .enterActions)
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Adds an action to a container's exit action list.
    public func addContainerExitAction(containerID: ID<Container>, action: ContainerAction) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: "Add Exit Action")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].onExitActions.append(action)
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .exitActions)
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Removes an action from a container's exit action list.
    public func removeContainerExitAction(containerID: ID<Container>, actionID: ID<ContainerAction>) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: "Remove Exit Action")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].onExitActions.removeAll { $0.id == actionID }
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .exitActions)
                hasUnsavedChanges = true
                return
            }
        }
    }

    // MARK: - Container Automation Lanes

    /// Adds an automation lane to a container.
    public func addAutomationLane(containerID: ID<Container>, lane: AutomationLane) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: "Add Automation Lane")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].automationLanes.append(lane)
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .automation)
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Removes an automation lane from a container.
    public func removeAutomationLane(containerID: ID<Container>, laneID: ID<AutomationLane>) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: "Remove Automation Lane")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].automationLanes.removeAll { $0.id == laneID }
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .automation)
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Adds a breakpoint to an automation lane on a container.
    public func addAutomationBreakpoint(containerID: ID<Container>, laneID: ID<AutomationLane>, breakpoint: AutomationBreakpoint) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                if let laneIndex = project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].automationLanes.firstIndex(where: { $0.id == laneID }) {
                    registerUndo(actionName: "Add Breakpoint")
                    project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].automationLanes[laneIndex].breakpoints.append(breakpoint)
                    markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .automation)
                    hasUnsavedChanges = true
                    return
                }
            }
        }
    }

    /// Removes a breakpoint from an automation lane on a container.
    public func removeAutomationBreakpoint(containerID: ID<Container>, laneID: ID<AutomationLane>, breakpointID: ID<AutomationBreakpoint>) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                if let laneIndex = project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].automationLanes.firstIndex(where: { $0.id == laneID }) {
                    registerUndo(actionName: "Remove Breakpoint")
                    project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].automationLanes[laneIndex].breakpoints.removeAll { $0.id == breakpointID }
                    markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .automation)
                    hasUnsavedChanges = true
                    return
                }
            }
        }
    }

    /// Updates a breakpoint in an automation lane on a container.
    public func updateAutomationBreakpoint(containerID: ID<Container>, laneID: ID<AutomationLane>, breakpoint: AutomationBreakpoint) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                if let laneIndex = project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].automationLanes.firstIndex(where: { $0.id == laneID }) {
                    if let bpIndex = project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].automationLanes[laneIndex].breakpoints.firstIndex(where: { $0.id == breakpoint.id }) {
                        registerUndo(actionName: "Edit Breakpoint")
                        project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].automationLanes[laneIndex].breakpoints[bpIndex] = breakpoint
                        markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .automation)
                        hasUnsavedChanges = true
                        return
                    }
                }
            }
        }
    }

    // MARK: - Track Automation Lanes

    /// Adds an automation lane to a track (for volume/pan automation).
    public func addTrackAutomationLane(trackID: ID<Track>, lane: AutomationLane) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        registerUndo(actionName: "Add Track Automation Lane")
        project.songs[currentSongIndex].tracks[trackIndex].trackAutomationLanes.append(lane)
        hasUnsavedChanges = true
    }

    /// Removes an automation lane from a track.
    public func removeTrackAutomationLane(trackID: ID<Track>, laneID: ID<AutomationLane>) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        registerUndo(actionName: "Remove Track Automation Lane")
        project.songs[currentSongIndex].tracks[trackIndex].trackAutomationLanes.removeAll { $0.id == laneID }
        hasUnsavedChanges = true
    }

    /// Adds a breakpoint to a track-level automation lane.
    public func addTrackAutomationBreakpoint(trackID: ID<Track>, laneID: ID<AutomationLane>, breakpoint: AutomationBreakpoint) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard let laneIndex = project.songs[currentSongIndex].tracks[trackIndex].trackAutomationLanes.firstIndex(where: { $0.id == laneID }) else { return }
        registerUndo(actionName: "Add Breakpoint")
        project.songs[currentSongIndex].tracks[trackIndex].trackAutomationLanes[laneIndex].breakpoints.append(breakpoint)
        hasUnsavedChanges = true
    }

    /// Removes a breakpoint from a track-level automation lane.
    public func removeTrackAutomationBreakpoint(trackID: ID<Track>, laneID: ID<AutomationLane>, breakpointID: ID<AutomationBreakpoint>) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard let laneIndex = project.songs[currentSongIndex].tracks[trackIndex].trackAutomationLanes.firstIndex(where: { $0.id == laneID }) else { return }
        registerUndo(actionName: "Remove Breakpoint")
        project.songs[currentSongIndex].tracks[trackIndex].trackAutomationLanes[laneIndex].breakpoints.removeAll { $0.id == breakpointID }
        hasUnsavedChanges = true
    }

    /// Updates a breakpoint in a track-level automation lane.
    public func updateTrackAutomationBreakpoint(trackID: ID<Track>, laneID: ID<AutomationLane>, breakpoint: AutomationBreakpoint) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard let laneIndex = project.songs[currentSongIndex].tracks[trackIndex].trackAutomationLanes.firstIndex(where: { $0.id == laneID }) else { return }
        guard let bpIndex = project.songs[currentSongIndex].tracks[trackIndex].trackAutomationLanes[laneIndex].breakpoints.firstIndex(where: { $0.id == breakpoint.id }) else { return }
        registerUndo(actionName: "Edit Breakpoint")
        project.songs[currentSongIndex].tracks[trackIndex].trackAutomationLanes[laneIndex].breakpoints[bpIndex] = breakpoint
        hasUnsavedChanges = true
    }

    /// Returns the selected container if one is selected.
    public var selectedContainer: Container? {
        guard let id = selectedContainerID, let song = currentSong else { return nil }
        for track in song.tracks {
            if let container = track.containers.first(where: { $0.id == id }) {
                return container
            }
        }
        return nil
    }

    /// Returns all containers in the current song (across all tracks).
    public var allContainersInCurrentSong: [Container] {
        guard let song = currentSong else { return [] }
        return song.tracks.flatMap(\.containers)
    }

    /// Returns all tracks in the current song.
    public var allTracksInCurrentSong: [Track] {
        guard let song = currentSong else { return [] }
        return song.tracks
    }

    /// Returns the track containing the selected container.
    public var selectedContainerTrack: Track? {
        guard let id = selectedContainerID, let song = currentSong else { return nil }
        for track in song.tracks {
            if track.containers.contains(where: { $0.id == id }) {
                return track
            }
        }
        return nil
    }

    /// Returns the track kind of the track containing the selected container.
    public var selectedContainerTrackKind: TrackKind? {
        selectedContainerTrack?.kind
    }

    /// Returns the currently selected track (via selectedTrackID).
    public var selectedTrack: Track? {
        guard let id = selectedTrackID, let song = currentSong else { return nil }
        return song.tracks.first(where: { $0.id == id })
    }

    // MARK: - Container Clone Management

    /// Creates a linked clone of a container at a new position on the same track.
    /// Cloning a clone links to the original parent (no nesting).
    /// Returns the new clone's ID, or nil if the clone would overlap.
    @discardableResult
    public func cloneContainer(trackID: ID<Track>, containerID: ID<Container>, newStartBar: Int) -> ID<Container>? {
        guard !project.songs.isEmpty else { return nil }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return nil }
        guard let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) else { return nil }

        let source = project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex]

        // No nested clones: link to original parent if source is already a clone
        let parentID = source.parentContainerID ?? source.id

        let clone = Container(
            name: source.name,
            startBar: max(newStartBar, 1),
            lengthBars: source.lengthBars,
            sourceRecordingID: source.sourceRecordingID,
            linkGroupID: source.linkGroupID,
            loopSettings: source.loopSettings,
            insertEffects: source.insertEffects,
            isEffectChainBypassed: source.isEffectChainBypassed,
            instrumentOverride: source.instrumentOverride,
            enterFade: source.enterFade,
            exitFade: source.exitFade,
            onEnterActions: source.onEnterActions,
            onExitActions: source.onExitActions,
            automationLanes: source.automationLanes,
            parentContainerID: parentID,
            overriddenFields: []
        )

        if hasOverlap(in: project.songs[currentSongIndex].tracks[trackIndex], with: clone) {
            return nil
        }

        registerUndo(actionName: "Clone Container")
        project.songs[currentSongIndex].tracks[trackIndex].containers.append(clone)
        selectedContainerID = clone.id
        hasUnsavedChanges = true
        return clone.id
    }

    /// Disconnects a clone from its parent, making it a standalone container.
    /// All fields become local (adds all fields to overriddenFields, clears parentContainerID).
    public func consolidateContainer(trackID: ID<Track>, containerID: ID<Container>) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) else { return }
        guard project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].parentContainerID != nil else { return }

        registerUndo(actionName: "Consolidate Container")

        // Resolve all inherited fields from parent before disconnecting
        let container = project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex]
        let allContainers = project.songs[currentSongIndex].tracks.flatMap(\.containers)
        let resolved = container.resolved { id in allContainers.first(where: { $0.id == id }) }

        project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex] = resolved
        project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].parentContainerID = nil
        project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].overriddenFields = Set(ContainerField.allCases)
        hasUnsavedChanges = true
    }

    /// Finds a container by ID across all tracks in the current song.
    public func findContainer(id: ID<Container>) -> Container? {
        guard let song = currentSong else { return nil }
        for track in song.tracks {
            if let container = track.containers.first(where: { $0.id == id }) {
                return container
            }
        }
        return nil
    }

    /// Marks a field as overridden on a clone container.
    private func markFieldOverridden(trackIndex: Int, containerIndex: Int, field: ContainerField) {
        guard project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].parentContainerID != nil else { return }
        project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].overriddenFields.insert(field)
    }

    // MARK: - Clipboard & Context Menu Operations

    /// Copies a container to the clipboard.
    public func copyContainer(trackID: ID<Track>, containerID: ID<Container>) {
        guard let song = currentSong else { return }
        guard let track = song.tracks.first(where: { $0.id == trackID }) else { return }
        guard let container = track.containers.first(where: { $0.id == containerID }) else { return }
        clipboard = [ClipboardContainerEntry(container: container, trackID: trackID)]
        clipboardBaseBar = container.startBar
        clipboardSectionRegion = nil
    }

    /// Copies all containers within a bar range (e.g., from a section) to the clipboard.
    /// If trackFilter is non-empty, only includes containers from those tracks.
    public func copyContainersInRange(startBar: Int, endBar: Int, trackFilter: Set<ID<Track>> = []) {
        guard let song = currentSong else { return }
        var entries: [ClipboardContainerEntry] = []
        for track in song.tracks {
            if !trackFilter.isEmpty && !trackFilter.contains(track.id) { continue }
            for container in track.containers {
                // Include containers that overlap the range
                if container.startBar < endBar && container.endBar > startBar {
                    entries.append(ClipboardContainerEntry(container: container, trackID: track.id))
                }
            }
        }
        clipboard = entries
        clipboardBaseBar = startBar
        clipboardSectionRegion = nil
    }

    /// Copies a section's containers and metadata to the clipboard.
    public func copySectionWithMetadata(sectionID: ID<SectionRegion>) {
        guard let song = currentSong else { return }
        guard let section = song.sections.first(where: { $0.id == sectionID }) else { return }
        copyContainersInRange(startBar: section.startBar, endBar: section.endBar)
        clipboardSectionRegion = section
    }

    /// Pastes clipboard containers to their original tracks at the given bar offset.
    /// If section metadata exists, also creates a section region.
    /// Returns the number of containers successfully pasted.
    @discardableResult
    public func pasteContainersToOriginalTracks(atBar: Int) -> Int {
        guard !project.songs.isEmpty else { return 0 }
        let hasContainers = !clipboard.isEmpty
        let hasSection = clipboardSectionRegion != nil
        guard hasContainers || hasSection else { return 0 }

        let offset = atBar - clipboardBaseBar
        var pasted = 0

        registerUndo(actionName: "Paste")
        for entry in clipboard {
            guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == entry.trackID }) else { continue }

            let newContainer = Container(
                name: entry.container.name,
                startBar: max(entry.container.startBar + offset, 1),
                lengthBars: entry.container.lengthBars,
                sourceRecordingID: entry.container.sourceRecordingID,
                linkGroupID: entry.container.linkGroupID,
                loopSettings: entry.container.loopSettings,
                insertEffects: entry.container.insertEffects,
                isEffectChainBypassed: entry.container.isEffectChainBypassed,
                instrumentOverride: entry.container.instrumentOverride,
                enterFade: entry.container.enterFade,
                exitFade: entry.container.exitFade,
                onEnterActions: entry.container.onEnterActions,
                onExitActions: entry.container.onExitActions,
                automationLanes: entry.container.automationLanes
            )

            if !hasOverlap(in: project.songs[currentSongIndex].tracks[trackIndex], with: newContainer) {
                project.songs[currentSongIndex].tracks[trackIndex].containers.append(newContainer)
                pasted += 1
            }
        }

        // Also paste section metadata if present
        if let section = clipboardSectionRegion {
            let newSection = SectionRegion(
                name: section.name,
                startBar: max(section.startBar + offset, 1),
                lengthBars: section.lengthBars,
                color: section.color,
                notes: section.notes
            )
            if !hasSectionOverlap(in: project.songs[currentSongIndex], with: newSection) {
                project.songs[currentSongIndex].sections.append(newSection)
            }
        }

        if pasted > 0 || hasSection {
            hasUnsavedChanges = true
        }
        return pasted
    }

    /// Duplicates a container as an independent copy at the next available position on the same track.
    @discardableResult
    public func duplicateContainer(trackID: ID<Track>, containerID: ID<Container>) -> ID<Container>? {
        guard !project.songs.isEmpty else { return nil }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return nil }
        guard let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) else { return nil }

        let source = project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex]

        let duplicate = Container(
            name: source.name,
            startBar: source.endBar,
            lengthBars: source.lengthBars,
            sourceRecordingID: source.sourceRecordingID,
            linkGroupID: source.linkGroupID,
            loopSettings: source.loopSettings,
            insertEffects: source.insertEffects,
            isEffectChainBypassed: source.isEffectChainBypassed,
            instrumentOverride: source.instrumentOverride,
            enterFade: source.enterFade,
            exitFade: source.exitFade,
            onEnterActions: source.onEnterActions,
            onExitActions: source.onExitActions,
            automationLanes: source.automationLanes
        )

        if hasOverlap(in: project.songs[currentSongIndex].tracks[trackIndex], with: duplicate) {
            return nil
        }

        registerUndo(actionName: "Duplicate Container")
        project.songs[currentSongIndex].tracks[trackIndex].containers.append(duplicate)
        selectedContainerID = duplicate.id
        hasUnsavedChanges = true
        return duplicate.id
    }

    /// Duplicates a track with all its containers.
    /// Master tracks cannot be duplicated.
    @discardableResult
    public func duplicateTrack(trackID: ID<Track>) -> ID<Track>? {
        guard !project.songs.isEmpty else { return nil }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return nil }

        let source = project.songs[currentSongIndex].tracks[trackIndex]
        guard source.kind != .master else { return nil }

        registerUndo(actionName: "Duplicate Track")
        let copy = Track(
            name: source.name + " Copy",
            kind: source.kind,
            volume: source.volume,
            pan: source.pan,
            isMuted: source.isMuted,
            isSoloed: source.isSoloed,
            containers: source.containers.map { container in
                Container(
                    name: container.name,
                    startBar: container.startBar,
                    lengthBars: container.lengthBars,
                    sourceRecordingID: container.sourceRecordingID,
                    linkGroupID: container.linkGroupID,
                    loopSettings: container.loopSettings,
                    insertEffects: container.insertEffects,
                    isEffectChainBypassed: container.isEffectChainBypassed,
                    instrumentOverride: container.instrumentOverride,
                    enterFade: container.enterFade,
                    exitFade: container.exitFade,
                    onEnterActions: container.onEnterActions,
                    onExitActions: container.onExitActions,
                    automationLanes: container.automationLanes,
                    parentContainerID: container.parentContainerID,
                    overriddenFields: container.overriddenFields
                )
            },
            insertEffects: source.insertEffects,
            sendLevels: source.sendLevels,
            instrumentComponent: source.instrumentComponent,
            inputPortID: source.inputPortID,
            outputPortID: source.outputPortID,
            midiInputDeviceID: source.midiInputDeviceID,
            midiInputChannel: source.midiInputChannel,
            isRecordArmed: source.isRecordArmed,
            isMonitoring: source.isMonitoring,
            trackAutomationLanes: source.trackAutomationLanes,
            expressionPedalCC: source.expressionPedalCC,
            expressionPedalTarget: source.expressionPedalTarget,
            orderIndex: project.songs[currentSongIndex].tracks.count
        )
        project.songs[currentSongIndex].tracks.insert(copy, at: trackIndex + 1)
        project.songs[currentSongIndex].ensureMasterTrackLast()
        reindexTracks()
        hasUnsavedChanges = true
        return copy.id
    }

    /// Pastes clipboard containers at the given bar on the given track.
    /// Returns the number of containers successfully pasted.
    @discardableResult
    public func pasteContainers(trackID: ID<Track>, atBar: Int) -> Int {
        guard !project.songs.isEmpty, !clipboard.isEmpty else { return 0 }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return 0 }

        let offset = atBar - clipboardBaseBar
        var pasted = 0

        registerUndo(actionName: "Paste")
        for entry in clipboard {
            let newContainer = Container(
                name: entry.container.name,
                startBar: max(entry.container.startBar + offset, 1),
                lengthBars: entry.container.lengthBars,
                sourceRecordingID: entry.container.sourceRecordingID,
                linkGroupID: entry.container.linkGroupID,
                loopSettings: entry.container.loopSettings,
                insertEffects: entry.container.insertEffects,
                isEffectChainBypassed: entry.container.isEffectChainBypassed,
                instrumentOverride: entry.container.instrumentOverride,
                enterFade: entry.container.enterFade,
                exitFade: entry.container.exitFade,
                onEnterActions: entry.container.onEnterActions,
                onExitActions: entry.container.onExitActions,
                automationLanes: entry.container.automationLanes
            )

            if !hasOverlap(in: project.songs[currentSongIndex].tracks[trackIndex], with: newContainer) {
                project.songs[currentSongIndex].tracks[trackIndex].containers.append(newContainer)
                pasted += 1
            }
        }

        if pasted > 0 {
            hasUnsavedChanges = true
        }
        return pasted
    }

    // MARK: - Cross-Song Copy

    /// Finds a matching track in the target song by name first, then by kind.
    /// Returns the track index if found, nil if no match.
    public func findMatchingTrack(in songIndex: Int, name: String, kind: TrackKind) -> Int? {
        let tracks = project.songs[songIndex].tracks
        // Match by name first
        if let index = tracks.firstIndex(where: { $0.name == name && $0.kind != .master }) {
            return index
        }
        // Fall back to match by kind
        if let index = tracks.firstIndex(where: { $0.kind == kind && $0.kind != .master }) {
            return index
        }
        return nil
    }

    /// Copies a container to a different song. If a matching track exists (by name, then kind),
    /// the container is placed there. Otherwise a new track is created.
    /// Returns the ID of the new container, or nil on failure.
    @discardableResult
    public func copyContainerToSong(trackID: ID<Track>, containerID: ID<Container>, targetSongID: ID<Song>) -> ID<Container>? {
        guard let sourceSongIndex = project.songs.firstIndex(where: { $0.id == currentSongID }),
              let targetSongIndex = project.songs.firstIndex(where: { $0.id == targetSongID }) else { return nil }
        guard sourceSongIndex != targetSongIndex else { return nil }
        guard let track = project.songs[sourceSongIndex].tracks.first(where: { $0.id == trackID }) else { return nil }
        guard let container = track.containers.first(where: { $0.id == containerID }) else { return nil }

        registerUndo(actionName: "Copy Container to Song")

        let newContainer = Container(
            name: container.name,
            startBar: container.startBar,
            lengthBars: container.lengthBars,
            sourceRecordingID: container.sourceRecordingID,
            linkGroupID: container.linkGroupID,
            loopSettings: container.loopSettings,
            insertEffects: container.insertEffects,
            isEffectChainBypassed: container.isEffectChainBypassed,
            instrumentOverride: container.instrumentOverride,
            enterFade: container.enterFade,
            exitFade: container.exitFade,
            onEnterActions: container.onEnterActions,
            onExitActions: container.onExitActions,
            automationLanes: container.automationLanes,
            midiSequence: container.midiSequence
        )

        let trackIndex: Int
        if let matchIndex = findMatchingTrack(in: targetSongIndex, name: track.name, kind: track.kind) {
            trackIndex = matchIndex
        } else {
            // Create a new track in the target song
            let newTrack = Track(
                name: track.name,
                kind: track.kind,
                volume: track.volume,
                pan: track.pan,
                insertEffects: track.insertEffects,
                sendLevels: track.sendLevels,
                instrumentComponent: track.instrumentComponent,
                inputPortID: track.inputPortID,
                outputPortID: track.outputPortID,
                midiInputDeviceID: track.midiInputDeviceID,
                midiInputChannel: track.midiInputChannel,
                orderIndex: project.songs[targetSongIndex].tracks.count
            )
            project.songs[targetSongIndex].tracks.append(newTrack)
            project.songs[targetSongIndex].ensureMasterTrackLast()
            trackIndex = project.songs[targetSongIndex].tracks.firstIndex(where: { $0.id == newTrack.id })!
        }

        if !hasOverlap(in: project.songs[targetSongIndex].tracks[trackIndex], with: newContainer) {
            project.songs[targetSongIndex].tracks[trackIndex].containers.append(newContainer)
            hasUnsavedChanges = true
            return newContainer.id
        }
        return nil
    }

    /// Copies an entire track (with all containers) to a different song.
    /// Creates a new track in the target song with matching configuration.
    /// Returns the ID of the new track, or nil on failure.
    @discardableResult
    public func copyTrackToSong(trackID: ID<Track>, targetSongID: ID<Song>) -> ID<Track>? {
        guard let sourceSongIndex = project.songs.firstIndex(where: { $0.id == currentSongID }),
              let targetSongIndex = project.songs.firstIndex(where: { $0.id == targetSongID }) else { return nil }
        guard sourceSongIndex != targetSongIndex else { return nil }
        guard let track = project.songs[sourceSongIndex].tracks.first(where: { $0.id == trackID }) else { return nil }
        guard track.kind != .master else { return nil }

        registerUndo(actionName: "Copy Track to Song")

        let copy = Track(
            name: track.name,
            kind: track.kind,
            volume: track.volume,
            pan: track.pan,
            isMuted: track.isMuted,
            isSoloed: track.isSoloed,
            containers: track.containers.map { container in
                Container(
                    name: container.name,
                    startBar: container.startBar,
                    lengthBars: container.lengthBars,
                    sourceRecordingID: container.sourceRecordingID,
                    linkGroupID: container.linkGroupID,
                    loopSettings: container.loopSettings,
                    insertEffects: container.insertEffects,
                    isEffectChainBypassed: container.isEffectChainBypassed,
                    instrumentOverride: container.instrumentOverride,
                    enterFade: container.enterFade,
                    exitFade: container.exitFade,
                    onEnterActions: container.onEnterActions,
                    onExitActions: container.onExitActions,
                    automationLanes: container.automationLanes,
                    parentContainerID: container.parentContainerID,
                    overriddenFields: container.overriddenFields,
                    midiSequence: container.midiSequence
                )
            },
            insertEffects: track.insertEffects,
            sendLevels: track.sendLevels,
            instrumentComponent: track.instrumentComponent,
            inputPortID: track.inputPortID,
            outputPortID: track.outputPortID,
            midiInputDeviceID: track.midiInputDeviceID,
            midiInputChannel: track.midiInputChannel,
            isEffectChainBypassed: track.isEffectChainBypassed,
            trackAutomationLanes: track.trackAutomationLanes,
            expressionPedalCC: track.expressionPedalCC,
            expressionPedalTarget: track.expressionPedalTarget,
            orderIndex: project.songs[targetSongIndex].tracks.count
        )

        project.songs[targetSongIndex].tracks.append(copy)
        project.songs[targetSongIndex].ensureMasterTrackLast()
        // Reindex tracks in target song
        for i in project.songs[targetSongIndex].tracks.indices {
            project.songs[targetSongIndex].tracks[i].orderIndex = i
        }
        hasUnsavedChanges = true
        return copy.id
    }

    /// Returns a list of songs other than the current song, for use in "Copy to Song…" menus.
    public var otherSongs: [(id: ID<Song>, name: String)] {
        project.songs.compactMap { song in
            song.id == currentSongID ? nil : (id: song.id, name: song.name)
        }
    }

    /// Splits a section at a given bar into two sections.
    @discardableResult
    public func splitSection(sectionID: ID<SectionRegion>, atBar: Int) -> Bool {
        guard !project.songs.isEmpty else { return false }
        guard let sectionIndex = project.songs[currentSongIndex].sections.firstIndex(where: { $0.id == sectionID }) else { return false }

        let section = project.songs[currentSongIndex].sections[sectionIndex]
        // atBar must be strictly inside the section
        guard atBar > section.startBar && atBar < section.endBar else { return false }

        let firstLength = atBar - section.startBar
        let secondLength = section.endBar - atBar

        registerUndo(actionName: "Split Section")
        project.songs[currentSongIndex].sections[sectionIndex].lengthBars = firstLength

        let secondSection = SectionRegion(
            name: section.name + " (2)",
            startBar: atBar,
            lengthBars: secondLength,
            color: section.color,
            notes: section.notes
        )
        project.songs[currentSongIndex].sections.insert(secondSection, at: sectionIndex + 1)
        hasUnsavedChanges = true
        return true
    }

    // MARK: - Section Management

    /// The currently selected section ID.
    public var selectedSectionID: ID<SectionRegion>?

    /// Adds a section region to the current song. Returns false if it would overlap.
    @discardableResult
    public func addSection(name: String? = nil, startBar: Int, lengthBars: Int, color: String = "#5B9BD5") -> Bool {
        guard !project.songs.isEmpty else { return false }
        let clampedStart = max(startBar, 1)
        let clampedLength = max(lengthBars, 1)
        let sectionCount = project.songs[currentSongIndex].sections.count
        let sectionName = name ?? "Section \(sectionCount + 1)"
        let section = SectionRegion(
            name: sectionName,
            startBar: clampedStart,
            lengthBars: clampedLength,
            color: color
        )

        if hasSectionOverlap(in: project.songs[currentSongIndex], with: section) {
            return false
        }

        registerUndo(actionName: "Add Section")
        project.songs[currentSongIndex].sections.append(section)
        selectedSectionID = section.id
        hasUnsavedChanges = true
        return true
    }

    /// Removes a section region from the current song.
    public func removeSection(sectionID: ID<SectionRegion>) {
        guard !project.songs.isEmpty else { return }
        registerUndo(actionName: "Remove Section")
        project.songs[currentSongIndex].sections.removeAll { $0.id == sectionID }
        if selectedSectionID == sectionID {
            selectedSectionID = nil
        }
        hasUnsavedChanges = true
    }

    /// Moves a section to a new start bar. Returns false if it would overlap.
    @discardableResult
    public func moveSection(sectionID: ID<SectionRegion>, newStartBar: Int) -> Bool {
        guard !project.songs.isEmpty else { return false }
        guard let sectionIndex = project.songs[currentSongIndex].sections.firstIndex(where: { $0.id == sectionID }) else { return false }

        let clampedStart = max(newStartBar, 1)
        var proposed = project.songs[currentSongIndex].sections[sectionIndex]
        proposed.startBar = clampedStart

        if hasSectionOverlap(in: project.songs[currentSongIndex], with: proposed, excluding: sectionID) {
            return false
        }

        registerUndo(actionName: "Move Section")
        project.songs[currentSongIndex].sections[sectionIndex].startBar = clampedStart
        hasUnsavedChanges = true
        return true
    }

    /// Resizes a section. Returns false if it would overlap.
    @discardableResult
    public func resizeSection(sectionID: ID<SectionRegion>, newStartBar: Int? = nil, newLengthBars: Int? = nil) -> Bool {
        guard !project.songs.isEmpty else { return false }
        guard let sectionIndex = project.songs[currentSongIndex].sections.firstIndex(where: { $0.id == sectionID }) else { return false }

        var proposed = project.songs[currentSongIndex].sections[sectionIndex]
        if let start = newStartBar { proposed.startBar = max(start, 1) }
        if let length = newLengthBars { proposed.lengthBars = max(length, 1) }

        if hasSectionOverlap(in: project.songs[currentSongIndex], with: proposed, excluding: sectionID) {
            return false
        }

        registerUndo(actionName: "Resize Section")
        if let start = newStartBar {
            project.songs[currentSongIndex].sections[sectionIndex].startBar = max(start, 1)
        }
        if let length = newLengthBars {
            project.songs[currentSongIndex].sections[sectionIndex].lengthBars = max(length, 1)
        }
        hasUnsavedChanges = true
        return true
    }

    /// Renames a section.
    public func renameSection(sectionID: ID<SectionRegion>, name: String) {
        guard !project.songs.isEmpty else { return }
        guard let sectionIndex = project.songs[currentSongIndex].sections.firstIndex(where: { $0.id == sectionID }) else { return }
        registerUndo(actionName: "Rename Section")
        project.songs[currentSongIndex].sections[sectionIndex].name = name
        hasUnsavedChanges = true
    }

    /// Changes the color of a section.
    public func recolorSection(sectionID: ID<SectionRegion>, color: String) {
        guard !project.songs.isEmpty else { return }
        guard let sectionIndex = project.songs[currentSongIndex].sections.firstIndex(where: { $0.id == sectionID }) else { return }
        registerUndo(actionName: "Recolor Section")
        project.songs[currentSongIndex].sections[sectionIndex].color = color
        hasUnsavedChanges = true
    }

    /// Updates the notes on a section.
    public func setSectionNotes(sectionID: ID<SectionRegion>, notes: String?) {
        guard !project.songs.isEmpty else { return }
        guard let sectionIndex = project.songs[currentSongIndex].sections.firstIndex(where: { $0.id == sectionID }) else { return }
        registerUndo(actionName: "Edit Section Notes")
        project.songs[currentSongIndex].sections[sectionIndex].notes = notes
        hasUnsavedChanges = true
    }

    /// Checks if a section would overlap any existing section in the song.
    private func hasSectionOverlap(in song: Song, with section: SectionRegion, excluding excludeID: ID<SectionRegion>? = nil) -> Bool {
        for existing in song.sections {
            if existing.id == excludeID { continue }
            if existing.id == section.id { continue }
            if section.startBar < existing.endBar && existing.startBar < section.endBar {
                return true
            }
        }
        return false
    }

    // MARK: - Expression Pedal Quick-Assign

    /// Assigns an expression pedal CC to a track, creating the corresponding MIDIParameterMapping.
    /// If `target` is nil, maps to track volume; otherwise maps to the specified effect parameter.
    public func assignExpressionPedal(trackID: ID<Track>, cc: UInt8, target: EffectPath?) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        registerUndo(actionName: "Assign Expression Pedal")

        // Remove any existing expression pedal mapping for this track
        let oldCC = project.songs[currentSongIndex].tracks[trackIndex].expressionPedalCC
        let oldTarget = project.songs[currentSongIndex].tracks[trackIndex].expressionPedalTarget
        if let oldCC {
            let oldTrigger = MIDITrigger.controlChange(channel: 0, controller: oldCC)
            let oldPath = oldTarget ?? .trackVolume(trackID: trackID)
            project.midiParameterMappings.removeAll { $0.trigger == oldTrigger && $0.targetPath == oldPath }
        }

        // Store pedal assignment on track
        project.songs[currentSongIndex].tracks[trackIndex].expressionPedalCC = cc
        project.songs[currentSongIndex].tracks[trackIndex].expressionPedalTarget = target

        // Create MIDIParameterMapping
        let trigger = MIDITrigger.controlChange(channel: 0, controller: cc)
        let targetPath = target ?? .trackVolume(trackID: trackID)
        let minValue: Float = targetPath.isTrackVolume ? 0.0 : 0.0
        let maxValue: Float = targetPath.isTrackVolume ? 2.0 : 1.0
        // Remove any existing mapping for this trigger or target to avoid conflicts
        project.midiParameterMappings.removeAll { $0.trigger == trigger || $0.targetPath == targetPath }
        let mapping = MIDIParameterMapping(
            trigger: trigger,
            targetPath: targetPath,
            minValue: minValue,
            maxValue: maxValue
        )
        project.midiParameterMappings.append(mapping)
        hasUnsavedChanges = true
        onMIDIParameterMappingsChanged?()
    }

    /// Removes the expression pedal assignment from a track, removing the corresponding MIDIParameterMapping.
    public func removeExpressionPedal(trackID: ID<Track>) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let track = project.songs[currentSongIndex].tracks[trackIndex]
        guard track.expressionPedalCC != nil else { return }
        registerUndo(actionName: "Remove Expression Pedal")

        // Remove the mapping
        let trigger = MIDITrigger.controlChange(channel: 0, controller: track.expressionPedalCC!)
        let targetPath = track.expressionPedalTarget ?? .trackVolume(trackID: trackID)
        project.midiParameterMappings.removeAll { $0.trigger == trigger && $0.targetPath == targetPath }

        // Clear pedal assignment
        project.songs[currentSongIndex].tracks[trackIndex].expressionPedalCC = nil
        project.songs[currentSongIndex].tracks[trackIndex].expressionPedalTarget = nil
        hasUnsavedChanges = true
        onMIDIParameterMappingsChanged?()
    }

    // MARK: - MIDI Parameter Mappings

    /// Adds a MIDI parameter mapping to the project.
    public func addMIDIParameterMapping(_ mapping: MIDIParameterMapping) {
        registerUndo(actionName: "Add MIDI Mapping")
        project.midiParameterMappings.append(mapping)
        hasUnsavedChanges = true
    }

    /// Removes a MIDI parameter mapping from the project.
    public func removeMIDIParameterMapping(mappingID: ID<MIDIParameterMapping>) {
        guard project.midiParameterMappings.contains(where: { $0.id == mappingID }) else { return }
        registerUndo(actionName: "Remove MIDI Mapping")
        project.midiParameterMappings.removeAll { $0.id == mappingID }
        hasUnsavedChanges = true
    }

    /// Removes all MIDI parameter mappings from the project.
    public func removeAllMIDIParameterMappings() {
        guard !project.midiParameterMappings.isEmpty else { return }
        registerUndo(actionName: "Remove All MIDI Mappings")
        project.midiParameterMappings.removeAll()
        hasUnsavedChanges = true
    }

    /// Removes any MIDI parameter mapping targeting a given EffectPath.
    public func removeMIDIParameterMapping(forTarget targetPath: EffectPath) {
        guard project.midiParameterMappings.contains(where: { $0.targetPath == targetPath }) else { return }
        registerUndo(actionName: "Remove MIDI Mapping")
        project.midiParameterMappings.removeAll { $0.targetPath == targetPath }
        hasUnsavedChanges = true
    }

    /// Returns the MIDI parameter mapping for a given target path, if one exists.
    public func midiParameterMapping(forTarget targetPath: EffectPath) -> MIDIParameterMapping? {
        project.midiParameterMappings.first(where: { $0.targetPath == targetPath })
    }

    /// Whether MIDI parameter learn mode is active.
    public var isMIDIParameterLearning: Bool = false

    /// The target path being learned (set during MIDI learn mode).
    public var midiLearnTargetPath: EffectPath?

    /// Callback invoked when MIDI parameter mappings change (to sync dispatcher).
    public var onMIDIParameterMappingsChanged: (() -> Void)?

    /// Callback invoked when MIDI control mappings change (to sync dispatcher).
    public var onMIDIMappingsChanged: (() -> Void)?

    /// Starts MIDI parameter learn mode for the given target path.
    public func startMIDIParameterLearn(targetPath: EffectPath) {
        isMIDIParameterLearning = true
        midiLearnTargetPath = targetPath
    }

    /// Cancels MIDI parameter learn mode.
    public func cancelMIDIParameterLearn() {
        isMIDIParameterLearning = false
        midiLearnTargetPath = nil
    }

    /// Completes MIDI parameter learn by creating a mapping for the received trigger.
    public func completeMIDIParameterLearn(trigger: MIDITrigger) {
        guard let targetPath = midiLearnTargetPath else { return }
        registerUndo(actionName: "MIDI Learn")
        // Remove any existing mapping for this trigger or target
        project.midiParameterMappings.removeAll { $0.trigger == trigger || $0.targetPath == targetPath }
        let mapping = MIDIParameterMapping(
            trigger: trigger,
            targetPath: targetPath
        )
        project.midiParameterMappings.append(mapping)
        hasUnsavedChanges = true
        isMIDIParameterLearning = false
        midiLearnTargetPath = nil
        onMIDIParameterMappingsChanged?()
    }

    // MARK: - Audio Directory

    /// Returns the audio directory for this project.
    /// Uses the project bundle's Audio/ folder if saved, otherwise a temp directory.
    public var audioDirectory: URL {
        let dir: URL
        if let projectURL = projectURL {
            dir = projectURL.appendingPathComponent("Audio")
        } else {
            dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("loops-audio")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Audio Import

    /// Imports an audio file into a track, creating a container at the specified bar.
    /// Returns the new container ID, or nil if import failed.
    public func importAudio(
        url: URL,
        trackID: ID<Track>,
        startBar: Int,
        audioDirectory: URL
    ) throws -> ID<Container>? {
        guard !project.songs.isEmpty else { return nil }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return nil }

        registerUndo(actionName: "Import Audio")
        let importer = AudioImporter()
        let recording = try importer.importAudio(from: url, to: audioDirectory)

        // Calculate container length in bars
        guard let song = currentSong else { return nil }
        let lengthBars = AudioImporter.barsForDuration(
            recording.durationSeconds,
            tempo: song.tempo,
            timeSignature: song.timeSignature
        )

        let container = Container(
            name: url.deletingPathExtension().lastPathComponent,
            startBar: max(startBar, 1),
            lengthBars: lengthBars,
            sourceRecordingID: recording.id,
            loopSettings: LoopSettings(loopCount: .count(1))
        )

        // Check for overlap
        if hasOverlap(in: project.songs[currentSongIndex].tracks[trackIndex], with: container) {
            return nil
        }

        project.sourceRecordings[recording.id] = recording
        project.songs[currentSongIndex].tracks[trackIndex].containers.append(container)
        selectedContainerID = container.id
        hasUnsavedChanges = true
        return container.id
    }

    /// Imports an audio file asynchronously. Creates a preview container immediately from metadata,
    /// then copies the file and generates waveform peaks on a background thread with progressive updates.
    /// Returns the new container ID, or nil if import failed.
    public func importAudioAsync(
        url: URL,
        trackID: ID<Track>,
        startBar: Int,
        audioDirectory: URL
    ) -> ID<Container>? {
        guard !project.songs.isEmpty else { return nil }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return nil }

        // Read metadata synchronously (fast — header only)
        guard let metadata = try? AudioImporter.readMetadata(from: url) else { return nil }
        guard let song = currentSong else { return nil }

        let lengthBars = AudioImporter.barsForDuration(
            metadata.durationSeconds,
            tempo: song.tempo,
            timeSignature: song.timeSignature
        )

        // Create a placeholder recording and container immediately
        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(
            id: recordingID,
            filename: "",
            sampleRate: metadata.sampleRate,
            sampleCount: metadata.sampleCount,
            waveformPeaks: nil
        )

        let container = Container(
            name: url.deletingPathExtension().lastPathComponent,
            startBar: max(startBar, 1),
            lengthBars: lengthBars,
            sourceRecordingID: recordingID,
            loopSettings: LoopSettings(loopCount: .count(1))
        )

        // Check for overlap
        if hasOverlap(in: project.songs[currentSongIndex].tracks[trackIndex], with: container) {
            return nil
        }

        registerUndo(actionName: "Import Audio")
        project.sourceRecordings[recordingID] = recording
        project.songs[currentSongIndex].tracks[trackIndex].containers.append(container)
        selectedContainerID = container.id
        hasUnsavedChanges = true

        let containerID = container.id

        // Background: file copy + progressive peak generation
        // Capture weak self once for the entire detached task
        let viewModel = self
        Task.detached {
            let importer = AudioImporter()
            guard let imported = try? importer.importAudioFile(from: url, to: audioDirectory) else { return }

            // Update recording with real filename
            await MainActor.run {
                viewModel.project.sourceRecordings[recordingID]?.filename = imported.filename
            }

            // Progressive peak generation
            let destURL = audioDirectory.appendingPathComponent(imported.filename)
            let generator = WaveformGenerator()
            let _ = try? generator.generatePeaksProgressively(from: destURL) { progressPeaks in
                let peaksCopy = progressPeaks
                Task { @MainActor in
                    viewModel.project.sourceRecordings[recordingID]?.waveformPeaks = peaksCopy
                }
            }

            await MainActor.run {
                viewModel.hasUnsavedChanges = true
            }
        }

        return containerID
    }

    /// Returns waveform peaks for a container, if available.
    public func waveformPeaks(for container: Container) -> [Float]? {
        // Check live recording peaks first (in-progress recording)
        if let livePeaks = liveRecordingPeaks[container.id], !livePeaks.isEmpty {
            return livePeaks
        }
        guard let recordingID = container.sourceRecordingID,
              let recording = project.sourceRecordings[recordingID] else { return nil }
        return recording.waveformPeaks
    }

    /// Updates live waveform peaks during an in-progress recording.
    /// Also propagates peaks to all linked containers (clones and link group members)
    /// so the waveform draws in real-time across all copies.
    public func updateRecordingPeaks(containerID: ID<Container>, peaks: [Float]) {
        liveRecordingPeaks[containerID] = peaks

        // Propagate to linked containers
        guard let song = currentSong else { return }
        let allContainers = song.tracks.flatMap(\.containers)
        guard let recordingContainer = allContainers.first(where: { $0.id == containerID }) else { return }

        for container in allContainers {
            if container.id == containerID { continue }
            let isCloneOfRecorded = container.parentContainerID == containerID
            let sharesLinkGroup = recordingContainer.linkGroupID != nil
                && container.linkGroupID == recordingContainer.linkGroupID
            let overridesRecording = container.overriddenFields.contains(.sourceRecording)
            if (isCloneOfRecorded || sharesLinkGroup) && !overridesRecording {
                liveRecordingPeaks[container.id] = peaks
            }
        }
    }

    // MARK: - MIDI Sequence Editing

    /// Sets or replaces the MIDI sequence on a container.
    public func setContainerMIDISequence(containerID: ID<Container>, sequence: MIDISequence?) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: sequence != nil ? "Set MIDI Sequence" : "Clear MIDI Sequence")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].midiSequence = sequence
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .midiSequence)
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Adds a MIDI note to a container's sequence. Creates the sequence if it doesn't exist.
    public func addMIDINote(containerID: ID<Container>, note: MIDINoteEvent) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                registerUndo(actionName: "Add MIDI Note")
                if project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].midiSequence == nil {
                    project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].midiSequence = MIDISequence()
                }
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].midiSequence?.notes.append(note)
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .midiSequence)
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Removes a MIDI note from a container's sequence.
    public func removeMIDINote(containerID: ID<Container>, noteID: ID<MIDINoteEvent>) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                guard project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].midiSequence != nil else { return }
                registerUndo(actionName: "Delete MIDI Note")
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].midiSequence?.notes.removeAll { $0.id == noteID }
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .midiSequence)
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Updates a MIDI note in a container's sequence (move, resize, velocity change).
    public func updateMIDINote(containerID: ID<Container>, note: MIDINoteEvent) {
        guard !project.songs.isEmpty else { return }
        for trackIndex in project.songs[currentSongIndex].tracks.indices {
            if let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) {
                guard var sequence = project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].midiSequence else { return }
                guard let noteIndex = sequence.notes.firstIndex(where: { $0.id == note.id }) else { return }
                registerUndo(actionName: "Edit MIDI Note")
                sequence.notes[noteIndex] = note
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].midiSequence = sequence
                markFieldOverridden(trackIndex: trackIndex, containerIndex: containerIndex, field: .midiSequence)
                hasUnsavedChanges = true
                return
            }
        }
    }

    // MARK: - MIDI File Import

    /// Imports a standard MIDI file and creates containers with MIDI sequences.
    public func importMIDIFile(url: URL, trackID: ID<Track>, startBar: Int) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }

        let importer = MIDIFileImporter()
        guard let result = try? importer.importFile(at: url) else { return }
        guard !result.sequences.isEmpty else { return }

        registerUndo(actionName: "Import MIDI File")

        let beatsPerBar = Double(project.songs[currentSongIndex].timeSignature.beatsPerBar)

        for sequence in result.sequences {
            let totalBeats = sequence.durationBeats
            let lengthBars = max(1, Int(ceil(totalBeats / beatsPerBar)))

            let container = Container(
                name: url.deletingPathExtension().lastPathComponent,
                startBar: startBar,
                lengthBars: lengthBars,
                midiSequence: sequence
            )

            // Check for overlap before adding
            let track = project.songs[currentSongIndex].tracks[trackIndex]
            guard !hasOverlap(in: track, with: container) else { continue }

            project.songs[currentSongIndex].tracks[trackIndex].containers.append(container)
        }

        hasUnsavedChanges = true
    }

    // MARK: - Private

    /// Checks if a container would overlap any existing container on the same track.
    private func hasOverlap(in track: Track, with container: Container, excluding excludeID: ID<Container>? = nil) -> Bool {
        for existing in track.containers {
            if existing.id == excludeID { continue }
            if existing.id == container.id { continue }
            if container.startBar < existing.endBar && existing.startBar < container.endBar {
                return true
            }
        }
        return false
    }
}
