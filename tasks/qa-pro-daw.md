# Manual QA Checklist — Pro DAW (PRD #144)

## Pre-QA
- [ ] All ralph loops exited with COMPLETE
- [ ] All 13 GitHub issues (#145-#157) are closed
- [ ] `swift build` passes on merged code
- [ ] `swift test` passes on merged code
- [ ] `swiftlint` passes on merged code
- [ ] No uncommitted changes
- [ ] All 3 worktree branches merged into main cleanly

## Functional QA

### PDC & Engine

**#145 — Plugin Delay Compensation**
- [ ] Insert a high-latency plugin (linear-phase EQ) on Track 1, leave Track 2 clean
- [ ] Play identical audio on both tracks — they must be perfectly in sync (no flanging)
- [ ] Check transport bar shows total PDC (e.g., "PDC: 1024 smp / 23.2ms")
- [ ] Check track header shows per-track PDC
- [ ] Add another plugin to Track 1 → PDC recalculates automatically
- [ ] Bypass the plugin → PDC recalculates
- [ ] Toggle PDC off in preferences → tracks are visibly out of sync (confirms PDC was working)
- [ ] Remove all plugins → PDC shows 0

**#146 — Low-Latency Monitoring**
- [ ] Enable Low-Latency Monitoring toggle
- [ ] Record-arm a track with high-latency plugins → plugins auto-bypass (visual "LL" badge)
- [ ] Record audio — roundtrip latency should be noticeably lower
- [ ] Stop recording → plugins re-enable automatically
- [ ] Disarm track → plugins stay enabled
- [ ] Change threshold setting (64/128/256/512) → different plugins bypass at different thresholds
- [ ] Verify playback-only tracks are NOT affected by LL mode

**#147 — Audio Test Suite**
- [ ] Run `swift test` — all new audio tests pass
- [ ] Verify sync tests use phase cancellation methodology
- [ ] Verify PDC tests exist and test with simulated latency
- [ ] Verify performance tests have `measure {}` baselines
- [ ] Run on a machine without audio hardware — hardware tests skip cleanly

### Audio Analysis & UI Polish

**#148 — Transient Detection**
- [ ] Import a drum loop → transient markers appear on waveform (thin vertical lines)
- [ ] Adjust sensitivity threshold → more/fewer transients shown
- [ ] Toggle transient display off → markers hidden
- [ ] Import a sustained pad → few/no transients (correct behavior)
- [ ] Clone a container → transients shared (same source recording)

**#149 — Snap-to-Transient**
- [ ] Hover cursor near a transient → cursor snaps to it (magnetic)
- [ ] Split at snapped position → clean split at transient
- [ ] Tab key → cursor jumps to next transient on selected track
- [ ] Shift+Tab → cursor jumps to previous transient
- [ ] With grid snap also enabled → transient snap takes priority when near

**#150 — Beat Slicing**
- [ ] Right-click drum container → "Slice at Transients"
- [ ] Container splits into individual hit containers at each transient
- [ ] Play the sliced containers → sounds identical to original
- [ ] Rearrange sliced containers → beat rearrangement works
- [ ] Try "Audio to MIDI" → MIDI notes created at transient positions
- [ ] Cmd+Z → undo restores original container

**#151 — Bitwig-Style Piano Roll Keyboard**
- [ ] Open piano roll → full-range keyboard indicator on left side
- [ ] Each row shows note name with black/white key visual
- [ ] C notes have bold text and stronger octave divider
- [ ] Scroll vertically → keyboard scrolls in sync
- [ ] Click a key row → preview note plays through instrument
- [ ] Works in both sheet and inline piano roll
- [ ] Row height matches zoom setting

**#152 — Info Pane**
- [ ] Info pane visible at bottom of left sidebar
- [ ] Hover over play button → shows "Play: Start playback. Shortcut: Space"
- [ ] Hover over track fader → shows "Volume Fader: Adjust track volume..."
- [ ] Hover over container edge → shows zone info (resize, trim, move)
- [ ] Hover over piano roll note → shows note editing info
- [ ] Nothing hovered → shows default context text
- [ ] Toggle off via View menu → pane hides
- [ ] Relaunch app → toggle state preserved

### Track UI & Tools

**#153 — Expanded Track Header**
- [ ] Track headers show: name, M/S/R, volume slider, pan knob, I/O pickers, sends, effect pills
- [ ] Drag header edge → resizable width
- [ ] Toggle compact mode → shows only name + M/S/R
- [ ] Adjust volume in header → mixer and inspector update
- [ ] Adjust volume in mixer → header updates
- [ ] Click effect pill → opens AU UI
- [ ] Click [+] → add effect menu

**#154 — Track Lane Visuals**
- [ ] Clear 1pt divider between each track lane
- [ ] Alternating background tints (subtle)
- [ ] Scroll down on tall track → track name stays sticky at top
- [ ] Mute a track → lane content at 0.4 opacity
- [ ] Solo a track → other lanes dimmed
- [ ] Record-arm → subtle red tint in lane
- [ ] Select track → accent-color 3pt left border

**#155 — Track Freeze**
- [ ] Right-click → "Freeze Track" on a track with plugins
- [ ] Track renders (progress indicator)
- [ ] Frozen: waveform shown, plugins disabled, snowflake icon
- [ ] Play → frozen audio plays (CPU usage drops)
- [ ] Try to edit container → blocked (dimmed, "Frozen" overlay)
- [ ] Volume/pan sliders still work
- [ ] "Unfreeze Track" → original containers and effects restored
- [ ] Save/reload project → freeze state preserved

**#156 — Clip Gain**
- [ ] Hover over container → see horizontal gain line
- [ ] Drag gain line up → waveform gets taller, gain value shows (e.g., "+3.2 dB")
- [ ] Drag gain line down → waveform shrinks
- [ ] Double-click → resets to 0 dB
- [ ] Play → audio level matches gain setting
- [ ] Gain applies before track fader (pre-fader)
- [ ] Visible in container inspector

**#157 — LUFS Metering**
- [ ] Master mixer strip shows: Integrated LUFS, Short-term, Momentary, True Peak
- [ ] Press play → meters animate, integrated accumulates
- [ ] Stop → integrated holds final value
- [ ] Play again → integrated resets
- [ ] Click meter → resets peak/integrated
- [ ] Color coding: green/yellow/red based on target
- [ ] Change target (-14/-23 LUFS) → thresholds adjust

## Integration QA (Cross-Worktree)
- [ ] PDC (#145) + Track Freeze (#155): Freeze a track with high-latency plugins → PDC recalculates (frozen track has 0 latency)
- [ ] Transient snap (#149) + Clip gain (#156): Snap to transient, then adjust clip gain → both work together
- [ ] Info pane (#152) + expanded header (#153): Hover over new header controls → info pane shows help
- [ ] Low-latency mode (#146) + LUFS metering (#157): Record in LL mode → LUFS still metering master output
- [ ] Piano roll keyboard (#151) + Info pane (#152): Hover piano keys → info pane shows note info

## Edge Cases
- [ ] PDC with 0 plugins on all tracks → PDC shows 0, no compensation applied
- [ ] Transient detection on very short audio (<100ms) → no crash
- [ ] Beat slicing with threshold so high no transients found → graceful message
- [ ] Freeze an empty track (no containers) → no crash, shows empty waveform
- [ ] Clip gain at -inf dB → audio silent, waveform flat line
- [ ] LUFS on silence → shows -inf or very low value
- [ ] Info pane with rapid hover changes → no lag or flicker
- [ ] Expanded track header at minimum track height → graceful truncation
