# Manual QA Checklist — DAW Polish (PRD #131)

## Pre-QA
- [ ] All ralph loops exited with COMPLETE
- [ ] All 12 GitHub issues (#132-#143) are closed
- [ ] `swift build` passes on merged code
- [ ] `swift test` passes on merged code
- [ ] `swiftlint` passes on merged code
- [ ] No uncommitted changes
- [ ] All 3 worktree branches merged into main cleanly

## Functional QA

### Engine & Transport

**#132 — Multi-Track Audio Sync**
- [ ] Import 10 audio files as 10 tracks, all starting at bar 1
- [ ] Import the same 10 files again as 10 more tracks, also starting at bar 1
- [ ] Press play — all 20 tracks must be perfectly in sync (no flanging/phasing)
- [ ] Repeat with tracks starting at bar 5 — still perfectly in sync
- [ ] Stop and start multiple times — sync is consistent every time
- [ ] Try with different audio file lengths and formats (WAV, CAF, AIFF)

**#133 — Return-to-Start**
- [ ] Toggle return-to-start button ON (back arrow next to stop)
- [ ] Place playhead at bar 5, press play, let it run to bar 12, press stop → playhead returns to bar 5
- [ ] While playing from bar 5, seek to bar 20 → stop → playhead still returns to bar 5 (not bar 20)
- [ ] At bar 5 (returned position), press stop again → playhead goes to bar 1
- [ ] Toggle return-to-start OFF → play from bar 5, stop at bar 12 → playhead stays at bar 12
- [ ] Quit and relaunch app → return-to-start toggle state is preserved
- [ ] Verify no debug print statements appear in console

### Automation

**#134 — Automation Snapping**
- [ ] Open an automation lane, set grid to 1/4 notes → breakpoints snap to quarter-note positions
- [ ] Switch grid to 1/16 → breakpoints snap to sixteenth-note positions
- [ ] Switch to adaptive mode → snapping adapts with zoom level
- [ ] Hold Cmd while dragging a breakpoint → fine-grained movement (snap disabled)
- [ ] Verify value snapping: dB parameters snap to 0.5 dB, percentage to 1%, pan to integers
- [ ] Grid lines in automation lane match the current snap resolution

**#135 — Automation Toolbar & Shapes**
- [ ] Expand an automation lane → toolbar appears above it
- [ ] Select Line tool → click start point, click end point → straight line of breakpoints generated
- [ ] Select Curve tool → generates exponential curve between two points
- [ ] Select S-Curve → generates smooth S-curve between two points
- [ ] Select Sine → click start, drag to end → sine wave breakpoints generated
- [ ] Select Triangle → periodic triangle wave
- [ ] Select Square → periodic square wave
- [ ] Shape replaces existing breakpoints in the drawn range only
- [ ] Cmd+Z undoes shape drawing
- [ ] Toolbar shows lane name and parameter info

**#136 — Marquee Selection for Automation**
- [ ] Click-drag on empty space in automation lane → marquee rectangle appears
- [ ] Release → breakpoints inside marquee are selected (distinct visual style)
- [ ] Drag selected breakpoints → all move as a group preserving relative positions
- [ ] Press Delete → all selected breakpoints removed
- [ ] Cmd+Click individual breakpoints → toggle selection
- [ ] Cmd+A → selects all breakpoints in the lane

### Containers & UI

**#137 — Timeline Performance**
- [ ] Create 20+ tracks with 5+ containers each (100+ total)
- [ ] Scroll horizontally — smooth, no stutter
- [ ] Scroll vertically — smooth, no stutter
- [ ] Zoom in/out with +/- keys — responsive, no lag
- [ ] Pinch-zoom on trackpad — smooth
- [ ] Scroll while playing back — no impact on audio

**#138 — Piano Roll Tools Positioning**
- [ ] Open inline piano roll for a MIDI container
- [ ] Scroll the piano roll content horizontally → toolbar stays pinned at right edge
- [ ] Toolbar does not disappear off-screen at any zoom level
- [ ] Toolbar is accessible next to the inspector area

**#139 — Container Crossfade**
- [ ] Drag container A's right edge over container B → B's start trims, overlap creates crossfade
- [ ] Visual crossfade indicator (X or gradient) appears in overlap region
- [ ] Play through crossfade region → smooth transition, both containers audible
- [ ] Drag crossfade boundary handles → crossfade length adjusts
- [ ] Right-click crossfade → change curve type (linear, equal-power, S-curve)
- [ ] Move container away → crossfade removed
- [ ] Save and reload project → crossfade preserved

**#140 — Multi-Select Containers**
- [ ] Cmd+Click containers → each is added/removed from selection (blue border)
- [ ] Shift+Click → selects range of containers on same track
- [ ] Drag any selected container → all selected move together
- [ ] Press Delete → all selected containers removed
- [ ] Cmd+A → selects all containers on focused track
- [ ] Click empty space → all deselected
- [ ] Right-click on multi-selection → context menu applies to all

**#141 — Multi-Select Tracks**
- [ ] Cmd+Click track headers → multiple tracks selected (highlighted)
- [ ] Shift+Click → range selection
- [ ] Batch solo → all selected tracks soloed
- [ ] Batch mute → all selected tracks muted
- [ ] Batch delete → all selected tracks deleted (with confirmation)

**#142 — Glue / Consolidate**
- [ ] Select 2+ adjacent audio containers on same track → Cmd+J or context menu "Glue"
- [ ] Containers merge into one spanning the full range
- [ ] Gaps between containers become silence
- [ ] Play the merged container → sounds correct (continuous audio with silence in gaps)
- [ ] Cmd+Z → undoes glue, original containers restored
- [ ] Test with MIDI containers → notes merged correctly

**#143 — Selected Container Shadow**
- [ ] Click a container between two siblings → subtle shadow extends over neighbors
- [ ] Shadow is ~20-30px wide, semi-transparent gradient
- [ ] Shadow does not block clicks on neighboring containers
- [ ] Click a different container → shadow moves to new selection
- [ ] Deselect → shadow disappears
- [ ] Verify shadow visible in both light and dark mode

## Integration QA (Cross-Worktree)
- [ ] Multi-select containers (#140) + crossfade (#139): Select overlapping containers, verify crossfade UI is correct
- [ ] Multi-select (#140) + glue (#142): Multi-select 3 containers, glue them
- [ ] Automation snap (#134) + performance (#137): Edit automation while 100+ containers are visible — no lag
- [ ] Return-to-start (#133) + audio sync (#132): Return-to-start with 20 synced tracks — all restart in sync
- [ ] Piano roll position (#138) + performance (#137): Open piano roll with many tracks — smooth scrolling

## Edge Cases
- [ ] Crossfade with containers on different tracks — should NOT create crossfade
- [ ] Glue containers from different tracks — should be disabled/error
- [ ] Multi-select + move that would create overlap — handle gracefully
- [ ] Automation marquee select with zero breakpoints — no crash
- [ ] Return-to-start during recording — should still work correctly
- [ ] Zoom to extreme levels (8 PPB and 2400 PPB) — all features still functional
- [ ] Empty project (no tracks/containers) — no crashes from selection/automation code
