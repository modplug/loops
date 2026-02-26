# PRD: Pro DAW — Engine Robustness, Audio Tools & Professional UX

## Overview

This PRD transforms Loops from a capable looper into a professional-grade DAW by adding critical audio engine features (plugin delay compensation, low-latency monitoring, transient detection, track freeze), professional UI patterns (expanded track headers with full routing, info pane, Bitwig-style piano roll keyboard, track lane visuals), and comprehensive audio testing infrastructure.

## Goals

- Guarantee timing accuracy with Plugin Delay Compensation (PDC) across all plugin chains
- Enable low-latency recording by bypassing high-latency plugins on monitored tracks
- Provide transient detection with snap-to-transient and beat slicing capabilities
- Add professional track header layout with volume, pan, sends, I/O, and effects visible inline
- Implement Ableton-style info pane for contextual help on hover
- Redesign piano roll keyboard to Bitwig-style full-range indicator
- Add track freeze, clip gain, and LUFS loudness metering
- Build a comprehensive audio test suite to prevent regressions

## Quality Gates

- `swift build` — Compiles without errors
- `swift test` — All unit tests pass
- `swiftlint` — No lint violations

Audio-specific tests:
- Tests requiring audio hardware gated behind `XCTSkipUnless(audioOutputAvailable)`
- Offline rendering tests use `engine.enableManualRenderingMode(.offline)`
- Performance tests use `measure {}` blocks with baselines

## User Stories

### US-001: Plugin Delay Compensation (PDC)

**Description:** As a user, I want all tracks to stay perfectly in sync regardless of plugin latency, even when some tracks have high-latency plugins (linear-phase EQs, lookahead limiters, convolution reverbs).

**Acceptance Criteria:**
- [ ] Query `AVAudioUnit.auAudioUnit.latency` for every plugin in every effect chain
- [ ] Sum per-chain latency: container effects + track effects + master effects
- [ ] Compute maximum latency across all active tracks
- [ ] Apply delay compensation to tracks with lower latency (insert delay buffers or offset scheduling)
- [ ] When a plugin is added/removed/bypassed, recalculate PDC across all tracks
- [ ] Display per-track latency in the track header (e.g., "PDC: 512 smp")
- [ ] Total PDC reported in transport bar (e.g., "PDC: 1024 smp / 23.2ms")
- [ ] Compensation is transparent — user hears no phase offset between tracks
- [ ] Write tests: render two tracks (one with latency plugin, one without), verify sample-aligned output
- [ ] PDC toggle in preferences to disable compensation (for debugging)

**Technical Notes:**
- `AVAudioUnit.auAudioUnit.latency` returns seconds — convert to samples at engine sample rate
- Current scheduling uses `AVAudioTime` with `hostTime` — PDC adds frame offset per track
- `PlaybackScheduler` schedules containers individually — add per-container delay offset based on chain latency difference from max
- Recalculation triggers: effect add/remove, bypass toggle, plugin swap
- Performance: PDC calculation is O(tracks × effects) — cache and invalidate on change

**Key Files:**
- `Sources/LoopsEngine/Playback/PlaybackScheduler.swift`
- `Sources/LoopsEngine/AudioUnit/AudioUnitHost.swift`
- `Sources/LoopsEngine/Audio/AudioEngineManager.swift`

---

### US-002: Low-Latency Monitoring Mode

**Description:** As a user, when recording I want minimal roundtrip latency. The app should automatically bypass high-latency plugins on the recording track so I hear myself with minimal delay.

**Acceptance Criteria:**
- [ ] Global "Low-Latency Monitoring" toggle in transport bar or preferences
- [ ] When enabled and a track is record-armed: temporarily bypass plugins whose latency exceeds a threshold (e.g., >256 samples)
- [ ] Visual indication on bypassed plugins (dimmed/hatched, "LL" badge)
- [ ] When recording stops or track is disarmed: re-enable bypassed plugins
- [ ] Threshold is user-configurable (default 256 samples, options: 64, 128, 256, 512)
- [ ] Low-latency mode does NOT affect playback-only tracks — only the record-armed track
- [ ] PDC recalculates when low-latency mode toggles (since chain latency changes)
- [ ] Works with both audio and MIDI (instrument) recording

**Technical Notes:**
- Query each plugin's latency, compare to threshold
- Bypass via `auAudioUnit.shouldBypassEffect = true` (preserves plugin state)
- Re-enable via `shouldBypassEffect = false` when recording ends
- Track `RecordingManager` arm state changes as triggers
- Interaction with PDC: when LL bypasses plugins, that track's chain latency drops — PDC rebalances

**Key Files:**
- `Sources/LoopsEngine/Playback/PlaybackScheduler.swift`
- `Sources/LoopsEngine/Recording/RecordingManager.swift`
- `Sources/LoopsEngine/AudioUnit/AudioUnitHost.swift`

---

### US-003: Audio Transient Detection

**Description:** As a user, I want the app to detect audio transients (drum hits, note onsets) and display them as markers on the waveform.

**Acceptance Criteria:**
- [ ] Implement transient detection algorithm (onset detection via spectral flux or energy-based approach)
- [ ] Analyze audio files on import (async, background thread) and cache results
- [ ] Transient markers shown as thin vertical lines on the waveform in ContainerView
- [ ] Transient sensitivity threshold: user-adjustable (0.0–1.0 slider in container inspector or toolbar)
- [ ] Markers update when threshold changes (re-filter cached analysis, don't re-analyze)
- [ ] Toggle transient display on/off per track or globally
- [ ] Transient data stored per `SourceRecording` (not per container — shared across clones)
- [ ] Analysis uses Accelerate/vDSP for performance
- [ ] Write tests: known audio file (click track) → verify transient positions match expected beat positions

**Technical Notes:**
- Spectral flux algorithm: STFT with 1024-sample window, 256-sample hop, detect positive flux peaks above threshold
- Alternative: energy-based — sliding window RMS, detect sudden increases
- Use `vDSP.FFT` from Accelerate framework for STFT
- Cache: store as array of sample positions per SourceRecording
- Display: ContainerView waveform Canvas draws vertical lines at transient positions (transformed by zoom/scroll)
- Consider running analysis in `WaveformGenerator` alongside peak generation

**Key Files:**
- New: `Sources/LoopsEngine/Audio/TransientDetector.swift`
- `Sources/LoopsEngine/Audio/WaveformGenerator.swift`
- `Sources/LoopsApp/Views/Timeline/ContainerView.swift`

---

### US-004: Snap-to-Transient & Tab-to-Transient

**Description:** As a user, I want the cursor to snap to nearby transients when hovering near one (magnetic snap), and I want Tab/Shift-Tab to jump between transients.

**Acceptance Criteria:**
- [ ] When cursor is within N pixels of a transient marker, it snaps to the transient position (magnetic)
- [ ] Snap radius configurable (default 8px, range 4-16px)
- [ ] Snap-to-transient works during split, trim, and crop operations
- [ ] Tab key: jump playhead/cursor to next transient on the selected track
- [ ] Shift+Tab: jump to previous transient
- [ ] Transient snapping is independent of grid snapping — both can be active, transient takes priority when in range
- [ ] Visual feedback: transient line highlights when cursor snaps to it
- [ ] Works in both timeline view and inline container editing

**Technical Notes:**
- Transient positions from US-003's cached data
- Convert sample positions to bar positions using `PositionConverter`
- Snap logic: in `TimelineViewModel.snappedBar()`, check transient proximity before grid snap
- Tab-to-transient: filter transients after current playhead position, jump to first

**Key Files:**
- `Sources/LoopsApp/ViewModels/TimelineViewModel.swift`
- `Sources/LoopsApp/Views/Timeline/ContainerView.swift`
- `Sources/LoopsApp/Views/Timeline/CursorOverlayView.swift`

---

### US-005: Beat Slicing from Transients

**Description:** As a user, I want to slice an audio container at all detected transients to create individual hit containers, enabling beat rearrangement and audio-to-MIDI conversion.

**Acceptance Criteria:**
- [ ] Context menu on audio container: "Slice at Transients"
- [ ] Splits container into N sub-containers at each transient position
- [ ] Each sub-container references the same source recording with adjusted `audioStartOffset` and `lengthBars`
- [ ] Option to create MIDI notes from transients (audio-to-MIDI): one MIDI note per transient, velocity from transient amplitude
- [ ] Sensitivity threshold applied before slicing (uses same threshold as US-003)
- [ ] Minimum slice length to avoid micro-slices (configurable, default 1/32 note)
- [ ] Undo support: un-slice restores original container
- [ ] Sliced containers maintain original track assignment

**Technical Notes:**
- Slicing is non-destructive — same source recording, different offset/length
- Audio-to-MIDI: for each transient, create `MIDINoteEvent` at corresponding beat position
- Velocity: normalize transient amplitude (from spectral flux peak) to 0-127
- Minimum slice filter: skip transients closer than `minSliceLength` to previous transient

**Key Files:**
- `Sources/LoopsApp/ViewModels/ProjectViewModel.swift`
- `Sources/LoopsCore/Models/Container.swift`
- New: `Sources/LoopsEngine/Audio/TransientDetector.swift` (extend from US-003)

---

### US-006: Expanded Track Header with Full Routing

**Description:** As a user, I want to see volume, pan, I/O routing, sends, and effects directly in the track header (Ableton arrangement-view style) without opening the inspector.

**Acceptance Criteria:**
- [ ] Track header width expands from 160pt to ~240pt (user-resizable via drag handle)
- [ ] Layout (top to bottom):
  - Track color dot + name + [M] [S] [R] buttons (existing row)
  - Horizontal volume slider with dB readout
  - Pan control with L/C/R readout
  - Input picker dropdown
  - Output picker dropdown
  - Send level knobs (one per bus track, labeled A, B, etc.)
  - Effect chain summary: pill badges for each effect (click to open AU UI)
  - [+] button to add effect
- [ ] Track name is sticky at top when scrolling vertically (stays visible when track is tall)
- [ ] Visual divider line between tracks (1pt, subtle, secondary color at 0.2 opacity)
- [ ] Compact mode toggle: collapse back to minimal header (name + M/S/R only)
- [ ] Volume/pan changes in header sync bidirectionally with mixer and inspector
- [ ] Effect pills show bypass state (dimmed when bypassed)

**Technical Notes:**
- Current `TrackHeaderView` is 160pt with basic controls — extend layout
- Volume slider: map 0..1 gain to dB display (`20 * log10(gain)`)
- Send levels: need `Track.sendLevels: [TypedID<Track>: Float]` or similar model
- Effect pills: derive from `track.insertEffects` array
- Sticky header: use `LazyVStack` pinned section header or `GeometryReader` offset trick

**Key Files:**
- `Sources/LoopsApp/Views/Timeline/TrackHeaderView.swift`
- `Sources/LoopsApp/ViewModels/ProjectViewModel.swift`
- `Sources/LoopsCore/Models/Track.swift`

---

### US-007: Track Lane Visual Improvements

**Description:** As a user, I want clear visual separation between tracks in the timeline with subtle dividers and alternating backgrounds for readability.

**Acceptance Criteria:**
- [ ] 1pt horizontal divider line between each track lane (secondary color at 0.2 opacity)
- [ ] Alternating track lane background tints (even tracks slightly darker, ~0.03 opacity difference)
- [ ] Track header title sticky at top of track when scrolling vertically (if track is taller than viewport, name stays visible)
- [ ] Mute/Solo state reflected in track lane: muted tracks have reduced opacity (0.4), soloed tracks are full opacity with others dimmed
- [ ] Record-armed tracks show subtle red tint in lane background
- [ ] Selected track has accent-color left border (3pt) extending full track height

**Technical Notes:**
- Dividers in `TrackLaneView` — add `Divider()` or custom rectangle between lanes
- Alternating backgrounds: use track index `% 2` for tint
- Sticky header: use `GeometryReader` to detect scroll position, pin track name overlay
- Mute opacity: wrap track lane content in `.opacity(track.isMuted ? 0.4 : 1.0)`

**Key Files:**
- `Sources/LoopsApp/Views/Timeline/TrackLaneView.swift`
- `Sources/LoopsApp/Views/Timeline/TimelineView.swift`
- `Sources/LoopsApp/Views/Timeline/TrackHeaderView.swift`

---

### US-008: Bitwig-Style Piano Roll Keyboard

**Description:** As a user, I want the piano roll to show a full-range keyboard indicator sidebar (like Bitwig) with note names, black/white key coloring, and C-note markers instead of the current 2-octave playable keyboard.

**Acceptance Criteria:**
- [ ] Replace `VirtualKeyboardView` with a full-range keyboard indicator spanning the entire visible pitch range
- [ ] Each row shows: note name (e.g., "C4", "F#3") aligned right, with a mini piano key visual
- [ ] White keys: light background row, black keys: slightly darker background row
- [ ] C notes are bold with a stronger divider line (octave boundary)
- [ ] Keyboard width: ~48pt (same as current `PianoRollLayout.keyboardWidth`)
- [ ] Clicking a key row plays a preview note (sends MIDI note-on/off to the track's instrument)
- [ ] Key indicator scrolls vertically with the piano roll content
- [ ] Works in both sheet piano roll (`PianoRollView`) and inline piano roll (`InlinePianoRollView`)
- [ ] Row height matches `PianoRollLayout.defaultRowHeight` (14pt default, user-adjustable)

**Technical Notes:**
- Current `VirtualKeyboardView` is a 2-octave playable keyboard at bottom — replace
- New view: `PianoKeyIndicatorView` — a Canvas that draws key backgrounds and labels
- Use `PianoRollEditorState.lowPitch` / `highPitch` to determine visible range
- Black key detection: `[1, 3, 6, 8, 10].contains(pitch % 12)`
- C detection: `pitch % 12 == 0`
- Note preview: send MIDI to track's instrument AU via `MIDIDispatcher`

**Key Files:**
- `Sources/LoopsApp/Views/MIDI/VirtualKeyboardView.swift` (replace)
- `Sources/LoopsApp/Views/MIDI/PianoRollView.swift`
- `Sources/LoopsApp/Views/MIDI/InlinePianoRollView.swift`
- `Sources/LoopsApp/Views/MIDI/PianoRollContentView.swift`
- `Sources/LoopsApp/ViewModels/PianoRollEditorState.swift`

---

### US-009: Info Pane (Contextual Help on Hover)

**Description:** As a user, I want a persistent info bar at the bottom of the left panel (below songs/setlist) that shows helpful information about whatever I'm hovering over — what it does, how to use it, keyboard shortcuts, value ranges.

**Acceptance Criteria:**
- [ ] Info pane positioned at the bottom of the left sidebar (below songs/setlist panel)
- [ ] Height: ~60-80pt, with subtle top border
- [ ] Toggle on/off via View menu or keyboard shortcut (persisted in UserDefaults)
- [ ] Content updates on hover: shows element name, description, shortcuts, value range
- [ ] When nothing is hovered: shows general context info ("Select a track to begin editing")
- [ ] Info entries for all major interactive elements:
  - Transport controls (play, stop, record, return-to-start, BPM, time sig)
  - Track header controls (M, S, R, volume, pan, I/O pickers)
  - Timeline operations (container zones: move, resize, trim, fade)
  - Piano roll operations (note editing, velocity, tools)
  - Automation (breakpoints, tools, lanes)
  - Mixer controls (fader, pan, sends)
- [ ] Info text is concise: name (bold), one-line description, shortcut if applicable
- [ ] Info data is centralized (not scattered across views) — single `InfoPaneContent` registry

**Technical Notes:**
- Create `InfoPaneManager` as an `@Observable` singleton holding current `InfoPaneEntry`
- Each view sets `InfoPaneManager.current` via `.onHover()` modifier
- `InfoPaneEntry`: `title: String`, `description: String`, `shortcut: String?`, `valueRange: String?`
- Registry: dictionary of identifiers → `InfoPaneEntry`, populated at app launch
- Avoid per-element `.help()` replacement — this is an additional system, not a replacement for native tooltips
- Performance: `.onHover()` is lightweight, only sets a reference

**Key Files:**
- New: `Sources/LoopsApp/ViewModels/InfoPaneManager.swift`
- New: `Sources/LoopsApp/Views/Shared/InfoPaneView.swift`
- All view files (add `.onHover` info registration)

---

### US-010: Track Freeze / Render-in-Place

**Description:** As a user, I want to freeze a track (bounce all plugins to audio) to free CPU, with the ability to unfreeze later.

**Acceptance Criteria:**
- [ ] Right-click track header → "Freeze Track" / keyboard shortcut
- [ ] Freezing renders the track's output (all containers through all effects) to a single audio file
- [ ] Frozen track: displays the rendered waveform, disables plugin UI, shows snowflake icon
- [ ] Frozen track plays back from rendered file (no plugin processing)
- [ ] "Unfreeze Track" restores original containers and effect chain
- [ ] Original container data and effect state preserved (stored alongside freeze file)
- [ ] Freeze file stored in project bundle
- [ ] Cannot edit containers on a frozen track (visual indication: dimmed, "Frozen" overlay)
- [ ] Volume and pan still adjustable on frozen tracks (post-freeze mix controls)
- [ ] Freeze accounts for automation (automation is baked into the rendered audio)

**Technical Notes:**
- Use `OfflineRenderer` to bounce the track — it already handles effects and fades
- Store freeze file as `.caf` in project bundle: `freeze-{trackID}.caf`
- Track model: add `isFrozen: Bool` and `freezeRecordingID: TypedID<SourceRecording>?`
- Frozen playback: create single container spanning full track length, referencing freeze file
- Unfreeze: restore original containers from preserved data

**Key Files:**
- `Sources/LoopsEngine/Audio/OfflineRenderer.swift`
- `Sources/LoopsCore/Models/Track.swift`
- `Sources/LoopsApp/ViewModels/ProjectViewModel.swift`
- `Sources/LoopsEngine/Persistence/ProjectBundle.swift`

---

### US-011: Clip Gain / Pre-Fader Gain

**Description:** As a user, I want a gain control on each container (separate from track volume) for level-matching before the fader, visible as a horizontal line on the waveform.

**Acceptance Criteria:**
- [ ] Each container has a `clipGain` property (default 1.0 / 0 dB)
- [ ] Visual: thin horizontal line across the container waveform at the gain level
- [ ] Drag the gain line up/down to adjust (range: -inf to +12 dB)
- [ ] Gain value shown on hover (e.g., "-3.2 dB")
- [ ] Double-click gain line resets to 0 dB
- [ ] Clip gain is applied before the effect chain (pre-fader, pre-effects)
- [ ] Waveform visual scales with clip gain (higher gain = taller waveform display)
- [ ] Works on both audio and MIDI containers (MIDI: adjusts velocity scaling)
- [ ] Clip gain shown in container inspector
- [ ] Write tests: verify offline render with clip gain produces correct amplitude

**Technical Notes:**
- Container model: add `clipGain: Float = 1.0`
- Apply in `PlaybackScheduler` when scheduling: multiply audio buffer by `clipGain` or use gain node
- Most efficient: insert `AVAudioUnitEQ` with single band as gain stage, or use `AVAudioMixerNode` volume
- Waveform display: scale peaks by `clipGain` in `ContainerView` Canvas drawing
- Gain line: horizontal line at `y = laneHeight * (1.0 - normalizedGainLevel)`

**Key Files:**
- `Sources/LoopsCore/Models/Container.swift`
- `Sources/LoopsApp/Views/Timeline/ContainerView.swift`
- `Sources/LoopsEngine/Playback/PlaybackScheduler.swift`

---

### US-012: LUFS Loudness Metering

**Description:** As a user, I want integrated LUFS, short-term LUFS, and true-peak metering on the master track for broadcast/streaming compliance.

**Acceptance Criteria:**
- [ ] Master track meter shows: Integrated LUFS, Short-term LUFS (3s window), Momentary LUFS (400ms window), True Peak (dBTP)
- [ ] Meter display in mixer strip for master track (replaces or augments existing level meter)
- [ ] Integrated LUFS accumulates from play start to stop (resets on play)
- [ ] Color coding: green (safe), yellow (approaching limit), red (over target)
- [ ] Target level configurable (default -14 LUFS for streaming, -23 LUFS for broadcast)
- [ ] True peak meter shows max since last reset
- [ ] Click to reset peak and integrated values
- [ ] Meter updates at display frame rate (~60 FPS) for short-term, less frequently for integrated
- [ ] Write tests: known audio file → verify LUFS measurement matches reference value (±0.5 LU tolerance)

**Technical Notes:**
- LUFS calculation per ITU-R BS.1770-4:
  1. Pre-filter: two biquad stages (high-shelf K-weighting)
  2. Mean square per channel per gate block (400ms)
  3. Channel-weighted sum: L=1, R=1, C=1, Ls=1.41, Rs=1.41
  4. Loudness = -0.691 + 10 * log10(sum)
  5. Gating: absolute gate at -70 LUFS, relative gate at -10 LU below ungated
- Install audio tap on master mixer node for real-time metering
- True peak: 4x oversampled peak detection per ITU-R BS.1770
- Performance: K-weighting filters are cheap (2 biquads), run on audio render thread

**Key Files:**
- New: `Sources/LoopsEngine/Audio/LoudnessMeter.swift`
- `Sources/LoopsApp/Views/Mixer/LevelMeterView.swift`
- `Sources/LoopsApp/Views/Mixer/MixerStripView.swift`

---

### US-013: Comprehensive Audio Test Suite

**Description:** As a developer, I want a robust audio test suite covering scheduling, sync, PDC, rendering, and loudness to prevent regressions and performance degradation.

**Acceptance Criteria:**
- [ ] Test categories:
  - **Sync tests**: Multiple tracks of identical audio → phase cancellation verification
  - **PDC tests**: Tracks with different chain latencies → output alignment verification
  - **Scheduling tests**: Container start/stop at exact sample positions
  - **Fade tests**: Enter/exit fades produce correct gain envelopes
  - **Automation tests**: Breakpoint interpolation produces correct values
  - **Offline render tests**: Rendered output matches expected reference
  - **Loudness tests**: Known signals → verified LUFS/true-peak values
  - **Transient tests**: Known signals (click tracks) → verified transient positions
  - **Performance tests**: Scheduling 100+ containers completes within time budget
- [ ] All offline tests use `engine.enableManualRenderingMode(.offline)`
- [ ] Hardware-dependent tests gated behind `XCTSkipUnless(audioOutputAvailable)`
- [ ] Performance tests use `measure {}` with baselines
- [ ] Test helper: `AudioTestHelper` with utilities for generating test signals (sine, click, silence, noise)
- [ ] Test helper: buffer comparison with tolerance (sample-by-sample amplitude check)
- [ ] Minimum 80% code coverage for `PlaybackScheduler` scheduling logic

**Technical Notes:**
- Test signal generation: `vDSP.fill(with: sine(frequency:sampleRate:))` for reference tones
- Phase cancellation test: mix two channels to mono → if in-phase, peaks double; if out-of-phase, near-silence
- PDC test: introduce known-latency dummy plugin (or simulate), verify output alignment
- Reference `OfflineRenderer` for offline engine setup patterns

**Key Files:**
- New: `Tests/LoopsEngineTests/AudioTestHelper.swift`
- New: `Tests/LoopsEngineTests/AudioSyncTests.swift`
- New: `Tests/LoopsEngineTests/PDCTests.swift`
- New: `Tests/LoopsEngineTests/LoudnessTests.swift`
- New: `Tests/LoopsEngineTests/TransientDetectionTests.swift`
- Existing: `Tests/LoopsEngineTests/PlaybackSchedulerTests.swift`

---

### US-014: Search Everywhere (Universal Command Palette)

**Description:** As a user, I want a Raycast/Spotlight-style modal search (Cmd+K) that lets me instantly find and navigate to anything in my project: tracks, containers, effects, sections, songs, commands, and more.

**Acceptance Criteria:**
- [ ] Cmd+K opens a floating modal overlay centered in the window (like Raycast/VS Code command palette)
- [ ] Single text input with instant fuzzy matching as you type
- [ ] Tab-based category filters at the top: All, Tracks, Containers, Effects, Sections, Songs, Commands
- [ ] **Searchable entities:**
  - **Tracks**: by name, kind (audio/midi/bus/backing), number → selects track, scrolls to it
  - **Containers/Regions**: by name, source recording filename, position (e.g., "Bar 12") → selects container, scrolls to it
  - **Effects/Plugins**: by displayName, plugin type → opens AU UI or scrolls to track
  - **Sections**: by name → jumps playhead to section start
  - **Songs**: by name → switches active song
  - **Setlist entries**: by song name → navigates to entry
  - **Automation parameters**: by parameter name, effect name → expands automation lane
  - **Commands/Actions**: "Solo Track 3", "Freeze Track", "Add EQ", "Toggle Metronome", "Zoom to Fit" → executes action
  - **MIDI devices**: by name → navigates to MIDI routing
  - **Audio files**: by source recording filename → highlights containers using that recording
- [ ] Results show: icon (entity type), name, context line (e.g., "Track 3 > Container > Bar 5-12"), keyboard shortcut (for commands)
- [ ] Fuzzy matching: "drm" matches "Drum Bus", "kik" matches "Kick Track"
- [ ] Most recently used items appear first when modal opens with empty query
- [ ] Arrow keys navigate results, Enter selects, Escape closes
- [ ] Modal closes after action is taken (navigation or command execution)
- [ ] Prefix shortcuts for power users:
  - `>` — commands only (like VS Code)
  - `@` — tracks only
  - `#` — sections only
  - `/` — songs/setlist only
- [ ] Search index updates live as project changes (tracks added/removed, containers moved, etc.)
- [ ] Performance: results appear within 16ms of keystroke for projects with 100+ tracks
- [ ] Cmd+K while modal is open → closes it (toggle behavior)
- [ ] Works when timeline, mixer, or piano roll is focused

**Technical Notes:**
- **Search index**: `SearchIndex` class in LoopsApp that observes `ProjectViewModel` changes and maintains a flat array of `SearchableItem` entries. Each entry has: `id`, `category: SearchCategory`, `title: String`, `subtitle: String?`, `keywords: [String]`, `action: () -> Void`
- **Fuzzy matching**: Use a simple subsequence match with scoring (consecutive chars score higher). No need for external dependencies — implement in ~30 lines
- **Command registry**: Static list of all available commands with their actions. Commands that require context (e.g., "Solo Track 3") are generated dynamically from current project state
- **Modal placement**: ZStack overlay in `LoopsRootView` after `UndoToastView`
- **Keyboard trigger**: `.onKeyPress("k", modifiers: .command)` in `MainContentView` — Cmd+K is unused, guard with `!isTextFieldFocused`
- **Result limit**: Show max 10 results at a time with smooth scrolling for more
- **Recent items**: Store last 10 selected items in UserDefaults for "recently used" when query is empty
- **Entity type icons**: SF Symbols — `waveform` (tracks), `rectangle` (containers), `slider.horizontal.3` (effects), `flag` (sections), `music.note.list` (songs), `command` (commands)
- **Performance**: Pre-compute search index on project load, update incrementally on mutations. Fuzzy match is O(n * query.length) — fast enough for 1000+ items

**Key Files:**
- New: `Sources/LoopsApp/ViewModels/SearchEverywhereViewModel.swift`
- New: `Sources/LoopsApp/Views/Shared/SearchEverywhereView.swift`
- `Sources/LoopsApp/Views/LoopsRootView.swift` (overlay placement)
- `Sources/LoopsApp/Views/MainContentView.swift` (Cmd+K handler)
- `Sources/LoopsApp/ViewModels/ProjectViewModel.swift` (data source for index)

---

### US-015: Centralized Keyboard Shortcut Registry & Customization

**Description:** As a user, I want all keyboard shortcuts managed through a single registry so they appear in Search Everywhere results, can be customized, and are consistent across the app. As a developer, I want to define shortcuts in one place instead of scattering `.onKeyPress()` across views.

**Acceptance Criteria:**
- [ ] `ShortcutRegistry` singleton that maps `ShortcutAction` (enum) → `KeyboardShortcut` + metadata
- [ ] All existing shortcuts migrated from scattered `.onKeyPress()` calls to the registry:
  - Transport: Space (play/pause), Enter (open editor), R (record arm), M (metronome toggle)
  - Editing: Cmd+C (copy), Cmd+V (paste), Cmd+Z (undo), Cmd+Shift+Z (redo), Delete (remove)
  - Navigation: Arrow keys, Home/End, 1-8 (select track by number)
  - Zoom: +/- (zoom in/out)
  - New: Cmd+K (Search Everywhere), Cmd+J (Glue), Tab/Shift+Tab (transient nav)
- [ ] Each registry entry: `action: ShortcutAction`, `keyEquivalent: KeyEquivalent`, `modifiers: EventModifiers`, `title: String`, `category: String` (Transport, Editing, Navigation, View, etc.)
- [ ] Search Everywhere (#158) queries the registry to show shortcuts next to command results
- [ ] Preferences panel: "Keyboard Shortcuts" tab showing all shortcuts grouped by category
- [ ] User can reassign shortcuts (stored in UserDefaults, overrides defaults)
- [ ] Conflict detection: warn if a shortcut is already assigned to another action
- [ ] Reset to defaults button
- [ ] Export/import shortcut presets (JSON file)
- [ ] Views consume shortcuts via registry: `ShortcutRegistry.shared.handle(key:modifiers:)` returns the action to execute
- [ ] Menu bar items automatically show correct shortcut labels from registry

**Technical Notes:**
- `ShortcutAction` enum: one case per action (~40-60 actions). Groups: transport, editing, navigation, view, tools
- Registry pattern: `[ShortcutAction: ShortcutBinding]` where `ShortcutBinding` has `key`, `modifiers`, `title`, `category`
- Default bindings defined as static dictionary, user overrides loaded from UserDefaults on launch
- Single `.onKeyPress` handler at MainContentView level that dispatches through registry
- Menu bar integration: `.keyboardShortcut()` modifier reads from registry for consistent labels
- Search Everywhere integration: command results include `shortcutBinding.displayString` (e.g., "⌘K", "Space", "⇧⌘Z")
- Conflict detection: on reassign, check `registry.values.contains(where: { $0.key == newKey && $0.modifiers == newModifiers })`

**Key Files:**
- New: `Sources/LoopsApp/ViewModels/ShortcutRegistry.swift`
- New: `Sources/LoopsApp/Views/Shared/ShortcutPreferencesView.swift`
- `Sources/LoopsApp/Views/MainContentView.swift` (consolidate handlers)
- `Sources/LoopsApp/Views/Shared/SearchEverywhereView.swift` (display shortcuts)

---

## Module Independence Map

| Module Group | Stories | Key Files/Areas | Independent From |
|---|---|---|---|
| **[PDC-Engine]** | US-001, US-002, US-013 | PlaybackScheduler, AudioUnitHost, AudioEngineManager, RecordingManager, new test files | [UI-TrackHeader], [UI-PianoRoll], [UI-InfoPane] |
| **[Audio-Analysis]** | US-003, US-004, US-005 | TransientDetector (new), WaveformGenerator, TimelineViewModel, ContainerView | [UI-TrackHeader], [UI-PianoRoll], [UI-InfoPane] |
| **[UI-TrackHeader]** | US-006, US-007 | TrackHeaderView, TrackLaneView, TimelineView, Track model | [PDC-Engine], [UI-PianoRoll] |
| **[UI-PianoRoll]** | US-008 | VirtualKeyboardView, PianoRollView, InlinePianoRollView, PianoRollContentView | [PDC-Engine], [UI-TrackHeader] |
| **[UI-InfoPane]** | US-009 | InfoPaneManager (new), InfoPaneView (new), all view files (minor .onHover additions) | [PDC-Engine], [Audio-Analysis] |
| **[UI-Search]** | US-014, US-015 | SearchEverywhereViewModel (new), SearchEverywhereView (new), ShortcutRegistry (new), LoopsRootView, MainContentView | [PDC-Engine], [Audio-Analysis], [Track-Tools] |
| **[Track-Tools]** | US-010, US-011, US-012 | OfflineRenderer, Track model, Container model, LoudnessMeter (new), MixerStripView | Partially overlaps [PDC-Engine] via PlaybackScheduler |

**Dependency Notes:**
- US-002 (Low-Latency Monitoring) depends on US-001 (PDC) — uses the same latency calculation
- US-004 (Snap-to-Transient) depends on US-003 (Transient Detection) — needs transient data
- US-005 (Beat Slicing) depends on US-003 (Transient Detection) — needs transient data
- US-013 (Test Suite) should be implemented alongside US-001 (PDC) for immediate coverage
- US-009 (Info Pane) touches many view files with minor additions — low conflict risk but broad surface area
