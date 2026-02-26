> Sub-PRD of prd-daw-polish. Parallel worktree: automation.

# Sub-PRD: Automation — Snapping, Toolbar, Shapes & Marquee Selection

## Overview

Make automation editing intuitive with proper grid-aware snapping, add a shaping toolbar with line/curve/LFO tools, and implement marquee selection for automation breakpoints. These changes are confined to automation views and LoopsCore automation models.

## Quality Gates

- `swift build` — Compiles without errors
- `swift test` — All unit tests pass
- `swiftlint` — No lint violations

## User Stories

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

**Key Files:**
- `Sources/LoopsApp/Views/Timeline/AutomationSubLaneView.swift`
- `Sources/LoopsApp/Views/Timeline/AutomationCoordinateMapping.swift` (if exists, or inline in SubLaneView)
- `Sources/LoopsCore/Models/AutomationLane.swift`
- `Sources/LoopsCore/Models/MIDISequence.swift` (SnapResolution, GridMode)

---

### US-005: Automation Toolbar with Shaping Tools

**Description:** As a user, I want a toolbar above the automation lane with tools for drawing shapes: pointer, line, curve, ramp, S-curve, sine, triangle, and square.

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
- [ ] Toolbar is positioned at the leading edge of the automation lane (always visible)

**Key Files:**
- `Sources/LoopsApp/Views/Timeline/AutomationSubLaneView.swift`
- New: `Sources/LoopsCore/Models/AutomationShapeGenerator.swift` — pure math for shape generation
- New: `Sources/LoopsApp/Views/Timeline/AutomationToolbarView.swift`

**Shape Math:**
- Sine: `value = 0.5 + 0.5 * sin(2π * t / period)`
- Triangle: `value = 2 * abs(2 * (t/period - floor(t/period + 0.5)))`
- Square: `value = t % period < period/2 ? 1.0 : 0.0`
- Line: linear interpolation between start and end values
- Exponential curve: `value = start + (end - start) * pow(t, 3)`
- S-Curve: `value = start + (end - start) * (3t² - 2t³)`

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
- [ ] Visual: selected breakpoints use a distinct color (e.g., filled accent color vs outlined)
- [ ] Add automation breakpoint selection state to the automation editing state

**Key Files:**
- `Sources/LoopsApp/Views/Timeline/AutomationSubLaneView.swift`
- `Sources/LoopsApp/ViewModels/` — automation editing state (may need new file or extend existing)
