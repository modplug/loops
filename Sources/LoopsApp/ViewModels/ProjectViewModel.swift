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
}
