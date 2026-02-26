> Sub-PRD of prd-daw-polish. Parallel worktree: containers-ui.

# Sub-PRD: Containers & UI — Performance, Selection, Crossfade, Glue & Visual Polish

## Overview

Improve timeline scroll/zoom performance, add container overlap with crossfading, implement multi-selection for containers and tracks, add glue/consolidate, fix piano roll toolbar positioning, and add Pro Tools-style selection shadows. These changes span timeline views, container model/views, and selection state.

## Quality Gates

- `swift build` — Compiles without errors
- `swift test` — All unit tests pass
- `swiftlint` — No lint violations

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

**Key Files:**
- `Sources/LoopsApp/Views/Timeline/TimelineView.swift`
- `Sources/LoopsApp/Views/Timeline/TrackLaneView.swift`
- `Sources/LoopsApp/Views/Timeline/ContainerView.swift`
- `Sources/LoopsApp/Views/Timeline/GridOverlayView.swift`
- `Sources/LoopsApp/ViewModels/TimelineViewModel.swift`

**Technical Notes:**
- Current implementation uses `LazyVStack`, `Canvas`, and `.equatable()` — verify these are actually preventing redraws
- Consider batching per-container Canvas into a single Canvas per track lane
- `PointerTrackingOverlay` with `NSTrackingArea` is good — verify it doesn't trigger SwiftUI updates

---

### US-006: Piano Roll Inline Tools Right-Alignment

**Description:** As a user, the piano roll inline tools should be right-aligned next to the inspector panel, not at the far right of the total grid width.

**Acceptance Criteria:**
- [ ] Inline piano roll toolbar is pinned to the right edge of the visible viewport
- [ ] Toolbar stays visible while scrolling horizontally
- [ ] Toolbar does not overlap content — content area is reduced to accommodate
- [ ] Position updates smoothly during scroll (no jitter or lag)
- [ ] Works correctly at all zoom levels

**Key Files:**
- `Sources/LoopsApp/Views/MIDI/InlinePianoRollView.swift`

---

### US-007: Container Overlap and Crossfade

**Description:** As a user, I want to drag a container on top of another so it cuts into the sibling. Overlapping regions automatically create a crossfade that can be manually adjusted.

**Acceptance Criteria:**
- [ ] Dragging container A's right edge over container B's left edge trims B's start and creates an overlap region
- [ ] The overlap region automatically generates a crossfade (A fades out, B fades in)
- [ ] Default crossfade length equals the overlap amount
- [ ] Crossfade type defaults to equal-power (S-curve)
- [ ] Visual crossfade indicator (X pattern or gradient) in overlap region
- [ ] User can manually adjust crossfade length by dragging crossfade boundary handles
- [ ] User can change crossfade curve type (linear, equal-power, S-curve) via context menu
- [ ] Moving a container away removes the crossfade
- [ ] Crossfade audio renders correctly during playback
- [ ] Add `Crossfade` model to LoopsCore with duration, curveType, container references
- [ ] Crossfade data persists with the project

**Key Files:**
- `Sources/LoopsCore/Models/Container.swift`
- `Sources/LoopsCore/Models/FadeSettings.swift`
- New: `Sources/LoopsCore/Models/Crossfade.swift`
- `Sources/LoopsApp/Views/Timeline/ContainerView.swift`
- `Sources/LoopsApp/ViewModels/ProjectViewModel.swift`

**Technical Notes:**
- Equal-power crossfade: `gainA = cos(t * π/2)`, `gainB = sin(t * π/2)`
- Container model has `startBar` and `lengthBars` — overlap means `containerA.endBar > containerB.startBar`

---

### US-008: Multi-Select Containers

**Description:** As a user, I want to select multiple containers using Cmd+Click (toggle) and Shift+Click (range), then operate on them as a group.

**Acceptance Criteria:**
- [ ] Cmd+Click on a container adds/removes it from multi-selection set
- [ ] Shift+Click selects all containers between last-selected and clicked (same track, by startBar)
- [ ] Multi-selected containers show selection highlight (blue border)
- [ ] Dragging any selected container moves all selected containers, preserving relative positions
- [ ] Delete key removes all selected containers
- [ ] Cmd+A selects all containers on focused track (or all if no track focused)
- [ ] Clicking empty space deselects all
- [ ] Context menu operations apply to all selected containers

**Key Files:**
- `Sources/LoopsApp/ViewModels/SelectionState.swift`
- `Sources/LoopsApp/Views/Timeline/ContainerView.swift`
- `Sources/LoopsApp/ViewModels/ProjectViewModel.swift`

---

### US-009: Multi-Select Tracks

**Description:** As a user, I want to select multiple tracks for batch operations.

**Acceptance Criteria:**
- [ ] Cmd+Click on track headers adds/removes tracks from multi-selection
- [ ] Shift+Click selects a range of tracks
- [ ] Multi-selected tracks show highlight in track header
- [ ] Batch operations: solo all, mute all, delete all, set color
- [ ] Dragging a selected track header reorders all selected tracks as a group
- [ ] Add `selectedTrackIDs: Set<TypedID<Track>>` to SelectionState

**Key Files:**
- `Sources/LoopsApp/ViewModels/SelectionState.swift`
- `Sources/LoopsApp/Views/Timeline/` — track header views

---

### US-011: Glue / Consolidate Containers

**Description:** As a user, I want to glue multiple containers into one. Empty space between becomes silence.

**Acceptance Criteria:**
- [ ] Select 2+ containers on same track → context menu "Glue" / Cmd+J
- [ ] Merges into one container spanning earliest startBar to latest endBar
- [ ] Empty gaps become silence in merged audio
- [ ] Audio containers: offline-render merged result to new CAF file
- [ ] MIDI containers: merge note sequences with correct timing offsets
- [ ] Automation lanes merged with re-offset breakpoints
- [ ] Original containers replaced by single merged container
- [ ] Undo support
- [ ] Requires US-008 (multi-select) to be implemented first

**Key Files:**
- `Sources/LoopsEngine/Audio/OfflineRenderer.swift`
- `Sources/LoopsApp/ViewModels/ProjectViewModel.swift`
- `Sources/LoopsCore/Models/Container.swift`

---

### US-012: Selected Container Shadow (Pro Tools Style)

**Description:** When a container is selected, display a subtle shadow overlay extending over neighboring containers and empty space.

**Acceptance Criteria:**
- [ ] Selected container casts gradient shadow extending left and right (20-30px)
- [ ] Shadow is semi-transparent (10-15% opacity dark gradient)
- [ ] Shadow only on the selected container
- [ ] Shadow does not interfere with click targets on neighbors (`allowsHitTesting(false)`)
- [ ] Shadow renders efficiently (no per-frame recomputation)
- [ ] Visible on both light and dark backgrounds

**Key Files:**
- `Sources/LoopsApp/Views/Timeline/ContainerView.swift`
