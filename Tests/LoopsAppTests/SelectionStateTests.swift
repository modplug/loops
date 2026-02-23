import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore

@Suite("SelectionState Tests")
struct SelectionStateTests {

    @Test("SelectionState is a standalone observable with four selection properties")
    @MainActor
    func standaloneProperties() {
        let state = SelectionState()
        #expect(state.selectedTrackID == nil)
        #expect(state.selectedContainerID == nil)
        #expect(state.selectedContainerIDs.isEmpty)
        #expect(state.selectedSectionID == nil)
    }

    @Test("Setting selectedTrackID clears selectedContainerID and selectedContainerIDs")
    @MainActor
    func trackClearsContainer() {
        let state = SelectionState()
        let containerID = ID<Container>()
        let trackID = ID<Track>()
        state.selectedContainerID = containerID
        state.selectedContainerIDs = [containerID]
        #expect(state.selectedContainerID == containerID)
        #expect(state.selectedContainerIDs.count == 1)

        state.selectedTrackID = trackID
        #expect(state.selectedTrackID == trackID)
        #expect(state.selectedContainerID == nil)
        #expect(state.selectedContainerIDs.isEmpty)
    }

    @Test("Setting selectedContainerID clears selectedTrackID")
    @MainActor
    func containerClearsTrack() {
        let state = SelectionState()
        let trackID = ID<Track>()
        let containerID = ID<Container>()
        state.selectedTrackID = trackID
        #expect(state.selectedTrackID == trackID)

        state.selectedContainerID = containerID
        #expect(state.selectedContainerID == containerID)
        #expect(state.selectedTrackID == nil)
    }

    @Test("deselectAll clears all four properties")
    @MainActor
    func deselectAll() {
        let state = SelectionState()
        state.selectedTrackID = ID<Track>()
        state.selectedContainerID = ID<Container>()
        state.selectedContainerIDs = [ID<Container>()]
        state.selectedSectionID = ID<SectionRegion>()

        state.deselectAll()
        #expect(state.selectedTrackID == nil)
        #expect(state.selectedContainerID == nil)
        #expect(state.selectedContainerIDs.isEmpty)
        #expect(state.selectedSectionID == nil)
    }

    @Test("ProjectViewModel.selectionState delegates selectedContainerID")
    @MainActor
    func vmDelegatesContainerID() {
        let vm = ProjectViewModel()
        let containerID = ID<Container>()
        vm.selectedContainerID = containerID
        #expect(vm.selectionState.selectedContainerID == containerID)

        let anotherID = ID<Container>()
        vm.selectionState.selectedContainerID = anotherID
        #expect(vm.selectedContainerID == anotherID)
    }

    @Test("ProjectViewModel.selectionState delegates selectedTrackID")
    @MainActor
    func vmDelegatesTrackID() {
        let vm = ProjectViewModel()
        let trackID = ID<Track>()
        vm.selectedTrackID = trackID
        #expect(vm.selectionState.selectedTrackID == trackID)

        let anotherID = ID<Track>()
        vm.selectionState.selectedTrackID = anotherID
        #expect(vm.selectedTrackID == anotherID)
    }

    @Test("ProjectViewModel.selectionState delegates selectedSectionID")
    @MainActor
    func vmDelegatesSectionID() {
        let vm = ProjectViewModel()
        let sectionID = ID<SectionRegion>()
        vm.selectedSectionID = sectionID
        #expect(vm.selectionState.selectedSectionID == sectionID)

        let anotherID = ID<SectionRegion>()
        vm.selectionState.selectedSectionID = anotherID
        #expect(vm.selectedSectionID == anotherID)
    }

    @Test("ProjectViewModel.selectionState delegates selectedContainerIDs")
    @MainActor
    func vmDelegatesContainerIDs() {
        let vm = ProjectViewModel()
        let ids: Set<ID<Container>> = [ID<Container>(), ID<Container>()]
        vm.selectedContainerIDs = ids
        #expect(vm.selectionState.selectedContainerIDs == ids)

        let newIDs: Set<ID<Container>> = [ID<Container>()]
        vm.selectionState.selectedContainerIDs = newIDs
        #expect(vm.selectedContainerIDs == newIDs)
    }

    @Test("Setting nil selectedTrackID does not clear container selection")
    @MainActor
    func nilTrackKeepsContainer() {
        let state = SelectionState()
        let containerID = ID<Container>()
        state.selectedContainerID = containerID

        state.selectedTrackID = nil
        #expect(state.selectedContainerID == containerID)
    }

    @Test("Setting nil selectedContainerID does not clear track selection")
    @MainActor
    func nilContainerKeepsTrack() {
        let state = SelectionState()
        let trackID = ID<Track>()
        state.selectedTrackID = trackID

        state.selectedContainerID = nil
        #expect(state.selectedTrackID == trackID)
    }
}
