import SwiftUI
import LoopsCore
import LoopsEngine

/// An entry in the container clipboard, storing a copied container and its source track ID.
public struct ClipboardContainerEntry: Equatable, Sendable {
    public let container: Container
    public let trackID: ID<Track>
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

    private let persistence = ProjectPersistence()

    public init(project: Project = Project()) {
        self.project = project
        let um = UndoManager()
        um.groupsByEvent = false
        self.undoManager = um
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

    /// Selects a song by its ID.
    public func selectSong(id: ID<Song>) {
        guard project.songs.contains(where: { $0.id == id }) else { return }
        currentSongID = id
        selectedContainerID = nil
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
        hasUnsavedChanges = true
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
        if let projectURL = projectURL {
            return projectURL.appendingPathComponent("Audio")
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("loops-audio")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
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

    /// Returns waveform peaks for a container, if available.
    public func waveformPeaks(for container: Container) -> [Float]? {
        guard let recordingID = container.sourceRecordingID,
              let recording = project.sourceRecordings[recordingID] else { return nil }
        return recording.waveformPeaks
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
