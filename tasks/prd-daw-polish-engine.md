> Sub-PRD of prd-daw-polish. Parallel worktree: engine-transport.

# Sub-PRD: Engine & Transport — Audio Sync and Return-to-Start

## Overview

Fix multi-track audio sync to guarantee sample-accurate playback, and implement reliable return-to-start transport behavior. These changes are confined to the engine and transport layers with no UI view file modifications.

## Quality Gates

- `swift build` — Compiles without errors
- `swift test` — All unit tests pass
- `swiftlint` — No lint violations

## User Stories

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

**Key Files:**
- `Sources/LoopsEngine/Playback/PlaybackScheduler.swift`
- `Sources/LoopsEngine/Audio/AudioEngineManager.swift`
- `Tests/` — new test files for sync verification

---

### US-003: Return-to-Start Transport Behavior

**Description:** As a user, when the return-to-start button is toggled on, pressing stop should return the playhead to where play was originally pressed.

**Acceptance Criteria:**
- [ ] When return-to-start is enabled and user presses Play at bar 5, then stops at bar 12 — playhead returns to bar 5
- [ ] When return-to-start is enabled and user seeks during playback (e.g., jumps to bar 20), the return position stays at bar 5 (original play position)
- [ ] Pressing stop a second time (already at return position) moves playhead to bar 1.0
- [ ] When return-to-start is disabled, stop leaves playhead at current position
- [ ] Return-to-start state persists across app sessions (UserDefaults)
- [ ] Return-to-start button in toolbar has clear visual toggle state (on/off)
- [ ] Write unit tests for TransportManager covering all return-to-start scenarios
- [ ] Remove debug print statements from TransportViewModel (`[RETURN-TO-START]` prints)

**Key Files:**
- `Sources/LoopsEngine/Playback/TransportManager.swift`
- `Sources/LoopsApp/ViewModels/TransportViewModel.swift`
