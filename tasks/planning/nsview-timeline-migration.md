# NSView Timeline Migration Plan

## Problem

The SwiftUI timeline re-evaluates ~37 view bodies per zoom step (doubles to ~58 when coalescing fails). With 8 tracks this produces ~100ms cascades on every scroll wheel tick. This scales linearly — 20 tracks would mean ~200ms per zoom step, well above the 16ms frame budget. Pro DAWs solve this by rendering the entire timeline grid in a single draw call with dirty-rect invalidation.

## Architecture

### What stays SwiftUI
- Toolbar (transport controls, BPM, time signature, snap, grid mode)
- Sidebar (Songs, Setlists)
- Inspector (Container, Storyline, Track)
- Mixer view
- Settings / preferences
- Export sheet
- Piano roll pop-out window (PianoRollView.swift — modal, not 60fps)

### What moves to NSView
- **TimelineCanvasView** — single custom NSView replacing:
  - GridOverlayView (bar/beat lines)
  - TrackLaneView (track backgrounds, container layout)
  - ContainerView (colored rects, waveforms, MIDI minimap, automation overlay, fades, crossfades)
  - WaveformView (peak path rendering)
  - MIDINoteMinimapView (tiny note rectangles)
  - AutomationOverlayView (curves on containers)
  - PlayheadView (vertical red line)
  - CursorOverlayView (vertical gray line)
  - Ghost track drop preview lanes
  - Range selection overlay

- **RulerCanvasView** — single custom NSView replacing:
  - RulerView (bar numbers, tick marks, range selection highlight)

- **SectionLaneCanvasView** — single custom NSView replacing:
  - SectionLaneView (colored section bands)

- **AutomationLaneCanvasView** — single custom NSView replacing:
  - AutomationSubLaneView (breakpoint editing, curve rendering)
  - AutomationToolbarView (tool selector — could stay SwiftUI, tiny)

- **InlinePianoRollCanvasView** — single custom NSView replacing:
  - InlinePianoRollView (compact MIDI editing below track)
  - PianoRollContentView (note grid, keyboard)

- **TrackHeaderView** — stays SwiftUI (not performance-critical, rarely re-evaluated, benefits from SwiftUI layout for buttons/menus). Wrapped alongside the NSView timeline in the existing MainContentView HStack.

### Rendering approach

```
MainContentView (SwiftUI — unchanged HSplitView)
├── Sidebar (SwiftUI)
├── Timeline area
│   ├── RulerCanvasView (NSViewRepresentable → NSView)
│   ├── SectionLaneCanvasView (NSViewRepresentable → NSView)
│   ├── HStack
│   │   ├── Track headers (SwiftUI VStack, unchanged)
│   │   └── NSScrollView (AppKit, replaces SwiftUI ScrollView)
│   │       └── TimelineCanvasView (single NSView, custom draw)
│   │           ├── draws: grid lines, track backgrounds, containers,
│   │           │   waveforms, MIDI minimaps, automation overlays,
│   │           │   fades, crossfades, selection highlights
│   │           ├── draws: automation sub-lanes (below tracks, if expanded)
│   │           ├── draws: inline piano roll (below MIDI tracks, if expanded)
│   │           ├── overlay: playhead line (CALayer, 60fps, no redraw)
│   │           └── overlay: cursor line (CALayer, 60fps, no redraw)
│   └── Master track row (SwiftUI header + NSView lane, pinned at bottom)
└── Inspector (SwiftUI)
```

### Key design decisions

**1. Single draw call vs. sublayers**
The entire grid + all containers + waveforms are drawn in one `draw(_:)` override. This eliminates the N-views-per-track problem. Waveform peaks are pre-rendered into cached CGImages at discrete zoom levels and blitted during scroll.

**2. Dirty-rect invalidation**
- Scroll: `setNeedsDisplay(newlyExposedRect)` — only redraw the strip that scrolled into view
- Zoom: `setNeedsDisplay(bounds)` — full redraw, but it's one draw call (~1-2ms for 20 tracks)
- Container edit (move/resize): `setNeedsDisplay(unionOfOldAndNewRect)` — redraw only affected area
- Playhead: separate CALayer, repositioned via `layer.position.x` — zero redraw cost

**3. Playhead and cursor as CALayers**
The playhead line and cursor line are thin `CALayer` sublayers positioned on top of the canvas. During playback, only `layer.position.x` changes (implicitly animated at 60fps by Core Animation). This avoids triggering `draw(_:)` at 60fps.

**4. Waveform tile cache**
Pre-render waveform peaks into CGImage tiles at several zoom levels (e.g., 8, 16, 32, 64, 120, 240, 480 pixels/bar). On zoom, pick the nearest cached tile and scale slightly. On exact match, blit directly. Cache invalidated only when peaks change (import/recording).

**5. Hit testing for gestures**
Replace SwiftUI's gesture system with `mouseDown/mouseDragged/mouseUp/mouseMoved` overrides on the NSView. Implement the Smart Tool zone logic in a `hitTest` method that determines which container/edge/zone the cursor is over, then dispatches to the appropriate gesture handler.

**6. Communication with SwiftUI**
The NSView reads from `TimelineViewModel` and `ProjectViewModel` (both `@Observable`). Changes flow:
- **SwiftUI → NSView:** ViewModel changes trigger `setNeedsDisplay()` via KVO or a thin observation bridge
- **NSView → SwiftUI:** Gesture callbacks invoke ProjectViewModel methods (same closures as today, but called from NSView instead of SwiftUI gesture handlers)

## Phases

### Phase 0: Foundation (non-breaking)
**Goal:** Create the NSView shell and rendering infrastructure without removing any SwiftUI code.

- [ ] Create `TimelineCanvasView: NSView` with basic `draw(_:)` that renders grid lines
- [ ] Create `TimelineCanvasRepresentable: NSViewRepresentable` bridge
- [ ] Add feature flag (`useNSViewTimeline`) to toggle between SwiftUI and NSView timeline
- [ ] Implement waveform tile cache (`WaveformTileCache`) with zoom-level-based CGImage generation
- [ ] Add playhead CALayer and cursor CALayer
- [ ] Set up observation bridge: TimelineViewModel changes → `setNeedsDisplay()`

**Files created:**
- `Sources/LoopsApp/Views/Timeline/Canvas/TimelineCanvasView.swift`
- `Sources/LoopsApp/Views/Timeline/Canvas/TimelineCanvasRepresentable.swift`
- `Sources/LoopsApp/Views/Timeline/Canvas/WaveformTileCache.swift`
- `Sources/LoopsApp/Views/Timeline/Canvas/TimelineHitTesting.swift`

**Estimated scope:** ~600 lines new code, 0 lines removed

### Phase 1: Grid + Containers + Waveforms (read-only)
**Goal:** Render the full timeline visually — grid lines, container rectangles, waveform peaks, MIDI minimaps — but with no interactivity yet.

- [ ] Draw track lane backgrounds (alternating opacity per track)
- [ ] Draw container rectangles (color, border, selected state, clone indicator)
- [ ] Draw waveform peaks inside containers (using tile cache, viewport-culled)
- [ ] Draw MIDI note minimaps inside MIDI containers
- [ ] Draw fade curves (enter/exit fade overlays)
- [ ] Draw crossfade regions between overlapping containers
- [ ] Draw range selection overlay
- [ ] Draw container record-arm indicator
- [ ] Implement viewport culling (only draw containers/tracks intersecting visible rect)
- [ ] Wire up to real Song/Track/Container data from ProjectViewModel

**Validation:** Side-by-side comparison with SwiftUI timeline — visual parity check

**Estimated scope:** ~1,200 lines new code

### Phase 2: Scroll + Zoom
**Goal:** Replace the SwiftUI ScrollView + HorizontalScrollSynchronizer with native NSScrollView hosting the TimelineCanvasView.

- [ ] Embed TimelineCanvasView as documentView of an NSScrollView
- [ ] Implement horizontal scroll sync with ruler and section lane NSScrollViews
- [ ] Implement Cmd+scroll zoom (anchored at cursor position)
- [ ] Implement dirty-rect scroll rendering (only redraw newly exposed strip)
- [ ] Implement pinch-to-zoom (trackpad magnification gesture)
- [ ] Wire zoom throttling (reuse existing `throttledZoom` logic)
- [ ] Update `TimelineViewModel.updateVisibleXRange` from NSScrollView bounds changes

**Validation:** Profile with `log stream` — expect ~0 SwiftUI body evaluations during scroll/zoom

**Estimated scope:** ~400 lines new code, ~200 lines removed from MainContentView scroll logic

### Phase 3: Container Gestures
**Goal:** Port all container interaction from SwiftUI gesture handlers to NSView mouse events.

- [ ] Implement `mouseDown`/`mouseDragged`/`mouseUp` dispatch
- [ ] Port Smart Tool zone detection (fade, resize, trim, move, select)
- [ ] Port container move (horizontal drag with grid snap)
- [ ] Port container resize (left/right edge drag)
- [ ] Port container trim (bottom edge drag, adjusts audioStartOffset)
- [ ] Port fade handle drag (top corner drag)
- [ ] Port click-to-select (single, Cmd+multi, Shift+range)
- [ ] Port double-click (open editor / toggle inline piano roll)
- [ ] Port right-click context menu (NSMenu, not SwiftUI `.contextMenu`)
- [ ] Port Alt+drag clone
- [ ] Port click-on-empty-area to set playhead
- [ ] Port drag-to-create container (in empty track area)
- [ ] Port file drop (audio/MIDI import via NSDraggingDestination)
- [ ] Implement cursor shape changes (resize arrows, move grab, crosshair, etc.)
- [ ] Port keyboard shortcuts (Delete to remove, +/- to zoom)

**Validation:** All container operations work identically. Run through existing test suite.

**Estimated scope:** ~1,500 lines new code (gesture handlers are verbose)

### Phase 4: Automation Lanes
**Goal:** Port automation sub-lane rendering and editing.

- [ ] Draw track-level automation lanes (below each track, when expanded)
- [x] Draw container-level automation lanes
- [x] Draw breakpoint dots and connecting curves (linear, bezier)
- [x] Draw grid lines in automation lanes
- [x] Draw 25%/50%/75% guide lines
- [x] Port breakpoint creation (click to add)
- [x] Port breakpoint drag (move value + position)
- [x] Port breakpoint deletion
- [ ] Port multi-select (Cmd+click, marquee drag)
- [x] Port shape tools (line, curve, fill range)
- [ ] Port automation toolbar (tool selector — keep as SwiftUI overlay or port to NSView)
- [x] Automation snapping to grid

**Validation:** Create automation curves, edit breakpoints, verify shape tools work.

**Estimated scope:** ~1,000 lines new code

### Phase 5: Inline Piano Roll
**Goal:** Port the inline MIDI editor that appears below MIDI tracks.

- [x] Draw piano roll grid (pitch rows, beat columns)
- [x] Draw keyboard labels on left edge
- [x] Draw MIDI notes (rectangles with velocity-based opacity)
- [x] Constrain MIDI note rendering/hit-testing to lane bounds and keep left note rail mapping in lockstep with note placement
- [ ] Draw ghost notes (from inactive containers, low opacity)
- [x] Draw playhead line within piano roll
- [x] Port note creation (click/drag)
- [x] Port note movement (drag pitch/time)
- [x] Port note resize (drag left/right edge)
- [x] Port note deletion (right-click / Delete key)
- [ ] Port note multi-select (Cmd+click, marquee)
- [x] Port note preview (play note on interaction)
- [x] Port resize handle for inline PR height
- [x] Port container switching within inline PR

**Validation:** Full MIDI editing workflow works inline.

**Estimated scope:** ~800 lines new code

### Phase 6: Ruler + Section Lane
**Goal:** Port ruler and section lane to NSView (optional — these are lightweight, but porting them simplifies scroll sync to pure AppKit).

- [ ] Port RulerView to RulerCanvasView (NSView with `draw(_:)`)
- [ ] Port ruler click-to-position and Shift+drag range select
- [ ] Port SectionLaneView to SectionCanvasView
- [ ] Port section create/move/resize/delete gestures
- [ ] Simplify scroll synchronization (all three are now NSScrollViews — direct bounds sync)

**Estimated scope:** ~400 lines new code

### Phase 7: Cleanup
**Goal:** Remove old SwiftUI views, feature flag, and dead code.

- [ ] Remove feature flag, make NSView timeline the only path
- [ ] Delete old SwiftUI files:
  - GridOverlayView.swift
  - TrackLaneView.swift
  - ContainerView.swift
  - WaveformView.swift
  - MIDINoteMinimapView.swift
  - AutomationOverlayView.swift
  - AutomationSubLaneView.swift
  - PlayheadView.swift
  - CursorOverlayView.swift
  - RulerView.swift (if ported)
  - SectionLaneView.swift (if ported)
  - InlinePianoRollView.swift
  - Parts of PianoRollContentView.swift used by inline view
- [ ] Remove performance signpost instrumentation from deleted views
- [ ] Simplify MainContentView (remove SwiftUI scroll machinery)
- [ ] Update tests

**Estimated removal:** ~5,000 lines of SwiftUI code

## Risk Areas

**1. Gesture complexity**
ContainerView alone is 1,170 lines, mostly gestures. The Smart Tool zone system with its state machine (fade, resize, trim, move, select, clone) is the hardest part to port. Mitigation: port gestures one zone at a time, validate each independently.

**2. Accessibility**
SwiftUI provides accessibility for free. The NSView will need manual `NSAccessibility` protocol conformance for containers, automation breakpoints, and MIDI notes. Can be deferred to after functional parity.

**3. Right-click menus**
SwiftUI `.contextMenu` becomes `NSMenu` built programmatically. The container context menu has ~15 items with dynamic content (paste availability, crossfade options, other songs list). Straightforward but tedious.

**4. Undo integration**
Currently undo is triggered through ProjectViewModel methods called from SwiftUI gesture handlers. The same methods will be called from NSView — no change needed in the undo system itself.

**5. Inline piano roll scroll sync**
The inline piano roll needs its own vertical scroll (pitch) while sharing horizontal scroll (time) with the timeline. In SwiftUI this is handled by nested ScrollViews. In NSView, this needs a clip view within the main canvas, or a separate overlaid NSScrollView for the piano roll area.

## Expected Performance Improvement

| Metric | SwiftUI (current) | NSView (target) |
|--------|-------------------|-----------------|
| Zoom step (8 tracks) | ~100ms (37 body evals) | ~2ms (1 draw call) |
| Zoom step (20 tracks) | ~250ms (est.) | ~3ms (1 draw call) |
| Scroll frame | ~50ms (19 body evals) | ~1ms (dirty-rect strip) |
| Playhead update | triggers body eval cascade | CALayer.position.x (0ms redraw) |
| Container move | ~30ms (ContainerView + parent re-eval) | ~1ms (invalidate old+new rect) |

## Migration order summary

```
Phase 0: Shell + infra          (~600 LOC new)     ← can ship behind flag
Phase 1: Read-only rendering    (~1,200 LOC new)   ← visual parity
Phase 2: Scroll + zoom          (~400 LOC new)     ← performance win unlocked
Phase 3: Container gestures     (~1,500 LOC new)   ← functional parity for containers
Phase 4: Automation lanes       (~1,000 LOC new)   ← functional parity for automation
Phase 5: Inline piano roll      (~800 LOC new)     ← functional parity for MIDI
Phase 6: Ruler + sections       (~400 LOC new)     ← optional, simplifies sync
Phase 7: Cleanup                (~5,000 LOC removed)
                                ─────────────────
                                ~5,900 LOC new, ~5,000 LOC removed
```

Phases 0-2 deliver the performance win. Phases 3-5 restore interactivity. Phase 6 is optional polish. Phase 7 removes dead weight.
