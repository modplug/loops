# PRD: Inspector, Automation, Recording & UX Overhaul

## Problem Statement

Loops is becoming a capable DAW but lacks several core workflow features that professional users expect:

- **Track selection is broken**: Clicking a track header sets `selectedTrackID` on one view model, but the visual highlight checks a different view model's `selectedTrackIDs` — they are never synchronized, so tracks never appear selected
- **No unified inspector editing**: The container inspector exists but is read-only for most fields. There is no track inspector, setlist entry inspector, or linked clip inspector
- **No effect or instrument automation**: Effect and instrument AU parameters cannot be automated through the timeline's automation lanes
- **No audio recording**: Audio cannot be recorded into containers during live playback
- **Mixer controls are broken**: Volume faders use a 24pt-wide rotated slider that's nearly impossible to drag. Pan knobs have a similarly tiny hit area
- **No track management**: Tracks cannot be selected, reordered, or deleted through the UI. No context menu for creating tracks
- **Audio import hangs the UI**: Dragging audio into the timeline blocks the main thread while generating waveform peaks
- **No wall-time clock**: There is no absolute time display — only bar/beat positions
- **No draggable container fades**: Fade-in/out requires code changes instead of being draggable handles in the UI
- **No setlist inspector**: Setlist entries have no way to configure transitions or fade-ins between songs
- **Linked clips hide differences**: Linked clips don't surface which parameters differ from the original container
- **Playhead appears to jump ahead of audio**: The UI playhead starts moving before audio actually plays, causing visible desynchronization
- **AU effect window sizing**: Effect plugin windows don't resize to fit the plugin's UI, unlike instrument windows which already do
- **MIDI monitoring is unimplemented**: The planned MIDI activity indicators, message log, and container badges remain unbuilt

These gaps force users into workarounds or make the app unusable for real production workflows.

## Extends

#71

## Solution

Implement a comprehensive set of features across five domains:

1. **Inspector system** — A unified, context-sensitive inspector sidebar that shows editable properties for the selected track, container, setlist entry, or linked clip. All fields that are currently display-only become editable using the same UI components from the existing modal editors, embedded inline.
2. **Track selection and management** — Fix the broken track selection highlight, add single-click selection with visual feedback, support drag-to-reorder, add delete via context menu, and add a right-click context menu on empty space for creating new tracks.
3. **Effect parameter automation** — Expose AU effect parameters as automatable targets in the timeline's automation lanes, with a parameter picker listing all parameters from all effects in the track's insert chain.
4. **Instrument parameter automation** — Expose AU instrument parameters as automatable targets alongside effect automation, with a searchable picker to handle instruments with hundreds of parameters.
5. **Audio recording** — Arm containers for audio recording during playback, rendering the waveform in real-time as audio arrives, stopping when the playhead exits the container's bar range.
6. **Mixer UI fixes** — Replace the broken fader and pan controls with properly sized drag areas (minimum 44pt), ensuring the mixer reflects actual engine state at all times.
7. **Master channel pinning** — Pin the master channel strip to the bottom of both the timeline track list and the mixer, so it's always visible regardless of scroll position.
8. **Async audio import** — Move waveform generation off the main thread. Show a preview rectangle immediately based on file metadata, then render the waveform progressively.
9. **Container fade handles** — Draggable handles at the top corners of containers for fade-in and fade-out, with a visual curve overlay and curve type selection in the inspector.
10. **Setlist entry inspector** — An inspector panel for setlist entries with transition mode (manual, automatic, automatic with delay), delay duration, and fade-in as a separate property.
11. **Wall-time clock** — An absolute time display in the transport bar and container inspector, converting bar-beat position to seconds using the song's tempo.
12. **AU effect window sizing** — Apply the same window-sizing logic already used for AU instruments to AU effect plugin windows.
13. **Playhead-audio sync fix** — Synchronize the UI playhead to the actual audio output using render time calibration.
14. **MIDI monitoring** — A MIDI log view (floating window) with real-time message display, per-track activity dots on MIDI track headers, and MIDI badges in the container inspector.

## User Stories

1. As a user, I want to click on a track header to select it, so that I can see its properties in the inspector.
2. As a user, I want the selected track to be visually highlighted (background color change), so that I can always see which track is active.
3. As a user, I want to see a track inspector panel showing the track's name, effects/inserts, routing, mix parameters, MIDI settings, expression pedal assignments, and automation summary, so that I have a single place to configure a track.
4. As a user, I want to edit all fields in the track inspector inline (volume, pan, name, routing, MIDI channel), so that I don't have to open separate modals for simple changes.
5. As a user, I want to add, remove, reorder, and bypass effects directly from the track inspector's effects section, so that I can manage my signal chain efficiently.
6. As a user, I want to drag tracks up and down in the track header area to reorder them, so that I can organize my arrangement.
7. As a user, I want to right-click a track header and see options like "Delete Track", so that I can remove unwanted tracks.
8. As a user, I want the inspector to update its contents based on what is currently selected (track, container, setlist entry), so that it's always contextually relevant.
9. As a user, I want the container inspector to have editable fields for all displayed properties, so that I can change effect settings, actions, fades, loop settings, and automation directly without opening the full detail editor.
10. As a user, I want the container inspector to use the same UI components as the ContainerDetailEditor modal tabs, so the editing experience is consistent.
11. As a user, I want to see the wall-time position (in seconds/minutes) of the selected container in its inspector, so that I know its absolute time position.
12. As a user, I want the inspector for a linked clip to show which container it is linked to (by name and position), so that I can identify the relationship.
13. As a user, I want the linked clip inspector to show a diff of which parameters differ from the parent container, so that I can understand what makes this instance unique.
14. As a user, I want AU effect plugin windows to resize to fit the plugin's UI, so that the window isn't too large or too small — matching the behavior already implemented for AU instruments.
15. As a user, I want to create automation lanes for AU effect parameters on tracks, so that I can draw envelopes that modulate effect settings over time.
16. As a user, I want to see and edit effect parameter automation in the track's automation sublanes in the timeline, so that I have visual control over effect modulation.
17. As a user, I want the automation parameter picker to list all parameters from all effects in the track's insert chain, so that I can automate any effect parameter.
18. As a user, I want inserting a MIDI instrument to expose its automatable parameters, so that I can create automation envelopes for synthesizer and sampler controls.
19. As a user, I want a searchable parameter picker when adding automation lanes, so that I can quickly find specific parameters among potentially hundreds of exposed AU parameters.
20. As a user, I want instrument parameter automation lanes to appear in the timeline alongside effect automation, so that I have a unified automation workflow.
21. As a user, I want to arm a container for recording, so that the system knows which container should capture audio.
22. As a user, I want the armed state to be visually indicated on the container in the timeline (e.g., red border or record icon), so that I can see which containers are record-ready.
23. As a user, I want audio to be recorded into the armed container when the transport is playing with record enabled and the playhead is over that container, so that I can capture audio during a live performance pass.
24. As a user, I want the recorded waveform to render in real-time as audio comes in, so that I get visual feedback during recording.
25. As a user, I want recording to stop when the playhead leaves the container's bar range, so that recording is scoped to the container boundary.
26. As a user, I want the mixer faders to respond to volume changes immediately and accurately, so that adjustments are reflected in real-time.
27. As a user, I want the mixer fader and pan knob drag areas to be large enough for precise control, so that I don't have to struggle with tiny hit targets.
28. As a user, I want the mixer to reflect the actual engine state (volume/pan values) at all times, so that the UI is never out of sync.
29. As a user, I want the master channel strip to always be visible at the bottom of both the track list and the mixer (above the scrollbar), so that I can always access master volume and metering.
30. As a user, I want to right-click on empty space in the tracks area to see a context menu with options to insert an Audio Track or MIDI Track, so that I can create new tracks without navigating menus.
31. As a user, I want there to always be enough empty space at the bottom of the track list (at least one track height) when scrolled to the bottom, so that I have room to right-click and create a new track.
32. As a user, I want dragging audio files into the timeline to not freeze the UI, so that the app remains responsive during import.
33. As a user, I want to see a preview rectangle showing how long the imported audio will be (based on file metadata) immediately on drop, so that I can position the container before processing completes.
34. As a user, I want the waveform to render progressively as the audio file is scanned, so that I get visual feedback during the import process.
35. As a user, I want the timeline to auto-scale/scroll if the imported audio extends beyond the current visible area, so that I can see the full container.
36. As a user, I want a wall-time clock display (in seconds/minutes) somewhere visible in the transport or toolbar area, so that I can see the absolute time position of the playhead.
37. As a user, I want the clock to update in real-time as the playhead moves during playback, so that it always reflects the current position.
38. As a user, I want to create fade-ins by dragging a handle at the top-left corner of a container, so that I can add smooth audio entries without editing code.
39. As a user, I want to create fade-outs by dragging a handle at the top-right corner of a container, so that I can add smooth audio exits.
40. As a user, I want the fade curve to be visually rendered on the container (like a diagonal line or curve overlay), so that I can see the fade shape.
41. As a user, I want to choose fade curve types (linear, exponential, s-curve) from the container inspector, so that I have control over the fade character.
42. As a user, I want the fade duration to be adjustable by dragging the fade handle horizontally, so that I can fine-tune the fade length visually.
43. As a user, I want the setlist sidebar entries to have an inspector panel when selected, so that I can configure per-entry options.
44. As a user, I want to choose the transition mode between songs: manual, automatic, automatic with delay, so that the setlist follows my live performance needs.
45. As a user, I want to configure a fade-in for setlist entry transitions, so that songs can blend smoothly.
46. As a user, I want to set a delay duration (in seconds) for automatic-with-delay transitions, so that I can control the gap between songs.
47. As a user, I want the playhead to start moving at the exact moment audio begins playing, so that the visual and audible experience is perfectly synchronized.
48. As a user, I want this sync to be accurate even when starting playback from bar 1, so that there is no visible preroll gap.
49. As a user, I want a MIDI log view (floating window) that shows all incoming MIDI messages in real-time with timestamp, device, channel, and message details, so that I can debug MIDI routing.
50. As a user, I want to filter the MIDI log by device and channel, so that I can focus on specific MIDI sources.
51. As a user, I want the MIDI log to have clear and pause buttons, so that I can control the display.
52. As a user, I want a blinking green activity dot on MIDI track headers when MIDI is received on that track's input, so that I can see activity at a glance.
53. As a user, I want a "MIDI" badge in the container inspector when the track is receiving MIDI and the playhead is within the container's range, so that I know which container is active.
54. As a user, I want the MIDI log to parse and display note names (like "C4"), CC names (like "Sustain"), and other human-readable labels, so that the log is easy to read.
55. As a user, I want the MIDI manager to handle NoteOff, Program Change, and Pitch Bend messages in addition to the existing NoteOn and CC parsing, so that the log is comprehensive.

## Implementation Decisions

### Modules

**TrackSelection** — Fix the broken track selection and add visual highlight
- Single-select model: clicking a track header sets a single selected track ID
- The visual highlight must check the canonical selected track ID, not a separate set that is never updated
- Selected track gets a highlighted background (accent color at 15% opacity)

**InspectorSystem** — Context-sensitive inspector sidebar
- Selection state managed centrally: selected track ID, selected container ID, or selected setlist entry ID
- Inspector renders different views based on selection type: track inspector, container inspector, setlist entry inspector, or linked clip inspector
- Editable fields reuse the same SwiftUI components from the existing modal editors, embedded directly

**TrackInspector** — Editable track-level inspector
- Shows track name, effects/inserts, I/O routing, MIDI routing, mix parameters, expression pedal assignments, and automation summary
- I/O routing section replaces display-only text with Picker/Menu controls
- Add/remove/reorder/bypass effects directly from the effects section

**ContainerInspector** — Make existing inspector editable
- Embed the editing components from the container detail editor tabs directly into the inspector sections
- Existing callbacks for property changes are already wired up

**LinkedClipInspector** — Show parent relationship and parameter diff
- Display which container the clip is linked to by name and position
- Compute and display which fields differ from the parent container using the override set

**SetlistEntryInspector** — New inspector for setlist entries
- Add `fadeIn: FadeSettings?` as a separate property on SetlistEntry (not part of the transition model)
- Transition model with mode (manual/automatic/automaticWithDelay) and delay duration
- Inspector panel renders when a setlist entry is selected in the sidebar

**MixerControls** — Fix fader and pan drag areas
- Replace the rotated Slider in the fader with a custom vertical drag gesture, minimum 44pt wide
- Replace the pan knob with a wider control, minimum 44pt
- Both use Float bindings and trigger engine parameter updates immediately on drag
- Verify that the mixer reads back actual engine state after changes to prevent UI drift

**MasterChannelPinning** — Pin master to bottom in both views
- In the timeline track layout, render the master track header and lane outside the scroll view, fixed at bottom
- In the mixer, render the master strip outside the scroll view, fixed at right or bottom
- Regular tracks scroll; master stays fixed

**EffectAutomation** — Expose AU effect parameters as automation targets
- Extend the automation context menu to list effects, using the existing parameter picker
- Query AU effect instances for their parameter tree
- The playback scheduler already evaluates track automation lanes — extend to cover effect parameters

**InstrumentAutomation** — Expose AU instrument parameters as automation targets
- New sentinel value in the effect path model for instrument parameters
- Load parameters via the audio unit discovery service
- Searchable parameter picker to handle instruments with hundreds of parameters

**AudioRecording** — Record audio into armed containers
- Add armed state to containers with visual indicator (red border or record icon)
- During playback with record enabled, start writing audio from the input tap to a new file when the playhead enters an armed container's bar range
- Generate waveform peaks incrementally and push to the container's waveform view
- Stop recording when the playhead exits the container range

**AsyncAudioImport** — Non-blocking audio file import
- Move waveform peak generation to a background task entirely
- On drop, immediately read audio file metadata (duration, sample rate) to calculate container length in bars
- Display an empty rectangle of the correct length, then progressively render peaks as they arrive
- Auto-scroll or zoom if the container extends beyond the visible timeline

**WallTimeClock** — Absolute time display
- Add a conversion method to translate bar-beat position to wall-time seconds using the song's tempo
- Display in the transport bar area (format: MM:SS.ms)
- Also display in the container inspector for the selected container's start/end positions

**ContainerFadeHandles** — Draggable fade UI
- Fade handles are small draggable triangles at the top-left (fade-in) and top-right (fade-out) corners
- Dragging horizontally adjusts fade duration in bars; vertical position is fixed
- Fade shape rendered as a semi-transparent overlay using the existing FadeSettings curve type
- Curve type selection in the container inspector (dropdown: linear, exponential, s-curve)

**AUEffectWindowSizing** — Match instrument window behavior
- Apply the same window-sizing logic already used for AU instruments to AU effect plugin windows
- The pattern exists in the audio unit UI host — extend it to cover effect plugin windows

**PlayheadSync** — Fix playhead-audio desynchronization
- Synchronize the UI playhead start to the actual audio render callback's start
- Use the player node's last render time or host time to calibrate
- Pay special attention to the first-bar case where buffer latency causes visible desync

**MIDIMonitoring** — Activity indicators and log view
- New observable monitor that taps into the MIDI manager's raw message callback
- Circular buffer of log entries with human-readable formatting (note names, CC names)
- Floating log window with device/channel filters, clear, and pause
- Per-track green activity dot on MIDI track headers with 300ms fade animation
- Container inspector MIDI badge when track is receiving and playhead is within range

## Testing Decisions

Good tests verify external behavior through the module's public interface, not implementation details. Tests should be resilient to refactoring.

### Modules to test

- **PositionConverter** — Unit tests for bar-position to seconds conversion at various tempos and time signatures
- **MIDIActivityMonitor** — Unit tests for message logging, per-track activity matching, and circular buffer behavior (prior art: existing MIDIDispatcher tests)
- **MIDILogEntry** — Unit tests for display string formatting (note names, CC names)
- **FadeSettings** — Unit tests for fade duration calculations if any new computation is added
- **SetlistTransition** — Unit tests for transition mode behavior
- **AsyncAudioImport** — Integration test verifying that peak generation runs off the main thread and produces correct peak data
- **AutomationParameterDiscovery** — Unit tests verifying that AU parameter trees are correctly flattened into searchable lists with correct effect path values
- **MixerBindings** — Verify that fader value changes propagate to the engine and read back correctly

### Prior art

- `Tests/LoopsEngineTests/` contains existing engine tests using offline rendering mode
- `Tests/LoopsCoreTests/` contains model tests
- Follow the same patterns for new tests

## Out of Scope

- MIDI recording / MIDI editor (piano roll)
- Audio effects processing changes (reverb, delay algorithms) — only UI and automation exposure
- Multi-track recording (recording to multiple containers simultaneously)
- Undo/redo system (valuable but separate effort)
- Plugin preset management / preset browser
- Audio time-stretching or pitch-shifting
- Video sync or timecode (SMPTE/MTC)
- Cross-platform support (macOS-only via AVAudioEngine)
