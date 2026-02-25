import SwiftUI
import QuartzCore
import LoopsCore

/// Groups viewport-related visible range that changes during scroll.
/// Stored separately from pixelsPerBar so scroll-only changes don't trigger
/// re-evaluation of views that only read pixelsPerBar (e.g. TimelineView).
public struct VisibleRange: Equatable, Sendable {
    public var xMin: CGFloat
    public var xMax: CGFloat

    public init(
        xMin: CGFloat = 0,
        xMax: CGFloat = .greatestFiniteMagnitude
    ) {
        self.xMin = xMin
        self.xMax = xMax
    }
}

/// Manages timeline display state: zoom, scroll offset, and pixel calculations.
@Observable
@MainActor
public final class TimelineViewModel {
    /// Pixels per bar at the current zoom level.
    /// Separate stored property so that scroll-only visible range changes
    /// don't trigger re-evaluation of views that read pixelsPerBar.
    public var pixelsPerBar: CGFloat = 120.0

    /// Visible+buffered X range in timeline coordinates.
    /// Separate from pixelsPerBar so scroll updates don't invalidate zoom-dependent views.
    public var visibleRange = VisibleRange()

    /// Left edge of the visible+buffered X range in timeline coordinates.
    public var visibleXMin: CGFloat {
        get { visibleRange.xMin }
        set { visibleRange.xMin = newValue }
    }

    /// Right edge of the visible+buffered X range in timeline coordinates.
    public var visibleXMax: CGFloat {
        get { visibleRange.xMax }
        set { visibleRange.xMax = newValue }
    }

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

    /// Height of the automation toolbar row.
    public static let automationToolbarHeight: CGFloat = 26

    /// Currently selected automation shape tool.
    public var selectedAutomationTool: AutomationTool = .pointer

    /// Current playhead position in bars (1-based).
    public var playheadBar: Double = 1.0

    /// Number of bars in the timeline (computed from content extent, viewport, and minimum).
    /// Derived — does not fire a separate @Observable notification during zoom.
    public var totalBars: Int {
        let viewportBars = viewportWidth > 0
            ? Int(ceil(viewportWidth / pixelsPerBar)) + Self.barPadding
            : 0
        return max(contentEndBar + Self.barPadding, viewportBars, Self.minimumTotalBars, manualMinBars)
    }

    /// Selected bar range from ruler drag (transient, not persisted). 1-based, inclusive.
    public var selectedRange: ClosedRange<Int>?

    /// Tracks selected for range copy filtering. Empty means all tracks included.
    public var selectedTrackIDs: Set<ID<Track>> = []

    /// Cursor x-coordinate in timeline space. nil when mouse is outside the timeline.
    public var cursorX: CGFloat?

    /// Whether snap-to-grid is enabled (toggled via toolbar).
    public var isSnapEnabled: Bool = true

    /// Grid mode: adaptive (zoom-dependent) or fixed resolution.
    public var gridMode: GridMode = .adaptive

    /// Feature flag: use high-performance NSView canvas instead of SwiftUI timeline.
    public var useNSViewTimeline: Bool = true

    /// Feature flag: use Metal GPU rendering instead of CoreGraphics.
    /// Only takes effect when `useNSViewTimeline` is also true.
    public var useMetalTimeline: Bool = true

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

    /// Absolute minimum pixels per bar (hard floor, no content).
    public static let absoluteMinPixelsPerBar: CGFloat = 8.0

    /// Minimum pixels per bar (fully zoomed out).
    /// Content-aware: ensures the entire project fits in the viewport with some padding,
    /// preventing an infinite grid of tiny unusable lines (like Bitwig's max zoom out).
    public var minPixelsPerBar: CGFloat {
        guard viewportWidth > 0 else { return Self.absoluteMinPixelsPerBar }
        let contentBars = CGFloat(max(contentEndBar + Self.barPadding, Self.minimumTotalBars))
        // At max zoom out, all content should fit in the viewport
        let contentFit = viewportWidth / contentBars
        return max(contentFit, Self.absoluteMinPixelsPerBar)
    }

    /// Maximum pixels per bar (fully zoomed in).
    /// 9600 ppb @ 4/4 = 2400 px/beat = ~600 px per sixteenth note for sample-level editing.
    public static let maxPixelsPerBar: CGFloat = 9600.0

    /// Zoom step multiplier for each zoom in/out action.
    private static let zoomFactor: CGFloat = 1.3

    /// Minimum interval between zoom operations (one per display frame at 60fps).
    private static let zoomThrottleInterval: CFTimeInterval = 1.0 / 60.0

    /// Timestamp of the last applied zoom operation.
    private var lastZoomTime: CFTimeInterval = 0

    /// Extra points rendered beyond the viewport on each side.
    public static let viewportBuffer: CGFloat = 500

    public init() {}

    /// Updates the visible X range unconditionally (no dead zone).
    /// Use during zoom so the range is correct in the same @Observable transaction as pixelsPerBar.
    public func forceUpdateVisibleXRange(scrollOffsetX: CGFloat, viewportWidth: CGFloat) {
        visibleRange = VisibleRange(
            xMin: scrollOffsetX - Self.viewportBuffer,
            xMax: scrollOffsetX + viewportWidth + Self.viewportBuffer
        )
    }

    /// Updates the visible X range from scroll position and viewport width.
    /// Called by the scroll synchronizer when scroll offset changes.
    public func updateVisibleXRange(scrollOffsetX: CGFloat, viewportWidth: CGFloat) {
        let newMin = scrollOffsetX - Self.viewportBuffer
        let newMax = scrollOffsetX + viewportWidth + Self.viewportBuffer
        // Only update if the change is significant (>50pt) to avoid excessive invalidation.
        // 50pt threshold absorbs scrollbar-induced viewport width oscillation (~17pt)
        // and minor scroll adjustments. The 500pt buffer ensures this doesn't cause pop-in.
        if abs(visibleRange.xMin - newMin) > 50 || abs(visibleRange.xMax - newMax) > 50 {
            visibleRange = VisibleRange(xMin: newMin, xMax: newMax)
        }
    }

    /// Total timeline width in points.
    public var totalWidth: CGFloat {
        CGFloat(totalBars) * pixelsPerBar
    }

    /// Frame width quantized to 4096-point boundaries. Changes only when totalWidth
    /// crosses a boundary, so views that read this for `.frame(width:)` avoid
    /// body re-evaluation on every zoom step.
    public private(set) var quantizedFrameWidth: CGFloat = 4096

    private static let frameWidthQuantum: CGFloat = 4096

    /// Call after any pixelsPerBar change to update the quantized frame width.
    /// Only fires an @Observable notification when the quantized value actually changes.
    private func syncQuantizedFrameWidth() {
        let newWidth = ceil(totalWidth / Self.frameWidthQuantum) * Self.frameWidthQuantum
        if newWidth != quantizedFrameWidth {
            quantizedFrameWidth = newWidth
        }
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

    /// Returns the effective snap resolution based on grid mode and zoom level.
    public func effectiveSnapResolution(timeSignature: TimeSignature) -> SnapResolution {
        switch gridMode {
        case .fixed(let res):
            return res
        case .adaptive:
            let ppBeat = pixelsPerBar / CGFloat(timeSignature.beatsPerBar)
            if ppBeat >= 150.0 { return .thirtySecond }
            if ppBeat >= 80.0 { return .sixteenth }
            if ppBeat >= 40.0 { return .quarter }
            return .whole
        }
    }

    /// Snaps a bar position to the nearest grid boundary.
    /// When `invertSnap` is true, the snap behavior is inverted (e.g., Cmd held).
    public func snappedBar(forXPosition x: CGFloat, timeSignature: TimeSignature, invertSnap: Bool = false) -> Double {
        let rawBar = bar(forXPosition: max(x, 0))
        let shouldSnap = invertSnap ? !isSnapEnabled : isSnapEnabled
        guard shouldSnap else { return max(rawBar, 1.0) }
        return forceSnapToGrid(rawBar, timeSignature: timeSignature)
    }

    /// Snaps a bar value to the current grid resolution (respects `isSnapEnabled`).
    public func snapToGrid(_ value: Double, timeSignature: TimeSignature) -> Double {
        guard isSnapEnabled else { return value }
        return forceSnapToGrid(value, timeSignature: timeSignature)
    }

    /// Snaps a bar value to the current grid resolution (always snaps, ignores `isSnapEnabled`).
    private func forceSnapToGrid(_ value: Double, timeSignature: TimeSignature) -> Double {
        let resolution = effectiveSnapResolution(timeSignature: timeSignature)
        let beatsPerBar = Double(timeSignature.beatsPerBar)
        let totalBeats = (value - 1.0) * beatsPerBar
        let snappedBeats = resolution.snap(totalBeats)
        return max((snappedBeats / beatsPerBar) + 1.0, 1.0)
    }

    /// Current playhead x-coordinate.
    public var playheadX: CGFloat {
        xPosition(forBar: playheadBar)
    }

    /// Zooms in by one step.
    public func zoomIn() {
        pixelsPerBar = min(pixelsPerBar * Self.zoomFactor, Self.maxPixelsPerBar)
        syncQuantizedFrameWidth()
    }

    /// Zooms out by one step.
    public func zoomOut() {
        pixelsPerBar = max(pixelsPerBar / Self.zoomFactor, minPixelsPerBar)
        syncQuantizedFrameWidth()
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
            pixelsPerBar = max(pixelsPerBar / Self.zoomFactor, minPixelsPerBar)
        }
        syncQuantizedFrameWidth()
        let newX = xPosition(forBar: barUnderCursor)
        let oldX = CGFloat(barUnderCursor - 1.0) * oldPPB
        return newX - oldX
    }

    /// Performs a zoom step and updates the visible range in a single observation transaction.
    /// Returns the new scroll offset for the caller to apply to the NSScrollView.
    /// @Observable batches mutations within a synchronous call, so changing pixelsPerBar
    /// and visibleRange in the same method produces a single SwiftUI update.
    @discardableResult
    public func zoomAndUpdateViewport(
        zoomIn isZoomIn: Bool,
        anchorBar: Double,
        mouseXRelativeToTimeline: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        let newPPB: CGFloat
        if isZoomIn {
            newPPB = min(pixelsPerBar * Self.zoomFactor, Self.maxPixelsPerBar)
        } else {
            newPPB = max(pixelsPerBar / Self.zoomFactor, minPixelsPerBar)
        }
        let newTimelineX = CGFloat(anchorBar - 1.0) * newPPB
        let newScrollOffset = max(0, newTimelineX - mouseXRelativeToTimeline)

        // Both mutations in one synchronous call → @Observable batches into single notification
        pixelsPerBar = newPPB
        syncQuantizedFrameWidth()
        visibleRange = VisibleRange(
            xMin: newScrollOffset - Self.viewportBuffer,
            xMax: newScrollOffset + viewportWidth + Self.viewportBuffer
        )
        return newScrollOffset
    }

    /// Performs a continuous zoom with a multiplicative factor and updates the visible range.
    /// Used for trackpad pinch-to-zoom where magnification provides smooth, proportional deltas
    /// instead of discrete 1.3x steps.
    /// Returns the new scroll offset for the caller to apply.
    @discardableResult
    public func zoomContinuousAndUpdateViewport(
        factor: CGFloat,
        anchorBar: Double,
        mouseXRelativeToTimeline: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        let newPPB = max(minPixelsPerBar, min(pixelsPerBar * factor, Self.maxPixelsPerBar))
        guard newPPB != pixelsPerBar else {
            return max(0, CGFloat(anchorBar - 1.0) * pixelsPerBar - mouseXRelativeToTimeline)
        }
        let newTimelineX = CGFloat(anchorBar - 1.0) * newPPB
        let newScrollOffset = max(0, newTimelineX - mouseXRelativeToTimeline)

        pixelsPerBar = newPPB
        syncQuantizedFrameWidth()
        visibleRange = VisibleRange(
            xMin: newScrollOffset - Self.viewportBuffer,
            xMax: newScrollOffset + viewportWidth + Self.viewportBuffer
        )
        return newScrollOffset
    }

    /// Throttled zoom for scroll wheel events. Returns `false` if the zoom was
    /// skipped because it arrived within the same display frame as the previous one.
    @discardableResult
    public func throttledZoom(zoomIn: Bool) -> Bool {
        let now = CACurrentMediaTime()
        guard now - lastZoomTime >= Self.zoomThrottleInterval else { return false }
        lastZoomTime = now
        if zoomIn { self.zoomIn() } else { self.zoomOut() }
        return true
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

    /// Returns the total height for a track including automation toolbar and sub-lanes.
    public func trackHeight(for track: Track, baseHeight: CGFloat) -> CGFloat {
        guard automationExpanded.contains(track.id) else { return baseHeight }
        let laneCount = automationLaneCount(for: track)
        guard laneCount > 0 else { return baseHeight }
        return baseHeight + Self.automationToolbarHeight + CGFloat(laneCount) * Self.automationSubLaneHeight
    }

    /// Minimum number of bars shown in the timeline.
    public static let minimumTotalBars: Int = 64

    /// Extra bars of padding shown after the last container.
    private static let barPadding: Int = 16

    /// Visible viewport width in points (set by the timeline's container view).
    public var viewportWidth: CGFloat = 0

    /// Furthest bar with content.
    private var contentEndBar: Int = 0

    /// Manual minimum bars override (set by ensureBarVisible, cleared by updateTotalBars).
    private var manualMinBars: Int = 0

    /// Expands the timeline's total bars if the given bar exceeds the current range.
    public func ensureBarVisible(_ bar: Double) {
        let barInt = Int(ceil(bar)) + 8
        if barInt > totalBars {
            manualMinBars = barInt
        }
    }

    /// Updates the content extent from the given tracks.
    public func updateTotalBars(for tracks: [Track]) {
        let maxEndBar = tracks.flatMap(\.containers).map(\.endBar).max() ?? 0
        contentEndBar = Int(ceil(maxEndBar))
        manualMinBars = 0
    }

    /// Sets the visible viewport width.
    public func setViewportWidth(_ width: CGFloat) {
        guard abs(viewportWidth - width) > 1 else { return }
        viewportWidth = width
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

    // MARK: - View Settings Persistence

    /// Captures the current view state into a `SongViewSettings` for persistence.
    public func captureViewSettings() -> SongViewSettings {
        SongViewSettings(
            trackHeights: trackHeights.mapValues { Double($0) },
            trackHeaderWidth: Double(trackHeaderWidth),
            pixelsPerBar: Double(pixelsPerBar),
            automationExpanded: automationExpanded
        )
    }

    /// Restores view state from persisted `SongViewSettings`.
    public func applyViewSettings(_ settings: SongViewSettings) {
        trackHeights = settings.trackHeights.mapValues { CGFloat($0) }
        trackHeaderWidth = CGFloat(settings.trackHeaderWidth)
        pixelsPerBar = CGFloat(settings.pixelsPerBar)
        syncQuantizedFrameWidth()
        automationExpanded = settings.automationExpanded
    }
}
