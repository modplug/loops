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

---

# Technical Architecture

This section provides the binding technical specification that all implementing agents MUST follow. It defines the exact module structure, data models, engine architecture, view hierarchy, and design constraints.

## 1. SPM Module Structure

### Package.swift

```swift
// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Loops",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LoopsCore", targets: ["LoopsCore"]),
        .library(name: "LoopsEngine", targets: ["LoopsEngine"]),
        .library(name: "LoopsApp", targets: ["LoopsApp"]),
    ],
    targets: [
        .target(
            name: "LoopsCore",
            dependencies: [],
            path: "Sources/LoopsCore"
        ),
        .testTarget(
            name: "LoopsCoreTests",
            dependencies: ["LoopsCore"],
            path: "Tests/LoopsCoreTests"
        ),
        .target(
            name: "LoopsEngine",
            dependencies: ["LoopsCore"],
            path: "Sources/LoopsEngine"
        ),
        .testTarget(
            name: "LoopsEngineTests",
            dependencies: ["LoopsEngine"],
            path: "Tests/LoopsEngineTests"
        ),
        .target(
            name: "LoopsApp",
            dependencies: ["LoopsCore", "LoopsEngine"],
            path: "Sources/LoopsApp"
        ),
        .testTarget(
            name: "LoopsAppTests",
            dependencies: ["LoopsApp"],
            path: "Tests/LoopsAppTests"
        ),
    ]
)
```

### Module Responsibilities

**LoopsCore** — Zero UI or audio dependencies. Only imports Foundation.
- All data model structs (Project, Song, Track, Container, SourceRecording, etc.)
- Codable conformances and serialization helpers
- Enums shared across the app (TrackKind, BoundaryMode, TransitionMode, etc.)
- Generic typed ID type, time/position types, protocol definitions
- Utility extensions on Foundation types

**LoopsEngine** — Imports AVFoundation, CoreMIDI, AudioToolbox, CoreAudio. Depends on LoopsCore.
- AudioEngineManager (AVAudioEngine lifecycle, device routing)
- TrackNode (per-track node subgraph)
- TransportManager (playback state machine, metronome)
- RecordingManager (tap installation, CAF writing)
- AudioUnitHosting (AU discovery, instantiation, parameter persistence)
- BusRouter (send/bus routing logic)
- MIDIManager (CoreMIDI client, port, event dispatch)
- MIDILearnController (learn mode state machine)
- DeviceManager (input/output device enumeration and selection)
- ProjectPersistence (reading/writing .loops bundles to disk)
- WaveformGenerator (audio file analysis for display data)
- OfflineRenderer (bounce/export)

**LoopsApp** — Imports SwiftUI. Depends on LoopsCore and LoopsEngine.
- App entry point (LoopsApp.swift with @main)
- Window and scene management
- All SwiftUI views (timeline, mixer, inspector, sidebar, transport bar, setlist, settings)
- View models annotated with @Observable and @MainActor
- Commands (menu bar items)
- Drag and drop handlers
- Custom SwiftUI shapes and drawing (waveform rendering, grid drawing)

### Dependency Graph

```
LoopsApp  -->  LoopsEngine  -->  LoopsCore
   |                                ^
   +--------------------------------+
```

## 2. Directory Structure

```
loops/
  Package.swift
  .gitignore
  tasks/
    prd-loops.md
  LoopsApp/                          # Xcode app target (thin shell)
    LoopsApp.xcodeproj/
    LoopsApp/
      LoopsAppMain.swift             # @main entry point
      Info.plist
      LoopsApp.entitlements          # Audio input, sandbox exceptions
      Assets.xcassets/
  Sources/
    LoopsCore/
      Models/
        Project.swift
        Song.swift
        Track.swift                  # Track struct + TrackKind enum
        Container.swift
        SourceRecording.swift
        LoopSettings.swift           # LoopSettings struct + BoundaryMode
        Setlist.swift
        SetlistEntry.swift           # SetlistEntry struct + TransitionMode
        MIDIMapping.swift            # MIDIMapping struct + MappableControl
        AudioDeviceSettings.swift
        InsertEffect.swift           # InsertEffect struct (AU parameter state)
        SendLevel.swift
        TimeSignature.swift
        Tempo.swift
      Position/
        BarBeatPosition.swift
        SamplePosition.swift
        PositionConverter.swift
      Identifiers/
        TypedID.swift                # Generic ID<Phantom> type
      Errors/
        LoopsError.swift
    LoopsEngine/
      Audio/
        AudioEngineManager.swift
        DeviceManager.swift
        TrackNode.swift
        BusRouter.swift
        InsertChainManager.swift
        MasterMixer.swift
        MetronomeGenerator.swift
      Recording/
        RecordingManager.swift
        CAFWriter.swift
        WaveformGenerator.swift
      Playback/
        TransportManager.swift
        PlaybackScheduler.swift
        LoopPlaybackController.swift
      AudioUnit/
        AudioUnitDiscovery.swift
        AudioUnitHost.swift
      MIDI/
        MIDIManager.swift
        MIDILearnController.swift
        MIDIDispatcher.swift
        FootPedalPresets.swift
      Persistence/
        ProjectPersistence.swift
        ProjectBundle.swift
        AutoSaveManager.swift
      Export/
        OfflineRenderer.swift
    LoopsApp/
      App/
        LoopsAppEntry.swift          # SwiftUI App struct, WindowGroup, commands
        AppState.swift               # Top-level @Observable app state
      ViewModels/
        ProjectViewModel.swift
        TimelineViewModel.swift
        TransportViewModel.swift
        MixerViewModel.swift
        InspectorViewModel.swift
        SetlistViewModel.swift
        SettingsViewModel.swift
      Views/
        MainWindow/
          MainContentView.swift      # HSplitView: sidebar + center + inspector
          ToolbarView.swift          # Transport bar, BPM, time sig
        Sidebar/
          SidebarView.swift
          SongListView.swift
          SetlistListView.swift
          SetlistEditorView.swift
        Timeline/
          TimelineView.swift
          RulerView.swift
          TrackLaneView.swift
          ContainerView.swift
          PlayheadView.swift
          WaveformView.swift
          GridOverlayView.swift
          TrackHeaderView.swift
        Mixer/
          MixerStripView.swift
          FaderView.swift
          PanKnobView.swift
          LevelMeterView.swift
          SendKnobView.swift
        Inspector/
          InspectorView.swift
          ContainerInspector.swift
          TrackInspector.swift
          InsertChainView.swift
          AudioUnitPickerView.swift
        Setlist/
          PerformView.swift
          PerformProgressView.swift
        Settings/
          SettingsView.swift
          AudioDeviceView.swift
          MIDIMappingView.swift
          FootPedalPresetView.swift
        Shared/
          AudioUnitWindowController.swift
  Tests/
    LoopsCoreTests/
      ModelSerializationTests.swift
      BarBeatPositionTests.swift
      LoopSettingsTests.swift
    LoopsEngineTests/
      AudioEngineManagerTests.swift
      TransportManagerTests.swift
      RecordingManagerTests.swift
      MIDIDispatcherTests.swift
      ProjectPersistenceTests.swift
    LoopsAppTests/
      TimelineViewModelTests.swift
      ProjectViewModelTests.swift
```

## 3. Data Model

All models are value types (structs) conforming to `Codable`, `Equatable`, and `Sendable`. Reference types are reserved for engine managers and view models only.

### Generic Typed ID

```swift
// Sources/LoopsCore/Identifiers/TypedID.swift
import Foundation

/// Phantom-typed identifier to prevent mixing up IDs from different model types.
struct ID<Phantom>: Hashable, Codable, Sendable {
    let rawValue: UUID

    init() { self.rawValue = UUID() }
    init(rawValue: UUID) { self.rawValue = rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(UUID.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
```

### Project

```swift
struct Project: Codable, Equatable, Sendable {
    var id: ID<Project>
    var name: String
    var songs: [Song]
    var setlists: [Setlist]
    var sourceRecordings: [ID<SourceRecording>: SourceRecording]
    var midiMappings: [MIDIMapping]
    var audioDeviceSettings: AudioDeviceSettings
    var schemaVersion: Int

    init(
        id: ID<Project> = ID(), name: String = "Untitled Project",
        songs: [Song] = [], setlists: [Setlist] = [],
        sourceRecordings: [ID<SourceRecording>: SourceRecording] = [:],
        midiMappings: [MIDIMapping] = [],
        audioDeviceSettings: AudioDeviceSettings = AudioDeviceSettings(),
        schemaVersion: Int = 1
    ) { /* assign all */ }
}
```

### Song

```swift
struct Song: Codable, Equatable, Sendable, Identifiable {
    var id: ID<Song>
    var name: String
    var tempo: Tempo
    var timeSignature: TimeSignature
    var tracks: [Track]
}
```

### Track and TrackKind

```swift
enum TrackKind: String, Codable, Sendable, CaseIterable {
    case audio, midi, bus, backing
}

struct Track: Codable, Equatable, Sendable, Identifiable {
    var id: ID<Track>
    var name: String
    var kind: TrackKind
    var volume: Float          // Linear gain 0.0...2.0 (0 = -inf, 1.0 = 0dB, 2.0 ~ +6dB)
    var pan: Float             // -1.0 (full left) to +1.0 (full right)
    var isMuted: Bool
    var isSoloed: Bool
    var containers: [Container]
    var insertEffects: [InsertEffect]
    var sendLevels: [SendLevel]
    var instrumentComponent: AudioComponentInfo?  // For MIDI tracks only
    var orderIndex: Int
}

/// Codable representation of AudioComponentDescription for AU identification
struct AudioComponentInfo: Codable, Equatable, Sendable {
    var componentType: UInt32
    var componentSubType: UInt32
    var componentManufacturer: UInt32
}
```

### Container

```swift
struct Container: Codable, Equatable, Sendable, Identifiable {
    var id: ID<Container>
    var name: String
    var startBar: Int          // 1-based
    var lengthBars: Int
    var sourceRecordingID: ID<SourceRecording>?
    var linkGroupID: ID<LinkGroup>?  // All containers with same linkGroupID share a recording
    var loopSettings: LoopSettings
    var isRecordArmed: Bool
    var volumeOverride: Float?
    var panOverride: Float?

    var endBar: Int { startBar + lengthBars }
}

enum LinkGroup {}  // Phantom type for link group identification
```

### SourceRecording

```swift
struct SourceRecording: Codable, Equatable, Sendable, Identifiable {
    var id: ID<SourceRecording>
    var filename: String       // Relative to project bundle's audio/ directory
    var sampleRate: Double
    var sampleCount: Int64
    var waveformPeaks: [Float]?

    var durationSeconds: Double { Double(sampleCount) / sampleRate }
}
```

### LoopSettings and BoundaryMode

```swift
enum BoundaryMode: String, Codable, Sendable, CaseIterable {
    case hardCut, crossfade, overdub
}

enum LoopCount: Codable, Equatable, Sendable {
    case count(Int)
    case fill
}

struct LoopSettings: Codable, Equatable, Sendable {
    var loopCount: LoopCount
    var boundaryMode: BoundaryMode
    var crossfadeDurationMs: Double  // Only used when boundaryMode == .crossfade
}
```

### Setlist and SetlistEntry

```swift
struct Setlist: Codable, Equatable, Sendable, Identifiable {
    var id: ID<Setlist>
    var name: String
    var entries: [SetlistEntry]
}

enum TransitionMode: Codable, Equatable, Sendable {
    case seamless
    case gap(durationSeconds: Double)
    case manualAdvance
}

struct SetlistEntry: Codable, Equatable, Sendable, Identifiable {
    var id: ID<SetlistEntry>
    var songID: ID<Song>
    var transitionToNext: TransitionMode
}
```

### MIDIMapping

```swift
enum MappableControl: String, Codable, Sendable, CaseIterable {
    case playPause, stop, recordArm, nextSong, previousSong, metronomeToggle
}

enum MIDITrigger: Codable, Equatable, Sendable {
    case controlChange(channel: UInt8, controller: UInt8)
    case noteOn(channel: UInt8, note: UInt8)
}

struct MIDIMapping: Codable, Equatable, Sendable, Identifiable {
    var id: ID<MIDIMapping>
    var control: MappableControl
    var trigger: MIDITrigger
    var sourceDeviceName: String?
}
```

### InsertEffect and SendLevel

```swift
struct InsertEffect: Codable, Equatable, Sendable, Identifiable {
    var id: ID<InsertEffect>
    var component: AudioComponentInfo
    var displayName: String
    var isBypassed: Bool
    var presetData: Data?      // Full AU state dictionary serialized
    var orderIndex: Int
}

struct SendLevel: Codable, Equatable, Sendable {
    var busTrackID: ID<Track>
    var level: Float           // 0.0 (silent) to 1.0 (unity)
    var isPreFader: Bool
}
```

### Supporting Types

```swift
struct TimeSignature: Codable, Equatable, Sendable {
    var beatsPerBar: Int       // Numerator (e.g. 4)
    var beatUnit: Int          // Denominator (e.g. 4 = quarter note)
}

struct Tempo: Codable, Equatable, Sendable {
    var bpm: Double            // Clamped to 20.0...300.0
    var beatDurationSeconds: Double { 60.0 / bpm }
}

struct BarBeatPosition: Codable, Equatable, Comparable, Sendable {
    var bar: Int               // 1-based
    var beat: Int              // 1-based within the bar
    var subBeatFraction: Double // 0.0..<1.0
}

struct SamplePosition: Codable, Equatable, Comparable, Sendable {
    var sampleOffset: Int64
}

protocol PositionConverter: Sendable {
    func samplePosition(for barBeat: BarBeatPosition, sampleRate: Double) -> SamplePosition
    func barBeatPosition(for sample: SamplePosition, sampleRate: Double) -> BarBeatPosition
    func sampleCount(forBars bars: Int, sampleRate: Double) -> Int64
}

struct AudioDeviceSettings: Codable, Equatable, Sendable {
    var inputDeviceUID: String?
    var outputDeviceUID: String?
    var bufferSize: Int        // 64, 128, 256, 512, or 1024
}

enum LoopsError: Error, Sendable {
    case engineStartFailed(underlying: String)
    case deviceNotFound(uid: String)
    case unsupportedSampleRate(Double)
    case tapInstallationFailed(String)
    case recordingWriteFailed(String)
    case audioFileCreationFailed(path: String)
    case projectLoadFailed(path: String, reason: String)
    case projectSaveFailed(path: String, reason: String)
    case schemaVersionMismatch(expected: Int, found: Int)
    case audioUnitLoadFailed(component: String)
    case audioUnitPresetRestoreFailed(String)
    case midiClientCreationFailed(status: Int32)
    case midiPortCreationFailed(status: Int32)
    case containerOverlap(trackID: String, bar: Int)
    case songNotFound(ID<Song>)
    case trackNotFound(ID<Track>)
}
```

## 4. AVAudioEngine Node Graph

### Topology Overview

```
                        +-----------+
                        | mainMixer |-----> engine.outputNode
                        +-----------+
                           ^   ^   ^
                           |   |   |
        +------------------+   |   +------------------+
        |                      |                      |
  [Track 1 Mixer]       [Track 2 Mixer]        [Bus 1 Mixer]
        ^                      ^                      ^
        |                      |                      |
  [Insert Chain]         [Insert Chain]         [Insert Chain]
   AU1 -> AU2             AU1                    AU1 -> AU2
        ^                      ^
        |                      |
  [PlayerNode]           [PlayerNode]
```

### Per-Track Node Subgraph (TrackNode class)

**Audio Track:**
```
AVAudioPlayerNode → [AU Effect 1] → [AU Effect 2] → ... → AVAudioMixerNode (track mixer)
                                                                  |
                                                                  ├→ mainMixerNode (direct out)
                                                                  └→ sendMixer → busMixerNode (via send level)
```

**MIDI Track:**
```
AVAudioUnitMIDIInstrument → [AU Effect 1] → ... → AVAudioMixerNode (track mixer) → mainMixerNode
```

**Bus Track:**
```
AVAudioMixerNode (bus input, receives sends) → [AU Effect 1] → ... → AVAudioMixerNode (bus output) → mainMixerNode
```

**Backing Track:**
```
AVAudioPlayerNode → [AU Effect 1] → ... → AVAudioMixerNode (track mixer) → mainMixerNode
```

### Dynamic Node Management

- **Adding a track:** Create nodes, `engine.attach()` each, `engine.connect()` in chain order. Can be done while engine is running.
- **Removing a track:** `engine.disconnectNodeOutput()` then `engine.detach()` each node, working backward from mainMixer.
- **Insert chain changes:** Disconnect segment, insert/remove AU node, reconnect. Engine stays running.
- **Loading an AU plugin:** Query `AVAudioUnitComponentManager.shared()`, call `AVAudioUnit.instantiate(with:options:)`, attach, reconnect chain, restore preset via `auAudioUnit.fullState`.

### Metronome

`AVAudioSourceNode` generating click samples programmatically on the render callback. Connects directly to `mainMixerNode`. Toggled via volume (0.0 = off).

## 5. View Architecture

### Observable Pattern

All view models use `@Observable` macro (NOT `ObservableObject`). Target is macOS 14+.

```swift
@Observable
@MainActor
final class AppState {
    var project: Project
    var currentSongID: ID<Song>?
    var selectedTrackID: ID<Track>?
    var selectedContainerID: ID<Container>?
    var isPerformMode: Bool = false

    let engine: AudioEngineManager
    let transport: TransportManager
    let midiManager: MIDIManager
    let persistence: ProjectPersistence
}
```

### View Hierarchy

```
LoopsRootView (@State var appState: AppState)
  ├── ToolbarView (play, stop, record arm, BPM, time sig, metronome)
  └── HSplitView
        ├── SidebarView (collapsible)
        │     ├── Picker (Songs / Setlists tab)
        │     ├── SongListView
        │     └── SetlistListView / SetlistEditorView
        └── HSplitView
              ├── VStack (center: timeline)
              │     ├── RulerView
              │     └── ScrollView(.horizontal, .vertical)
              │           └── ZStack
              │                 ├── GridOverlayView
              │                 ├── ForEach track → TrackHeaderView + TrackLaneView
              │                 │     └── ForEach container → ContainerView → WaveformView
              │                 └── PlayheadView
              └── InspectorView (collapsible)
                    ├── ContainerInspector (when container selected)
                    └── TrackInspector (when track selected)
                          ├── MixerStripView
                          ├── InsertChainView
                          └── SendLevelsView
```

### AU Plugin UI Hosting

Audio Unit UIs are NSView-based. Hosted in floating `NSPanel` windows via `NSViewRepresentable`. Opened separately from the main SwiftUI hierarchy.

## 6. Auto-Recording Flow

Step-by-step sequence when auto-record fires:

1. **Transport tick detects container entry** — `TransportManager` tracks playhead position, converts to `BarBeatPosition`, checks if any record-armed container spans current bar.
2. **RecordingManager begins recording** — Generates UUID filename, creates `AVAudioFile` for CAF writing in `projectBundle/audio/`, installs tap on `engine.inputNode`, tap closure writes buffers to file.
3. **Waveform data streams to UI** — Every N buffers in tap closure, compute peak amplitude. Dispatch to MainActor via `Task { @MainActor in }`. TimelineViewModel appends peaks for live display.
4. **Transport tick detects container exit** — When playhead passes container's `endBar`, notifies RecordingManager to stop.
5. **RecordingManager stops recording** — Removes tap, closes file, computes final waveform peaks via WaveformGenerator, returns `SourceRecording` value.
6. **Model update** — ProjectViewModel adds `SourceRecording` to `project.sourceRecordings`, sets container's `sourceRecordingID`. If linked, updates all linked containers. Pushes undo action.
7. **Persistence** — AutoSaveManager detects mutation, schedules debounced save (2s). CAF is already on disk; only `project.json` updates.

### Thread Safety

- Tap closure runs on real-time I/O thread. NO memory allocation, NO locks, NO actor awaits.
- `RecordingManager` is a Swift `actor` to serialize start/stop calls.
- Model mutations happen exclusively on `@MainActor`.
- Use `OSAllocatedUnfairLock` for small atomic state between threads. Lock-free ring buffers for level metering.

## 7. Persistence Architecture

### .loops Bundle Structure

```
MyProject.loops/
  project.json            # All metadata (Project struct serialized)
  audio/                  # All audio files
    a1b2c3d4-....caf     # UUID-named source recordings
```

### UTType Declaration

In Info.plist: `com.loops.project` conforming to `com.apple.package` + `public.data`, extension `.loops`.

### Save Strategy

- **Auto-save:** `AutoSaveManager` observes mutations, 2-second debounce timer, atomic write (temp file + rename).
- **Manual save:** Cmd+S triggers immediate save.
- **Audio files:** Written at recording time, not during save. Only `project.json` updates on save.
- **Orphan cleanup:** Unused CAF files cleaned on explicit "compact project" action only.

## 8. MIDI Architecture

### CoreMIDI Setup

`MIDIManager` creates a `MIDIClientRef` and `MIDIInputPortRef` using `MIDIInputPortCreateWithProtocol` (MIDI 1.0). Connects to all available sources. Handles device add/remove notifications.

### Event Dispatch

`MIDIDispatcher` receives events on CoreMIDI callback thread:
1. Parse event to determine CC or NoteOn
2. Create `MIDITrigger` value
3. If in learn mode → call `onMIDILearnEvent` callback
4. Otherwise → look up in mappings table (protected by `OSAllocatedUnfairLock`), call `onControlTriggered`
5. If unmapped and MIDI track instrument exists → route to AU instrument

### MIDI Learn Flow

1. User clicks "MIDI Learn" next to a control → `MIDILearnController.startLearning(for: .playPause)`
2. User presses MIDI button → dispatcher fires callback with `MIDITrigger`
3. `MIDILearnController` exits learn mode, creates `MIDIMapping`
4. Mapping added to `project.midiMappings`, dispatcher table updated atomically

### Foot Pedal Presets

```swift
enum FootPedalPreset: String, CaseIterable, Sendable {
    case generic2Button = "Generic 2-Button Pedal"
    case generic4Button = "Generic 4-Button Pedal"
    // Each case provides pre-configured MIDIMapping arrays
}
```

## 9. Key Design Decisions (Binding Constraints)

These rules are mandatory for ALL implementing agents:

1. **@Observable, not ObservableObject** — macOS 14+ target. Use `@Observable` macro. Never use `ObservableObject`, `@Published`, or `@StateObject`. Use `@State` at the root.

2. **Value types for models, reference types for managers** — All LoopsCore models are `struct`s. Classes/actors only for engine managers and view models.

3. **@MainActor for all UI state** — Every view model is `@MainActor`. All Project mutations happen on MainActor. `RecordingManager` is a Swift `actor`.

4. **Lock-free on the audio thread** — Real-time callbacks must NEVER allocate memory, acquire locks, call actor `await`, or use ObjC methods that autorelease.

5. **Typed errors** — All throwing functions throw `LoopsError`. No `try!` or `fatalError()` in production code. `try?` only when failure is genuinely ignorable.

6. **No `any` types** — Per project rules. Use generics with protocol constraints instead.

7. **Module boundaries** — LoopsCore: only Foundation. LoopsEngine: AVFoundation, CoreMIDI, AudioToolbox, CoreAudio + LoopsCore. LoopsApp: SwiftUI, AppKit + LoopsCore + LoopsEngine. Cross-module types must be `public`.

8. **Audio files: CAF internally, WAV/AIFF for export** — Filenames are UUID strings in the `audio/` subdirectory.

9. **1-based musical positions** — Bar 1 is the first bar. Sample positions are 0-based Int64. Container positions are always integer bars.

10. **Undo via UndoManager** — Each mutating action registers undo closure capturing previous state. Per-session only.

11. **Naming conventions** — Swift files: PascalCase. Directories: PascalCase. Audio files: UUID-based. JSON keys: camelCase (default Codable).
