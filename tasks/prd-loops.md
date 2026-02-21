# PRD: Loops — A macOS Live Looper DAW

## Overview

Loops is a native macOS application for live looping musicians. It combines the timeline-based arrangement of a traditional DAW (like Bitwig or Pro Tools) with a purpose-built looping workflow. Musicians define song templates with tracks, parts, and containers on a timeline — then perform live without touching the interface. The app auto-records into containers, reuses recordings across linked containers, and manages an entire setlist for hands-free live shows.

## Goals

- Provide a timeline-based looper that eliminates manual loop triggering during live performance
- Support auto-recording with linked containers so one take populates an entire song arrangement
- Enable full setlist management with configurable transitions between songs
- Host Audio Unit insert effects and instruments natively
- Support MIDI control for transport and foot pedal workflows
- Deliver professional-grade audio latency via AVAudioEngine

## Quality Gates

These commands must pass for every user story:
- `swift build` — Project compiles without errors
- `swift test` — All unit tests pass

For UI stories, also include:
- Manual visual verification that the UI renders correctly

## User Stories

### US-001: Create Swift/SwiftUI project scaffold
**Description:** As a developer, I want a clean SPM-compatible Xcode project so that the app has a solid foundation to build on.

**Acceptance Criteria:**
- [ ] macOS app target using SwiftUI App lifecycle
- [ ] Minimum deployment target macOS 14 (Sonoma)
- [ ] Project compiles and launches an empty window
- [ ] SPM package structure with separate modules: `LoopsApp` (UI), `LoopsEngine` (audio), `LoopsCore` (shared models)
- [ ] Basic test targets for each module

### US-002: Core audio engine initialization
**Description:** As a musician, I want the app to initialize a reliable audio engine so that I can record and play back audio through my audio interface.

**Acceptance Criteria:**
- [ ] AVAudioEngine initializes on app launch
- [ ] Default system input/output device selected automatically
- [ ] Engine handles sample rates of 44.1kHz and 48kHz
- [ ] Engine starts and stops cleanly without crashes
- [ ] Audio device changes (plugging in an interface) are handled gracefully
- [ ] Unit tests verify engine lifecycle (init, start, stop, restart)

### US-003: Audio device selection
**Description:** As a musician, I want to select my audio input and output devices so that I can use my preferred audio interface.

**Acceptance Criteria:**
- [ ] Settings/preferences view lists available input devices
- [ ] Settings/preferences view lists available output devices
- [ ] Selecting a device switches the engine to that device
- [ ] Buffer size is configurable (64, 128, 256, 512, 1024 samples)
- [ ] Current device and buffer size persists across app restarts

### US-004: Project data model and persistence
**Description:** As a musician, I want my songs and setlists saved to disk so that I can close the app and resume later.

**Acceptance Criteria:**
- [ ] `Song` model: name, tempo (BPM), time signature, tracks, containers
- [ ] `Track` model: name, type (audio/MIDI/bus), volume, pan, mute, solo, insert effect chain, send levels
- [ ] `Container` model: position (bar), length (bars), loop settings, source recording reference, independent effects/mix overrides
- [ ] `SourceRecording` model: reference to audio file on disk, sample rate, length
- [ ] `Setlist` model: ordered list of songs with per-transition settings
- [ ] `Project` model: contains multiple songs and setlists
- [ ] Project saved as a folder bundle (`.loops` extension) containing JSON metadata + audio files (CAF format)
- [ ] Unit tests verify serialization round-trip (encode → decode → equality)

### US-005: Timeline view — track layout
**Description:** As a musician, I want to see a horizontal timeline with vertically stacked tracks so that I can arrange my song structure visually.

**Acceptance Criteria:**
- [ ] Horizontal timeline with bar/beat grid based on song BPM and time signature
- [ ] Tracks stacked vertically with track headers on the left (name, type icon, mute/solo buttons)
- [ ] Timeline is scrollable horizontally (time) and vertically (tracks)
- [ ] Playhead (vertical line) indicates current position
- [ ] Zoom in/out on the timeline (horizontal zoom)
- [ ] Bar numbers displayed at the top ruler

### US-006: Track management
**Description:** As a musician, I want to add, remove, and configure tracks so that I can build my song template.

**Acceptance Criteria:**
- [ ] Add new track (audio, MIDI, or bus/send) via menu or button
- [ ] Remove track with confirmation dialog
- [ ] Rename track by double-clicking the track header name
- [ ] Reorder tracks via drag and drop in the track header area
- [ ] Track type is visually distinct (different icons/colors for audio, MIDI, bus)

### US-007: Container creation and editing on timeline
**Description:** As a musician, I want to place and resize containers on the timeline so that I can define where loops occur in my arrangement.

**Acceptance Criteria:**
- [ ] Create a container by clicking and dragging on a track's timeline area
- [ ] Container snaps to bar/beat grid
- [ ] Resize container by dragging left/right edges
- [ ] Move container by dragging the body
- [ ] Delete container via right-click context menu or Delete key
- [ ] Container displays its name, length in bars, and loop settings visually
- [ ] Containers cannot overlap on the same track

### US-008: Container loop settings
**Description:** As a musician, I want to configure loop behavior per container so that each section of my song can behave differently.

**Acceptance Criteria:**
- [ ] Container inspector panel (sidebar or popover) shows loop settings when container is selected
- [ ] Loop count setting: number of times the recorded audio loops within the container (or "fill" to loop until container ends)
- [ ] Boundary mode per container: hard cut, crossfade (with configurable duration in ms), or overdub (layers stack on each repeat)
- [ ] Settings saved to the container model and persisted

### US-009: Linked containers
**Description:** As a musician, I want to link containers so that a recording made in one container is reused everywhere it's linked, while each instance can have its own effects and mix settings.

**Acceptance Criteria:**
- [ ] Link containers by selecting multiple containers and choosing "Link" from context menu
- [ ] Linked containers share the same `SourceRecording` reference
- [ ] Linked containers display a visual indicator (same color or icon) showing they are linked
- [ ] Each linked container retains independent volume, pan, and effect override settings
- [ ] Recording into any linked container updates the shared source recording for all linked instances
- [ ] Unlinking a container creates an independent copy of the source recording

### US-010: Transport controls
**Description:** As a musician, I want play, stop, record, and position controls so that I can navigate and control playback of my arrangement.

**Acceptance Criteria:**
- [ ] Play/pause button starts/stops playback from the playhead position
- [ ] Stop button stops playback and returns playhead to the beginning
- [ ] Record arm button (global) enables recording when playback enters a record-enabled container
- [ ] Click on timeline ruler moves the playhead to that position
- [ ] BPM display with editable tempo field
- [ ] Time signature display (e.g., 4/4, 3/4)
- [ ] Metronome toggle with audible click on the beat

### US-011: Auto-record into containers
**Description:** As a musician, I want the app to automatically start and stop recording when the playhead enters and exits a container that is armed for recording, so that I can perform without touching the interface.

**Acceptance Criteria:**
- [ ] Per-container record-arm toggle (visual indicator on the container)
- [ ] When global record is armed and playback enters a record-armed container, recording begins automatically from the audio input
- [ ] Recording stops when the playhead exits the container's time range
- [ ] Recorded audio is saved as a CAF file inside the project bundle
- [ ] The container's `SourceRecording` reference is updated to point to the new recording
- [ ] If the container is linked, all linked containers now reference the new recording
- [ ] Visual waveform appears in the container during and after recording
- [ ] If a container already has a recording, re-recording replaces it (with undo support)

### US-012: Audio playback of containers
**Description:** As a musician, I want containers to play back their recorded audio in sync with the timeline so that I hear my arrangement as designed.

**Acceptance Criteria:**
- [ ] Containers with a source recording play audio when the playhead passes through them
- [ ] Audio is sample-accurately synced to the bar/beat grid
- [ ] Looping within a container works according to the container's loop settings
- [ ] Hard cut boundary mode: audio stops/starts cleanly at boundaries
- [ ] Crossfade boundary mode: configurable crossfade applied at loop points
- [ ] Overdub boundary mode: each loop pass is layered on top of the previous
- [ ] Empty containers (no recording) produce silence
- [ ] Track volume, pan, mute, and solo affect playback

### US-013: Track mixer — volume, pan, mute, solo
**Description:** As a musician, I want basic mixing controls per track so that I can balance my live arrangement.

**Acceptance Criteria:**
- [ ] Volume fader per track (in dB, range -inf to +6 dB)
- [ ] Pan knob per track (L-R)
- [ ] Mute button per track (silences output)
- [ ] Solo button per track (silences all non-soloed tracks)
- [ ] Level meter per track showing real-time audio level
- [ ] Master output level meter and volume fader

### US-014: Audio Unit insert effects hosting
**Description:** As a musician, I want to load Audio Unit effects on my tracks so that I can add reverb, delay, and other processing.

**Acceptance Criteria:**
- [ ] Per-track insert effect chain displayed in a track inspector or mixer view
- [ ] "Add Effect" button shows a list of installed Audio Unit effect plugins (type: `kAudioUnitType_Effect`)
- [ ] Selected AU plugin loads and its UI can be opened in a floating window
- [ ] Audio from the track routes through the insert chain in order
- [ ] Effects can be reordered via drag and drop
- [ ] Effects can be bypassed individually
- [ ] Effects can be removed from the chain
- [ ] Effect parameters are saved with the project

### US-015: Audio Unit instrument hosting (for MIDI tracks)
**Description:** As a musician, I want to load Audio Unit instruments on MIDI tracks so that I can use software synths and samplers.

**Acceptance Criteria:**
- [ ] MIDI tracks have an instrument slot (one AU instrument per MIDI track)
- [ ] "Set Instrument" shows a list of installed Audio Unit instruments (type: `kAudioUnitType_MusicDevice`)
- [ ] Selected AU instrument loads and its UI can be opened in a floating window
- [ ] MIDI input is routed to the instrument, audio output is routed to the track's signal chain
- [ ] Instrument parameters are saved with the project

### US-016: Bus/send track routing
**Description:** As a musician, I want bus/send tracks so that I can route multiple tracks to shared effects like reverb or delay.

**Acceptance Criteria:**
- [ ] Bus tracks appear in the track list like other tracks
- [ ] Each audio/MIDI track has configurable send levels to each bus track
- [ ] Bus tracks have their own insert effect chain
- [ ] Bus track output is mixed into the master output
- [ ] Send level is adjustable (0% to 100%) per track per bus

### US-017: Sidebar song browser
**Description:** As a musician, I want a sidebar listing all songs in my project so that I can navigate between songs quickly.

**Acceptance Criteria:**
- [ ] Left sidebar shows a list of all songs in the current project
- [ ] Selecting a song loads its timeline in the main editor area
- [ ] Double-clicking a song opens it for editing (same as selecting)
- [ ] Right-click context menu: rename, duplicate, delete (with confirmation)
- [ ] "New Song" button at the bottom of the song list
- [ ] Songs display name and BPM
- [ ] Sidebar is collapsible

### US-018: Setlist / playlist management
**Description:** As a musician, I want to create and manage setlists so that I can plan the song order for my live shows.

**Acceptance Criteria:**
- [ ] "Playlist" tab in the sidebar (alongside the song browser)
- [ ] Create a new setlist with a name
- [ ] Add songs from the project to the setlist
- [ ] Reorder songs in the setlist via drag and drop
- [ ] Remove songs from the setlist
- [ ] Per-transition settings between songs: seamless (gapless), configurable gap (silence duration in seconds), or manual advance (wait for trigger)
- [ ] Multiple setlists per project

### US-019: Setlist playback mode
**Description:** As a musician, I want to play through a setlist in order during a live performance so that I can run an entire show hands-free.

**Acceptance Criteria:**
- [ ] "Perform" mode activated from a setlist (full-screen or focused view)
- [ ] Current song plays through its timeline
- [ ] When a song finishes, transition behavior executes (seamless, gap, or manual advance)
- [ ] For manual advance: a clear "Next Song" indicator and trigger (spacebar, MIDI, or on-screen button)
- [ ] Display shows current song name, next song name, and progress
- [ ] Perform mode can be exited back to the editor

### US-020: MIDI learn for transport controls
**Description:** As a musician, I want to map MIDI controls to transport functions so that I can control the app with my foot pedals and controllers.

**Acceptance Criteria:**
- [ ] MIDI learn mode: click a transport control, then press/send a MIDI CC or note to map it
- [ ] Mappable controls: play/pause, stop, record arm, next song, previous song, metronome toggle
- [ ] MIDI mappings saved per project
- [ ] MIDI mappings display shows current assignments
- [ ] Clear mapping option per control

### US-021: Foot pedal presets
**Description:** As a musician, I want preset MIDI mappings for common looper pedals so that setup is fast.

**Acceptance Criteria:**
- [ ] Preset selector in MIDI settings (e.g., "Generic 2-button pedal", "Generic 4-button pedal")
- [ ] Each preset maps common pedal buttons to transport controls
- [ ] Presets are a starting point and can be customized after loading
- [ ] At least 2 built-in presets for common configurations

### US-022: Waveform display in containers
**Description:** As a musician, I want to see waveforms in containers so that I can visually identify recordings on the timeline.

**Acceptance Criteria:**
- [ ] Containers with audio display a waveform overview
- [ ] Waveform generates from the source recording's audio data
- [ ] Waveform scales with container zoom level
- [ ] Waveform updates in real-time during recording
- [ ] Linked containers show the same waveform

### US-023: Import audio files into containers
**Description:** As a musician, I want to drag audio files onto the timeline so that I can use pre-recorded material in my arrangements.

**Acceptance Criteria:**
- [ ] Drag and drop audio files (WAV, AIFF, CAF, MP3, M4A) from Finder onto a track's timeline
- [ ] Audio is imported and converted to CAF inside the project bundle
- [ ] A new container is created at the drop position with the imported audio as its source recording
- [ ] Imported audio is time-stretched or trimmed to fit the container's bar grid (or container auto-sizes to fit the audio)
- [ ] File → Import Audio menu option as alternative to drag and drop

### US-024: Backing track support
**Description:** As a musician, I want a dedicated backing track type so that I can play pre-recorded tracks alongside my live loops without looping behavior.

**Acceptance Criteria:**
- [ ] "Backing Track" track type available when adding a new track
- [ ] Backing tracks play audio linearly (no looping) — the audio plays once from the track start
- [ ] Audio files can be dragged onto a backing track
- [ ] Backing tracks have the same mixer controls (volume, pan, mute, solo)
- [ ] Backing tracks have insert effect support
- [ ] Backing tracks are visually distinct from loop tracks

### US-025: Undo/Redo system
**Description:** As a musician, I want undo and redo so that I can recover from mistakes during editing and recording.

**Acceptance Criteria:**
- [ ] Cmd+Z undoes the last action
- [ ] Cmd+Shift+Z redoes the last undone action
- [ ] Undoable actions: container create/delete/move/resize, track add/remove, recording, parameter changes
- [ ] Undo stack persists for the current session (cleared on project close)
- [ ] Edit menu shows "Undo [action name]" and "Redo [action name]"

### US-026: Audio export
**Description:** As a musician, I want to export my arrangement as an audio file so that I can share or distribute my recorded performance.

**Acceptance Criteria:**
- [ ] File → Export Audio menu option
- [ ] Export renders the full timeline to a single audio file
- [ ] Export format options: WAV (16/24-bit, 44.1/48kHz) and AIFF
- [ ] Export is offline (faster than real-time)
- [ ] Progress indicator during export
- [ ] Exported file includes all tracks, effects, and mix settings

## Functional Requirements

- FR-1: The audio engine must initialize AVAudioEngine with configurable input/output devices and buffer sizes
- FR-2: Audio recording must write to CAF files inside the project bundle directory
- FR-3: Playback must be sample-accurately synchronized to the bar/beat grid based on the song's BPM and time signature
- FR-4: Linked containers must reference the same SourceRecording; updating one updates all
- FR-5: Each container must independently store volume, pan, and effect override settings
- FR-6: Auto-record must trigger when the playhead enters a record-armed container during record-armed playback
- FR-7: The container boundary mode (hard cut, crossfade, overdub) must be applied during playback looping
- FR-8: Audio Unit plugins must be loaded via AVAudioUnitComponent and hosted in the AVAudioEngine graph
- FR-9: Bus/send routing must use AVAudioMixerNode with per-track send levels
- FR-10: The project must be saved as a `.loops` folder bundle containing a `project.json` metadata file and an `audio/` subdirectory for CAF files
- FR-11: Setlist playback must respect per-transition settings (seamless, gap, manual advance) between songs
- FR-12: MIDI input must be received via CoreMIDI and routed to mapped controls or AU instruments
- FR-13: The app must handle audio device hot-plugging without crashing

## Non-Goals (Out of Scope)

- **Multi-track simultaneous recording** — v1 records one input at a time
- **Time-stretching / pitch-shifting** — imported audio must match the project tempo manually
- **Video sync** — no video playback or sync features
- **Collaboration / cloud sync** — single-user, local projects only
- **Windows or Linux support** — macOS only
- **Plugin format support beyond AU** — no VST3, AAX, or CLAP in v1 (AU only)
- **Advanced MIDI editing** — no piano roll or MIDI sequence editor in v1
- **Per-track MIDI mapping** — v1 maps MIDI to transport and pedal controls only

## Technical Considerations

- **Audio Engine:** AVAudioEngine with `AVAudioSession` for device management. Core Audio for low-level device enumeration.
- **Module structure:** Three SPM modules — `LoopsApp` (SwiftUI views), `LoopsEngine` (audio engine, AU hosting, MIDI), `LoopsCore` (models, serialization, shared types)
- **Thread safety:** Audio engine callbacks run on a real-time thread. UI updates must be dispatched to the main thread. Use `@MainActor` for view models.
- **File format:** CAF for internal audio storage. WAV/AIFF for export.
- **AU hosting:** Use `AVAudioUnitComponentManager` to discover plugins. Load via `AVAudioUnit.instantiate(with:options:)`.
- **MIDI:** CoreMIDI for MIDI input. `MIDIClientCreate`, `MIDIInputPortCreate` for receiving messages.
- **Persistence:** Codable structs serialized to JSON. Project bundle is a directory with `.loops` extension registered as a document type.

## Success Metrics

- A musician can define a 4-song setlist, each with 3-5 sections (intro, verse, chorus, bridge, outro)
- The musician can perform the entire setlist by pressing "Play" once and only using foot pedals
- Auto-recording captures audio into containers without manual interaction
- Linked containers correctly replay recorded material throughout the arrangement
- Audio latency is under 10ms with a 256-sample buffer at 48kHz
- All Audio Unit effects and instruments load and function correctly

## Open Questions

- Should container effect overrides be full insert chains or just parameter tweaks (e.g., wet/dry, volume)?
- What's the maximum realistic track count before performance degrades with AVAudioEngine?
- Should v2 include a "rehearsal mode" where you can practice individual sections in a loop?
- Should we support AAF/OMF export for moving projects to other DAWs?
