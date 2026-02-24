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
                    selectedBreakpointID: selectedBreakpointID,
                    onAddBreakpoint: { breakpoint in
                        onAddTrackBreakpoint?(lane.id, breakpoint)
                    },
                    onUpdateBreakpoint: { breakpoint in
                        onUpdateTrackBreakpoint?(lane.id, breakpoint)
                    },
                    onDeleteBreakpoint: { breakpointID in
                        onDeleteTrackBreakpoint?(lane.id, breakpointID)
                    },
                    onSelectBreakpoint: onSelectBreakpoint,
                    snapResolution: snapResolution,
                    timeSignature: timeSignature
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
                            selectedBreakpointID: selectedBreakpointID,
                            onAddBreakpoint: { breakpoint in
                                onAddBreakpoint?(container.id, lane.id, breakpoint)
                            },
                            onUpdateBreakpoint: { breakpoint in
                                onUpdateBreakpoint?(container.id, lane.id, breakpoint)
                            },
                            onDeleteBreakpoint: { breakpointID in
                                onDeleteBreakpoint?(container.id, lane.id, breakpointID)
                            },
                            onSelectBreakpoint: onSelectBreakpoint,
                            snapResolution: snapResolution,
                            timeSignature: timeSignature
                        )
                        .offset(x: CGFloat(container.startBar - 1) * pixelsPerBar)
                    }
                }
            }
        }
        .frame(width: CGFloat(totalBars) * pixelsPerBar, height: height)
    }
}

/// Renders one container's automation curve in a sub-lane with full interaction support.
private struct AutomationSubLaneContainerView: View {
    let container: Container
    let lane: AutomationLane
    let laneColorIndex: Int
    let pixelsPerBar: CGFloat
    let height: CGFloat
    let selectedBreakpointID: ID<AutomationBreakpoint>?
    var onAddBreakpoint: ((_ breakpoint: AutomationBreakpoint) -> Void)?
    var onUpdateBreakpoint: ((_ breakpoint: AutomationBreakpoint) -> Void)?
    var onDeleteBreakpoint: ((_ breakpointID: ID<AutomationBreakpoint>) -> Void)?
    var onSelectBreakpoint: ((_ breakpointID: ID<AutomationBreakpoint>?) -> Void)?
    var snapResolution: SnapResolution?
    var timeSignature: TimeSignature?

    @State private var hoveredBreakpointID: ID<AutomationBreakpoint>?
    @State private var draggedBreakpointID: ID<AutomationBreakpoint>?
    @State private var dragPosition: CGPoint?

    private var containerWidth: CGFloat {
        CGFloat(container.lengthBars) * pixelsPerBar
    }

    private var color: Color {
        AutomationColors.color(at: laneColorIndex)
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
            }
            .frame(width: containerWidth, height: height)

            // Tooltip overlay for hovered/dragged breakpoint
            if let tooltipBP = tooltipBreakpoint {
                let x = AutomationCoordinateMapping.xForPosition(tooltipBP.position, containerLengthBars: container.lengthBars, pixelsPerBar: pixelsPerBar)
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

            // Invisible interaction layer for breakpoint dragging and click-to-add
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: containerWidth, height: height)
                .gesture(clickGesture)
                .overlay(breakpointDragOverlay)
        }
        .frame(width: containerWidth, height: height)
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

    /// Snaps a normalized value (0–1) if snap is active.
    private func snapValue(_ value: Float) -> Float {
        guard shouldSnap else { return value }
        return AutomationCoordinateMapping.snappedValue(value, parameterMin: lane.parameterMin, parameterMax: lane.parameterMax, parameterUnit: lane.parameterUnit)
    }

    private var tooltipBreakpoint: AutomationBreakpoint? {
        if let dragID = draggedBreakpointID, let pos = dragPosition {
            let rawValue = AutomationCoordinateMapping.valueForY(pos.y, height: height)
            let rawPosition = AutomationCoordinateMapping.positionForX(pos.x, containerLengthBars: container.lengthBars, pixelsPerBar: pixelsPerBar)
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
            let barPosition = Double(step) / Double(resolution) * Double(container.lengthBars)
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
        for bp in lane.breakpoints {
            let x = AutomationCoordinateMapping.xForPosition(bp.position, containerLengthBars: container.lengthBars, pixelsPerBar: pixelsPerBar)
            let y = AutomationCoordinateMapping.yForValue(bp.value, height: size.height)
            let isSelected = bp.id == selectedBreakpointID
            let isDragged = bp.id == draggedBreakpointID
            let radius: CGFloat = isSelected || isDragged ? 5 : 4

            let dotRect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: dotRect), with: .color(color))
            if isSelected {
                let ringRect = CGRect(x: x - radius - 1, y: y - radius - 1, width: (radius + 1) * 2, height: (radius + 1) * 2)
                context.stroke(Path(ellipseIn: ringRect), with: .color(.white), lineWidth: 1)
            }
        }
    }

    // MARK: - Interaction

    private var clickGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let rawPosition = AutomationCoordinateMapping.positionForX(value.location.x, containerLengthBars: container.lengthBars, pixelsPerBar: pixelsPerBar)
                let rawVal = AutomationCoordinateMapping.valueForY(value.location.y, height: height)

                // Check if click is near an existing breakpoint
                if let nearBP = nearestBreakpoint(to: value.location, threshold: 8) {
                    onSelectBreakpoint?(nearBP.id)
                    return
                }

                // Add new breakpoint at click position (snapped)
                let bp = AutomationBreakpoint(position: snapPosition(rawPosition), value: snapValue(rawVal))
                onAddBreakpoint?(bp)
            }
    }

    private var breakpointDragOverlay: some View {
        ForEach(lane.breakpoints) { bp in
            let x = AutomationCoordinateMapping.xForPosition(bp.position, containerLengthBars: container.lengthBars, pixelsPerBar: pixelsPerBar)
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
                            draggedBreakpointID = bp.id
                            onSelectBreakpoint?(bp.id)
                            dragPosition = value.location
                        }
                        .onEnded { value in
                            let rawPosition = AutomationCoordinateMapping.positionForX(value.location.x, containerLengthBars: container.lengthBars, pixelsPerBar: pixelsPerBar)
                            let rawValue = AutomationCoordinateMapping.valueForY(value.location.y, height: height)
                            var updated = bp
                            updated.position = snapPosition(rawPosition)
                            updated.value = snapValue(rawValue)
                            onUpdateBreakpoint?(updated)
                            draggedBreakpointID = nil
                            dragPosition = nil
                        }
                )
                .position(x: x, y: y)
        }
    }

    private func nearestBreakpoint(to point: CGPoint, threshold: CGFloat) -> AutomationBreakpoint? {
        var closest: AutomationBreakpoint?
        var closestDist = threshold
        for bp in lane.breakpoints {
            let bpX = AutomationCoordinateMapping.xForPosition(bp.position, containerLengthBars: container.lengthBars, pixelsPerBar: pixelsPerBar)
            let bpY = AutomationCoordinateMapping.yForValue(bp.value, height: height)
            let dist = hypot(point.x - bpX, point.y - bpY)
            if dist < closestDist {
                closestDist = dist
                closest = bp
            }
        }
        return closest
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
    let selectedBreakpointID: ID<AutomationBreakpoint>?
    var onAddBreakpoint: ((_ breakpoint: AutomationBreakpoint) -> Void)?
    var onUpdateBreakpoint: ((_ breakpoint: AutomationBreakpoint) -> Void)?
    var onDeleteBreakpoint: ((_ breakpointID: ID<AutomationBreakpoint>) -> Void)?
    var onSelectBreakpoint: ((_ breakpointID: ID<AutomationBreakpoint>?) -> Void)?
    var snapResolution: SnapResolution?
    var timeSignature: TimeSignature?

    @State private var hoveredBreakpointID: ID<AutomationBreakpoint>?
    @State private var draggedBreakpointID: ID<AutomationBreakpoint>?
    @State private var dragPosition: CGPoint?

    private var totalWidth: CGFloat {
        CGFloat(totalBars) * pixelsPerBar
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

    /// Snaps a normalized value (0–1) if snap is active.
    private func snapValue(_ value: Float) -> Float {
        guard shouldSnap else { return value }
        return AutomationCoordinateMapping.snappedValue(value, parameterMin: lane.parameterMin, parameterMax: lane.parameterMax, parameterUnit: lane.parameterUnit)
    }

    var body: some View {
        ZStack {
            // Curve + breakpoints
            Canvas { context, size in
                drawCurve(in: context, size: size)
                drawBreakpoints(in: context, size: size)
            }
            .frame(width: totalWidth, height: height)

            // Tooltip overlay for hovered/dragged breakpoint
            if let tooltipBP = tooltipBreakpoint {
                let x = AutomationCoordinateMapping.xForPosition(tooltipBP.position, containerLengthBars: Double(totalBars), pixelsPerBar: pixelsPerBar)
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

            // Invisible interaction layer
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: totalWidth, height: height)
                .gesture(clickGesture)
                .overlay(breakpointDragOverlay)
        }
        .frame(width: totalWidth, height: height)
    }

    private var tooltipBreakpoint: AutomationBreakpoint? {
        if let dragID = draggedBreakpointID, let pos = dragPosition {
            let rawValue = AutomationCoordinateMapping.valueForY(pos.y, height: height)
            let rawPosition = AutomationCoordinateMapping.positionForX(pos.x, containerLengthBars: Double(totalBars), pixelsPerBar: pixelsPerBar)
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
            let barPosition = Double(step) / Double(resolution) * Double(totalBars)
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
        for bp in lane.breakpoints {
            let x = AutomationCoordinateMapping.xForPosition(bp.position, containerLengthBars: Double(totalBars), pixelsPerBar: pixelsPerBar)
            let y = AutomationCoordinateMapping.yForValue(bp.value, height: size.height)
            let isSelected = bp.id == selectedBreakpointID
            let isDragged = bp.id == draggedBreakpointID
            let radius: CGFloat = isSelected || isDragged ? 5 : 4

            let dotRect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: dotRect), with: .color(color))
            if isSelected {
                let ringRect = CGRect(x: x - radius - 1, y: y - radius - 1, width: (radius + 1) * 2, height: (radius + 1) * 2)
                context.stroke(Path(ellipseIn: ringRect), with: .color(.white), lineWidth: 1)
            }
        }
    }

    private var clickGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let rawPosition = AutomationCoordinateMapping.positionForX(value.location.x, containerLengthBars: Double(totalBars), pixelsPerBar: pixelsPerBar)
                let rawVal = AutomationCoordinateMapping.valueForY(value.location.y, height: height)

                if let nearBP = nearestBreakpoint(to: value.location, threshold: 8) {
                    onSelectBreakpoint?(nearBP.id)
                    return
                }

                let bp = AutomationBreakpoint(position: snapPosition(rawPosition), value: snapValue(rawVal))
                onAddBreakpoint?(bp)
            }
    }

    private var breakpointDragOverlay: some View {
        ForEach(lane.breakpoints) { bp in
            let x = AutomationCoordinateMapping.xForPosition(bp.position, containerLengthBars: Double(totalBars), pixelsPerBar: pixelsPerBar)
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
                            draggedBreakpointID = bp.id
                            onSelectBreakpoint?(bp.id)
                            dragPosition = value.location
                        }
                        .onEnded { value in
                            let rawPosition = AutomationCoordinateMapping.positionForX(value.location.x, containerLengthBars: Double(totalBars), pixelsPerBar: pixelsPerBar)
                            let rawValue = AutomationCoordinateMapping.valueForY(value.location.y, height: height)
                            var updated = bp
                            updated.position = snapPosition(rawPosition)
                            updated.value = snapValue(rawValue)
                            onUpdateBreakpoint?(updated)
                            draggedBreakpointID = nil
                            dragPosition = nil
                        }
                )
                .position(x: x, y: y)
        }
    }

    private func nearestBreakpoint(to point: CGPoint, threshold: CGFloat) -> AutomationBreakpoint? {
        var closest: AutomationBreakpoint?
        var closestDist = threshold
        for bp in lane.breakpoints {
            let bpX = AutomationCoordinateMapping.xForPosition(bp.position, containerLengthBars: Double(totalBars), pixelsPerBar: pixelsPerBar)
            let bpY = AutomationCoordinateMapping.yForValue(bp.value, height: height)
            let dist = hypot(point.x - bpX, point.y - bpY)
            if dist < closestDist {
                closestDist = dist
                closest = bp
            }
        }
        return closest
    }
}
