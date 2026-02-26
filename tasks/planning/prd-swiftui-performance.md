# PRD: SwiftUI Performance — Observable Blast Radius & View Memoization

## Problem Statement

The Loops UI feels sluggish during normal operation. The root cause is not SwiftUI itself but specific architectural patterns that trigger excessive view re-evaluation:

- **Monolithic ProjectViewModel**: A single 2,500-line `@Observable` class holding 43+ properties — selection state, clipboard data, undo history, live recording peaks, export sheet state, and MIDI learning targets. Changing any property (e.g. `selectedContainerID`) forces every view that reads any property from this object to re-evaluate — including the entire timeline, inspector, and mixer.
- **60fps playhead cascading through view tree**: `TimelineViewModel.playheadBar` updates 60 times per second. Although a direct callback pattern exists (`onPlayheadChanged`), the TimelineView still holds `@Bindable var viewModel: TimelineViewModel` and re-evaluates its entire body (including all TrackLaneViews and ContainerViews) on every tick.
- **No view memoization**: Zero `EquatableView` or manual `Equatable` conformances on any view in the codebase. SwiftUI's default structural diffing is applied everywhere, including heavy views like ContainerView (528 lines, 12+ closure params) and TrackLaneView (25+ closure params).
- **MixerView dictionary observation**: `mixerViewModel.trackLevels[track.id]` — reading from an `@Observable` dictionary in a `ForEach` means any single track's level change re-evaluates the entire mixer.
- **No lazy stacking**: Timeline tracks and mixer strips use eager `VStack` / `ScrollView` + `ForEach` — all tracks render even when scrolled off screen.
- **PlayheadView has no identity optimization**: A simple Rectangle recomputed 60 times per second with no Equatable short-circuit.

The app already has good patterns in place (Canvas-based waveform rendering, direct callbacks for some real-time data), but the @Observable blast radius undermines them.

## Solution

Reduce unnecessary SwiftUI view re-evaluations by splitting monolithic state, isolating high-frequency updates, and adding view memoization:

1. **Split ProjectViewModel** into focused, single-responsibility observable objects (SelectionState, ClipboardState, UndoState, ExportState, MIDILearnState) so that a selection change doesn't invalidate the undo history UI or mixer.
2. **Isolate playhead rendering** from the main view tree — use a dedicated overlay that reads playhead position without triggering parent re-evaluation. SwiftUI's `TimelineView` scheduler or a `CADisplayLink`-backed approach that only touches the playhead layer.
3. **Add Equatable conformance** to key container and track views so SwiftUI can skip re-evaluation when inputs haven't changed.
4. **Per-track level isolation** in the mixer — each MixerStripView should observe only its own track's level, not the entire dictionary.
5. **Lazy stacking** for track lists and mixer strips to avoid rendering off-screen content.
6. **Throttle meter updates** — coalesce audio level updates to 30fps instead of per-buffer.

## User Stories

1. As a user, I want the UI to respond instantly when I click a track or container, so that the app feels snappy during editing.
2. As a user, I want playback to not cause visible lag in the inspector or mixer panels, so that the UI stays responsive while music is playing.
3. As a user, I want scrolling through many tracks in the timeline to be smooth, so that I can navigate large projects without stutter.
4. As a user, I want the mixer faders and meters to animate smoothly without causing the rest of the UI to lag, so that level monitoring doesn't degrade editing performance.
5. As a user, I want selecting a different container to update only the inspector — not cause the timeline waveforms to flicker or re-render, so that selection feels lightweight.
6. As a user, I want the playhead to move smoothly at 60fps without causing the track area or inspector to re-evaluate, so that playback animation is decoupled from editing state.
7. As a user, I want undo/redo operations to not cause the entire UI to flash or stutter, so that the undo workflow feels instant.
8. As a user, I want zooming the timeline to only re-render visible tracks, so that zoom gestures remain responsive in large projects.
9. As a user, I want opening the export sheet or toggling MIDI learn mode to not trigger re-renders of unrelated views like the timeline or mixer.
10. As a user, I want the app to remain responsive with 20+ tracks, each containing multiple containers with waveforms and automation, so that real production projects don't degrade the UI.

## Implementation Decisions

### Modules

**SelectionState** — Extracted from ProjectViewModel. Holds `selectedContainerID`, `selectedContainerIDs`, `selectedTrackID`, `selectedSectionID`. Only views that display selection highlighting or the inspector observe this object.

**ClipboardState** — Extracted from ProjectViewModel. Holds `clipboard`, `clipboardBaseBar`, `clipboardSectionRegion`. Only paste-related UI observes this.

**UndoState** — Extracted from ProjectViewModel. Holds `undoHistory`, `undoHistoryCursor`, `undoToastMessage`. Only the undo panel and toast observe this.

**ProjectViewModel (slimmed)** — Retains core project data (`project`, `projectURL`, `hasUnsavedChanges`, `songs`, `tracks`) and mutation methods. Dramatically fewer properties means fewer spurious invalidations.

**PlayheadOverlay** — A standalone view that renders the playhead line. Receives position updates through a direct callback or `TimelineView` scheduler, isolated from the rest of the timeline view tree so playhead movement doesn't trigger TrackLaneView or ContainerView re-evaluation.

**MixerStripViewModel** — Per-track observable that holds a single track's level and peak. MixerStripView observes only its own instance. The parent MixerView no longer holds a dictionary of all levels.

### Architectural approach

- Use `@Observable` granularity as the primary tool — SwiftUI's observation tracking means splitting state into multiple objects is the most effective way to reduce blast radius.
- Prefer composition over inheritance — each extracted state object is a plain `@Observable` class, not a subclass.
- Keep the existing direct-callback pattern for real-time data but ensure views that hold `@Bindable` references to ViewModels don't accidentally subscribe to high-frequency properties.
- Add `Equatable` conformance to view inputs (not the views themselves) using wrapper structs where closure-heavy views can't conform directly.
- Use `LazyVStack` in the timeline and mixer `ForEach` loops.

### Migration strategy

Each vertical slice is independently shippable. The ProjectViewModel extraction slices can be done one state group at a time — extract SelectionState, update all call sites, verify, then move to ClipboardState, etc. No big-bang refactor.

## Testing Decisions

### What to test

- **Behavior, not implementation**: Tests verify that state changes propagate correctly (e.g. selecting a container updates the inspector's displayed data), not that specific SwiftUI view bodies are called.
- **State isolation**: After splitting ViewModels, verify that mutating one state object doesn't trigger observers of another.
- **Regression**: Ensure all existing tests pass after each extraction — the public API of ProjectViewModel should remain stable even as internals are extracted.

### Modules to test

- **SelectionState**: Selection logic (single select, multi-select, deselect) extracted from ProjectViewModel
- **UndoState**: Undo/redo cursor management
- **MixerStripViewModel**: Level update coalescing and peak hold behavior

### Prior art

- Existing `ProjectViewModelTests` in the test suite — these should continue to pass after extraction, verifying the refactor is behavior-preserving.

## Out of Scope

- Rewriting any views in AppKit/NSView — this PRD is purely SwiftUI optimization
- Adding Instruments/profiling tooling to the project
- GPU-accelerated waveform rendering (Metal/CALayer) — a future PRD if needed after these optimizations
- Refactoring the engine layer or audio processing pipeline
- Changing the data model or persistence layer
- Adding new user-facing features — this is purely a performance refactor

## Further Notes

- The codebase already uses Canvas for waveform/grid/automation rendering, which is good. This PRD builds on that foundation by fixing the observation layer above it.
- The direct-callback pattern in `LoopsAppEntry.swift` for playhead and recording peaks is the right idea — this PRD extends that pattern and makes it more robust.
- `swift build` and `swift test` must pass after every slice. No slice should break compilation or existing tests.
