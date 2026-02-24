import SwiftUI
import LoopsCore

/// Renders a single automation sub-lane row for one automation parameter.
/// Shows the automation curve for each container in the track that targets this parameter,
/// positioned at the container's timeline location.
/// Also supports track-level automation lanes (volume/pan) that span the full timeline.
struct AutomationSubLaneView: View {
    let targetPath: EffectPath
    let containers: [Container]
    let laneColorIndex: Int
    let pixelsPerBar: CGFloat
    let totalBars: Int
    let height: CGFloat
    let selectedBreakpointID: ID<AutomationBreakpoint>?
    var onAddBreakpoint: ((_ containerID: ID<Container>, _ laneID: ID<AutomationLane>, _ breakpoint: AutomationBreakpoint) -> Void)?
    var onUpdateBreakpoint: ((_ containerID: ID<Container>, _ laneID: ID<AutomationLane>, _ breakpoint: AutomationBreakpoint) -> Void)?
    var onDeleteBreakpoint: ((_ containerID: ID<Container>, _ laneID: ID<AutomationLane>, _ breakpointID: ID<AutomationBreakpoint>) -> Void)?
    var onSelectBreakpoint: ((_ breakpointID: ID<AutomationBreakpoint>?) -> Void)?
    /// Track-level automation lane for this path (nil if container-level only).
    var trackAutomationLane: AutomationLane?
    var onAddTrackBreakpoint: ((_ laneID: ID<AutomationLane>, _ breakpoint: AutomationBreakpoint) -> Void)?
    var onUpdateTrackBreakpoint: ((_ laneID: ID<AutomationLane>, _ breakpoint: AutomationBreakpoint) -> Void)?
    var onDeleteTrackBreakpoint: ((_ laneID: ID<AutomationLane>, _ breakpointID: ID<AutomationBreakpoint>) -> Void)?
    /// Snap resolution for horizontal position snapping (nil = snap disabled).
    var snapResolution: SnapResolution?
    /// Time signature for beat-based snap calculations.
    var timeSignature: TimeSignature?
    /// Grid mode for drawing grid lines in the sub-lane.
    var gridMode: GridMode?
    /// Currently selected shape tool.
    var selectedTool: AutomationTool = .pointer
    /// Grid spacing in bars for shape generation breakpoint density.
    var gridSpacingBars: Double = 0.25
    /// Callback to replace breakpoints in a range on a container lane with shape-generated ones.
    var onReplaceBreakpoints: ((_ containerID: ID<Container>, _ laneID: ID<AutomationLane>, _ startPosition: Double, _ endPosition: Double, _ breakpoints: [AutomationBreakpoint]) -> Void)?
    /// Callback to replace breakpoints in a range on a track lane with shape-generated ones.
    var onReplaceTrackBreakpoints: ((_ laneID: ID<AutomationLane>, _ startPosition: Double, _ endPosition: Double, _ breakpoints: [AutomationBreakpoint]) -> Void)?
    /// Multi-selection: set of selected breakpoint IDs. Falls back to single selectedBreakpointID if nil.
    var selectedBreakpointIDs: Set<ID<AutomationBreakpoint>>?
    /// Callback to replace the full set of selected breakpoint IDs (marquee / Cmd+click).
    var onSetSelectedBreakpoints: ((_ breakpointIDs: Set<ID<AutomationBreakpoint>>) -> Void)?

    /// Resolved set of selected IDs (prefers multi-select set, falls back to singular).
    private var resolvedSelectedIDs: Set<ID<AutomationBreakpoint>> {
        if let ids = selectedBreakpointIDs { return ids }
        if let id = selectedBreakpointID { return [id] }
        return []
    }

    /// Resolved callback for setting the selection set.
    private var resolvedSetSelected: (Set<ID<AutomationBreakpoint>>) -> Void {
        if let cb = onSetSelectedBreakpoints { return cb }
        // Fall back to single-select callback
        return { ids in
            onSelectBreakpoint?(ids.first)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Sub-lane background
            Rectangle()
                .fill(AutomationColors.color(at: laneColorIndex).opacity(0.05))
                .frame(width: CGFloat(totalBars) * pixelsPerBar, height: height)

            // Grid lines reflecting current snap resolution
            if let ts = timeSignature, let gm = gridMode {
                GridOverlayView(
                    totalBars: totalBars,
                    pixelsPerBar: pixelsPerBar,
                    timeSignature: ts,
                    height: height,
                    gridMode: gm
                )
                .opacity(0.5)
                .allowsHitTesting(false)
            }

            // Horizontal guide lines at 25%, 50%, 75%
            ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: CGFloat(totalBars) * pixelsPerBar, height: 0.5)
                    .offset(y: CGFloat(1.0 - fraction) * height)
            }

            // Track-level automation lane (spans entire timeline)
            if let lane = trackAutomationLane {
                TrackAutomationSubLaneView(
                    lane: lane,
                    laneColorIndex: laneColorIndex,
                    pixelsPerBar: pixelsPerBar,
                    totalBars: totalBars,
                    height: height,
                    selectedBreakpointIDs: resolvedSelectedIDs,
                    onAddBreakpoint: { breakpoint in
                        onAddTrackBreakpoint?(lane.id, breakpoint)
                    },
                    onUpdateBreakpoint: { breakpoint in
                        onUpdateTrackBreakpoint?(lane.id, breakpoint)
                    },
                    onDeleteBreakpoint: { breakpointID in
                        onDeleteTrackBreakpoint?(lane.id, breakpointID)
                    },
                    onSetSelectedBreakpoints: resolvedSetSelected,
                    snapResolution: snapResolution,
                    timeSignature: timeSignature,
                    selectedTool: selectedTool,
                    gridSpacingBars: gridSpacingBars,
                    onReplaceBreakpoints: { startPos, endPos, breakpoints in
                        onReplaceTrackBreakpoints?(lane.id, startPos, endPos, breakpoints)
                    }
                )
            }

            // Render automation for each container that has a lane targeting this path
            if trackAutomationLane == nil {
                ForEach(containers) { container in
                    if let lane = container.automationLanes.first(where: { $0.targetPath == targetPath }) {
                        AutomationSubLaneContainerView(
                            container: container,
                            lane: lane,
                            laneColorIndex: laneColorIndex,
                            pixelsPerBar: pixelsPerBar,
                            height: height,
                            selectedBreakpointIDs: resolvedSelectedIDs,
                            onAddBreakpoint: { breakpoint in
                                onAddBreakpoint?(container.id, lane.id, breakpoint)
                            },
                            onUpdateBreakpoint: { breakpoint in
                                onUpdateBreakpoint?(container.id, lane.id, breakpoint)
                            },
                            onDeleteBreakpoint: { breakpointID in
                                onDeleteBreakpoint?(container.id, lane.id, breakpointID)
                            },
                            onSetSelectedBreakpoints: resolvedSetSelected,
                            snapResolution: snapResolution,
                            timeSignature: timeSignature,
                            selectedTool: selectedTool,
                            gridSpacingBars: gridSpacingBars,
                            onReplaceBreakpoints: { startPos, endPos, breakpoints in
                                onReplaceBreakpoints?(container.id, lane.id, startPos, endPos, breakpoints)
                            }
                        )
                        .offset(x: CGFloat(container.startBar - 1) * pixelsPerBar)
                    }
                }
            }
        }
        .frame(width: CGFloat(totalBars) * pixelsPerBar, height: height)
    }
}

// MARK: - Equatable

extension AutomationSubLaneView: Equatable {
    static func == (lhs: AutomationSubLaneView, rhs: AutomationSubLaneView) -> Bool {
        lhs.targetPath == rhs.targetPath &&
        lhs.containers == rhs.containers &&
        lhs.laneColorIndex == rhs.laneColorIndex &&
        lhs.pixelsPerBar == rhs.pixelsPerBar &&
        lhs.totalBars == rhs.totalBars &&
        lhs.height == rhs.height &&
        lhs.selectedBreakpointID == rhs.selectedBreakpointID &&
        lhs.trackAutomationLane == rhs.trackAutomationLane
    }
}

/// Renders one container's automation curve in a sub-lane with full interaction support.
private struct AutomationSubLaneContainerView: View {
    let container: Container
    let lane: AutomationLane
    let laneColorIndex: Int
    let pixelsPerBar: CGFloat
    let height: CGFloat
    let selectedBreakpointIDs: Set<ID<AutomationBreakpoint>>
    var onAddBreakpoint: ((_ breakpoint: AutomationBreakpoint) -> Void)?
    var onUpdateBreakpoint: ((_ breakpoint: AutomationBreakpoint) -> Void)?
    var onDeleteBreakpoint: ((_ breakpointID: ID<AutomationBreakpoint>) -> Void)?
    var onSetSelectedBreakpoints: ((Set<ID<AutomationBreakpoint>>) -> Void)?
    var snapResolution: SnapResolution?
    var timeSignature: TimeSignature?
    var selectedTool: AutomationTool = .pointer
    var gridSpacingBars: Double = 0.25
    var onReplaceBreakpoints: ((_ startPosition: Double, _ endPosition: Double, _ breakpoints: [AutomationBreakpoint]) -> Void)?

    @State private var hoveredBreakpointID: ID<AutomationBreakpoint>?
    @State private var draggedBreakpointID: ID<AutomationBreakpoint>?
    @State private var dragPosition: CGPoint?
    @State private var dragStartPosition: Double?
    @State private var dragStartValue: Float?
    @State private var shapeDragStart: CGPoint?
    @State private var shapeDragEnd: CGPoint?
    @State private var marqueeOrigin: CGPoint?
    @State private var marqueeCurrent: CGPoint?

    private var containerWidth: CGFloat {
        CGFloat(container.lengthBars) * pixelsPerBar
    }

    private var containerLengthBars: Double {
        Double(container.lengthBars)
    }

    private var color: Color {
        AutomationColors.color(at: laneColorIndex)
    }

    /// IDs of breakpoints in this lane that are in the selection.
    private var selectedInLane: Set<ID<AutomationBreakpoint>> {
        let laneIDs = Set(lane.breakpoints.map(\.id))
        return selectedBreakpointIDs.intersection(laneIDs)
    }

    /// Returns whether snapping should be applied (respects Cmd key to invert).
    private var shouldSnap: Bool {
        let cmdHeld = NSEvent.modifierFlags.contains(.command)
        return cmdHeld ? (snapResolution == nil) : (snapResolution != nil)
    }

    /// Snaps a position (0-based bar offset) if snap is active.
    private func snapPosition(_ position: Double) -> Double {
        guard shouldSnap, let res = snapResolution, let ts = timeSignature else { return position }
        return AutomationCoordinateMapping.snappedPosition(position, snapResolution: res, timeSignature: ts)
    }

    /// Snaps a normalized value (0-1) if snap is active.
    private func snapValue(_ value: Float) -> Float {
        guard shouldSnap else { return value }
        return AutomationCoordinateMapping.snappedValue(value, parameterMin: lane.parameterMin, parameterMax: lane.parameterMax, parameterUnit: lane.parameterUnit)
    }

    /// Computes position/value delta from drag start to current drag position.
    private var groupDragDelta: (positionDelta: Double, valueDelta: Float)? {
        guard let dragPos = dragPosition,
              let startPos = dragStartPosition,
              let startVal = dragStartValue else { return nil }
        let currentPos = AutomationCoordinateMapping.positionForX(dragPos.x, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
        let currentVal = AutomationCoordinateMapping.valueForY(dragPos.y, height: height)
        return (positionDelta: currentPos - startPos, valueDelta: currentVal - startVal)
    }

    var body: some View {
        ZStack {
            // Container background tint
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.08))
                .frame(width: containerWidth, height: height)

            // Curve + breakpoints
            Canvas { context, size in
                drawCurve(lane: lane, in: context, size: size)
                drawBreakpoints(lane: lane, in: context, size: size)
                drawShapePreview(in: context, size: size)
            }
            .frame(width: containerWidth, height: height)

            // Tooltip overlay for hovered/dragged breakpoint
            if let tooltipBP = tooltipBreakpoint {
                let x = AutomationCoordinateMapping.xForPosition(tooltipBP.position, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
                let y = AutomationCoordinateMapping.yForValue(tooltipBP.value, height: height)
                Group {
                    if let min = lane.parameterMin, let max = lane.parameterMax {
                        let displayValue = min + tooltipBP.value * (max - min)
                        let unit = lane.parameterUnit ?? ""
                        Text(String(format: "%.1f %@", displayValue, unit).trimmingCharacters(in: .whitespaces))
                    } else {
                        Text(String(format: "%.2f", tooltipBP.value))
                    }
                }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                    .cornerRadius(2)
                    .offset(x: x - containerWidth / 2, y: y - height / 2 - 14)
                    .allowsHitTesting(false)
            }

            // Marquee selection rectangle overlay
            if let origin = marqueeOrigin, let current = marqueeCurrent {
                let rect = marqueeRect(origin: origin, current: current)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.1))
                    .border(Color.accentColor.opacity(0.5), width: 1)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }

            // Invisible interaction layer for breakpoint dragging, marquee, shape tools, and click-to-add
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: containerWidth, height: height)
                .gesture(selectedTool == .pointer ? clickGesture : nil)
                .gesture(selectedTool == .pointer ? marqueeDragGesture : nil)
                .gesture(selectedTool != .pointer ? shapeDrawGesture : nil)
                .overlay(selectedTool == .pointer ? breakpointDragOverlay : nil)
        }
        .frame(width: containerWidth, height: height)
    }

    private var tooltipBreakpoint: AutomationBreakpoint? {
        if let dragID = draggedBreakpointID, let pos = dragPosition {
            let rawValue = AutomationCoordinateMapping.valueForY(pos.y, height: height)
            let rawPosition = AutomationCoordinateMapping.positionForX(pos.x, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
            return AutomationBreakpoint(id: dragID, position: snapPosition(rawPosition), value: snapValue(rawValue))
        }
        if let hoverID = hoveredBreakpointID {
            return lane.breakpoints.first { $0.id == hoverID }
        }
        return nil
    }

    // MARK: - Drawing

    private func drawCurve(lane: AutomationLane, in context: GraphicsContext, size: CGSize) {
        let sorted = lane.breakpoints.sorted { $0.position < $1.position }
        guard !sorted.isEmpty else { return }

        var path = Path()
        let resolution = max(Int(size.width / 2), 2)
        for step in 0...resolution {
            let barPosition = Double(step) / Double(resolution) * containerLengthBars
            guard let value = lane.interpolatedValue(atBar: barPosition) else { continue }
            let x = CGFloat(step) / CGFloat(resolution) * size.width
            let y = CGFloat(1.0 - value) * size.height
            if step == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 1.5)
    }

    private func drawBreakpoints(lane: AutomationLane, in context: GraphicsContext, size: CGSize) {
        let delta = groupDragDelta
        for bp in lane.breakpoints {
            let isSelected = selectedBreakpointIDs.contains(bp.id)
            let isDragged = bp.id == draggedBreakpointID

            // Compute draw position, applying group drag delta for selected breakpoints
            var drawPosition = bp.position
            var drawValue = bp.value
            if isDragged, let pos = dragPosition {
                drawPosition = AutomationCoordinateMapping.positionForX(pos.x, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
                drawValue = AutomationCoordinateMapping.valueForY(pos.y, height: size.height)
            } else if isSelected, let d = delta {
                drawPosition = max(0, min(drawPosition + d.positionDelta, containerLengthBars))
                drawValue = max(0, min(drawValue + d.valueDelta, 1))
            }

            let x = AutomationCoordinateMapping.xForPosition(drawPosition, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
            let y = AutomationCoordinateMapping.yForValue(drawValue, height: size.height)
            let radius: CGFloat = isSelected || isDragged ? 5 : 4

            let dotRect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)

            if isSelected {
                // Selected: filled accent color
                context.fill(Path(ellipseIn: dotRect), with: .color(Color.accentColor))
                let ringRect = CGRect(x: x - radius - 1, y: y - radius - 1, width: (radius + 1) * 2, height: (radius + 1) * 2)
                context.stroke(Path(ellipseIn: ringRect), with: .color(.white), lineWidth: 1)
            } else {
                // Unselected: filled with lane color
                context.fill(Path(ellipseIn: dotRect), with: .color(color))
            }
        }
    }

    private func drawShapePreview(in context: GraphicsContext, size: CGSize) {
        guard let start = shapeDragStart, let end = shapeDragEnd else { return }
        let startPos = AutomationCoordinateMapping.positionForX(start.x, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
        let endPos = AutomationCoordinateMapping.positionForX(end.x, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
        let startVal = AutomationCoordinateMapping.valueForY(start.y, height: height)
        let endVal = AutomationCoordinateMapping.valueForY(end.y, height: height)
        let minPos = min(startPos, endPos)
        let maxPos = max(startPos, endPos)

        let previewBreakpoints = AutomationShapeGenerator.generate(
            tool: selectedTool,
            startPosition: minPos,
            endPosition: maxPos,
            startValue: startPos <= endPos ? startVal : endVal,
            endValue: startPos <= endPos ? endVal : startVal,
            gridSpacing: gridSpacingBars
        )
        guard previewBreakpoints.count >= 2 else { return }

        // Draw preview curve
        var path = Path()
        for (i, bp) in previewBreakpoints.enumerated() {
            let x = AutomationCoordinateMapping.xForPosition(bp.position, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
            let y = AutomationCoordinateMapping.yForValue(bp.value, height: size.height)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(path, with: .color(color.opacity(0.5)), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
    }

    // MARK: - Interaction

    private var clickGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let isCommand = NSEvent.modifierFlags.contains(.command)
                let rawPosition = AutomationCoordinateMapping.positionForX(value.location.x, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
                let rawVal = AutomationCoordinateMapping.valueForY(value.location.y, height: height)

                // Check if click is near an existing breakpoint
                if let nearBP = nearestBreakpoint(to: value.location, threshold: 8) {
                    if isCommand {
                        // Cmd+Click: toggle in/out of selection
                        var newSet = selectedBreakpointIDs
                        if newSet.contains(nearBP.id) {
                            newSet.remove(nearBP.id)
                        } else {
                            newSet.insert(nearBP.id)
                        }
                        onSetSelectedBreakpoints?(newSet)
                    } else {
                        // Plain click: select just this breakpoint
                        onSetSelectedBreakpoints?([nearBP.id])
                    }
                    return
                }

                // Click on empty space: clear selection and add new breakpoint
                if !selectedBreakpointIDs.isEmpty {
                    onSetSelectedBreakpoints?([])
                }
                let bp = AutomationBreakpoint(position: snapPosition(rawPosition), value: snapValue(rawVal))
                onAddBreakpoint?(bp)
            }
    }

    private var marqueeDragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                // Only start marquee if not clicking near a breakpoint
                if marqueeOrigin == nil {
                    if nearestBreakpoint(to: value.startLocation, threshold: 8) != nil {
                        return // Let breakpoint drag handle it
                    }
                    marqueeOrigin = value.startLocation
                }
                marqueeCurrent = value.location
            }
            .onEnded { _ in
                guard let origin = marqueeOrigin, let current = marqueeCurrent else { return }
                let rect = marqueeRect(origin: origin, current: current)
                let isCommand = NSEvent.modifierFlags.contains(.command)

                // Find breakpoints within marquee
                var marqueeSelection = Set<ID<AutomationBreakpoint>>()
                for bp in lane.breakpoints {
                    let bpX = AutomationCoordinateMapping.xForPosition(bp.position, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
                    let bpY = AutomationCoordinateMapping.yForValue(bp.value, height: height)
                    if rect.contains(CGPoint(x: bpX, y: bpY)) {
                        marqueeSelection.insert(bp.id)
                    }
                }

                if isCommand {
                    // Cmd+Marquee: add to existing selection
                    onSetSelectedBreakpoints?(selectedBreakpointIDs.union(marqueeSelection))
                } else {
                    onSetSelectedBreakpoints?(marqueeSelection)
                }

                marqueeOrigin = nil
                marqueeCurrent = nil
            }
    }

    private var shapeDrawGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                shapeDragStart = value.startLocation
                shapeDragEnd = value.location
            }
            .onEnded { value in
                defer {
                    shapeDragStart = nil
                    shapeDragEnd = nil
                }
                let start = value.startLocation
                let end = value.location
                let startPos = AutomationCoordinateMapping.positionForX(start.x, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
                let endPos = AutomationCoordinateMapping.positionForX(end.x, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
                let startVal = AutomationCoordinateMapping.valueForY(start.y, height: height)
                let endVal = AutomationCoordinateMapping.valueForY(end.y, height: height)
                let minPos = min(startPos, endPos)
                let maxPos = max(startPos, endPos)
                guard maxPos - minPos > 0.01 else { return }

                let breakpoints = AutomationShapeGenerator.generate(
                    tool: selectedTool,
                    startPosition: minPos,
                    endPosition: maxPos,
                    startValue: startPos <= endPos ? startVal : endVal,
                    endValue: startPos <= endPos ? endVal : startVal,
                    gridSpacing: gridSpacingBars
                )
                guard !breakpoints.isEmpty else { return }
                onReplaceBreakpoints?(minPos, maxPos, breakpoints)
            }
    }

    @ViewBuilder
    private var breakpointDragOverlay: some View {
        ForEach(lane.breakpoints) { bp in
            let x = AutomationCoordinateMapping.xForPosition(bp.position, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
            let y = AutomationCoordinateMapping.yForValue(bp.value, height: height)
            Circle()
                .fill(Color.clear)
                .frame(width: 16, height: 16)
                .contentShape(Circle())
                .onHover { hovering in
                    hoveredBreakpointID = hovering ? bp.id : nil
                }
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if draggedBreakpointID == nil {
                                draggedBreakpointID = bp.id
                                dragStartPosition = bp.position
                                dragStartValue = bp.value
                                // If dragging an unselected breakpoint, select just it
                                if !selectedBreakpointIDs.contains(bp.id) {
                                    onSetSelectedBreakpoints?([bp.id])
                                }
                            }
                            dragPosition = value.location
                        }
                        .onEnded { value in
                            let rawPosition = AutomationCoordinateMapping.positionForX(value.location.x, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
                            let rawValue = AutomationCoordinateMapping.valueForY(value.location.y, height: height)
                            let newPosition = snapPosition(rawPosition)
                            let newValue = snapValue(rawValue)
                            let posDelta = newPosition - snapPosition(dragStartPosition ?? bp.position)
                            let valDelta = newValue - snapValue(dragStartValue ?? bp.value)

                            // Apply delta to all selected breakpoints in this lane
                            let toMove = lane.breakpoints.filter { selectedBreakpointIDs.contains($0.id) }
                            if toMove.count > 1 {
                                for selectedBP in toMove {
                                    var updated = selectedBP
                                    updated.position = snapPosition(max(0, min(updated.position + posDelta, containerLengthBars)))
                                    updated.value = snapValue(max(0, min(updated.value + valDelta, 1)))
                                    onUpdateBreakpoint?(updated)
                                }
                            } else {
                                var updated = bp
                                updated.position = newPosition
                                updated.value = newValue
                                onUpdateBreakpoint?(updated)
                            }

                            draggedBreakpointID = nil
                            dragPosition = nil
                            dragStartPosition = nil
                            dragStartValue = nil
                        }
                )
                .position(x: x, y: y)
        }
    }

    private func nearestBreakpoint(to point: CGPoint, threshold: CGFloat) -> AutomationBreakpoint? {
        var closest: AutomationBreakpoint?
        var closestDist = threshold
        for bp in lane.breakpoints {
            let bpX = AutomationCoordinateMapping.xForPosition(bp.position, containerLengthBars: containerLengthBars, pixelsPerBar: pixelsPerBar)
            let bpY = AutomationCoordinateMapping.yForValue(bp.value, height: height)
            let dist = hypot(point.x - bpX, point.y - bpY)
            if dist < closestDist {
                closestDist = dist
                closest = bp
            }
        }
        return closest
    }

    private func marqueeRect(origin: CGPoint, current: CGPoint) -> CGRect {
        let minX = min(origin.x, current.x)
        let minY = min(origin.y, current.y)
        let maxX = max(origin.x, current.x)
        let maxY = max(origin.y, current.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Renders a track-level automation lane that spans the entire timeline.
/// Used for track volume/pan automation where breakpoint positions are in absolute bars (0-based).
private struct TrackAutomationSubLaneView: View {
    let lane: AutomationLane
    let laneColorIndex: Int
    let pixelsPerBar: CGFloat
    let totalBars: Int
    let height: CGFloat
    let selectedBreakpointIDs: Set<ID<AutomationBreakpoint>>
    var onAddBreakpoint: ((_ breakpoint: AutomationBreakpoint) -> Void)?
    var onUpdateBreakpoint: ((_ breakpoint: AutomationBreakpoint) -> Void)?
    var onDeleteBreakpoint: ((_ breakpointID: ID<AutomationBreakpoint>) -> Void)?
    var onSetSelectedBreakpoints: ((Set<ID<AutomationBreakpoint>>) -> Void)?
    var snapResolution: SnapResolution?
    var timeSignature: TimeSignature?
    var selectedTool: AutomationTool = .pointer
    var gridSpacingBars: Double = 0.25
    var onReplaceBreakpoints: ((_ startPosition: Double, _ endPosition: Double, _ breakpoints: [AutomationBreakpoint]) -> Void)?

    @State private var hoveredBreakpointID: ID<AutomationBreakpoint>?
    @State private var draggedBreakpointID: ID<AutomationBreakpoint>?
    @State private var dragPosition: CGPoint?
    @State private var dragStartPosition: Double?
    @State private var dragStartValue: Float?
    @State private var shapeDragStart: CGPoint?
    @State private var shapeDragEnd: CGPoint?
    @State private var marqueeOrigin: CGPoint?
    @State private var marqueeCurrent: CGPoint?

    private var totalWidth: CGFloat {
        CGFloat(totalBars) * pixelsPerBar
    }

    private var totalBarsDouble: Double {
        Double(totalBars)
    }

    private var color: Color {
        AutomationColors.color(at: laneColorIndex)
    }

    /// Returns whether snapping should be applied (respects Cmd key to invert).
    private var shouldSnap: Bool {
        let cmdHeld = NSEvent.modifierFlags.contains(.command)
        return cmdHeld ? (snapResolution == nil) : (snapResolution != nil)
    }

    /// Snaps a position (0-based bar offset) if snap is active.
    private func snapPosition(_ position: Double) -> Double {
        guard shouldSnap, let res = snapResolution, let ts = timeSignature else { return position }
        return AutomationCoordinateMapping.snappedPosition(position, snapResolution: res, timeSignature: ts)
    }

    /// Snaps a normalized value (0-1) if snap is active.
    private func snapValue(_ value: Float) -> Float {
        guard shouldSnap else { return value }
        return AutomationCoordinateMapping.snappedValue(value, parameterMin: lane.parameterMin, parameterMax: lane.parameterMax, parameterUnit: lane.parameterUnit)
    }

    /// Computes position/value delta from drag start to current drag position.
    private var groupDragDelta: (positionDelta: Double, valueDelta: Float)? {
        guard let dragPos = dragPosition,
              let startPos = dragStartPosition,
              let startVal = dragStartValue else { return nil }
        let currentPos = AutomationCoordinateMapping.positionForX(dragPos.x, containerLengthBars: totalBarsDouble, pixelsPerBar: pixelsPerBar)
        let currentVal = AutomationCoordinateMapping.valueForY(dragPos.y, height: height)
        return (positionDelta: currentPos - startPos, valueDelta: currentVal - startVal)
    }

    var body: some View {
        ZStack {
            // Curve + breakpoints
            Canvas { context, size in
                drawCurve(in: context, size: size)
                drawBreakpoints(in: context, size: size)
                drawShapePreview(in: context, size: size)
            }
            .frame(width: totalWidth, height: height)

            // Tooltip overlay for hovered/dragged breakpoint
            if let tooltipBP = tooltipBreakpoint {
                let x = AutomationCoordinateMapping.xForPosition(tooltipBP.position, containerLengthBars: totalBarsDouble, pixelsPerBar: pixelsPerBar)
                let y = AutomationCoordinateMapping.yForValue(tooltipBP.value, height: height)
                Text(String(format: "%.2f", tooltipBP.value))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                    .cornerRadius(2)
                    .offset(x: x - totalWidth / 2, y: y - height / 2 - 14)
                    .allowsHitTesting(false)
            }

            // Marquee selection rectangle overlay
            if let origin = marqueeOrigin, let current = marqueeCurrent {
                let rect = marqueeRect(origin: origin, current: current)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.1))
                    .border(Color.accentColor.opacity(0.5), width: 1)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }

            // Invisible interaction layer
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: totalWidth, height: height)
                .gesture(selectedTool == .pointer ? clickGesture : nil)
                .gesture(selectedTool == .pointer ? marqueeDragGesture : nil)
                .gesture(selectedTool != .pointer ? shapeDrawGesture : nil)
                .overlay(selectedTool == .pointer ? breakpointDragOverlay : nil)
        }
        .frame(width: totalWidth, height: height)
    }

    private var tooltipBreakpoint: AutomationBreakpoint? {
        if let dragID = draggedBreakpointID, let pos = dragPosition {
            let rawValue = AutomationCoordinateMapping.valueForY(pos.y, height: height)
            let rawPosition = AutomationCoordinateMapping.positionForX(pos.x, containerLengthBars: totalBarsDouble, pixelsPerBar: pixelsPerBar)
            return AutomationBreakpoint(id: dragID, position: snapPosition(rawPosition), value: snapValue(rawValue))
        }
        if let hoverID = hoveredBreakpointID {
            return lane.breakpoints.first { $0.id == hoverID }
        }
        return nil
    }

    private func drawCurve(in context: GraphicsContext, size: CGSize) {
        let sorted = lane.breakpoints.sorted { $0.position < $1.position }
        guard !sorted.isEmpty else { return }

        var path = Path()
        let resolution = max(Int(size.width / 2), 2)
        for step in 0...resolution {
            let barPosition = Double(step) / Double(resolution) * totalBarsDouble
            guard let value = lane.interpolatedValue(atBar: barPosition) else { continue }
            let x = CGFloat(step) / CGFloat(resolution) * size.width
            let y = CGFloat(1.0 - value) * size.height
            if step == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 1.5)
    }

    private func drawBreakpoints(in context: GraphicsContext, size: CGSize) {
        let delta = groupDragDelta
        for bp in lane.breakpoints {
            let isSelected = selectedBreakpointIDs.contains(bp.id)
            let isDragged = bp.id == draggedBreakpointID

            // Compute draw position, applying group drag delta for selected breakpoints
            var drawPosition = bp.position
            var drawValue = bp.value
            if isDragged, let pos = dragPosition {
                drawPosition = AutomationCoordinateMapping.positionForX(pos.x, containerLengthBars: totalBarsDouble, pixelsPerBar: pixelsPerBar)
                drawValue = AutomationCoordinateMapping.valueForY(pos.y, height: size.height)
            } else if isSelected, let d = delta {
                drawPosition = max(0, min(drawPosition + d.positionDelta, totalBarsDouble))
                drawValue = max(0, min(drawValue + d.valueDelta, 1))
            }

            let x = AutomationCoordinateMapping.xForPosition(drawPosition, containerLengthBars: totalBarsDouble, pixelsPerBar: pixelsPerBar)
            let y = AutomationCoordinateMapping.yForValue(drawValue, height: size.height)
            let radius: CGFloat = isSelected || isDragged ? 5 : 4

            let dotRect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)

            if isSelected {
                // Selected: filled accent color
                context.fill(Path(ellipseIn: dotRect), with: .color(Color.accentColor))
                let ringRect = CGRect(x: x - radius - 1, y: y - radius - 1, width: (radius + 1) * 2, height: (radius + 1) * 2)
                context.stroke(Path(ellipseIn: ringRect), with: .color(.white), lineWidth: 1)
            } else {
                // Unselected: filled with lane color
                context.fill(Path(ellipseIn: dotRect), with: .color(color))
            }
        }
    }

    private func drawShapePreview(in context: GraphicsContext, size: CGSize) {
        guard let start = shapeDragStart, let end = shapeDragEnd else { return }
        let startPos = AutomationCoordinateMapping.positionForX(start.x, containerLengthBars: totalBarsDouble, pixelsPerBar: pixelsPerBar)
        let endPos = AutomationCoordinateMapping.positionForX(end.x, containerLengthBars: totalBarsDouble, pixelsPerBar: pixelsPerBar)
        let startVal = AutomationCoordinateMapping.valueForY(start.y, height: height)
        let endVal = AutomationCoordinateMapping.valueForY(end.y, height: height)
        let minPos = min(startPos, endPos)
        let maxPos = max(startPos, endPos)

        let previewBreakpoints = AutomationShapeGenerator.generate(
            tool: selectedTool,
            startPosition: minPos,
            endPosition: maxPos,
            startValue: startPos <= endPos ? startVal : endVal,
            endValue: startPos <= endPos ? endVal : startVal,
            gridSpacing: gridSpacingBars
        )
        guard previewBreakpoints.count >= 2 else { return }

        var path = Path()
        for (i, bp) in previewBreakpoints.enumerated() {
            let x = AutomationCoordinateMapping.xForPosition(bp.position, containerLengthBars: totalBarsDouble, pixelsPerBar: pixelsPerBar)
            let y = AutomationCoordinateMapping.yForValue(bp.value, height: size.height)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(path, with: .color(color.opacity(0.5)), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
    }

    private var clickGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let isCommand = NSEvent.modifierFlags.contains(.command)
                let rawPosition = AutomationCoordinateMapping.positionForX(value.location.x, containerLengthBars: totalBarsDouble, pixelsPerBar: pixelsPerBar)
                let rawVal = AutomationCoordinateMapping.valueForY(value.location.y, height: height)

                if let nearBP = nearestBreakpoint(to: value.location, threshold: 8) {
                    if isCommand {
                        // Cmd+Click: toggle in/out of selection
                        var newSet = selectedBreakpointIDs
                        if newSet.contains(nearBP.id) {
                            newSet.remove(nearBP.id)
                        } else {
                            newSet.insert(nearBP.id)
                        }
                        onSetSelectedBreakpoints?(newSet)
                    } else {
                        // Plain click: select just this breakpoint
                        onSetSelectedBreakpoints?([nearBP.id])
                    }
                    return
                }

                // Click on empty space: clear selection and add new breakpoint
                if !selectedBreakpointIDs.isEmpty {
                    onSetSelectedBreakpoints?([])
                }
                let bp = AutomationBreakpoint(position: snapPosition(rawPosition), value: snapValue(rawVal))
                onAddBreakpoint?(bp)
            }
    }

    private var marqueeDragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if marqueeOrigin == nil {
                    if nearestBreakpoint(to: value.startLocation, threshold: 8) != nil {
                        return
                    }
                    marqueeOrigin = value.startLocation
                }
                marqueeCurrent = value.location
            }
            .onEnded { _ in
                guard let origin = marqueeOrigin, let current = marqueeCurrent else { return }
                let rect = marqueeRect(origin: origin, current: current)
                let isCommand = NSEvent.modifierFlags.contains(.command)

                var marqueeSelection = Set<ID<AutomationBreakpoint>>()
                for bp in lane.breakpoints {
                    let bpX = AutomationCoordinateMapping.xForPosition(bp.position, containerLengthBars: totalBarsDouble, pixelsPerBar: pixelsPerBar)
                    let bpY = AutomationCoordinateMapping.yForValue(bp.value, height: height)
                    if rect.contains(CGPoint(x: bpX, y: bpY)) {
                        marqueeSelection.insert(bp.id)
                    }
                }

                if isCommand {
                    onSetSelectedBreakpoints?(selectedBreakpointIDs.union(marqueeSelection))
                } else {
                    onSetSelectedBreakpoints?(marqueeSelection)
                }

                marqueeOrigin = nil
                marqueeCurrent = nil
            }
    }

    private var shapeDrawGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                shapeDragStart = value.startLocation
                shapeDragEnd = value.location
            }
            .onEnded { value in
                defer {
                    shapeDragStart = nil
                    shapeDragEnd = nil
                }
                let start = value.startLocation
                let end = value.location
                let startPos = AutomationCoordinateMapping.positionForX(start.x, containerLengthBars: totalBarsDouble, pixelsPerBar: pixelsPerBar)
                let endPos = AutomationCoordinateMapping.positionForX(end.x, containerLengthBars: totalBarsDouble, pixelsPerBar: pixelsPerBar)
                let startVal = AutomationCoordinateMapping.valueForY(start.y, height: height)
                let endVal = AutomationCoordinateMapping.valueForY(end.y, height: height)
                let minPos = min(startPos, endPos)
                let maxPos = max(startPos, endPos)
                guard maxPos - minPos > 0.01 else { return }

                let breakpoints = AutomationShapeGenerator.generate(
                    tool: selectedTool,
                    startPosition: minPos,
                    endPosition: maxPos,
                    startValue: startPos <= endPos ? startVal : endVal,
                    endValue: startPos <= endPos ? endVal : startVal,
                    gridSpacing: gridSpacingBars
                )
                guard !breakpoints.isEmpty else { return }
                onReplaceBreakpoints?(minPos, maxPos, breakpoints)
            }
    }

    @ViewBuilder
    private var breakpointDragOverlay: some View {
        ForEach(lane.breakpoints) { bp in
            let x = AutomationCoordinateMapping.xForPosition(bp.position, containerLengthBars: totalBarsDouble, pixelsPerBar: pixelsPerBar)
            let y = AutomationCoordinateMapping.yForValue(bp.value, height: height)
            Circle()
                .fill(Color.clear)
                .frame(width: 16, height: 16)
                .contentShape(Circle())
                .onHover { hovering in
                    hoveredBreakpointID = hovering ? bp.id : nil
                }
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if draggedBreakpointID == nil {
                                draggedBreakpointID = bp.id
                                dragStartPosition = bp.position
                                dragStartValue = bp.value
                                if !selectedBreakpointIDs.contains(bp.id) {
                                    onSetSelectedBreakpoints?([bp.id])
                                }
                            }
                            dragPosition = value.location
                        }
                        .onEnded { value in
                            let rawPosition = AutomationCoordinateMapping.positionForX(value.location.x, containerLengthBars: totalBarsDouble, pixelsPerBar: pixelsPerBar)
                            let rawValue = AutomationCoordinateMapping.valueForY(value.location.y, height: height)
                            let newPosition = snapPosition(rawPosition)
                            let newValue = snapValue(rawValue)
                            let posDelta = newPosition - snapPosition(dragStartPosition ?? bp.position)
                            let valDelta = newValue - snapValue(dragStartValue ?? bp.value)

                            let toMove = lane.breakpoints.filter { selectedBreakpointIDs.contains($0.id) }
                            if toMove.count > 1 {
                                for selectedBP in toMove {
                                    var updated = selectedBP
                                    updated.position = snapPosition(max(0, min(updated.position + posDelta, totalBarsDouble)))
                                    updated.value = snapValue(max(0, min(updated.value + valDelta, 1)))
                                    onUpdateBreakpoint?(updated)
                                }
                            } else {
                                var updated = bp
                                updated.position = newPosition
                                updated.value = newValue
                                onUpdateBreakpoint?(updated)
                            }

                            draggedBreakpointID = nil
                            dragPosition = nil
                            dragStartPosition = nil
                            dragStartValue = nil
                        }
                )
                .position(x: x, y: y)
        }
    }

    private func nearestBreakpoint(to point: CGPoint, threshold: CGFloat) -> AutomationBreakpoint? {
        var closest: AutomationBreakpoint?
        var closestDist = threshold
        for bp in lane.breakpoints {
            let bpX = AutomationCoordinateMapping.xForPosition(bp.position, containerLengthBars: totalBarsDouble, pixelsPerBar: pixelsPerBar)
            let bpY = AutomationCoordinateMapping.yForValue(bp.value, height: height)
            let dist = hypot(point.x - bpX, point.y - bpY)
            if dist < closestDist {
                closestDist = dist
                closest = bp
            }
        }
        return closest
    }

    private func marqueeRect(origin: CGPoint, current: CGPoint) -> CGRect {
        let minX = min(origin.x, current.x)
        let minY = min(origin.y, current.y)
        let maxX = max(origin.x, current.x)
        let maxY = max(origin.y, current.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
