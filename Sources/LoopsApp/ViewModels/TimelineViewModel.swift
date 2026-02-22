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

    /// Minimum pixels per bar (fully zoomed out).
    public static let minPixelsPerBar: CGFloat = 30.0

    /// Maximum pixels per bar (fully zoomed in).
    public static let maxPixelsPerBar: CGFloat = 500.0

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

    /// Snaps a bar position to the nearest bar or beat boundary depending on zoom level.
    /// At low zoom (pixelsPerBar < beatSnapThreshold), snaps to whole bars.
    /// At high zoom, snaps to the nearest beat within the bar.
    public func snappedBar(forXPosition x: CGFloat, timeSignature: TimeSignature) -> Double {
        let rawBar = bar(forXPosition: max(x, 0))
        let ppBeat = pixelsPerBar / CGFloat(timeSignature.beatsPerBar)
        // Snap to beat when each beat is at least 40 pixels wide
        if ppBeat >= 40.0 {
            let beatsPerBar = Double(timeSignature.beatsPerBar)
            let totalBeats = (rawBar - 1.0) * beatsPerBar
            let snappedBeats = (totalBeats).rounded()
            return max((snappedBeats / beatsPerBar) + 1.0, 1.0)
        } else {
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
    }

    /// Zooms out by one step.
    public func zoomOut() {
        pixelsPerBar = max(pixelsPerBar / Self.zoomFactor, Self.minPixelsPerBar)
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

    /// Returns the total height for a track including automation sub-lanes.
    public func trackHeight(for track: Track, baseHeight: CGFloat) -> CGFloat {
        guard automationExpanded.contains(track.id) else { return baseHeight }
        let laneCount = automationLaneCount(for: track)
        guard laneCount > 0 else { return baseHeight }
        return baseHeight + CGFloat(laneCount) * Self.automationSubLaneHeight
    }

    /// Expands the timeline's total bars if the given bar exceeds the current range.
    public func ensureBarVisible(_ bar: Int) {
        if bar > totalBars {
            totalBars = bar + 8
        }
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
