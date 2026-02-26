# PRD: DAW Polish — Performance, Sync, Editing & UX Improvements

## Overview

This PRD addresses a collection of performance issues, audio sync bugs, and missing DAW-standard editing features in Loops. The changes span the audio engine (multi-track sync), timeline view (scroll/zoom performance), transport (return-to-start), automation editing (snapping, toolbar, shapes), container management (overlap, crossfade, glue, selection shadow), and multi-selection across containers, tracks, and automation points.

## Goals

- Achieve buttery-smooth timeline scrolling and zooming comparable to commercial DAWs
- Guarantee sample-accurate sync when multiple tracks play the same audio from the same start point
- Implement return-to-start transport behavior reliably
- Make automation editing intuitive with proper grid snapping and shaping tools
- Support container overlap with automatic crossfading
- Enable multi-selection workflows across containers, tracks, and automation
- Add glue/consolidate for merging containers
- Improve visual feedback for selected containers (Pro Tools-style shadow)

## Quality Gates

These commands must pass for every user story:
- `swift build` — Project compiles without errors
- `swift test` — All unit tests pass
- `swiftlint` — No lint violations

For audio sync tests, use conditional test execution:
- Tests requiring audio hardware should check for available output devices and skip on CI

## User Stories

### US-001: Timeline Scroll & Zoom Performance

**Description:** As a user, I want timeline scrolling and zooming to feel instant and responsive, like in Bitwig or Pro Tools.

**Acceptance Criteria:**
- [ ] Profile current scroll/zoom performance and identify bottlenecks
- [ ] Reduce view re-evaluations during scroll — only visible tracks should compute layout
- [ ] Zoom gestures (pinch, +/-, scroll wheel with modifier) complete within one frame (16ms)
- [ ] Use `drawingGroup()` or Metal-backed rendering where SwiftUI Canvas is insufficient
- [ ] Debounce or throttle zoom state changes to avoid cascading relayout
- [ ] Waveform rendering uses pre-computed LOD (level of detail) peaks — no recomputation on zoom
- [ ] Grid overlay redraws only on zoom/scroll change, not on unrelated state mutations
- [ ] Automation overlays and container views use `.equatable()` to skip unnecessary redraws
- [ ] 100+ containers across 20+ tracks scroll smoothly at 60 FPS

**Technical Notes:**
- Current implementation uses `LazyVStack`, `Canvas`, and `.equatable()` — verify these are actually preventing redraws via Instruments profiling
- Consider replacing per-container `Canvas` with a single `Canvas` per track lane that batches all container waveforms
- `TimelineView` (605 lines) and `TrackLaneView` are the primary targets
- `GridOverlayView` already uses Canvas — ensure it doesn't redraw on non-scroll/zoom changes
- `PointerTrackingOverlay` with `NSTrackingArea` is good — verify it doesn't trigger SwiftUI updates

---

### US-002: Multi-Track Audio Sync (Sample-Accurate Playback)

**Description:** As a user, when I import the same 10 backing tracks twice (20 tracks total) starting at the same bar, they must play in perfect sync with zero audible phase offset.

**Acceptance Criteria:**
- [ ] All `AVAudioPlayerNode.scheduleSegment()` calls use the same `AVAudioTime` reference (derived from a single `hostTime` + offset calculation)
- [ ] The scheduling loop computes one shared `startTime` and passes it to every player node
- [ ] No per-track delay from sequential `player.play(at:)` calls — batch all `.play()` calls with the same `AVAudioTime`
- [ ] Write integration tests that render 2+ tracks of identical audio offline, mix to mono, and verify zero-crossing alignment (phase cancellation test)
- [ ] Tests use `engine.enableManualRenderingMode(.offline)` so they run without audio hardware
- [ ] Tests that require a real audio device are gated behind `XCTSkipUnless(audioOutputAvailable)` and run locally
- [ ] Verify that `PlaybackScheduler.prepare()` phase-2 (stop/connect/start) does not introduce variable latency between tracks

**Technical Notes:**
- Current code in `PlaybackScheduler` (2,795 lines) schedules containers individually — need to verify all share the same host-time anchor
- `AVAudioPlayerNode.scheduleSegment(file:startingFrame:frameCount:at:)` — the `at:` parameter must be identical across all nodes for sync
- Phase cancellation test: sum two identical signals — if in sync, amplitude doubles; if out of sync by even 1 sample, destructive interference is measurable
- `AudioEngineManager` has no locks despite `@unchecked Sendable` — verify thread safety during multi-track scheduling

---

### US-003: Return-to-Start Transport Behavior

**Description:** As a user, when the return-to-start button (back arrow next to stop) is toggled on, pressing stop should return the playhead to where play was originally pressed. This is standard DAW behavior.

**Acceptance Criteria:**
- [ ] When return-to-start is enabled and user presses Play at bar 5, then stops at bar 12 — playhead returns to bar 5
- [ ] When return-to-start is enabled and user seeks during playback (e.g., jumps to bar 20), the return position stays at bar 5 (original play position)
- [ ] Pressing stop a second time (already at return position) moves playhead to bar 1.0
- [ ] When return-to-start is disabled, stop leaves playhead at current position
- [ ] Return-to-start state persists across app sessions (UserDefaults)
- [ ] Return-to-start button in toolbar has clear visual toggle state (on/off)
- [ ] Write unit tests for TransportManager covering all return-to-start scenarios
- [ ] Remove debug print statements from TransportViewModel (`[RETURN-TO-START]` prints)

**Technical Notes:**
- `TransportManager.swift` already has `returnToStartEnabled` and `userPlayStartBar` — verify correctness
- `TransportViewModel.swift` has extensive debug prints that should be cleaned up
- Current logic: `if returnToStartEnabled && abs(playheadBar - userPlayStartBar) > 0.001` — edge case when playhead hasn't moved should be handled
- The `isPerformMode` flag bypasses return-to-start — keep this behavior

---

### US-004: Automation Snapping to Grid

**Description:** As a user, when I edit automation breakpoints, they should snap to the current grid resolution (adaptive or fixed), not to arbitrary values.

**Acceptance Criteria:**
- [ ] Automation breakpoint horizontal position snaps to `TimelineViewModel.effectiveSnapResolution()` when snap is enabled
- [ ] Automation breakpoint value snaps to sensible increments based on parameter range (e.g., dB values snap to 0.5 dB, percentage to 1%, pan to integer values)
- [ ] Holding Cmd disables snap (fine-grained control), consistent with timeline snap-override behavior
- [ ] Moving breakpoints respects both horizontal (time) and vertical (value) snapping independently
- [ ] Grid lines in automation sub-lanes reflect the current snap resolution
- [ ] Existing `AutomationCoordinateMapping` functions updated to include snap logic
- [ ] Write unit tests for automation snap calculations

**Technical Notes:**
- `AutomationSubLaneView` handles breakpoint editing
- `AutomationCoordinateMapping` has pure functions for position↔pixel conversion — add snap-aware variants
- `SnapResolution.snap(_:)` already exists for beat snapping — reuse for automation time axis
- Value snapping needs parameter metadata (min, max, unit) from `AutomationLane.displayMetadata`

---

### US-005: Automation Toolbar with Shaping Tools

**Description:** As a user, I want a toolbar above the automation lane (like the piano roll toolbar) with tools for drawing shapes: line, curve, ramp, S-curve, sine, triangle, and square.

**Acceptance Criteria:**
- [ ] Toolbar appears above expanded automation sub-lanes, styled consistently with piano roll toolbar
- [ ] Tools: Pointer (default), Line, Curve (exponential), Ramp (linear), S-Curve, Sine, Triangle, Square
- [ ] **Pointer**: Default — click to add point, drag to move points
- [ ] **Line**: Click start point, click end point — generates a straight line of breakpoints between them
- [ ] **Curve/Ramp/S-Curve**: Same interaction as Line but generates curved interpolation
- [ ] **Sine/Triangle/Square**: Click start, drag to end — generates periodic breakpoints. Frequency determined by grid resolution (one cycle per grid unit)
- [ ] Shape tools replace existing breakpoints in the drawn range (destructive within range, non-destructive outside)
- [ ] Undo support for all shape operations
- [ ] Toolbar shows current automation lane name and parameter info
- [ ] Toolbar is right-aligned next to the inspector panel (not at the far right of the total grid)

**Technical Notes:**
- Reference `InlinePianoRollView` toolbar implementation for styling consistency
- Periodic shapes need a `frequency` derived from snap resolution or explicit user input
- Shape generation is pure math — create `AutomationShapeGenerator` utility in `LoopsCore`
- Sine: `value = 0.5 + 0.5 * sin(2π * t / period)`
- Triangle: `value = 2 * abs(2 * (t/period - floor(t/period + 0.5))) `
- Square: `value = t % period < period/2 ? 1.0 : 0.0`

---

### US-006: Piano Roll Inline Tools Right-Alignment

**Description:** As a user, the piano roll inline tools should be right-aligned next to the inspector panel, not positioned at the far right of the total grid width, so they're always accessible without scrolling.

**Acceptance Criteria:**
- [ ] Inline piano roll toolbar is pinned to the right edge of the visible viewport (not the full scrollable content width)
- [ ] Toolbar stays visible while scrolling horizontally through the piano roll
- [ ] Toolbar does not overlap content — content area is reduced to accommodate the toolbar
- [ ] Position updates smoothly during scroll (no jitter or lag)
- [ ] Works correctly at all zoom levels

**Technical Notes:**
- `InlinePianoRollView` currently positions tools relative to the total grid width
- Use a `GeometryReader` or overlay pinned to the scroll view's visible frame
- Alternatively, use `ZStack` with alignment and `offset` based on scroll position
- Consider using `.safeAreaInset()` or a fixed-position overlay outside the scroll content

---

### US-007: Container Overlap and Crossfade

**Description:** As a user, I want to drag a container on top of another container so it cuts into the sibling (like extending a waveform over another in Pro Tools). Overlapping regions should automatically create a crossfade that can be manually adjusted.

**Acceptance Criteria:**
- [ ] Dragging container A's right edge over container B's left edge trims B's start and creates an overlap region
- [ ] The overlap region automatically generates a crossfade (A fades out, B fades in)
- [ ] Default crossfade length equals the overlap amount
- [ ] Crossfade type defaults to equal-power (S-curve)
- [ ] A visual crossfade indicator (X pattern or gradient) appears in the overlap region
- [ ] User can manually adjust crossfade length by dragging the crossfade boundary handles
- [ ] User can change crossfade curve type (linear, equal-power, S-curve) via context menu
- [ ] Moving a container away from its sibling removes the crossfade
- [ ] Crossfade audio is rendered correctly during playback (both containers audible in transition)
- [ ] Model: Add `Crossfade` struct with `duration`, `curveType`, and reference to both containers
- [ ] Crossfade data persists with the project

**Technical Notes:**
- Container model has `startBar` and `lengthBars` — overlap means `containerA.endBar > containerB.startBar`
- Need to add `Crossfade` model to `LoopsCore` linking two containers
- `PlaybackScheduler` must schedule both containers and apply gain envelopes in the overlap region
- `ContainerView` needs a crossfade visual overlay in the overlap zone
- Existing `FadeSettings` (`enterFade`, `exitFade`) can inform crossfade curve implementation
- Use `CurveType` enum (already exists: linear, exponential, sCurve) for crossfade curves
- Equal-power crossfade: `gainA = cos(t * π/2)`, `gainB = sin(t * π/2)`

---

### US-008: Multi-Select Containers

**Description:** As a user, I want to select multiple containers using Cmd+Click (toggle) and Shift+Click (range), then move, delete, or operate on them as a group.

**Acceptance Criteria:**
- [ ] Cmd+Click on a container adds/removes it from the multi-selection set
- [ ] Shift+Click selects all containers between the last-selected and clicked container (on the same track, ordered by startBar)
- [ ] Multi-selected containers show selection highlight (blue border)
- [ ] Dragging any selected container moves all selected containers as a group, preserving relative positions
- [ ] Delete key removes all selected containers
- [ ] Cmd+A selects all containers on the focused track (or all containers if no track focused)
- [ ] Clicking on empty space deselects all
- [ ] `SelectionState.selectedContainerIDs` (Set) is the backing store — already exists
- [ ] Context menu operations (delete, clone, split) apply to all selected containers

**Technical Notes:**
- `SelectionState` already has `selectedContainerIDs: Set<TypedID<Container>>` — build on this
- Container ordering for Shift+Click: sort containers on the same track by `startBar`
- Group drag: compute delta from drag start, apply to all selected containers' `startBar`
- Ensure `ProjectViewModel` mutation methods support batch operations

---

### US-009: Multi-Select Tracks

**Description:** As a user, I want to select multiple tracks for batch operations (solo, mute, delete, reorder).

**Acceptance Criteria:**
- [ ] Cmd+Click on track headers adds/removes tracks from multi-selection
- [ ] Shift+Click selects a range of tracks
- [ ] Multi-selected tracks show highlight in track header
- [ ] Batch operations: solo all, mute all, delete all, set color
- [ ] Dragging a selected track header reorders all selected tracks as a group
- [ ] Add `selectedTrackIDs: Set<TypedID<Track>>` to `SelectionState`

**Technical Notes:**
- Current `SelectionState` has `selectedTrackID` (singular) — extend to `selectedTrackIDs` (Set)
- Maintain backward compatibility: single-track operations still work via computed property
- Track header views need Cmd/Shift click handling

---

### US-010: Marquee Selection for Automation Points

**Description:** As a user, I want to draw a marquee rectangle over automation breakpoints to select multiple points, then move or delete them as a group.

**Acceptance Criteria:**
- [ ] Click-drag on empty space in automation sub-lane starts a marquee selection rectangle
- [ ] All breakpoints within the marquee rectangle are selected (highlighted)
- [ ] Selected breakpoints can be dragged as a group (preserving relative positions and values)
- [ ] Delete key removes all selected breakpoints
- [ ] Cmd+Click adds/removes individual breakpoints from selection
- [ ] Cmd+A selects all breakpoints in the active automation lane
- [ ] Visual: selected breakpoints use a distinct color (e.g., filled vs outlined)
- [ ] Add `selectedBreakpointIndices: Set<Int>` or similar to automation editing state

**Technical Notes:**
- `AutomationSubLaneView` is the target view
- Marquee is a temporary overlay (rectangle from drag start to current position)
- Hit testing: check if breakpoint position/value falls within the marquee's bar-range and value-range
- Group drag: compute delta in bar-position and value, apply to all selected breakpoints

---

### US-011: Glue / Consolidate Containers

**Description:** As a user, I want to select multiple containers (or a range) and glue them into a single container. Empty space between containers is included as silence in the merged result.

**Acceptance Criteria:**
- [ ] Select 2+ containers on the same track → context menu "Glue" / keyboard shortcut (Cmd+J)
- [ ] Merges all selected containers into one container spanning from earliest startBar to latest endBar
- [ ] Empty gaps between containers become silence in the merged audio
- [ ] Audio containers: offline-render the merged result to a new CAF file
- [ ] MIDI containers: merge note sequences with correct timing offsets
- [ ] Automation lanes are merged (breakpoints from all containers, re-offset to new container start)
- [ ] The original containers are replaced by the single merged container
- [ ] Undo support: unglue restores original containers
- [ ] Works with multi-selected containers (US-008)

**Technical Notes:**
- Use `OfflineRenderer` to bounce the merged audio — it already supports fade processing
- MIDI merge: offset each note's beat position by the container's relative start offset
- Automation merge: re-map breakpoint positions from per-container offsets to merged-container offsets
- Consider adding `GlueOperation` that stores original containers for undo

---

### US-012: Selected Container Shadow (Pro Tools Style)

**Description:** As a user, when I select a container that has neighboring containers, I want a subtle shadow/overlay extending from the selected container over its neighbors, making it visually obvious which container is focused.

**Acceptance Criteria:**
- [ ] Selected container casts a subtle gradient shadow extending left and right over adjacent containers and empty space
- [ ] Shadow is semi-transparent (e.g., 10-15% opacity dark gradient, 20-30px wide)
- [ ] Shadow only appears on the selected container, not all containers
- [ ] Shadow does not interfere with click targets on neighboring containers
- [ ] Shadow renders efficiently (no per-frame recomputation)
- [ ] Shadow is visible on both light and dark backgrounds

**Technical Notes:**
- Implement as an overlay on `ContainerView` that extends beyond its bounds
- Use `.clipped(false)` or `ZStack` layering to allow shadow to overflow
- Shadow gradient: linear from accent color at 15% opacity to transparent
- Only render for `selectionState.selectedContainerID == container.id`
- Consider using `.shadow()` modifier or custom `Canvas` drawing
- `allowsHitTesting(false)` on the shadow layer so clicks pass through to neighbors

---

## Module Independence Map

Tag each user story with its module group. Stories in different module groups that share no files are candidates for parallel execution.

| Module Group | Stories | Key Files/Areas | Independent From |
|---|---|---|---|
| **[Performance]** | US-001 | TimelineView, TrackLaneView, GridOverlayView, ContainerView rendering | [Engine], [Transport] |
| **[Engine]** | US-002 | PlaybackScheduler, AudioEngineManager, TransportManager scheduling | [UI-Automation], [UI-Piano] |
| **[Transport]** | US-003 | TransportManager, TransportViewModel | [UI-Automation], [UI-Piano] |
| **[UI-Automation]** | US-004, US-005, US-010 | AutomationSubLaneView, AutomationOverlayView, AutomationCoordinateMapping, LoopsCore models | [Engine], [Transport] |
| **[UI-Piano]** | US-006 | InlinePianoRollView | [Engine], [Transport], [UI-Automation] |
| **[UI-Containers]** | US-007, US-008, US-011, US-012 | ContainerView, Container model, SelectionState, ProjectViewModel | Partially overlaps [Performance] |
| **[UI-Tracks]** | US-009 | TrackHeaderView, SelectionState | [Engine], [UI-Piano] |

**Dependency Notes:**
- US-008 (multi-select containers) should be implemented before US-011 (glue) since glue operates on selected containers
- US-004 (automation snap) should be implemented before US-005 (automation toolbar) and US-010 (marquee select)
- US-007 (container overlap/crossfade) touches both LoopsCore model and PlaybackScheduler — partial engine overlap
- US-001 (performance) may touch ContainerView which is also modified by US-007, US-008, US-012
