import SwiftUI
import LoopsCore

/// Manages setlist editing and perform mode state.
@Observable
@MainActor
public final class SetlistViewModel {
    public var project: ProjectViewModel

    /// The currently selected setlist ID in the sidebar.
    public var selectedSetlistID: ID<Setlist>?

    /// The currently selected setlist entry ID for inspector display.
    public var selectedSetlistEntryID: ID<SetlistEntry>?

    /// Whether perform mode is active.
    public var isPerformMode: Bool = false

    /// Index of the currently playing entry in perform mode.
    public var currentEntryIndex: Int = 0

    /// Progress through the current song (0.0...1.0).
    public var currentSongProgress: Double = 0.0

    public init(project: ProjectViewModel) {
        self.project = project
    }

    // MARK: - Setlist CRUD

    /// The currently selected setlist, if any.
    public var selectedSetlist: Setlist? {
        guard let id = selectedSetlistID else { return nil }
        return project.project.setlists.first(where: { $0.id == id })
    }

    /// The currently selected setlist entry, if any.
    public var selectedSetlistEntry: SetlistEntry? {
        guard let setlist = selectedSetlist,
              let entryID = selectedSetlistEntryID else { return nil }
        return setlist.entries.first(where: { $0.id == entryID })
    }

    /// Creates a new setlist.
    public func createSetlist(name: String = "New Setlist") {
        let setlist = Setlist(name: name)
        project.project.setlists.append(setlist)
        selectedSetlistID = setlist.id
        project.hasUnsavedChanges = true
    }

    /// Removes a setlist by ID.
    public func removeSetlist(id: ID<Setlist>) {
        project.project.setlists.removeAll { $0.id == id }
        if selectedSetlistID == id {
            selectedSetlistID = project.project.setlists.first?.id
        }
        project.hasUnsavedChanges = true
    }

    /// Renames a setlist.
    public func renameSetlist(id: ID<Setlist>, newName: String) {
        guard let index = project.project.setlists.firstIndex(where: { $0.id == id }) else { return }
        project.project.setlists[index].name = newName
        project.hasUnsavedChanges = true
    }

    /// Selects a setlist by ID.
    public func selectSetlist(id: ID<Setlist>) {
        guard project.project.setlists.contains(where: { $0.id == id }) else { return }
        selectedSetlistID = id
    }

    // MARK: - Entry Management

    /// Adds a song to the selected setlist.
    public func addEntry(songID: ID<Song>) {
        guard let setlistIndex = selectedSetlistIndex else { return }
        let entry = SetlistEntry(songID: songID)
        project.project.setlists[setlistIndex].entries.append(entry)
        project.hasUnsavedChanges = true
    }

    /// Removes an entry from the selected setlist.
    public func removeEntry(id: ID<SetlistEntry>) {
        guard let setlistIndex = selectedSetlistIndex else { return }
        project.project.setlists[setlistIndex].entries.removeAll { $0.id == id }
        project.hasUnsavedChanges = true
    }

    /// Moves entries within the selected setlist (drag-and-drop reorder).
    public func moveEntries(from source: IndexSet, to destination: Int) {
        guard let setlistIndex = selectedSetlistIndex else { return }
        project.project.setlists[setlistIndex].entries.move(fromOffsets: source, toOffset: destination)
        project.hasUnsavedChanges = true
    }

    /// Updates the transition mode for a specific entry.
    public func updateTransition(entryID: ID<SetlistEntry>, transition: TransitionMode) {
        guard let setlistIndex = selectedSetlistIndex else { return }
        guard let entryIndex = project.project.setlists[setlistIndex].entries.firstIndex(where: { $0.id == entryID }) else { return }
        project.project.setlists[setlistIndex].entries[entryIndex].transitionToNext = transition
        project.hasUnsavedChanges = true
    }

    /// Updates the fade-in settings for a specific entry.
    public func updateFadeIn(entryID: ID<SetlistEntry>, fadeIn: FadeSettings?) {
        guard let setlistIndex = selectedSetlistIndex else { return }
        guard let entryIndex = project.project.setlists[setlistIndex].entries.firstIndex(where: { $0.id == entryID }) else { return }
        project.project.setlists[setlistIndex].entries[entryIndex].fadeIn = fadeIn
        project.hasUnsavedChanges = true
    }

    // MARK: - Perform Mode

    /// Enters perform mode with the selected setlist.
    public func enterPerformMode() {
        guard selectedSetlist != nil else { return }
        currentEntryIndex = 0
        currentSongProgress = 0.0
        isPerformMode = true
        loadCurrentPerformSong()
    }

    /// Exits perform mode and returns to editor.
    public func exitPerformMode() {
        isPerformMode = false
    }

    /// Advances to the next song in the setlist.
    public func advanceToNextSong() {
        guard let setlist = selectedSetlist else { return }
        guard currentEntryIndex < setlist.entries.count - 1 else { return }
        currentEntryIndex += 1
        currentSongProgress = 0.0
        loadCurrentPerformSong()
    }

    /// Goes back to the previous song in the setlist.
    public func goToPreviousSong() {
        guard currentEntryIndex > 0 else { return }
        currentEntryIndex -= 1
        currentSongProgress = 0.0
        loadCurrentPerformSong()
    }

    /// The current entry in perform mode.
    public var currentPerformEntry: SetlistEntry? {
        guard let setlist = selectedSetlist else { return nil }
        guard setlist.entries.indices.contains(currentEntryIndex) else { return nil }
        return setlist.entries[currentEntryIndex]
    }

    /// The next entry in perform mode, if any.
    public var nextPerformEntry: SetlistEntry? {
        guard let setlist = selectedSetlist else { return nil }
        let nextIndex = currentEntryIndex + 1
        guard setlist.entries.indices.contains(nextIndex) else { return nil }
        return setlist.entries[nextIndex]
    }

    /// Song name for an entry.
    public func songName(for entry: SetlistEntry) -> String {
        project.project.songs.first(where: { $0.id == entry.songID })?.name ?? "Unknown Song"
    }

    /// Song for an entry.
    public func song(for entry: SetlistEntry) -> Song? {
        project.project.songs.first(where: { $0.id == entry.songID })
    }

    /// Updates currentSongProgress based on the playhead position and song length.
    /// songLengthBars should be the last bar with content (1-based endBar).
    public func updateSongProgress(playheadBar: Double, songLengthBars: Int) {
        guard isPerformMode, songLengthBars > 1 else {
            currentSongProgress = 0.0
            return
        }
        // playheadBar is 1-based, songLengthBars is the endBar (exclusive)
        // progress = (playhead - 1) / (length - 1), clamped to 0...1
        let progress = (playheadBar - 1.0) / Double(songLengthBars - 1)
        currentSongProgress = min(max(progress, 0.0), 1.0)
    }

    /// Returns the active section at the given bar position for the current perform song.
    public func activeSectionID(atBar bar: Double) -> ID<SectionRegion>? {
        guard let entry = currentPerformEntry,
              let song = song(for: entry) else { return nil }
        let barInt = Int(bar)
        return song.sections.first(where: { $0.startBar <= barInt && $0.endBar > barInt })?.id
    }

    // MARK: - Private

    private var selectedSetlistIndex: Int? {
        guard let id = selectedSetlistID else { return nil }
        return project.project.setlists.firstIndex(where: { $0.id == id })
    }

    private func loadCurrentPerformSong() {
        guard let entry = currentPerformEntry else { return }
        project.selectSong(id: entry.songID)
    }
}
