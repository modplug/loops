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

    /// Current playhead position in bars (1-based).
    public var playheadBar: Double = 1.0

    /// Number of bars visible in the timeline.
    public var totalBars: Int = 64

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
}
