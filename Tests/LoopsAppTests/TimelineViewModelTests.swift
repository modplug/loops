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

    // MARK: - Click-to-Position (#73)

    @Test("Snapped bar at x=0 returns bar 1")
    @MainActor
    func snappedBarAtOrigin() {
        let vm = TimelineViewModel()
        vm.pixelsPerBar = 100
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        // x=0 → bar 1
        #expect(vm.snappedBar(forXPosition: 0, timeSignature: ts) == 1.0)
    }

    @Test("Snapped bar at x=pixelsPerBar returns bar 2")
    @MainActor
    func snappedBarAtOneBar() {
        let vm = TimelineViewModel()
        vm.pixelsPerBar = 100
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        // x=100 → bar 2.0 (raw 2.0, snapped to whole bar)
        #expect(vm.snappedBar(forXPosition: 100, timeSignature: ts) == 2.0)
    }

    @Test("Snap-to-bar at low zoom: rounds to nearest whole bar")
    @MainActor
    func snapToBarLowZoom() {
        let vm = TimelineViewModel()
        // Low zoom: pixelsPerBar=60, 4/4 time → 15 pixels per beat (< 40 threshold)
        vm.pixelsPerBar = 60
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)

        // x=20 → rawBar = 20/60 + 1 = 1.333 → rounds to 1.0
        #expect(vm.snappedBar(forXPosition: 20, timeSignature: ts) == 1.0)
        // x=40 → rawBar = 40/60 + 1 = 1.667 → rounds to 2.0
        #expect(vm.snappedBar(forXPosition: 40, timeSignature: ts) == 2.0)
        // x=150 → rawBar = 150/60 + 1 = 3.5 → rounds to 4.0
        #expect(vm.snappedBar(forXPosition: 150, timeSignature: ts) == 4.0)
    }

    @Test("Snap-to-beat at high zoom: rounds to nearest beat")
    @MainActor
    func snapToBeatHighZoom() {
        let vm = TimelineViewModel()
        // High zoom: pixelsPerBar=200, 4/4 time → 50 pixels per beat (>= 40 threshold)
        vm.pixelsPerBar = 200
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)

        // x=0 → bar 1.0 (beat 1 of bar 1)
        #expect(vm.snappedBar(forXPosition: 0, timeSignature: ts) == 1.0)
        // x=50 → rawBar = 50/200 + 1 = 1.25 → 1 beat = 0.25 bar → snapped bar 1.25
        #expect(vm.snappedBar(forXPosition: 50, timeSignature: ts) == 1.25)
        // x=100 → rawBar = 100/200 + 1 = 1.5 → 2 beats = 0.5 bar → snapped bar 1.5
        #expect(vm.snappedBar(forXPosition: 100, timeSignature: ts) == 1.5)
        // x=175 → rawBar = 175/200 + 1 = 1.875 → 3.5 beats → rounds to 4 beats = 1.0 bar → bar 2.0
        #expect(vm.snappedBar(forXPosition: 175, timeSignature: ts) == 2.0)
    }

    @Test("Snap-to-bar at various pixelsPerBar values")
    @MainActor
    func snapAtVariousZoom() {
        let vm = TimelineViewModel()
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)

        // At minimum zoom (30 ppb, 7.5 per beat → bar snap)
        vm.pixelsPerBar = 30
        let bar30 = vm.snappedBar(forXPosition: 45, timeSignature: ts)
        // rawBar = 45/30 + 1 = 2.5 → rounds to 3
        #expect(bar30 == 3.0)

        // At maximum zoom (500 ppb, 125 per beat → beat snap)
        vm.pixelsPerBar = 500
        let bar500 = vm.snappedBar(forXPosition: 125, timeSignature: ts)
        // rawBar = 125/500 + 1 = 1.25 → snaps to 1 beat = 0.25 bar → 1.25
        #expect(bar500 == 1.25)
    }

    @Test("Snapped bar clamps negative x to bar 1")
    @MainActor
    func snappedBarNegativeX() {
        let vm = TimelineViewModel()
        vm.pixelsPerBar = 100
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        #expect(vm.snappedBar(forXPosition: -50, timeSignature: ts) == 1.0)
    }

    @Test("Snap-to-beat with 3/4 time signature")
    @MainActor
    func snapToBeatThreeFour() {
        let vm = TimelineViewModel()
        // High zoom: pixelsPerBar=180, 3/4 → 60 pixels per beat (>= 40)
        vm.pixelsPerBar = 180
        let ts = TimeSignature(beatsPerBar: 3, beatUnit: 4)

        // x=60 → rawBar = 60/180 + 1 = 1.333 → totalBeats = 0.333*3 = 1 beat → snapped 1/3 bar → 1.333
        let result = vm.snappedBar(forXPosition: 60, timeSignature: ts)
        #expect(abs(result - (1.0 + 1.0/3.0)) < 0.001)
    }
}
