> Sub-PRD of prd-pro-daw. Parallel worktree: track-ui-tools.

# Sub-PRD: Track UI & Tools — Headers, Lanes, Freeze, Clip Gain & LUFS Metering

## Overview

Redesign track headers to show full routing (Ableton-style), improve track lane visuals, add track freeze, clip gain, and LUFS loudness metering. These changes span track header/lane views, Track/Container models, OfflineRenderer, and mixer views.

## Quality Gates

- `swift build` — Compiles without errors
- `swift test` — All unit tests pass
- `swiftlint` — No lint violations

## User Stories

### US-006: Expanded Track Header with Full Routing

**Description:** Show volume, pan, I/O routing, sends, and effects directly in the track header.

**Acceptance Criteria:**
- [ ] Track header width expands to ~240pt (user-resizable)
- [ ] Layout: name + M/S/R, volume slider with dB, pan with L/C/R, input picker, output picker, send knobs, effect pills with [+] button
- [ ] Track name sticky at top when scrolling vertically
- [ ] Visual divider between tracks (1pt, subtle)
- [ ] Compact mode toggle (name + M/S/R only)
- [ ] Volume/pan sync bidirectionally with mixer and inspector
- [ ] Effect pills show bypass state

**Key Files:**
- `Sources/LoopsApp/Views/Timeline/TrackHeaderView.swift`
- `Sources/LoopsApp/ViewModels/ProjectViewModel.swift`
- `Sources/LoopsCore/Models/Track.swift`

---

### US-007: Track Lane Visual Improvements

**Description:** Clear visual separation between tracks with dividers, alternating backgrounds, and state indicators.

**Acceptance Criteria:**
- [ ] 1pt horizontal divider between each track lane
- [ ] Alternating track lane background tints
- [ ] Track header title sticky at top of track
- [ ] Muted tracks: reduced opacity (0.4); soloed tracks: full opacity, others dimmed
- [ ] Record-armed tracks: subtle red tint
- [ ] Selected track: accent-color left border (3pt)

**Key Files:**
- `Sources/LoopsApp/Views/Timeline/TrackLaneView.swift`
- `Sources/LoopsApp/Views/Timeline/TimelineView.swift`
- `Sources/LoopsApp/Views/Timeline/TrackHeaderView.swift`

---

### US-010: Track Freeze / Render-in-Place

**Description:** Bounce a track's output to audio to free CPU, with ability to unfreeze.

**Acceptance Criteria:**
- [ ] Right-click header → "Freeze Track" / shortcut
- [ ] Renders all containers through all effects to single audio file
- [ ] Frozen: shows rendered waveform, disables plugin UI, snowflake icon
- [ ] Plays from rendered file (no plugin processing)
- [ ] "Unfreeze" restores original containers and effects
- [ ] Original data preserved alongside freeze file
- [ ] Freeze file in project bundle
- [ ] Cannot edit containers while frozen (dimmed, "Frozen" overlay)
- [ ] Volume/pan still adjustable
- [ ] Automation baked into rendered audio

**Key Files:**
- `Sources/LoopsEngine/Audio/OfflineRenderer.swift`
- `Sources/LoopsCore/Models/Track.swift`
- `Sources/LoopsApp/ViewModels/ProjectViewModel.swift`
- `Sources/LoopsEngine/Persistence/ProjectBundle.swift`

---

### US-011: Clip Gain / Pre-Fader Gain

**Description:** Per-container gain control (separate from track volume) visible as a line on the waveform.

**Acceptance Criteria:**
- [ ] Container has `clipGain` property (default 1.0 / 0 dB)
- [ ] Thin horizontal line on waveform at gain level
- [ ] Drag up/down to adjust (range: -inf to +12 dB)
- [ ] Value shown on hover (dB)
- [ ] Double-click resets to 0 dB
- [ ] Applied pre-fader, pre-effects
- [ ] Waveform visual scales with clip gain
- [ ] Shown in container inspector
- [ ] Tests: offline render with clip gain → correct amplitude

**Key Files:**
- `Sources/LoopsCore/Models/Container.swift`
- `Sources/LoopsApp/Views/Timeline/ContainerView.swift`
- `Sources/LoopsEngine/Playback/PlaybackScheduler.swift`

---

### US-012: LUFS Loudness Metering

**Description:** Integrated LUFS, short-term LUFS, and true-peak metering on the master track.

**Acceptance Criteria:**
- [ ] Master meter: Integrated LUFS, Short-term (3s), Momentary (400ms), True Peak (dBTP)
- [ ] Display in master mixer strip
- [ ] Integrated LUFS accumulates play→stop (resets on play)
- [ ] Color coding: green (safe), yellow (approaching), red (over target)
- [ ] Target configurable (-14 LUFS streaming, -23 LUFS broadcast)
- [ ] True peak shows max since reset
- [ ] Click to reset
- [ ] ~60 FPS updates
- [ ] Tests: known audio → verified LUFS (±0.5 LU tolerance)

**Key Files:**
- New: `Sources/LoopsEngine/Audio/LoudnessMeter.swift`
- `Sources/LoopsApp/Views/Mixer/LevelMeterView.swift`
- `Sources/LoopsApp/Views/Mixer/MixerStripView.swift`
- New: `Tests/LoopsEngineTests/LoudnessTests.swift`
