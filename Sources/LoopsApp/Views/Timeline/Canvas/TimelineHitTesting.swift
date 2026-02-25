import AppKit
import LoopsCore

// MARK: - Hit Test Result

/// Result of a hit test on the timeline canvas.
/// Identifies what the cursor is over and which gesture zone applies.
enum TimelineHitResult: Equatable {
    /// Click in the ruler area (bar numbers).
    case ruler

    /// Click on a section band.
    case section(sectionID: ID<SectionRegion>)

    /// Click on empty section lane background (no section).
    case sectionBackground

    /// Empty track area (no container).
    case trackBackground(trackID: ID<Track>)

    /// A container, with the specific Smart Tool zone.
    case container(containerID: ID<Container>, trackID: ID<Track>, zone: ContainerZone)

    /// Empty space below all tracks.
    case emptyArea

    /// Specific zone within a container (matches Pro Tools Smart Tool).
    enum ContainerZone: Equatable {
        case fadeLeft
        case fadeRight
        case resizeLeft
        case resizeRight
        case trimLeft
        case trimRight
        case move
        case selector
    }
}

// MARK: - Hit Testing

extension TimelineCanvasView {

    /// Edge threshold in points for zone detection.
    static let edgeThreshold: CGFloat = 12

    /// Performs hit testing at the given point in the canvas coordinate system.
    /// Returns what's under the cursor and the applicable gesture zone.
    func hitTest(at point: NSPoint) -> TimelineHitResult {
        if showRulerAndSections {
            // Check ruler area
            if point.y < Self.rulerHeight {
                return .ruler
            }

            // Check section lane area
            if point.y < Self.trackAreaTop {
                // Check individual section bands
                for sl in sectionLayouts.reversed() {
                    if sl.rect.contains(point) {
                        return .section(sectionID: sl.section.id)
                    }
                }
                return .sectionBackground
            }
        }

        // Check containers (in reverse draw order — topmost first)
        for trackLayout in trackLayouts.reversed() {
            for cl in trackLayout.containers.reversed() {
                if cl.rect.contains(point) {
                    let zone = detectZone(point: point, containerRect: cl.rect)
                    return .container(
                        containerID: cl.container.id,
                        trackID: trackLayout.track.id,
                        zone: zone
                    )
                }
            }

            // Point is in this track's Y band but not over a container
            let trackRect = NSRect(
                x: 0,
                y: trackLayout.yOrigin,
                width: bounds.width,
                height: trackLayout.height
            )
            if trackRect.contains(point) {
                return .trackBackground(trackID: trackLayout.track.id)
            }
        }

        return .emptyArea
    }

    /// Detects the Smart Tool zone based on cursor position within a container rect.
    ///
    /// Layout (3×3 grid):
    /// ```
    ///  ┌──────────┬──────────────────┬──────────┐
    ///  │ fadeLeft  │    selector      │ fadeRight │  top third
    ///  ├──────────┼──────────────────┼──────────┤
    ///  │ resizeL  │      move        │ resizeR  │  middle third
    ///  ├──────────┼──────────────────┼──────────┤
    ///  │ trimLeft │    (move)        │ trimRight│  bottom third
    ///  └──────────┴──────────────────┴──────────┘
    /// ```
    private func detectZone(point: NSPoint, containerRect: NSRect) -> TimelineHitResult.ContainerZone {
        let localX = point.x - containerRect.minX
        let localY = point.y - containerRect.minY
        let width = containerRect.width
        let height = containerRect.height
        let edge = Self.edgeThreshold

        let isLeftEdge = localX < edge
        let isRightEdge = localX > width - edge
        let relativeY = localY / height

        if relativeY < 1.0 / 3.0 {
            // Top third
            if isLeftEdge { return .fadeLeft }
            if isRightEdge { return .fadeRight }
            return .selector
        } else if relativeY < 2.0 / 3.0 {
            // Middle third
            if isLeftEdge { return .resizeLeft }
            if isRightEdge { return .resizeRight }
            return .move
        } else {
            // Bottom third
            if isLeftEdge { return .trimLeft }
            if isRightEdge { return .trimRight }
            return .move
        }
    }

    /// Returns the rects that would need to be invalidated when moving a container
    /// from one bar position to another. Used for dirty-rect optimization.
    func rectsToInvalidateForMove(
        containerID: ID<Container>,
        fromBar: Double,
        toBar: Double,
        trackID: ID<Track>
    ) -> [NSRect] {
        guard let trackLayout = trackLayouts.first(where: { $0.track.id == trackID }),
              let cl = trackLayout.containers.first(where: { $0.container.id == containerID }) else {
            return []
        }

        let oldRect = cl.rect
        let deltaX = CGFloat(toBar - fromBar) * pixelsPerBar
        let newRect = oldRect.offsetBy(dx: deltaX, dy: 0)

        // Inflate slightly to cover borders and shadows
        let padding: CGFloat = 4
        return [
            oldRect.insetBy(dx: -padding, dy: -padding),
            newRect.insetBy(dx: -padding, dy: -padding)
        ]
    }
}
