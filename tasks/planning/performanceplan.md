# Timeline Zoom/Scroll Performance Plan

## Problem

Zooming and scrolling the timeline becomes sluggish with 15+ tracks. Each zoom step triggers **3 separate SwiftUI evaluation passes** across all tracks, meaning 15 tracks = 45 TrackLaneView evaluations + 15 waveform Canvas redraws per single scroll-wheel tick.

---

## Root Cause Analysis

### Why 3 evaluation passes per zoom step

The zoom handler in `MainContentView.swift` (~line 810-838) does this sequence:

```
1. viewModel.zoomAround(...)       → mutates pixelsPerBar (stored @Observable property)
2. viewModel.forceUpdateVisibleXRange(...)  → mutates visibleXMin + visibleXMax
3. scrollView.setBoundsOrigin(...)  → triggers AppKit boundsDidChange notification
   → HorizontalScrollSynchronizer callback
   → viewModel.updateVisibleXRange(...)  → may mutate visibleXMin/visibleXMax again
```

Each stored `@Observable` property mutation fires a **separate** SwiftUI observation notification. SwiftUI batches mutations within a single synchronous scope, but the `setBoundsOrigin` callback is re-entrant (comes back through AppKit's notification system), so it arrives as a new observation transaction.

This creates 2-3 separate evaluation passes where every view reading `pixelsPerBar`, `visibleXMin`, or `visibleXMax` re-evaluates its body.

### What `_printChanges()` showed

```
TrackLaneView: @self, @identity, _viewModel changed.  (×3 per track per zoom step)
```

The `_viewModel` changed notification means the view's observation of `TimelineViewModel` is being invalidated — any stored property read by the view body triggers this.

### The multiplication problem

- `TimelineView` has two instances (master track + regular tracks)
- Each contains a `ForEach` over tracks → N TrackLaneViews
- Each TrackLaneView contains ContainerViews with WaveformView Canvas
- Total per zoom step: **3 passes × N tracks × waveform Canvas redraw = O(3N) evaluations**

---

## Fixes Applied So Far

### P1: Viewport-Aware Rendering (DONE)

**WaveformView** (`WaveformView.swift`): Added `visibleMinX`/`visibleMaxX` parameters. Both `drawDetailedPath` and `drawDownsampledPath` now compute the visible peak/column range and only build path segments within that range. Reduced Canvas path operations from ~8192 to ~100-1500 depending on zoom level.

**GridOverlayView** (`GridOverlayView.swift`): Already had viewport-aware rendering. Fixed a crash where `startBar > endBar` when `visibleXMin` was stale (set at a higher ppb before zoom-out reduced ppb). Fix: compute `endBar` first, then clamp `startBar = min(max(0, ...), endBar)`.

**ContainerView** (`ContainerView.swift`): Added `visibleXMin`/`visibleXMax` (timeline coordinates), converts to local coordinates before passing to WaveformView: `localVisibleMinX = visibleXMin - containerOriginX`.

**TrackLaneView** (`TrackLaneView.swift`): Passes `visibleXMin`/`visibleXMax` from TimelineViewModel through to ContainerView.

**Impact**: Individual waveform draws are now fast (~100-500 path ops instead of 8192). But we still draw all N waveforms 3 times per zoom step.

### totalBars as Computed Property (DONE)

**TimelineViewModel** (`TimelineViewModel.swift`): Converted `totalBars` from a stored property to a computed property. This eliminated one `@Observable` notification during zoom (previously `recalculateTotalBars()` was called inside zoom methods, mutating a stored property).

**Impact**: Removed one source of notification, but the 3-pass problem persists because it comes from the scroll callback re-entrancy.

### ContainerView Equatable Quantization (TRIED AND REVERTED)

Attempted quantizing `visibleXMin`/`visibleXMax` to 500pt steps in ContainerView's `Equatable` conformance to reduce spurious redraws. **Caused waveforms to disappear** — when the viewport scrolled within a quantization step, the Canvas rendered paths based on the old (stale) visible range, leaving blank areas. Reverted to exact comparison.

### P2: Batch Zoom State Updates (DONE)

Added `isZooming` flag to `HorizontalScrollSynchronizer` (`MainContentView.swift`). During zoom, the flag suppresses the re-entrant `boundsDidChange` notification from `setBoundsOrigin`, eliminating 2 of the 3 redundant SwiftUI evaluation passes. The zoom handler already calls `forceUpdateVisibleXRange()` with the correct values, so the scroll callback's `updateVisibleXRange()` was fully redundant during zoom.

**Implementation**: Approach #1 (isZooming guard). Set `isZooming = true` before `setBoundsOrigin`/`reflectScrolledClipView`, reset after. Guard in `boundsDidChange` handler: `!self.isZooming`.

**Impact**: 3× → 1× evaluations per zoom step. 15-track zoom step goes from ~45 to ~15 evaluations.

### P4: Equatable WaveformView with Quantized Visible Range (DONE)

Added `Equatable` conformance to `WaveformView` (`WaveformView.swift`) with O(1) peaks identity check (count + sentinel samples). Applied `.equatable()` in ContainerView where WaveformView is used.

**Key fix**: Quantized `localVisibleMinX`/`localVisibleMaxX` to 200pt steps in ContainerView *before* passing to WaveformView (`floor` for min, `ceil` for max). This differs from the earlier failed attempt: instead of quantizing in ContainerView's Equatable (which left stale closure values), the input values are quantized so WaveformView draws correctly with quantized coordinates. The 500pt viewport buffer provides 300pt of headroom.

**Impact**: WaveformView Canvas skips redraws for scroll movements <200pt. Combined with P2, this means most zoom/scroll operations only trigger 1 evaluation pass with minimal Canvas work.

### Debug Logging Cleanup (DONE)

Removed all `[PERF]` print statements and `Self._printChanges()` calls from:
- `TimelineViewModel.updateVisibleXRange`
- `GridOverlayView.body`
- `WaveformView.drawDetailedPath` and `drawDownsampledPath`
- `TrackLaneView.body`
- `TimelineView.body`

---

## Remaining Priorities

### P3: Waveform Peak Mipmap (LOW PRIORITY — marginal with viewport culling)

With P1's viewport culling and P4's Equatable, per-draw cost is already low. At 100 peaks/second, a 3-minute recording has 18,000 peaks. The downsampled path only runs when `visibleCount > 4096`, and with viewport culling, only ~100-1500 columns are drawn. The `maxInRange` loop covers ~2-4 peaks per column — fast enough.

Worth revisiting if recordings exceed 10+ minutes or if profiling shows downsampling as a bottleneck.

---

## Key Files

| File | Role |
|------|------|
| `Sources/LoopsApp/Views/MainWindow/MainContentView.swift` ~810 | Zoom handler (zoomAround + forceUpdate + setBoundsOrigin) |
| `Sources/LoopsApp/Views/MainWindow/MainContentView.swift` ~2067 | HorizontalScrollSynchronizer with `isZooming` flag |
| `Sources/LoopsApp/ViewModels/TimelineViewModel.swift` | Timeline state: pixelsPerBar, visibleXMin/Max, totalBars |
| `Sources/LoopsApp/Views/Timeline/TimelineView.swift` | Two instances (master + regular), ForEach over tracks |
| `Sources/LoopsApp/Views/Timeline/TrackLaneView.swift` | Per-track lane, passes visible range to ContainerView |
| `Sources/LoopsApp/Views/Timeline/ContainerView.swift` | Per-container view with WaveformView (quantized visible range), Equatable |
| `Sources/LoopsApp/Views/Timeline/WaveformView.swift` | Canvas-based waveform drawing, viewport-aware, Equatable |
| `Sources/LoopsApp/Views/Timeline/GridOverlayView.swift` | Canvas grid lines, viewport-aware, Equatable |

---

## Testing

All 47 `TimelineViewModelTests` pass after the changes. Key tests updated:
- `totalWidth()` — expects computed totalBars (64 default × ppb)
- `ensureBarVisibleExpands/NoShrink/AtBoundary` — uses `manualMinBars` path

Run `swift test --filter TimelineViewModelTests` to verify after any further changes.
