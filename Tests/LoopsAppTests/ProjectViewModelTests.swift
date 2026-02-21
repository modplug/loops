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
}
