import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore

@Suite("TimelineViewModel Tests")
struct TimelineViewModelTests {

    @Test("Default state")
    @MainActor
    func defaultState() {
        let vm = TimelineViewModel()
        #expect(vm.pixelsPerBar == 120.0)
        #expect(vm.playheadBar == 1.0)
        #expect(vm.totalBars == 64)
    }

    @Test("Total width calculation")
    @MainActor
    func totalWidth() {
        let vm = TimelineViewModel()
        vm.totalBars = 32
        vm.pixelsPerBar = 100
        #expect(vm.totalWidth == 3200.0)
    }

    @Test("Bar to x-position conversion")
    @MainActor
    func barToXPosition() {
        let vm = TimelineViewModel()
        vm.pixelsPerBar = 100
        // Bar 1 starts at x=0
        #expect(vm.xPosition(forBar: 1.0) == 0.0)
        // Bar 2 starts at x=100
        #expect(vm.xPosition(forBar: 2.0) == 100.0)
        // Bar 5 starts at x=400
        #expect(vm.xPosition(forBar: 5.0) == 400.0)
    }

    @Test("X-position to bar conversion")
    @MainActor
    func xPositionToBar() {
        let vm = TimelineViewModel()
        vm.pixelsPerBar = 100
        #expect(vm.bar(forXPosition: 0) == 1.0)
        #expect(vm.bar(forXPosition: 100) == 2.0)
        #expect(vm.bar(forXPosition: 250) == 3.5)
    }

    @Test("Playhead x position")
    @MainActor
    func playheadXPosition() {
        let vm = TimelineViewModel()
        vm.pixelsPerBar = 100
        vm.playheadBar = 3.0
        #expect(vm.playheadX == 200.0)
    }

    @Test("Zoom in increases pixels per bar")
    @MainActor
    func zoomIn() {
        let vm = TimelineViewModel()
        let before = vm.pixelsPerBar
        vm.zoomIn()
        #expect(vm.pixelsPerBar > before)
    }

    @Test("Zoom out decreases pixels per bar")
    @MainActor
    func zoomOut() {
        let vm = TimelineViewModel()
        let before = vm.pixelsPerBar
        vm.zoomOut()
        #expect(vm.pixelsPerBar < before)
    }

    @Test("Zoom in respects maximum")
    @MainActor
    func zoomInMax() {
        let vm = TimelineViewModel()
        for _ in 0..<50 {
            vm.zoomIn()
        }
        #expect(vm.pixelsPerBar <= TimelineViewModel.maxPixelsPerBar)
    }

    @Test("Zoom out respects minimum")
    @MainActor
    func zoomOutMin() {
        let vm = TimelineViewModel()
        for _ in 0..<50 {
            vm.zoomOut()
        }
        #expect(vm.pixelsPerBar >= TimelineViewModel.minPixelsPerBar)
    }

    @Test("Pixels per beat calculation")
    @MainActor
    func pixelsPerBeat() {
        let vm = TimelineViewModel()
        vm.pixelsPerBar = 120
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        #expect(vm.pixelsPerBeat(timeSignature: ts) == 30.0)

        let ts3 = TimeSignature(beatsPerBar: 3, beatUnit: 4)
        #expect(vm.pixelsPerBeat(timeSignature: ts3) == 40.0)
    }

    // MARK: - Selected Range (#69)

    @Test("Selected range defaults to nil")
    @MainActor
    func selectedRangeDefault() {
        let vm = TimelineViewModel()
        #expect(vm.selectedRange == nil)
        #expect(vm.selectedTrackIDs.isEmpty)
    }

    @Test("Set and clear selected range")
    @MainActor
    func setAndClearSelectedRange() {
        let vm = TimelineViewModel()
        vm.selectedRange = 3...8
        #expect(vm.selectedRange == 3...8)
        vm.clearSelectedRange()
        #expect(vm.selectedRange == nil)
    }

    @Test("Toggle track selection adds and removes")
    @MainActor
    func toggleTrackSelection() {
        let vm = TimelineViewModel()
        let trackID = ID<Track>()
        let trackID2 = ID<Track>()

        #expect(vm.selectedTrackIDs.isEmpty)
        vm.toggleTrackSelection(trackID: trackID)
        #expect(vm.selectedTrackIDs.contains(trackID))
        #expect(vm.selectedTrackIDs.count == 1)

        vm.toggleTrackSelection(trackID: trackID2)
        #expect(vm.selectedTrackIDs.count == 2)

        vm.toggleTrackSelection(trackID: trackID)
        #expect(!vm.selectedTrackIDs.contains(trackID))
        #expect(vm.selectedTrackIDs.count == 1)
    }
}
