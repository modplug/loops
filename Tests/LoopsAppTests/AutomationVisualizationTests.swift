import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore

@Suite("Automation Visualization Tests")
struct AutomationVisualizationTests {

    // MARK: - Coordinate Mapping Tests

    @Test("Breakpoint position to x-coordinate mapping")
    func positionToX() {
        // position 0 at start of container → x = 0
        let x0 = AutomationCoordinateMapping.xForPosition(0.0, containerLengthBars: 4.0, pixelsPerBar: 100)
        #expect(x0 == 0.0)

        // position 2.0 (2 bars in) with 100px/bar → x = 200
        let x2 = AutomationCoordinateMapping.xForPosition(2.0, containerLengthBars: 4.0, pixelsPerBar: 100)
        #expect(x2 == 200.0)

        // position at end of 4-bar container → x = 400
        let xEnd = AutomationCoordinateMapping.xForPosition(4.0, containerLengthBars: 4.0, pixelsPerBar: 100)
        #expect(xEnd == 400.0)

        // fractional position: 1.5 bars → x = 150
        let xFrac = AutomationCoordinateMapping.xForPosition(1.5, containerLengthBars: 4.0, pixelsPerBar: 100)
        #expect(xFrac == 150.0)
    }

    @Test("Breakpoint value to y-coordinate mapping")
    func valueToY() {
        let height: CGFloat = 200

        // value 1.0 (max) → y = 0 (top)
        let yMax = AutomationCoordinateMapping.yForValue(1.0, height: height)
        #expect(yMax == 0.0)

        // value 0.0 (min) → y = 200 (bottom)
        let yMin = AutomationCoordinateMapping.yForValue(0.0, height: height)
        #expect(yMin == 200.0)

        // value 0.5 (mid) → y = 100 (center)
        let yMid = AutomationCoordinateMapping.yForValue(0.5, height: height)
        #expect(yMid == 100.0)

        // value 0.75 → y = 50
        let yQ = AutomationCoordinateMapping.yForValue(0.75, height: height)
        #expect(yQ == 50.0)
    }

    @Test("X-coordinate to breakpoint position mapping")
    func xToPosition() {
        // x = 0 → position = 0
        let p0 = AutomationCoordinateMapping.positionForX(0, containerLengthBars: 4.0, pixelsPerBar: 100)
        #expect(p0 == 0.0)

        // x = 200 with 100px/bar → position = 2.0
        let p2 = AutomationCoordinateMapping.positionForX(200, containerLengthBars: 4.0, pixelsPerBar: 100)
        #expect(p2 == 2.0)

        // x = 400 → position = 4.0 (clamped to container length)
        let pEnd = AutomationCoordinateMapping.positionForX(400, containerLengthBars: 4.0, pixelsPerBar: 100)
        #expect(pEnd == 4.0)

        // Negative x → clamped to 0
        let pNeg = AutomationCoordinateMapping.positionForX(-50, containerLengthBars: 4.0, pixelsPerBar: 100)
        #expect(pNeg == 0.0)

        // Beyond container → clamped to container length
        let pBeyond = AutomationCoordinateMapping.positionForX(600, containerLengthBars: 4.0, pixelsPerBar: 100)
        #expect(pBeyond == 4.0)
    }

    @Test("Y-coordinate to breakpoint value mapping")
    func yToValue() {
        let height: CGFloat = 200

        // y = 0 (top) → value = 1.0
        let vTop = AutomationCoordinateMapping.valueForY(0, height: height)
        #expect(vTop == 1.0)

        // y = 200 (bottom) → value = 0.0
        let vBottom = AutomationCoordinateMapping.valueForY(200, height: height)
        #expect(vBottom == 0.0)

        // y = 100 (center) → value = 0.5
        let vMid = AutomationCoordinateMapping.valueForY(100, height: height)
        #expect(vMid == 0.5)

        // Negative y → clamped to 1.0
        let vNeg = AutomationCoordinateMapping.valueForY(-50, height: height)
        #expect(vNeg == 1.0)

        // Beyond height → clamped to 0.0
        let vBeyond = AutomationCoordinateMapping.valueForY(300, height: height)
        #expect(vBeyond == 0.0)
    }

    @Test("Round-trip: position → x → position")
    func positionRoundTrip() {
        let containerLength = 8.0
        let pixelsPerBar: CGFloat = 120

        for position in [0.0, 1.0, 2.5, 4.0, 7.99, 8.0] {
            let x = AutomationCoordinateMapping.xForPosition(position, containerLengthBars: containerLength, pixelsPerBar: pixelsPerBar)
            let recovered = AutomationCoordinateMapping.positionForX(x, containerLengthBars: containerLength, pixelsPerBar: pixelsPerBar)
            #expect(abs(recovered - position) < 0.001, "Round-trip failed for position \(position)")
        }
    }

    @Test("Round-trip: value → y → value")
    func valueRoundTrip() {
        let height: CGFloat = 300

        for value: Float in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let y = AutomationCoordinateMapping.yForValue(value, height: height)
            let recovered = AutomationCoordinateMapping.valueForY(y, height: height)
            #expect(abs(recovered - value) < 0.001, "Round-trip failed for value \(value)")
        }
    }

    // MARK: - Add Breakpoint at Click Position

    @Test("Add breakpoint at click position produces correct bar/value")
    func addBreakpointAtClickPosition() {
        // Simulate clicking at x=150, y=80 in a 4-bar container at 100px/bar, height 200
        let containerLengthBars = 4.0
        let pixelsPerBar: CGFloat = 100
        let height: CGFloat = 200

        let clickX: CGFloat = 150
        let clickY: CGFloat = 80

        let position = AutomationCoordinateMapping.positionForX(clickX, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
        let value = AutomationCoordinateMapping.valueForY(clickY, height: height)

        // x=150 at 100px/bar → position = 1.5 bars
        #expect(abs(position - 1.5) < 0.001)

        // y=80 at height=200 → value = 1 - 80/200 = 0.6
        #expect(abs(value - 0.6) < 0.001)

        // Create the breakpoint
        let bp = AutomationBreakpoint(position: position, value: value)
        #expect(abs(bp.position - 1.5) < 0.001)
        #expect(abs(bp.value - 0.6) < 0.001)
    }

    // MARK: - Drag Breakpoint Updates Position and Value

    @Test("Drag breakpoint updates position and value correctly")
    func dragBreakpointUpdates() {
        let containerLengthBars = 8.0
        let pixelsPerBar: CGFloat = 120
        let height: CGFloat = 160

        // Start position: bar 2.0, value 0.5
        var bp = AutomationBreakpoint(position: 2.0, value: 0.5)

        // Simulate drag to new pixel location: x=480, y=40
        let newX: CGFloat = 480
        let newY: CGFloat = 40

        let newPosition = AutomationCoordinateMapping.positionForX(newX, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
        let newValue = AutomationCoordinateMapping.valueForY(newY, height: height)

        bp.position = newPosition
        bp.value = newValue

        // x=480 at 120px/bar → position = 4.0
        #expect(abs(bp.position - 4.0) < 0.001)

        // y=40 at height=160 → value = 1 - 40/160 = 0.75
        #expect(abs(bp.value - 0.75) < 0.001)
    }

    @Test("Drag breakpoint clamps to container bounds")
    func dragBreakpointClamps() {
        let containerLengthBars = 4.0
        let pixelsPerBar: CGFloat = 100
        let height: CGFloat = 200

        // Drag beyond container to the right
        let posRight = AutomationCoordinateMapping.positionForX(600, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
        #expect(posRight == 4.0)

        // Drag beyond container to the left
        let posLeft = AutomationCoordinateMapping.positionForX(-100, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
        #expect(posLeft == 0.0)

        // Drag above the lane
        let valAbove = AutomationCoordinateMapping.valueForY(-50, height: height)
        #expect(valAbove == 1.0)

        // Drag below the lane
        let valBelow = AutomationCoordinateMapping.valueForY(300, height: height)
        #expect(valBelow == 0.0)
    }

    // MARK: - TimelineViewModel Automation Expanded State

    @Test("Toggle automation expanded adds and removes track ID")
    @MainActor
    func toggleAutomationExpanded() {
        let vm = TimelineViewModel()
        let trackID = ID<Track>()

        #expect(vm.automationExpanded.isEmpty)

        vm.toggleAutomationExpanded(trackID: trackID)
        #expect(vm.automationExpanded.contains(trackID))

        vm.toggleAutomationExpanded(trackID: trackID)
        #expect(!vm.automationExpanded.contains(trackID))
    }

    @Test("Track height includes sub-lane space when expanded")
    @MainActor
    func trackHeightWithSubLanes() {
        let vm = TimelineViewModel()
        let targetPath = EffectPath(trackID: ID<Track>(), effectIndex: 0, parameterAddress: 42)
        let lane = AutomationLane(targetPath: targetPath, breakpoints: [
            AutomationBreakpoint(position: 0, value: 0.5)
        ])
        let container = Container(name: "C1", startBar: 1, lengthBars: 4, automationLanes: [lane])
        let track = Track(name: "T1", kind: .audio, containers: [container])

        let baseHeight: CGFloat = 80

        // Not expanded → base height
        let h1 = vm.trackHeight(for: track, baseHeight: baseHeight)
        #expect(h1 == baseHeight)

        // Expanded → base + sub-lane height
        vm.automationExpanded.insert(track.id)
        let h2 = vm.trackHeight(for: track, baseHeight: baseHeight)
        #expect(h2 == baseHeight + TimelineViewModel.automationSubLaneHeight)
    }

    @Test("Track height with no automation lanes stays at base when expanded")
    @MainActor
    func trackHeightNoAutomation() {
        let vm = TimelineViewModel()
        let track = Track(name: "T1", kind: .audio)

        vm.automationExpanded.insert(track.id)
        let h = vm.trackHeight(for: track, baseHeight: 80)
        #expect(h == 80)
    }

    @Test("Automation lane count across multiple containers")
    @MainActor
    func automationLaneCountMultipleContainers() {
        let vm = TimelineViewModel()
        let path1 = EffectPath(trackID: ID<Track>(), effectIndex: 0, parameterAddress: 1)
        let path2 = EffectPath(trackID: ID<Track>(), effectIndex: 0, parameterAddress: 2)

        let c1 = Container(name: "C1", startBar: 1, lengthBars: 4, automationLanes: [
            AutomationLane(targetPath: path1),
            AutomationLane(targetPath: path2)
        ])
        let c2 = Container(name: "C2", startBar: 5, lengthBars: 4, automationLanes: [
            AutomationLane(targetPath: path1)  // same path as c1's first lane
        ])

        let track = Track(name: "T1", kind: .audio, containers: [c1, c2])

        // 2 unique paths (path1 appears in both containers but counts once)
        let count = vm.automationLaneCount(for: track)
        #expect(count == 2)
    }

    // MARK: - Automation Snap Position Tests

    @Test("Snap position to quarter note resolution in 4/4")
    func snapPositionQuarter4_4() {
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)

        // Position 0.3 bars → 0.3 * 4 beats = 1.2 beats → snaps to 1.0 beat → 0.25 bars
        let snapped = AutomationCoordinateMapping.snappedPosition(0.3, snapResolution: .quarter, timeSignature: ts)
        #expect(abs(snapped - 0.25) < 0.001)

        // Position 0.0 → stays at 0.0
        let snapZero = AutomationCoordinateMapping.snappedPosition(0.0, snapResolution: .quarter, timeSignature: ts)
        #expect(abs(snapZero - 0.0) < 0.001)

        // Position 1.0 → stays at 1.0 (exactly on bar boundary)
        let snapOne = AutomationCoordinateMapping.snappedPosition(1.0, snapResolution: .quarter, timeSignature: ts)
        #expect(abs(snapOne - 1.0) < 0.001)
    }

    @Test("Snap position to eighth note resolution in 4/4")
    func snapPositionEighth4_4() {
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)

        // Position 0.15 bars → 0.6 beats → snaps to 0.5 beats → 0.125 bars
        let snapped = AutomationCoordinateMapping.snappedPosition(0.15, snapResolution: .eighth, timeSignature: ts)
        #expect(abs(snapped - 0.125) < 0.001)

        // Position 0.5 → 2.0 beats → snaps to 2.0 → 0.5 bars
        let snapHalf = AutomationCoordinateMapping.snappedPosition(0.5, snapResolution: .eighth, timeSignature: ts)
        #expect(abs(snapHalf - 0.5) < 0.001)
    }

    @Test("Snap position to whole note resolution in 4/4")
    func snapPositionWhole4_4() {
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)

        // Position 0.6 bars → 2.4 beats → snaps to 4.0 beats (1 whole) → 1.0 bar
        let snapped = AutomationCoordinateMapping.snappedPosition(0.6, snapResolution: .whole, timeSignature: ts)
        #expect(abs(snapped - 1.0) < 0.001)

        // Position 0.1 bars → 0.4 beats → snaps to 0.0 → 0.0 bars
        let snapNear0 = AutomationCoordinateMapping.snappedPosition(0.1, snapResolution: .whole, timeSignature: ts)
        #expect(abs(snapNear0 - 0.0) < 0.001)
    }

    @Test("Snap position to sixteenth note resolution in 3/4")
    func snapPositionSixteenth3_4() {
        let ts = TimeSignature(beatsPerBar: 3, beatUnit: 4)

        // Position 0.1 bars → 0.3 beats → snaps to 0.25 beats → 0.25/3 ≈ 0.0833 bars
        let snapped = AutomationCoordinateMapping.snappedPosition(0.1, snapResolution: .sixteenth, timeSignature: ts)
        #expect(abs(snapped - 0.25 / 3.0) < 0.001)
    }

    @Test("Snap position never goes negative")
    func snapPositionNonNegative() {
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)

        let snapped = AutomationCoordinateMapping.snappedPosition(-0.1, snapResolution: .quarter, timeSignature: ts)
        #expect(snapped >= 0.0)
    }

    // MARK: - Automation Snap Value Tests

    @Test("Snap value with dB unit — 0.5 dB increments")
    func snapValueDB() {
        // Range -60 to 0 dB, normalized value
        // Normalized 0.5 → -30 dB → stays at -30 (already on 0.5 increment)
        let snapped = AutomationCoordinateMapping.snappedValue(0.5, parameterMin: -60, parameterMax: 0, parameterUnit: "dB")
        #expect(abs(snapped - 0.5) < 0.001)

        // Normalized 0.342 → -60 + 0.342 * 60 = -39.48 dB → snaps to -39.5 dB → ((-39.5 + 60) / 60) = 0.3417
        let snapped2 = AutomationCoordinateMapping.snappedValue(0.342, parameterMin: -60, parameterMax: 0, parameterUnit: "dB")
        let expected = Float((-39.5 + 60.0) / 60.0)
        #expect(abs(snapped2 - expected) < 0.01)
    }

    @Test("Snap value with percent unit — 1% increments")
    func snapValuePercent() {
        // Range 0 to 100%, value 0.555 → 55.5% → snaps to 56% → 0.56
        let snapped = AutomationCoordinateMapping.snappedValue(0.555, parameterMin: 0, parameterMax: 100, parameterUnit: "%")
        #expect(abs(snapped - 0.56) < 0.01)
    }

    @Test("Snap value with no metadata — 5% increments of 0–1 range")
    func snapValueNoMetadata() {
        // 0.33 → snaps to 0.35 (nearest 0.05)
        let snapped = AutomationCoordinateMapping.snappedValue(0.33, parameterMin: nil, parameterMax: nil, parameterUnit: nil)
        #expect(abs(snapped - 0.35) < 0.01)

        // 0.0 → stays at 0.0
        let snapZero = AutomationCoordinateMapping.snappedValue(0.0, parameterMin: nil, parameterMax: nil, parameterUnit: nil)
        #expect(abs(snapZero - 0.0) < 0.001)

        // 1.0 → stays at 1.0
        let snapOne = AutomationCoordinateMapping.snappedValue(1.0, parameterMin: nil, parameterMax: nil, parameterUnit: nil)
        #expect(abs(snapOne - 1.0) < 0.001)
    }

    @Test("Snap value with generic unit — 5% of range")
    func snapValueGenericUnit() {
        // Range 20 to 20000 Hz, 5% = 999 Hz increment
        // Normalized 0.5 → 10010 Hz → snaps to nearest 999 multiple
        let snapped = AutomationCoordinateMapping.snappedValue(0.5, parameterMin: 20, parameterMax: 20000, parameterUnit: "Hz")
        // 10010 / 999 = 10.02 → 10 * 999 = 9990 → normalized: (9990 - 20) / 19980 ≈ 0.4995
        #expect(abs(snapped - 0.5) < 0.02)
    }

    @Test("Snap value clamps to 0–1 range")
    func snapValueClamps() {
        // Extreme values should be clamped
        let snappedHigh = AutomationCoordinateMapping.snappedValue(1.0, parameterMin: 0, parameterMax: 100, parameterUnit: "%")
        #expect(snappedHigh <= 1.0)
        #expect(snappedHigh >= 0.0)

        let snappedLow = AutomationCoordinateMapping.snappedValue(0.0, parameterMin: 0, parameterMax: 100, parameterUnit: "%")
        #expect(snappedLow >= 0.0)
        #expect(snappedLow <= 1.0)
    }

    @Test("Snap value with pan unit — integer increments")
    func snapValuePan() {
        // Pan range -1 to 1, normalized 0.35 → -1 + 0.35 * 2 = -0.3 → snaps to 0 → normalized (0 + 1)/2 = 0.5
        let snapped = AutomationCoordinateMapping.snappedValue(0.35, parameterMin: -1, parameterMax: 1, parameterUnit: "pan")
        #expect(abs(snapped - 0.5) < 0.01) // snaps to center (0 pan)
    }
}
