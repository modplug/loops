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
}
