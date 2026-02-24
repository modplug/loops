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

    // MARK: - Multi-Select Track Tests

    @Test("selectedTrackIDs defaults to empty")
    @MainActor
    func selectedTrackIDsDefault() {
        let state = SelectionState()
        #expect(state.selectedTrackIDs.isEmpty)
    }

    @Test("Setting selectedTrackIDs clears selectedTrackID and container selection")
    @MainActor
    func multiTrackClearsSingleAndContainers() {
        let state = SelectionState()
        let trackID = ID<Track>()
        let containerID = ID<Container>()
        state.selectedTrackID = trackID
        state.selectedContainerID = containerID

        let ids: Set<ID<Track>> = [ID<Track>(), ID<Track>()]
        state.selectedTrackIDs = ids
        #expect(state.selectedTrackIDs == ids)
        #expect(state.selectedTrackID == nil)
        #expect(state.selectedContainerID == nil)
    }

    @Test("Setting selectedTrackID clears selectedTrackIDs")
    @MainActor
    func singleTrackClearsMulti() {
        let state = SelectionState()
        state.selectedTrackIDs = [ID<Track>(), ID<Track>()]
        #expect(state.selectedTrackIDs.count == 2)

        state.selectedTrackID = ID<Track>()
        #expect(state.selectedTrackIDs.isEmpty)
    }

    @Test("deselectAll clears selectedTrackIDs")
    @MainActor
    func deselectAllClearsMultiTrack() {
        let state = SelectionState()
        state.selectedTrackIDs = [ID<Track>(), ID<Track>()]
        state.deselectAll()
        #expect(state.selectedTrackIDs.isEmpty)
    }

    @Test("isTrackSelected returns true for single or multi-selected track")
    @MainActor
    func isTrackSelectedHelper() {
        let state = SelectionState()
        let trackA = ID<Track>()
        let trackB = ID<Track>()
        let trackC = ID<Track>()

        // Not selected
        #expect(!state.isTrackSelected(trackA))

        // Single selection
        state.selectedTrackID = trackA
        #expect(state.isTrackSelected(trackA))
        #expect(!state.isTrackSelected(trackB))

        // Multi-selection
        state.selectedTrackIDs = [trackA, trackB]
        #expect(state.isTrackSelected(trackA))
        #expect(state.isTrackSelected(trackB))
        #expect(!state.isTrackSelected(trackC))
    }

    @Test("allSelectedTrackIDs returns correct union")
    @MainActor
    func allSelectedTrackIDsUnion() {
        let state = SelectionState()
        let trackA = ID<Track>()
        let trackB = ID<Track>()

        // Empty
        #expect(state.allSelectedTrackIDs.isEmpty)

        // Single
        state.selectedTrackID = trackA
        #expect(state.allSelectedTrackIDs == [trackA])

        // Multi
        state.selectedTrackIDs = [trackA, trackB]
        #expect(state.allSelectedTrackIDs == [trackA, trackB])
    }

    @Test("toggleTrackInMultiSelect promotes single to multi and toggles")
    @MainActor
    func toggleMultiSelect() {
        let state = SelectionState()
        let trackA = ID<Track>()
        let trackB = ID<Track>()
        let trackC = ID<Track>()

        // Start with single selection
        state.selectedTrackID = trackA

        // Cmd+Click trackB → promotes to multi-select with both
        state.toggleTrackInMultiSelect(trackB)
        #expect(state.selectedTrackIDs == [trackA, trackB])
        #expect(state.selectedTrackID == nil) // cleared by multi-select

        // Cmd+Click trackC → adds trackC
        state.toggleTrackInMultiSelect(trackC)
        #expect(state.selectedTrackIDs == [trackA, trackB, trackC])

        // Cmd+Click trackB → removes trackB
        state.toggleTrackInMultiSelect(trackB)
        #expect(state.selectedTrackIDs == [trackA, trackC])

        // Cmd+Click trackA → removes trackA, only trackC left → demotes to single
        state.toggleTrackInMultiSelect(trackA)
        #expect(state.selectedTrackIDs.isEmpty)
        #expect(state.selectedTrackID == trackC)
    }

    @Test("selectTrackRange selects contiguous range from anchor to target")
    @MainActor
    func rangeSelectTracks() {
        let state = SelectionState()
        let trackA = ID<Track>()
        let trackB = ID<Track>()
        let trackC = ID<Track>()
        let trackD = ID<Track>()
        let ordered = [trackA, trackB, trackC, trackD]

        // Set anchor via single selection
        state.selectedTrackID = trackA

        // Shift+Click trackC → selects A, B, C
        state.selectTrackRange(to: trackC, orderedTrackIDs: ordered)
        #expect(state.selectedTrackIDs == [trackA, trackB, trackC])

        // Shift+Click trackD from existing multi-selection (anchor = first multi-selected = trackA)
        state.selectTrackRange(to: trackD, orderedTrackIDs: ordered)
        #expect(state.selectedTrackIDs == [trackA, trackB, trackC, trackD])
    }

    @Test("selectTrackRange with no anchor falls back to single select")
    @MainActor
    func rangeSelectNoAnchor() {
        let state = SelectionState()
        let trackA = ID<Track>()
        let trackB = ID<Track>()

        state.selectTrackRange(to: trackB, orderedTrackIDs: [trackA, trackB])
        #expect(state.selectedTrackID == trackB)
        #expect(state.selectedTrackIDs.isEmpty)
    }

    @Test("Setting empty selectedTrackIDs does not clear container selection")
    @MainActor
    func emptyMultiTrackKeepsContainers() {
        let state = SelectionState()
        let containerID = ID<Container>()
        state.selectedContainerID = containerID

        state.selectedTrackIDs = []
        #expect(state.selectedContainerID == containerID)
    }

    @Test("ProjectViewModel.selectionState delegates selectedTrackIDs")
    @MainActor
    func vmDelegatesTrackIDs() {
        let vm = ProjectViewModel()
        let ids: Set<ID<Track>> = [ID<Track>(), ID<Track>()]
        vm.selectedTrackIDs = ids
        #expect(vm.selectionState.selectedTrackIDs == ids)

        let newIDs: Set<ID<Track>> = [ID<Track>()]
        vm.selectionState.selectedTrackIDs = newIDs
        #expect(vm.selectedTrackIDs == newIDs)
    }
}
