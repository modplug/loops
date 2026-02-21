import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore

@Suite("SetlistViewModel Tests")
struct SetlistViewModelTests {

    @Test("Create setlist")
    @MainActor
    func createSetlist() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        let vm = SetlistViewModel(project: projectVM)

        vm.createSetlist(name: "Friday Gig")
        #expect(projectVM.project.setlists.count == 1)
        #expect(projectVM.project.setlists[0].name == "Friday Gig")
        #expect(vm.selectedSetlistID == projectVM.project.setlists[0].id)
        #expect(projectVM.hasUnsavedChanges)
    }

    @Test("Remove setlist")
    @MainActor
    func removeSetlist() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        let vm = SetlistViewModel(project: projectVM)

        vm.createSetlist(name: "Set 1")
        vm.createSetlist(name: "Set 2")
        #expect(projectVM.project.setlists.count == 2)

        let firstID = projectVM.project.setlists[0].id
        vm.removeSetlist(id: firstID)
        #expect(projectVM.project.setlists.count == 1)
        #expect(projectVM.project.setlists[0].name == "Set 2")
    }

    @Test("Rename setlist")
    @MainActor
    func renameSetlist() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        let vm = SetlistViewModel(project: projectVM)

        vm.createSetlist(name: "Old Name")
        let setlistID = projectVM.project.setlists[0].id
        vm.renameSetlist(id: setlistID, newName: "New Name")
        #expect(projectVM.project.setlists[0].name == "New Name")
    }

    @Test("Add entry to setlist")
    @MainActor
    func addEntry() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        let vm = SetlistViewModel(project: projectVM)

        vm.createSetlist(name: "Test")
        let songID = projectVM.project.songs[0].id
        vm.addEntry(songID: songID)

        #expect(projectVM.project.setlists[0].entries.count == 1)
        #expect(projectVM.project.setlists[0].entries[0].songID == songID)
    }

    @Test("Remove entry from setlist")
    @MainActor
    func removeEntry() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        let vm = SetlistViewModel(project: projectVM)

        vm.createSetlist(name: "Test")
        let songID = projectVM.project.songs[0].id
        vm.addEntry(songID: songID)
        let entryID = projectVM.project.setlists[0].entries[0].id
        vm.removeEntry(id: entryID)

        #expect(projectVM.project.setlists[0].entries.isEmpty)
    }

    @Test("Move entries reorders")
    @MainActor
    func moveEntries() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        projectVM.addSong()
        let vm = SetlistViewModel(project: projectVM)

        vm.createSetlist(name: "Test")
        vm.addEntry(songID: projectVM.project.songs[0].id)
        vm.addEntry(songID: projectVM.project.songs[1].id)

        let firstSongID = projectVM.project.setlists[0].entries[0].songID
        let secondSongID = projectVM.project.setlists[0].entries[1].songID

        vm.moveEntries(from: IndexSet(integer: 0), to: 2)

        #expect(projectVM.project.setlists[0].entries[0].songID == secondSongID)
        #expect(projectVM.project.setlists[0].entries[1].songID == firstSongID)
    }

    @Test("Update transition mode")
    @MainActor
    func updateTransition() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        let vm = SetlistViewModel(project: projectVM)

        vm.createSetlist(name: "Test")
        vm.addEntry(songID: projectVM.project.songs[0].id)
        let entryID = projectVM.project.setlists[0].entries[0].id

        vm.updateTransition(entryID: entryID, transition: .seamless)
        #expect(projectVM.project.setlists[0].entries[0].transitionToNext == .seamless)

        vm.updateTransition(entryID: entryID, transition: .gap(durationSeconds: 3.0))
        #expect(projectVM.project.setlists[0].entries[0].transitionToNext == .gap(durationSeconds: 3.0))
    }

    @Test("Enter perform mode")
    @MainActor
    func enterPerformMode() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        let vm = SetlistViewModel(project: projectVM)

        vm.createSetlist(name: "Test")
        vm.addEntry(songID: projectVM.project.songs[0].id)

        vm.enterPerformMode()
        #expect(vm.isPerformMode)
        #expect(vm.currentEntryIndex == 0)
    }

    @Test("Exit perform mode")
    @MainActor
    func exitPerformMode() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        let vm = SetlistViewModel(project: projectVM)

        vm.createSetlist(name: "Test")
        vm.addEntry(songID: projectVM.project.songs[0].id)

        vm.enterPerformMode()
        vm.exitPerformMode()
        #expect(!vm.isPerformMode)
    }

    @Test("Advance to next song in perform mode")
    @MainActor
    func advanceToNextSong() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        projectVM.addSong()
        let vm = SetlistViewModel(project: projectVM)

        vm.createSetlist(name: "Test")
        vm.addEntry(songID: projectVM.project.songs[0].id)
        vm.addEntry(songID: projectVM.project.songs[1].id)

        vm.enterPerformMode()
        #expect(vm.currentEntryIndex == 0)

        vm.advanceToNextSong()
        #expect(vm.currentEntryIndex == 1)
        #expect(projectVM.currentSongID == projectVM.project.songs[1].id)
    }

    @Test("Cannot advance past last song")
    @MainActor
    func cannotAdvancePastLast() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        let vm = SetlistViewModel(project: projectVM)

        vm.createSetlist(name: "Test")
        vm.addEntry(songID: projectVM.project.songs[0].id)

        vm.enterPerformMode()
        vm.advanceToNextSong()
        #expect(vm.currentEntryIndex == 0) // Still at 0, only 1 entry
    }

    @Test("Go to previous song")
    @MainActor
    func goToPreviousSong() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        projectVM.addSong()
        let vm = SetlistViewModel(project: projectVM)

        vm.createSetlist(name: "Test")
        vm.addEntry(songID: projectVM.project.songs[0].id)
        vm.addEntry(songID: projectVM.project.songs[1].id)

        vm.enterPerformMode()
        vm.advanceToNextSong()
        #expect(vm.currentEntryIndex == 1)

        vm.goToPreviousSong()
        #expect(vm.currentEntryIndex == 0)
    }

    @Test("Song name lookup")
    @MainActor
    func songNameLookup() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        let vm = SetlistViewModel(project: projectVM)

        vm.createSetlist(name: "Test")
        vm.addEntry(songID: projectVM.project.songs[0].id)

        let entry = projectVM.project.setlists[0].entries[0]
        #expect(vm.songName(for: entry) == "Song 1")
    }

    @Test("Selected setlist property")
    @MainActor
    func selectedSetlist() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        let vm = SetlistViewModel(project: projectVM)

        #expect(vm.selectedSetlist == nil)

        vm.createSetlist(name: "Test")
        #expect(vm.selectedSetlist != nil)
        #expect(vm.selectedSetlist?.name == "Test")
    }

    @Test("Multiple setlists per project")
    @MainActor
    func multipleSetlists() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        let vm = SetlistViewModel(project: projectVM)

        vm.createSetlist(name: "Set 1")
        vm.createSetlist(name: "Set 2")
        vm.createSetlist(name: "Set 3")

        #expect(projectVM.project.setlists.count == 3)
        #expect(vm.selectedSetlistID == projectVM.project.setlists[2].id)

        vm.selectSetlist(id: projectVM.project.setlists[0].id)
        #expect(vm.selectedSetlist?.name == "Set 1")
    }

    @Test("Enter perform mode without setlist is no-op")
    @MainActor
    func enterPerformModeNoSetlist() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        let vm = SetlistViewModel(project: projectVM)

        vm.enterPerformMode()
        #expect(!vm.isPerformMode)
    }

    @Test("Current and next perform entries")
    @MainActor
    func performEntries() {
        let projectVM = ProjectViewModel()
        projectVM.newProject()
        projectVM.addSong()
        let vm = SetlistViewModel(project: projectVM)

        vm.createSetlist(name: "Test")
        vm.addEntry(songID: projectVM.project.songs[0].id)
        vm.addEntry(songID: projectVM.project.songs[1].id)

        vm.enterPerformMode()
        #expect(vm.currentPerformEntry != nil)
        #expect(vm.nextPerformEntry != nil)
        #expect(vm.currentPerformEntry?.songID == projectVM.project.songs[0].id)
        #expect(vm.nextPerformEntry?.songID == projectVM.project.songs[1].id)

        vm.advanceToNextSong()
        #expect(vm.currentPerformEntry?.songID == projectVM.project.songs[1].id)
        #expect(vm.nextPerformEntry == nil)
    }
}
