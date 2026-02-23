import SwiftUI
import LoopsCore

/// Manages timeline display state: zoom, scroll offset, and pixel calculations.
@Observable
@MainActor
public final class TimelineViewModel {
    /// Pixels per bar at the current zoom level.
    public var pixelsPerBar: CGFloat = 120.0

    /// Horizontal scroll offset in points.
    public var scrollOffset: CGPoint = .zero

    /// Tracks with automation sub-lanes expanded.
    public var automationExpanded: Set<ID<Track>> = []

    /// Per-track custom row heights. Tracks not in this dictionary use the default height.
    public var trackHeights: [ID<Track>: CGFloat] = [:]

    /// Width of the track header column in points.
    public var trackHeaderWidth: CGFloat = 160

    /// Default track row height.
    public static let defaultTrackHeight: CGFloat = 80

    /// Minimum track row height.
    public static let minimumTrackHeight: CGFloat = 40

    /// Height of each automation sub-lane row.
    public static let automationSubLaneHeight: CGFloat = 40

    /// Current playhead position in bars (1-based).
    public var playheadBar: Double = 1.0

    /// Number of bars visible in the timeline.
    public var totalBars: Int = 64

    /// Selected bar range from ruler drag (transient, not persisted). 1-based, inclusive.
    public var selectedRange: ClosedRange<Int>?

    /// Tracks selected for range copy filtering. Empty means all tracks included.
    public var selectedTrackIDs: Set<ID<Track>> = []

    /// Cursor x-coordinate in timeline space. nil when mouse is outside the timeline.
    public var cursorX: CGFloat?

    /// Cursor position in bars (1-based), derived from cursorX.
    public var cursorBar: Double? {
        guard let x = cursorX else { return nil }
        return bar(forXPosition: x)
    }

    /// Default track header column width.
    public static let defaultHeaderWidth: CGFloat = 160

    /// Minimum track header column width.
    public static let minHeaderWidth: CGFloat = 100

    /// Maximum track header column width.
    public static let maxHeaderWidth: CGFloat = 400

    /// Minimum pixels per bar (fully zoomed out).
    public static let minPixelsPerBar: CGFloat = 8.0

    /// Maximum pixels per bar (fully zoomed in).
    /// 2400 ppb @ 4/4 = 600 px/beat = ~150 px per sixteenth note for drum transient editing.
    public static let maxPixelsPerBar: CGFloat = 2400.0

    /// Zoom step multiplier for each zoom in/out action.
    private static let zoomFactor: CGFloat = 1.3

    public init() {}

    /// Total timeline width in points.
    public var totalWidth: CGFloat {
        CGFloat(totalBars) * pixelsPerBar
    }

    /// Pixels per beat given a time signature.
    public func pixelsPerBeat(timeSignature: TimeSignature) -> CGFloat {
        pixelsPerBar / CGFloat(timeSignature.beatsPerBar)
    }

    /// Converts a bar position (1-based) to an x-coordinate.
    public func xPosition(forBar bar: Double) -> CGFloat {
        CGFloat(bar - 1.0) * pixelsPerBar
    }

    /// Converts an x-coordinate to a bar position (1-based).
    public func bar(forXPosition x: CGFloat) -> Double {
        (Double(x) / Double(pixelsPerBar)) + 1.0
    }

    /// Snaps a bar position to the nearest grid boundary depending on zoom level.
    /// Multi-level snapping: 1/32 → 1/16 → beat → whole bar as zoom decreases.
    public func snappedBar(forXPosition x: CGFloat, timeSignature: TimeSignature) -> Double {
        let rawBar = bar(forXPosition: max(x, 0))
        let ppBeat = pixelsPerBar / CGFloat(timeSignature.beatsPerBar)
        let beatsPerBar = Double(timeSignature.beatsPerBar)

        if ppBeat >= 150.0 {
            // Snap to 1/32 notes (8 subdivisions per beat)
            let totalSubdivisions = (rawBar - 1.0) * beatsPerBar * 8.0
            let snapped = totalSubdivisions.rounded()
            return max((snapped / (beatsPerBar * 8.0)) + 1.0, 1.0)
        } else if ppBeat >= 80.0 {
            // Snap to 1/16 notes (4 subdivisions per beat)
            let totalSubdivisions = (rawBar - 1.0) * beatsPerBar * 4.0
            let snapped = totalSubdivisions.rounded()
            return max((snapped / (beatsPerBar * 4.0)) + 1.0, 1.0)
        } else if ppBeat >= 40.0 {
            // Snap to beats
            let totalBeats = (rawBar - 1.0) * beatsPerBar
            let snappedBeats = totalBeats.rounded()
            return max((snappedBeats / beatsPerBar) + 1.0, 1.0)
        } else {
            // Snap to whole bars
            return max(rawBar.rounded(), 1.0)
        }
    }

    /// Current playhead x-coordinate.
    public var playheadX: CGFloat {
        xPosition(forBar: playheadBar)
    }

    /// Zooms in by one step.
    public func zoomIn() {
        pixelsPerBar = min(pixelsPerBar * Self.zoomFactor, Self.maxPixelsPerBar)
        recalculateTotalBars()
    }

    /// Zooms out by one step.
    public func zoomOut() {
        pixelsPerBar = max(pixelsPerBar / Self.zoomFactor, Self.minPixelsPerBar)
        recalculateTotalBars()
    }

    /// Zooms in/out around a specific timeline X position.
    /// Returns the scroll offset delta needed to keep that position visually stable.
    @discardableResult
    public func zoomAround(timelineX: CGFloat, zoomIn: Bool) -> CGFloat {
        let barUnderCursor = bar(forXPosition: timelineX)
        let oldPPB = pixelsPerBar
        if zoomIn {
            pixelsPerBar = min(pixelsPerBar * Self.zoomFactor, Self.maxPixelsPerBar)
        } else {
            pixelsPerBar = max(pixelsPerBar / Self.zoomFactor, Self.minPixelsPerBar)
        }
        recalculateTotalBars()
        let newX = xPosition(forBar: barUnderCursor)
        let oldX = CGFloat(barUnderCursor - 1.0) * oldPPB
        return newX - oldX
    }

    /// Sets the track header column width, clamped to min/max bounds.
    public func setTrackHeaderWidth(_ width: CGFloat) {
        trackHeaderWidth = min(max(width, Self.minHeaderWidth), Self.maxHeaderWidth)
    }

    /// Toggles a track's selection for range copy filtering.
    public func toggleTrackSelection(trackID: ID<Track>) {
        if selectedTrackIDs.contains(trackID) {
            selectedTrackIDs.remove(trackID)
        } else {
            selectedTrackIDs.insert(trackID)
        }
    }

    /// Clears the selected range.
    public func clearSelectedRange() {
        selectedRange = nil
    }

    /// Toggles automation sub-lane expansion for a track.
    public func toggleAutomationExpanded(trackID: ID<Track>) {
        if automationExpanded.contains(trackID) {
            automationExpanded.remove(trackID)
        } else {
            automationExpanded.insert(trackID)
        }
    }

    /// Returns the base row height for a track (custom or default).
    public func baseTrackHeight(for trackID: ID<Track>) -> CGFloat {
        trackHeights[trackID] ?? Self.defaultTrackHeight
    }

    /// Sets a custom height for a track, clamped to the minimum.
    public func setTrackHeight(_ height: CGFloat, for trackID: ID<Track>) {
        trackHeights[trackID] = max(height, Self.minimumTrackHeight)
    }

    /// Resets a track's height to the default.
    public func resetTrackHeight(for trackID: ID<Track>) {
        trackHeights.removeValue(forKey: trackID)
    }

    /// Returns the total height for a track including automation sub-lanes.
    public func trackHeight(for track: Track, baseHeight: CGFloat) -> CGFloat {
        guard automationExpanded.contains(track.id) else { return baseHeight }
        let laneCount = automationLaneCount(for: track)
        guard laneCount > 0 else { return baseHeight }
        return baseHeight + CGFloat(laneCount) * Self.automationSubLaneHeight
    }

    /// Minimum number of bars shown in the timeline.
    public static let minimumTotalBars: Int = 64

    /// Extra bars of padding shown after the last container.
    private static let barPadding: Int = 16

    /// Visible viewport width in points (set by the timeline's container view).
    public var viewportWidth: CGFloat = 0

    /// Furthest bar with content.
    private var contentEndBar: Int = 0

    /// Expands the timeline's total bars if the given bar exceeds the current range.
    public func ensureBarVisible(_ bar: Int) {
        if bar > totalBars {
            totalBars = bar + 8
        }
    }

    /// Updates the content extent from the given tracks and recalculates totalBars.
    public func updateTotalBars(for tracks: [Track]) {
        contentEndBar = tracks.flatMap(\.containers).map(\.endBar).max() ?? 0
        recalculateTotalBars()
    }

    /// Sets the visible viewport width and recalculates totalBars.
    public func setViewportWidth(_ width: CGFloat) {
        guard abs(viewportWidth - width) > 1 else { return }
        viewportWidth = width
        recalculateTotalBars()
    }

    /// Recalculates totalBars from content extent, viewport size, and minimum.
    private func recalculateTotalBars() {
        let viewportBars = viewportWidth > 0
            ? Int(ceil(viewportWidth / pixelsPerBar)) + Self.barPadding
            : 0
        totalBars = max(contentEndBar + Self.barPadding, viewportBars, Self.minimumTotalBars)
    }

    /// Returns the number of unique automation lanes across all containers and track-level automation.
    public func automationLaneCount(for track: Track) -> Int {
        var paths = Set<EffectPath>()
        for lane in track.trackAutomationLanes {
            paths.insert(lane.targetPath)
        }
        for container in track.containers {
            for lane in container.automationLanes {
                paths.insert(lane.targetPath)
            }
        }
        return paths.count
    }
}
