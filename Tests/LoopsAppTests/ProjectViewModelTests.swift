import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore

@Suite("ProjectViewModel Tests")
struct ProjectViewModelTests {

    @Test("New project creates a default song")
    @MainActor
    func newProject() {
        let vm = ProjectViewModel()
        vm.newProject()
        #expect(vm.project.songs.count == 1)
        #expect(vm.project.songs[0].name == "Song 1")
    }

    @Test("Add audio track to current song")
    @MainActor
    func addAudioTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        #expect(vm.project.songs[0].tracks.count == 1)
        #expect(vm.project.songs[0].tracks[0].name == "Audio 1")
        #expect(vm.project.songs[0].tracks[0].kind == .audio)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Add multiple tracks auto-increments names")
    @MainActor
    func addMultipleTracks() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        #expect(vm.project.songs[0].tracks.count == 3)
        #expect(vm.project.songs[0].tracks[0].name == "Audio 1")
        #expect(vm.project.songs[0].tracks[1].name == "Audio 2")
        #expect(vm.project.songs[0].tracks[2].name == "MIDI 1")
    }

    @Test("Remove track by ID")
    @MainActor
    func removeTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        let audioTrackID = vm.project.songs[0].tracks[0].id
        vm.removeTrack(id: audioTrackID)
        #expect(vm.project.songs[0].tracks.count == 1)
        #expect(vm.project.songs[0].tracks[0].kind == .midi)
    }

    @Test("Rename track")
    @MainActor
    func renameTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.renameTrack(id: trackID, newName: "Lead Guitar")
        #expect(vm.project.songs[0].tracks[0].name == "Lead Guitar")
    }

    @Test("Move track reorders and reindexes")
    @MainActor
    func moveTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        vm.addTrack(kind: .bus)

        // Move track at index 0 to index 2
        vm.moveTrack(from: IndexSet(integer: 0), to: 2)
        #expect(vm.project.songs[0].tracks[0].kind == .midi)
        #expect(vm.project.songs[0].tracks[1].kind == .audio)
        #expect(vm.project.songs[0].tracks[2].kind == .bus)

        // Verify orderIndex was updated
        for (i, track) in vm.project.songs[0].tracks.enumerated() {
            #expect(track.orderIndex == i)
        }
    }

    @Test("Toggle mute")
    @MainActor
    func toggleMute() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(!vm.project.songs[0].tracks[0].isMuted)
        vm.toggleMute(trackID: trackID)
        #expect(vm.project.songs[0].tracks[0].isMuted)
        vm.toggleMute(trackID: trackID)
        #expect(!vm.project.songs[0].tracks[0].isMuted)
    }

    @Test("Toggle solo")
    @MainActor
    func toggleSolo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(!vm.project.songs[0].tracks[0].isSoloed)
        vm.toggleSolo(trackID: trackID)
        #expect(vm.project.songs[0].tracks[0].isSoloed)
    }

    @Test("Current song returns first song")
    @MainActor
    func currentSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        #expect(vm.currentSong?.name == "Song 1")
    }

    @Test("Track operations on empty project are safe")
    @MainActor
    func emptyProjectSafety() {
        let vm = ProjectViewModel()
        // These should all be no-ops, not crashes
        vm.addTrack(kind: .audio)
        vm.removeTrack(id: ID<Track>())
        vm.renameTrack(id: ID<Track>(), newName: "Test")
        vm.toggleMute(trackID: ID<Track>())
        vm.toggleSolo(trackID: ID<Track>())
    }

    // MARK: - Container Management

    @Test("Add container to track")
    @MainActor
    func addContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let result = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        #expect(result)
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)
        #expect(vm.project.songs[0].tracks[0].containers[0].startBar == 1)
        #expect(vm.project.songs[0].tracks[0].containers[0].lengthBars == 4)
        #expect(vm.selectedContainerID != nil)
    }

    @Test("Container overlap prevention")
    @MainActor
    func containerOverlap() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        // Add first container: bars 1-4
        let first = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        #expect(first)

        // Try overlapping container: bars 3-6 — should fail
        let overlap = vm.addContainer(trackID: trackID, startBar: 3, lengthBars: 4)
        #expect(!overlap)
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)

        // Non-overlapping container: bars 5-8 — should succeed
        let noOverlap = vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4)
        #expect(noOverlap)
        #expect(vm.project.songs[0].tracks[0].containers.count == 2)
    }

    @Test("Remove container")
    @MainActor
    func removeContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        vm.selectedContainerID = containerID
        vm.removeContainer(trackID: trackID, containerID: containerID)
        #expect(vm.project.songs[0].tracks[0].containers.isEmpty)
        #expect(vm.selectedContainerID == nil)
    }

    @Test("Move container")
    @MainActor
    func moveContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let result = vm.moveContainer(trackID: trackID, containerID: containerID, newStartBar: 5)
        #expect(result)
        #expect(vm.project.songs[0].tracks[0].containers[0].startBar == 5)
    }

    @Test("Move container prevents overlap")
    @MainActor
    func moveContainerOverlap() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let _ = vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4)
        let firstID = vm.project.songs[0].tracks[0].containers[0].id

        // Try to move first container to bar 4 — would overlap with second
        let result = vm.moveContainer(trackID: trackID, containerID: firstID, newStartBar: 4)
        #expect(!result)
        #expect(vm.project.songs[0].tracks[0].containers[0].startBar == 1)
    }

    @Test("Resize container")
    @MainActor
    func resizeContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let result = vm.resizeContainer(trackID: trackID, containerID: containerID, newLengthBars: 8)
        #expect(result)
        #expect(vm.project.songs[0].tracks[0].containers[0].lengthBars == 8)
    }

    @Test("Resize container prevents overlap")
    @MainActor
    func resizeContainerOverlap() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let _ = vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4)
        let firstID = vm.project.songs[0].tracks[0].containers[0].id

        // Try to extend first container to 6 bars — would overlap
        let result = vm.resizeContainer(trackID: trackID, containerID: firstID, newLengthBars: 6)
        #expect(!result)
        #expect(vm.project.songs[0].tracks[0].containers[0].lengthBars == 4)
    }

    @Test("Container startBar clamps to minimum 1")
    @MainActor
    func containerStartBarClamp() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let result = vm.addContainer(trackID: trackID, startBar: -5, lengthBars: 4)
        #expect(result)
        #expect(vm.project.songs[0].tracks[0].containers[0].startBar == 1)
    }

    // MARK: - Song Management

    @Test("New project sets currentSongID")
    @MainActor
    func newProjectSetsSongID() {
        let vm = ProjectViewModel()
        vm.newProject()
        #expect(vm.currentSongID != nil)
        #expect(vm.currentSongID == vm.project.songs[0].id)
    }

    @Test("Add song creates new song with default settings")
    @MainActor
    func addSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSong()
        #expect(vm.project.songs.count == 2)
        #expect(vm.project.songs[1].name == "Song 2")
        #expect(vm.currentSongID == vm.project.songs[1].id)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Select song by ID")
    @MainActor
    func selectSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSong()
        let firstSongID = vm.project.songs[0].id
        vm.selectSong(id: firstSongID)
        #expect(vm.currentSongID == firstSongID)
        #expect(vm.currentSongIndex == 0)
    }

    @Test("Remove song selects nearest")
    @MainActor
    func removeSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSong()
        vm.addSong()
        #expect(vm.project.songs.count == 3)

        let secondSongID = vm.project.songs[1].id
        vm.selectSong(id: secondSongID)
        vm.removeSong(id: secondSongID)

        #expect(vm.project.songs.count == 2)
        #expect(vm.currentSongID != nil)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Cannot remove last song")
    @MainActor
    func cannotRemoveLastSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        #expect(vm.project.songs.count == 1)
        let songID = vm.project.songs[0].id
        vm.removeSong(id: songID)
        #expect(vm.project.songs.count == 1)
    }

    @Test("Rename song")
    @MainActor
    func renameSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id
        vm.renameSong(id: songID, newName: "My Cool Song")
        #expect(vm.project.songs[0].name == "My Cool Song")
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Duplicate song creates copy")
    @MainActor
    func duplicateSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        let songID = vm.project.songs[0].id
        vm.duplicateSong(id: songID)

        #expect(vm.project.songs.count == 2)
        #expect(vm.project.songs[1].name == "Song 1 Copy")
        #expect(vm.project.songs[1].tracks.count == 2)
        #expect(vm.project.songs[1].tempo == vm.project.songs[0].tempo)
        // IDs should be different
        #expect(vm.project.songs[1].id != vm.project.songs[0].id)
        #expect(vm.project.songs[1].tracks[0].id != vm.project.songs[0].tracks[0].id)
        // Should select the copy
        #expect(vm.currentSongID == vm.project.songs[1].id)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Select nonexistent song is no-op")
    @MainActor
    func selectNonexistentSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        let originalID = vm.currentSongID
        vm.selectSong(id: ID<Song>())
        #expect(vm.currentSongID == originalID)
    }

    @Test("Selecting a song clears container selection")
    @MainActor
    func selectSongClearsContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        #expect(vm.selectedContainerID != nil)

        vm.addSong()
        let secondSongID = vm.project.songs[1].id
        vm.selectSong(id: vm.project.songs[0].id)
        vm.selectSong(id: secondSongID)
        #expect(vm.selectedContainerID == nil)
    }

    // MARK: - Volume / Pan

    @Test("Set track volume is clamped")
    @MainActor
    func setTrackVolume() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.setTrackVolume(trackID: trackID, volume: 1.5)
        #expect(vm.project.songs[0].tracks[0].volume == 1.5)

        vm.setTrackVolume(trackID: trackID, volume: 3.0)
        #expect(vm.project.songs[0].tracks[0].volume == 2.0) // clamped

        vm.setTrackVolume(trackID: trackID, volume: -1.0)
        #expect(vm.project.songs[0].tracks[0].volume == 0.0) // clamped
    }

    @Test("Set track pan is clamped")
    @MainActor
    func setTrackPan() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.setTrackPan(trackID: trackID, pan: 0.5)
        #expect(vm.project.songs[0].tracks[0].pan == 0.5)

        vm.setTrackPan(trackID: trackID, pan: 2.0)
        #expect(vm.project.songs[0].tracks[0].pan == 1.0) // clamped

        vm.setTrackPan(trackID: trackID, pan: -5.0)
        #expect(vm.project.songs[0].tracks[0].pan == -1.0) // clamped
    }

    // MARK: - Undo / Redo

    @Test("Undo add track restores previous state")
    @MainActor
    func undoAddTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        #expect(vm.project.songs[0].tracks.isEmpty)

        vm.addTrack(kind: .audio)
        #expect(vm.project.songs[0].tracks.count == 1)
        #expect(vm.undoManager?.canUndo == true)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks.isEmpty)
    }

    @Test("Redo restores undone action")
    @MainActor
    func redoAddTrack() {
        let vm = ProjectViewModel()
        vm.newProject()

        vm.addTrack(kind: .audio)
        #expect(vm.project.songs[0].tracks.count == 1)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks.isEmpty)
        #expect(vm.undoManager?.canRedo == true)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks.count == 1)
    }

    @Test("Undo remove track restores track")
    @MainActor
    func undoRemoveTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.removeTrack(id: trackID)
        #expect(vm.project.songs[0].tracks.isEmpty)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks.count == 1)
    }

    @Test("Undo rename track restores old name")
    @MainActor
    func undoRenameTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.renameTrack(id: trackID, newName: "Lead")
        #expect(vm.project.songs[0].tracks[0].name == "Lead")

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].name == "Audio 1")
    }

    @Test("Undo toggle mute restores state")
    @MainActor
    func undoToggleMute() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.toggleMute(trackID: trackID)
        #expect(vm.project.songs[0].tracks[0].isMuted)

        vm.undoManager?.undo()
        #expect(!vm.project.songs[0].tracks[0].isMuted)
    }

    @Test("Undo toggle solo restores state")
    @MainActor
    func undoToggleSolo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.toggleSolo(trackID: trackID)
        #expect(vm.project.songs[0].tracks[0].isSoloed)

        vm.undoManager?.undo()
        #expect(!vm.project.songs[0].tracks[0].isSoloed)
    }

    @Test("Undo add container restores empty track")
    @MainActor
    func undoAddContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].containers.isEmpty)
    }

    @Test("Undo remove container restores it")
    @MainActor
    func undoRemoveContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        vm.removeContainer(trackID: trackID, containerID: containerID)
        #expect(vm.project.songs[0].tracks[0].containers.isEmpty)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)
    }

    @Test("Undo move container restores position")
    @MainActor
    func undoMoveContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let _ = vm.moveContainer(trackID: trackID, containerID: containerID, newStartBar: 5)
        #expect(vm.project.songs[0].tracks[0].containers[0].startBar == 5)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].containers[0].startBar == 1)
    }

    @Test("Undo resize container restores dimensions")
    @MainActor
    func undoResizeContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let _ = vm.resizeContainer(trackID: trackID, containerID: containerID, newLengthBars: 8)
        #expect(vm.project.songs[0].tracks[0].containers[0].lengthBars == 8)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].containers[0].lengthBars == 4)
    }

    @Test("Undo add song restores song count")
    @MainActor
    func undoAddSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        #expect(vm.project.songs.count == 1)

        vm.addSong()
        #expect(vm.project.songs.count == 2)

        vm.undoManager?.undo()
        #expect(vm.project.songs.count == 1)
    }

    @Test("Undo remove song restores it")
    @MainActor
    func undoRemoveSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSong()
        #expect(vm.project.songs.count == 2)
        let secondID = vm.project.songs[1].id

        vm.removeSong(id: secondID)
        #expect(vm.project.songs.count == 1)

        vm.undoManager?.undo()
        #expect(vm.project.songs.count == 2)
    }

    @Test("Undo rename song restores name")
    @MainActor
    func undoRenameSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id

        vm.renameSong(id: songID, newName: "Renamed")
        #expect(vm.project.songs[0].name == "Renamed")

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].name == "Song 1")
    }

    @Test("Undo duplicate song removes copy")
    @MainActor
    func undoDuplicateSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id

        vm.duplicateSong(id: songID)
        #expect(vm.project.songs.count == 2)

        vm.undoManager?.undo()
        #expect(vm.project.songs.count == 1)
    }

    @Test("Undo volume change restores value")
    @MainActor
    func undoVolumeChange() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.setTrackVolume(trackID: trackID, volume: 0.5)
        #expect(vm.project.songs[0].tracks[0].volume == 0.5)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].volume == 1.0) // default
    }

    @Test("Undo pan change restores value")
    @MainActor
    func undoPanChange() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.setTrackPan(trackID: trackID, pan: -0.5)
        #expect(vm.project.songs[0].tracks[0].pan == -0.5)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].pan == 0.0) // default
    }

    @Test("New project clears undo stack")
    @MainActor
    func newProjectClearsUndo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        #expect(vm.undoManager?.canUndo == true)

        vm.newProject()
        #expect(vm.undoManager?.canUndo == false)
    }

    @Test("Undo action name is set correctly")
    @MainActor
    func undoActionName() {
        let vm = ProjectViewModel()
        vm.newProject()

        vm.addTrack(kind: .audio)
        #expect(vm.undoManager?.undoActionName == "Add Track")

        let trackID = vm.project.songs[0].tracks[0].id
        vm.toggleMute(trackID: trackID)
        #expect(vm.undoManager?.undoActionName == "Toggle Mute")
    }

    @Test("Multiple undo/redo operations")
    @MainActor
    func multipleUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()

        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        vm.addTrack(kind: .bus)
        #expect(vm.project.songs[0].tracks.count == 3)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks.count == 2)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks.count == 1)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks.count == 2)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks.count == 3)
    }

    // MARK: - Container Detail Editor Tests (Reorder Effects)

    @Test("Reorder container effects moves effect down")
    @MainActor
    func reorderContainerEffectsDown() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        let effectA = InsertEffect(component: comp, displayName: "Reverb", orderIndex: 0)
        let effectB = InsertEffect(component: comp, displayName: "Delay", orderIndex: 1)
        let effectC = InsertEffect(component: comp, displayName: "Chorus", orderIndex: 2)

        vm.addContainerEffect(containerID: containerID, effect: effectA)
        vm.addContainerEffect(containerID: containerID, effect: effectB)
        vm.addContainerEffect(containerID: containerID, effect: effectC)

        let effects = vm.project.songs[0].tracks[0].containers[0].insertEffects
        #expect(effects.count == 3)

        // Move first effect to position 2 (after second)
        vm.reorderContainerEffects(containerID: containerID, from: IndexSet(integer: 0), to: 2)

        let reordered = vm.project.songs[0].tracks[0].containers[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(reordered[0].displayName == "Delay")
        #expect(reordered[1].displayName == "Reverb")
        #expect(reordered[2].displayName == "Chorus")
        #expect(reordered[0].orderIndex == 0)
        #expect(reordered[1].orderIndex == 1)
        #expect(reordered[2].orderIndex == 2)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Reorder container effects moves effect up")
    @MainActor
    func reorderContainerEffectsUp() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "Reverb", orderIndex: 0))
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "Delay", orderIndex: 1))
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "Chorus", orderIndex: 2))

        // Move last effect to position 0 (beginning)
        vm.reorderContainerEffects(containerID: containerID, from: IndexSet(integer: 2), to: 0)

        let reordered = vm.project.songs[0].tracks[0].containers[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(reordered[0].displayName == "Chorus")
        #expect(reordered[1].displayName == "Reverb")
        #expect(reordered[2].displayName == "Delay")
    }

    @Test("Reorder container effects with undo restores original order")
    @MainActor
    func reorderContainerEffectsUndo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "Reverb", orderIndex: 0))
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "Delay", orderIndex: 1))

        vm.reorderContainerEffects(containerID: containerID, from: IndexSet(integer: 0), to: 2)

        let afterReorder = vm.project.songs[0].tracks[0].containers[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(afterReorder[0].displayName == "Delay")
        #expect(afterReorder[1].displayName == "Reverb")

        vm.undoManager?.undo()

        let afterUndo = vm.project.songs[0].tracks[0].containers[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(afterUndo[0].displayName == "Reverb")
        #expect(afterUndo[1].displayName == "Delay")
    }

    @Test("Reorder with invalid container ID is no-op")
    @MainActor
    func reorderContainerEffectsInvalidID() {
        let vm = ProjectViewModel()
        vm.newProject()

        let bogusID = ID<Container>()
        vm.reorderContainerEffects(containerID: bogusID, from: IndexSet(integer: 0), to: 1)
        // Should not crash or modify state — no unsaved changes from reorder
        #expect(!vm.hasUnsavedChanges)
    }

    @Test("Selected container returns correct container")
    @MainActor
    func selectedContainerProperty() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        vm.selectedContainerID = containerID
        #expect(vm.selectedContainer != nil)
        #expect(vm.selectedContainer?.id == containerID)
        #expect(vm.selectedContainerTrackKind == .audio)
    }

    @Test("All containers in current song returns all containers across tracks")
    @MainActor
    func allContainersInCurrentSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        let track1ID = vm.project.songs[0].tracks[0].id
        let track2ID = vm.project.songs[0].tracks[1].id
        let _ = vm.addContainer(trackID: track1ID, startBar: 1, lengthBars: 2)
        let _ = vm.addContainer(trackID: track1ID, startBar: 3, lengthBars: 2)
        let _ = vm.addContainer(trackID: track2ID, startBar: 1, lengthBars: 4)

        let allContainers = vm.allContainersInCurrentSong
        #expect(allContainers.count == 3)
    }

    @Test("All tracks in current song returns all tracks")
    @MainActor
    func allTracksInCurrentSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        vm.addTrack(kind: .bus)

        let allTracks = vm.allTracksInCurrentSong
        #expect(allTracks.count == 3)
    }
}
