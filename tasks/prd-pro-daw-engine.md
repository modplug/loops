> Sub-PRD of prd-pro-daw. Parallel worktree: pdc-engine.

# Sub-PRD: PDC Engine — Plugin Delay Compensation, Low-Latency Monitoring & Audio Test Suite

## Overview

Implement Plugin Delay Compensation (PDC) to keep all tracks in sync regardless of plugin latency, add low-latency monitoring mode for recording, and build a comprehensive audio test suite. These changes are confined to the engine layer (PlaybackScheduler, AudioUnitHost, RecordingManager) and test files.

## Quality Gates

- `swift build` — Compiles without errors
- `swift test` — All unit tests pass
- `swiftlint` — No lint violations

## User Stories

### US-001: Plugin Delay Compensation (PDC)

**Description:** Keep all tracks in sync regardless of plugin latency.

**Acceptance Criteria:**
- [ ] Query `AVAudioUnit.auAudioUnit.latency` for every plugin in every effect chain
- [ ] Sum per-chain latency: container effects + track effects + master effects
- [ ] Compute maximum latency across all active tracks
- [ ] Apply delay compensation to tracks with lower latency
- [ ] Recalculate PDC when plugins are added/removed/bypassed
- [ ] Display per-track latency in track header (e.g., "PDC: 512 smp")
- [ ] Total PDC in transport bar
- [ ] Write tests: render two tracks (one with latency plugin, one without), verify sample-aligned output
- [ ] PDC toggle in preferences

**Key Files:**
- `Sources/LoopsEngine/Playback/PlaybackScheduler.swift`
- `Sources/LoopsEngine/AudioUnit/AudioUnitHost.swift`
- `Sources/LoopsEngine/Audio/AudioEngineManager.swift`

---

### US-002: Low-Latency Monitoring Mode

**Description:** Bypass high-latency plugins on record-armed tracks for minimal roundtrip latency.

**Acceptance Criteria:**
- [ ] Global "Low-Latency Monitoring" toggle
- [ ] When enabled + track record-armed: bypass plugins exceeding threshold (default 256 samples)
- [ ] Visual indication on bypassed plugins ("LL" badge)
- [ ] Re-enable plugins when recording stops
- [ ] Threshold configurable (64, 128, 256, 512 samples)
- [ ] Only affects record-armed track
- [ ] PDC recalculates when LL toggles

**Key Files:**
- `Sources/LoopsEngine/Playback/PlaybackScheduler.swift`
- `Sources/LoopsEngine/Recording/RecordingManager.swift`
- `Sources/LoopsEngine/AudioUnit/AudioUnitHost.swift`

**Blocked by:** US-001 (PDC)

---

### US-013: Comprehensive Audio Test Suite

**Description:** Build a robust audio test suite covering sync, PDC, scheduling, rendering, and loudness.

**Acceptance Criteria:**
- [ ] Sync tests: phase cancellation verification
- [ ] PDC tests: output alignment with different chain latencies
- [ ] Scheduling tests: exact sample positions
- [ ] Fade tests: correct gain envelopes
- [ ] Automation tests: correct interpolation values
- [ ] Performance tests with `measure {}` baselines
- [ ] `AudioTestHelper` for test signal generation and buffer comparison
- [ ] All offline tests use manual rendering mode
- [ ] Hardware tests gated behind `XCTSkipUnless`

**Key Files:**
- New: `Tests/LoopsEngineTests/AudioTestHelper.swift`
- New: `Tests/LoopsEngineTests/AudioSyncTests.swift`
- New: `Tests/LoopsEngineTests/PDCTests.swift`
- Existing: `Tests/LoopsEngineTests/PlaybackSchedulerTests.swift`
