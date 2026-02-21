import SwiftUI
import LoopsCore
import LoopsEngine

/// Manages the current project state and file operations.
@Observable
@MainActor
public final class ProjectViewModel {
    public var project: Project
    public var projectURL: URL?
    public var hasUnsavedChanges: Bool = false

    private let persistence = ProjectPersistence()

    public init(project: Project = Project()) {
        self.project = project
    }

    /// Creates a new empty project with a default song.
    public func newProject() {
        let defaultSong = Song(name: "Song 1")
        project = Project(songs: [defaultSong])
        projectURL = nil
        hasUnsavedChanges = false
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
        projectURL = url
        hasUnsavedChanges = false
    }

    // MARK: - Song Access

    /// Index of the currently active song.
    public var currentSongIndex: Int {
        get { min(_currentSongIndex, max(project.songs.count - 1, 0)) }
        set { _currentSongIndex = newValue }
    }
    private var _currentSongIndex: Int = 0

    /// The currently active song, if any.
    public var currentSong: Song? {
        guard !project.songs.isEmpty else { return nil }
        return project.songs[currentSongIndex]
    }

    // MARK: - Track Management

    /// Adds a new track to the current song with auto-generated name.
    public func addTrack(kind: TrackKind) {
        guard !project.songs.isEmpty else { return }
        let existingCount = project.songs[currentSongIndex].tracks
            .filter { $0.kind == kind }.count
        let name = "\(kind.displayName) \(existingCount + 1)"
        let orderIndex = project.songs[currentSongIndex].tracks.count
        let track = Track(name: name, kind: kind, orderIndex: orderIndex)
        project.songs[currentSongIndex].tracks.append(track)
        hasUnsavedChanges = true
    }

    /// Removes a track from the current song by ID.
    public func removeTrack(id: ID<Track>) {
        guard !project.songs.isEmpty else { return }
        project.songs[currentSongIndex].tracks.removeAll { $0.id == id }
        reindexTracks()
        hasUnsavedChanges = true
    }

    /// Renames a track in the current song.
    public func renameTrack(id: ID<Track>, newName: String) {
        guard !project.songs.isEmpty else { return }
        guard let index = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == id }) else { return }
        project.songs[currentSongIndex].tracks[index].name = newName
        hasUnsavedChanges = true
    }

    /// Moves a track from one index to another (reordering).
    public func moveTrack(from source: IndexSet, to destination: Int) {
        guard !project.songs.isEmpty else { return }
        project.songs[currentSongIndex].tracks.move(fromOffsets: source, toOffset: destination)
        reindexTracks()
        hasUnsavedChanges = true
    }

    /// Toggles mute on a track.
    public func toggleMute(trackID: ID<Track>) {
        guard !project.songs.isEmpty else { return }
        guard let index = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.songs[currentSongIndex].tracks[index].isMuted.toggle()
        hasUnsavedChanges = true
    }

    /// Toggles solo on a track.
    public func toggleSolo(trackID: ID<Track>) {
        guard !project.songs.isEmpty else { return }
        guard let index = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.songs[currentSongIndex].tracks[index].isSoloed.toggle()
        hasUnsavedChanges = true
    }

    private func reindexTracks() {
        guard !project.songs.isEmpty else { return }
        for i in project.songs[currentSongIndex].tracks.indices {
            project.songs[currentSongIndex].tracks[i].orderIndex = i
        }
    }

    // MARK: - Container Management

    /// The currently selected container ID.
    public var selectedContainerID: ID<Container>?

    /// Adds a container to a track. Returns false if it would overlap an existing container.
    public func addContainer(trackID: ID<Track>, startBar: Int, lengthBars: Int) -> Bool {
        guard !project.songs.isEmpty else { return false }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return false }

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
        project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].isRecordArmed.toggle()
        hasUnsavedChanges = true
    }

    /// Updates the source recording for a container after recording completes.
    public func setContainerRecording(trackID: ID<Track>, containerID: ID<Container>, recording: SourceRecording) {
        guard !project.songs.isEmpty else { return }
        guard let trackIndex = project.songs[currentSongIndex].tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard let containerIndex = project.songs[currentSongIndex].tracks[trackIndex].containers.firstIndex(where: { $0.id == containerID }) else { return }

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
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].loopSettings = settings
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
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].name = name
                hasUnsavedChanges = true
                return
            }
        }
    }

    /// Links containers by setting the same linkGroupID.
    public func linkContainers(containerIDs: [ID<Container>]) {
        guard !project.songs.isEmpty, containerIDs.count >= 2 else { return }
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
                project.songs[currentSongIndex].tracks[trackIndex].containers[containerIndex].linkGroupID = nil
                hasUnsavedChanges = true
                return
            }
        }
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
