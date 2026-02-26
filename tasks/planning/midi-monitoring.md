# MIDI Monitoring & Activity Indicators

## Context

When working with MIDI in a DAW, it's essential to see what's happening in real-time. Currently the app receives MIDI input via `MIDIManager` and dispatches it through `MIDIDispatcher`, but there's no visibility into the raw MIDI stream, no per-track activity indicators, and no way to tell which container is receiving MIDI at the current playhead position. This makes MIDI routing debugging difficult.

## Features

### 1. MIDIActivityMonitor (Engine Layer)

**New file:** `Sources/LoopsEngine/MIDI/MIDIActivityMonitor.swift`

An `@Observable @MainActor` class that taps into `MIDIManager.onMIDIEventFromDevice` and provides:

- **Message log**: Circular buffer (~500 entries) of `MIDILogEntry` with timestamp, device, channel, message type, values
- **Per-track activity**: Compares incoming MIDI device+channel against each track's `midiInputDeviceID`/`midiInputChannel` using existing `MIDITrackFilter.matches()` to set per-track activity timestamps
- Exposes `recentMessages: [MIDILogEntry]` and `isTrackActive(_ trackID: ID<Track>) -> Bool` (true if activity within last ~300ms)

**New struct:** `MIDILogEntry` in `Sources/LoopsCore/Models/MIDILogEntry.swift`
- `id`, `timestamp: Date`, `deviceName: String?`, `deviceID: String?`, `channel: UInt8`
- `message: MIDILogMessage` enum with cases: `.noteOn(note, velocity)`, `.noteOff(note, velocity)`, `.controlChange(controller, value)`, `.programChange(program)`, `.pitchBend(value)`, `.other(status)`
- Helper `displayString` for human-readable formatting (note names like "C4", CC names like "Sustain")

### 2. MIDIManager Extension

**Modified:** `Sources/LoopsEngine/MIDI/MIDIManager.swift`

- Add new callback: `onRawMIDIMessage: ((UInt32, String?) -> Void)?` — fires for every received MIDI word with device ID
- Extend `parseMessage` to handle NoteOff (0x80), Program Change (0xC0), Pitch Bend (0xE0) in addition to existing CC/NoteOn
- Fire `onRawMIDIMessage` before the existing `onMIDIEventFromDevice` dispatch

### 3. MIDI Log View

**New file:** `Sources/LoopsApp/Views/MIDI/MIDILogView.swift`

Scrolling table of MIDI messages, opened via keyboard shortcut or menu:

```
┌─ MIDI Log ──────────────────────────────────────────┐
│ [Clear]  [Pause]   Filter: [All Devices v] [All v]  │
│──────────────────────────────────────────────────────│
│ Time       Device              Ch  Message           │
│ 12:01:03   Komplete Audio 6     1  NoteOn C4 v=100  │
│ 12:01:03   Komplete Audio 6     1  CC64 (Sustain) 127│
│ 12:01:04   Komplete Audio 6     1  NoteOff C4       │
└──────────────────────────────────────────────────────┘
```

- Auto-scrolls to bottom unless user scrolls up
- Device and channel filter dropdowns
- Clear and pause buttons
- Presented as a floating window (like plugin windows) via Cmd+Shift+L

### 4. Track Header MIDI Activity Dot

**Modified:** `Sources/LoopsApp/Views/Timeline/TrackHeaderView.swift`

- Small green circle next to MIDI track names that pulses bright on activity, fades over ~300ms
- Only on `.midi` kind tracks
- New parameter: `isMIDIActive: Bool`
- Uses SwiftUI animation (opacity transition) for the fade effect

### 5. Container Inspector MIDI Badge

**Modified:** `Sources/LoopsApp/Views/Inspector/ContainerInspector.swift`

- Green "MIDI" pill/badge near the container name section
- Visible when: track has MIDI activity AND playhead is within this container's bar range
- Requires knowing the container's track ID and current playhead position

## Data Flow

```
CoreMIDI → MIDIManager.handleEventList()
               ├→ onMIDIEventFromDevice (existing: MIDIDispatcher)
               └→ onRawMIDIMessage (new)
                      ↓
               MIDIActivityMonitor.recordMessage()
                   ├→ recentMessages[] (circular log buffer)
                   └→ trackActivity[trackID] = Date.now
                          ↓ (@Observable)
                   ├→ MIDILogView (reads recentMessages)
                   ├→ TrackHeaderView (reads isTrackActive)
                   └→ ContainerInspector (reads isTrackActive + playhead)
```

## Wiring

- `MIDIActivityMonitor` created in `LoopsAppEntry` alongside existing engine setup
- Connected to `MIDIManager.onRawMIDIMessage` in the same place `MIDIDispatcher` is connected
- Passed to `MainContentView` → `TrackHeaderView` for activity dots
- Passed to `ContainerInspector` for MIDI badge
- `MIDILogView` opened as floating NSWindow (reuse pattern from `PluginWindowManager`)

## Files

| File | Change |
|------|--------|
| `Sources/LoopsCore/Models/MIDILogEntry.swift` | **NEW** — log entry + message enum |
| `Sources/LoopsEngine/MIDI/MIDIActivityMonitor.swift` | **NEW** — observable monitor |
| `Sources/LoopsEngine/MIDI/MIDIManager.swift` | Add `onRawMIDIMessage`, extend parsing |
| `Sources/LoopsApp/Views/MIDI/MIDILogView.swift` | **NEW** — scrolling log panel |
| `Sources/LoopsApp/Views/Timeline/TrackHeaderView.swift` | MIDI activity dot |
| `Sources/LoopsApp/Views/Inspector/ContainerInspector.swift` | MIDI receive badge |
| `Sources/LoopsApp/Views/MainWindow/MainContentView.swift` | Wire monitor to views |
| `Sources/LoopsApp/App/LoopsAppEntry.swift` | Create + inject monitor |
| `Tests/LoopsEngineTests/MIDIActivityMonitorTests.swift` | **NEW** |
| `Tests/LoopsCoreTests/MIDILogEntryTests.swift` | **NEW** |

## Verification

1. `swift build` passes
2. `swift test` — all existing + new tests pass
3. Run app → Cmd+Shift+L opens MIDI log → send MIDI from controller → messages appear
4. MIDI track headers show blinking green dot on matching MIDI input
5. Container inspector shows "MIDI" badge when playhead is inside container and track is receiving MIDI
