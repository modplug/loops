> Sub-PRD of prd-pro-daw. Parallel worktree: audio-analysis-ui.

# Sub-PRD: Audio Analysis & UI Polish — Transients, Piano Roll & Info Pane

## Overview

Implement audio transient detection with snap-to-transient and beat slicing, redesign the piano roll keyboard to Bitwig-style, and add an Ableton-style info pane. These changes span audio analysis (new TransientDetector), piano roll views, and a new info pane system.

## Quality Gates

- `swift build` — Compiles without errors
- `swift test` — All unit tests pass
- `swiftlint` — No lint violations

## User Stories

### US-003: Audio Transient Detection

**Description:** Detect audio transients and display them as markers on the waveform.

**Acceptance Criteria:**
- [ ] Transient detection via spectral flux or energy-based onset detection
- [ ] Analyze audio on import (async, background thread), cache results
- [ ] Thin vertical markers on waveform in ContainerView
- [ ] User-adjustable sensitivity threshold (0.0–1.0)
- [ ] Markers update on threshold change (re-filter, don't re-analyze)
- [ ] Toggle display on/off per track or globally
- [ ] Data stored per SourceRecording
- [ ] Uses Accelerate/vDSP for performance
- [ ] Tests: click track → verify transient positions match expected beats

**Key Files:**
- New: `Sources/LoopsEngine/Audio/TransientDetector.swift`
- `Sources/LoopsEngine/Audio/WaveformGenerator.swift`
- `Sources/LoopsApp/Views/Timeline/ContainerView.swift`
- New: `Tests/LoopsEngineTests/TransientDetectionTests.swift`

---

### US-004: Snap-to-Transient & Tab-to-Transient

**Description:** Magnetic cursor snapping to transients and keyboard navigation between transients.

**Acceptance Criteria:**
- [ ] Cursor snaps when within N pixels of transient (default 8px, configurable 4-16px)
- [ ] Snap works during split, trim, crop operations
- [ ] Tab: jump to next transient on selected track
- [ ] Shift+Tab: jump to previous transient
- [ ] Transient snap priority over grid snap when in range
- [ ] Visual highlight on snapped transient
- [ ] Works in timeline and inline container editing

**Key Files:**
- `Sources/LoopsApp/ViewModels/TimelineViewModel.swift`
- `Sources/LoopsApp/Views/Timeline/ContainerView.swift`
- `Sources/LoopsApp/Views/Timeline/CursorOverlayView.swift`

**Blocked by:** US-003 (Transient Detection)

---

### US-005: Beat Slicing from Transients

**Description:** Slice audio containers at detected transients for beat rearrangement and audio-to-MIDI.

**Acceptance Criteria:**
- [ ] Context menu: "Slice at Transients"
- [ ] Splits container into sub-containers at each transient position
- [ ] Sub-containers reference same source recording with adjusted offsets
- [ ] Option: audio-to-MIDI (one MIDI note per transient, velocity from amplitude)
- [ ] Sensitivity threshold applied before slicing
- [ ] Minimum slice length (default 1/32 note)
- [ ] Undo support

**Key Files:**
- `Sources/LoopsApp/ViewModels/ProjectViewModel.swift`
- `Sources/LoopsCore/Models/Container.swift`
- `Sources/LoopsEngine/Audio/TransientDetector.swift`

**Blocked by:** US-003 (Transient Detection)

---

### US-008: Bitwig-Style Piano Roll Keyboard

**Description:** Replace the 2-octave playable keyboard with a full-range keyboard indicator sidebar with note names and key coloring.

**Acceptance Criteria:**
- [ ] Full-range keyboard indicator spanning visible pitch range
- [ ] Note names (e.g., "C4", "F#3") with mini piano key visual per row
- [ ] White keys: light row background; black keys: darker row background
- [ ] C notes bold with stronger divider (octave boundary)
- [ ] Width: ~48pt (same as current)
- [ ] Click key row → preview note (MIDI note-on/off to instrument)
- [ ] Scrolls with piano roll content
- [ ] Works in both sheet and inline piano roll
- [ ] Row height matches editorState settings

**Key Files:**
- `Sources/LoopsApp/Views/MIDI/VirtualKeyboardView.swift` (replace)
- `Sources/LoopsApp/Views/MIDI/PianoRollView.swift`
- `Sources/LoopsApp/Views/MIDI/InlinePianoRollView.swift`
- `Sources/LoopsApp/Views/MIDI/PianoRollContentView.swift`

---

### US-009: Info Pane (Contextual Help on Hover)

**Description:** Persistent info bar at bottom of left sidebar showing contextual help for hovered elements.

**Acceptance Criteria:**
- [ ] Positioned at bottom of left sidebar (below songs/setlist panel)
- [ ] Height: ~60-80pt with subtle top border
- [ ] Toggle on/off via View menu (persisted in UserDefaults)
- [ ] Updates on hover: element name, description, shortcuts, value range
- [ ] Default text when nothing hovered
- [ ] Info entries for all major interactive elements
- [ ] Centralized `InfoPaneContent` registry
- [ ] Concise text: name (bold), description, shortcut

**Key Files:**
- New: `Sources/LoopsApp/ViewModels/InfoPaneManager.swift`
- New: `Sources/LoopsApp/Views/Shared/InfoPaneView.swift`
- Various view files (minor `.onHover` additions)

---

### US-014: Search Everywhere (Universal Command Palette)

**Description:** Raycast/Spotlight-style modal search (Cmd+K) to instantly find and navigate to anything in the project.

**Acceptance Criteria:**
- [ ] Cmd+K opens floating modal overlay centered in window
- [ ] Single text input with instant fuzzy matching
- [ ] Tab categories: All, Tracks, Containers, Effects, Sections, Songs, Commands
- [ ] Searchable: tracks, containers, effects, sections, songs, setlist entries, automation params, commands, MIDI devices, audio files
- [ ] Results show: icon, name, context line, shortcut (for commands)
- [ ] Fuzzy matching with scoring (consecutive chars rank higher)
- [ ] Recent items shown when query is empty
- [ ] Arrow keys navigate, Enter selects, Escape closes
- [ ] Prefix shortcuts: `>` commands, `@` tracks, `#` sections, `/` songs
- [ ] Index updates live on project changes
- [ ] Results within 16ms for 100+ track projects
- [ ] Toggle: Cmd+K while open closes it

**Key Files:**
- New: `Sources/LoopsApp/ViewModels/SearchEverywhereViewModel.swift`
- New: `Sources/LoopsApp/Views/Shared/SearchEverywhereView.swift`
- `Sources/LoopsApp/Views/LoopsRootView.swift`
- `Sources/LoopsApp/Views/MainContentView.swift`

---

### US-015: Centralized Keyboard Shortcut Registry & Customization

**Description:** All keyboard shortcuts managed through a single registry so they appear in Search Everywhere, can be customized, and are consistent.

**Acceptance Criteria:**
- [ ] `ShortcutRegistry` singleton mapping `ShortcutAction` → `KeyboardShortcut` + metadata
- [ ] All existing scattered `.onKeyPress()` migrated to registry
- [ ] Each entry: action, key, modifiers, title, category (Transport, Editing, Navigation, View)
- [ ] Search Everywhere queries registry to show shortcuts next to command results
- [ ] Preferences panel: "Keyboard Shortcuts" tab, grouped by category
- [ ] User can reassign shortcuts (persisted in UserDefaults)
- [ ] Conflict detection on reassign
- [ ] Reset to defaults button
- [ ] Export/import shortcut presets (JSON)
- [ ] Single `.onKeyPress` handler at MainContentView dispatches through registry
- [ ] Menu bar items show correct shortcut labels from registry

**Key Files:**
- New: `Sources/LoopsApp/ViewModels/ShortcutRegistry.swift`
- New: `Sources/LoopsApp/Views/Shared/ShortcutPreferencesView.swift`
- `Sources/LoopsApp/Views/MainContentView.swift`
- `Sources/LoopsApp/Views/Shared/SearchEverywhereView.swift`

**Blocked by:** US-014 (Search Everywhere) — registry feeds shortcut labels into search results
