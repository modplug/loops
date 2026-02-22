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
        let x0 = AutomationCoordinateMapping.xForPosition(0.0, containerLengthBars: 4, pixelsPerBar: 100)
        #expect(x0 == 0.0)

        // position 2.0 (2 bars in) with 100px/bar → x = 200
        let x2 = AutomationCoordinateMapping.xForPosition(2.0, containerLengthBars: 4, pixelsPerBar: 100)
        #expect(x2 == 200.0)

        // position at end of 4-bar container → x = 400
        let xEnd = AutomationCoordinateMapping.xForPosition(4.0, containerLengthBars: 4, pixelsPerBar: 100)
        #expect(xEnd == 400.0)

        // fractional position: 1.5 bars → x = 150
        let xFrac = AutomationCoordinateMapping.xForPosition(1.5, containerLengthBars: 4, pixelsPerBar: 100)
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
        let p0 = AutomationCoordinateMapping.positionForX(0, containerLengthBars: 4, pixelsPerBar: 100)
        #expect(p0 == 0.0)

        // x = 200 with 100px/bar → position = 2.0
        let p2 = AutomationCoordinateMapping.positionForX(200, containerLengthBars: 4, pixelsPerBar: 100)
        #expect(p2 == 2.0)

        // x = 400 → position = 4.0 (clamped to container length)
        let pEnd = AutomationCoordinateMapping.positionForX(400, containerLengthBars: 4, pixelsPerBar: 100)
        #expect(pEnd == 4.0)

        // Negative x → clamped to 0
        let pNeg = AutomationCoordinateMapping.positionForX(-50, containerLengthBars: 4, pixelsPerBar: 100)
        #expect(pNeg == 0.0)

        // Beyond container → clamped to container length
        let pBeyond = AutomationCoordinateMapping.positionForX(600, containerLengthBars: 4, pixelsPerBar: 100)
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
        let containerLength = 8
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
        let containerLengthBars = 4
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
        let containerLengthBars = 8
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
        let containerLengthBars = 4
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
}
