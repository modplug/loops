import AppKit
import Testing
@testable import LoopsApp
@testable import LoopsCore

@Suite("PlaybackGrid Core Tests")
struct PlaybackGridCoreTests {

    @Test("Scene builder computes track/container/section geometry")
    func sceneBuilderGeometry() {
        let container = Container(name: "Clip", startBar: 2.0, lengthBars: 4.0)
        let track = Track(name: "Audio 1", kind: .audio, containers: [container])
        let section = SectionRegion(name: "Verse", startBar: 1, lengthBars: 8)

        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [section],
            timeSignature: TimeSignature(),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .adaptive,
            selectedContainerIDs: [container.id],
            selectedSectionID: section.id,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let builder = PlaybackGridSceneBuilder()
        let scene = builder.build(snapshot: snapshot)

        #expect(scene.trackLayouts.count == 1)
        #expect(scene.sectionLayouts.count == 1)

        let trackLayout = scene.trackLayouts[0]
        #expect(abs(trackLayout.yOrigin - PlaybackGridLayout.trackAreaTop) < 0.01)

        let containerLayout = trackLayout.containers[0]
        #expect(abs(containerLayout.rect.minX - 120) < 0.01)
        #expect(abs(containerLayout.rect.width - 480) < 0.01)
        #expect(containerLayout.isSelected)
    }

    @Test("Picking resolves container smart-tool zones")
    func pickingContainerZones() {
        let container = Container(name: "Clip", startBar: 1.0, lengthBars: 4.0)
        let track = Track(name: "Audio 1", kind: .audio, containers: [container])

        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .adaptive,
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let scene = PlaybackGridSceneBuilder().build(snapshot: snapshot)
        let picker = PlaybackGridPickingRenderer()

        let topLeft = picker.pick(
            at: CGPoint(x: 2, y: PlaybackGridLayout.trackAreaTop + 2),
            scene: scene,
            snapshot: snapshot,
            visibleRect: CGRect(x: 0, y: 0, width: 1000, height: 500),
            canvasWidth: 1000
        )

        #expect(topLeft.kind == .containerZone)
        #expect(topLeft.containerID == container.id)
        #expect(topLeft.zone == .fadeLeft)
    }

    @Test("Picking empty grid area resolves to track background for playhead set")
    func pickingEmptyGridAsTrackBackground() {
        let snapshot = PlaybackGridSnapshot(
            tracks: [],
            sections: [],
            timeSignature: TimeSignature(),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .adaptive,
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )
        let scene = PlaybackGridSceneBuilder().build(snapshot: snapshot)
        let picker = PlaybackGridPickingRenderer()
        let pick = picker.pick(
            at: CGPoint(x: 210, y: PlaybackGridLayout.trackAreaTop + 40),
            scene: scene,
            snapshot: snapshot,
            visibleRect: CGRect(x: 0, y: 0, width: 1000, height: 500),
            canvasWidth: 1000
        )
        #expect(pick.kind == .trackBackground)
    }

    @Test("Picking resolves MIDI note and automation breakpoint")
    func pickingMIDINoteAndAutomationBreakpoint() {
        let midiNote = MIDINoteEvent(pitch: 64, startBeat: 0, duration: 1)
        let lane = AutomationLane(
            targetPath: .trackVolume(trackID: ID()),
            breakpoints: [AutomationBreakpoint(position: 1.0, value: 0.5)]
        )
        let container = Container(
            name: "Clip",
            startBar: 1.0,
            lengthBars: 4.0,
            automationLanes: [lane],
            midiSequence: MIDISequence(notes: [midiNote])
        )
        let track = Track(name: "MIDI 1", kind: .midi, containers: [container])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .adaptive,
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let builder = PlaybackGridSceneBuilder()
        builder.resolvedMIDISequenceProvider = { $0.midiSequence }
        let scene = builder.build(snapshot: snapshot)
        let picker = PlaybackGridPickingRenderer()

        let midiPick = picker.pick(
            at: midiNoteRect(
                note: midiNote,
                container: container,
                trackID: track.id,
                snapshot: snapshot
            ).center,
            scene: scene,
            snapshot: snapshot,
            visibleRect: CGRect(x: 0, y: 0, width: 1000, height: 500),
            canvasWidth: 1000
        )
        #expect(midiPick.kind == .midiNote)
        #expect(midiPick.midiNoteID == midiNote.id)

        let automationPick = picker.pick(
            at: CGPoint(x: 120, y: PlaybackGridLayout.trackAreaTop + 40),
            scene: scene,
            snapshot: snapshot,
            visibleRect: CGRect(x: 0, y: 0, width: 1000, height: 500),
            canvasWidth: 1000
        )
        #expect(automationPick.kind == .automationBreakpoint)
        #expect(automationPick.automationLaneID == lane.id)
    }

    @Test("Picking resolves MIDI notes in inline MIDI lane")
    func pickingMIDINoteInInlineLane() {
        let midiNote = MIDINoteEvent(pitch: 64, startBeat: 0, duration: 1)
        let container = Container(
            name: "Clip",
            startBar: 1.0,
            lengthBars: 4.0,
            midiSequence: MIDISequence(notes: [midiNote])
        )
        let track = Track(name: "MIDI 1", kind: .midi, containers: [container])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            inlineMIDILaneHeights: [track.id: 220],
            defaultTrackHeight: 80,
            gridMode: .adaptive,
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let builder = PlaybackGridSceneBuilder()
        builder.resolvedMIDISequenceProvider = { $0.midiSequence }
        let scene = builder.build(snapshot: snapshot)
        let picker = PlaybackGridPickingRenderer()

        let pick = picker.pick(
            at: midiNoteRect(
                note: midiNote,
                container: container,
                trackID: track.id,
                snapshot: snapshot
            ).center,
            scene: scene,
            snapshot: snapshot,
            visibleRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
            canvasWidth: 1000
        )

        #expect(pick.kind == .midiNote)
        #expect(pick.midiNoteID == midiNote.id)
    }

    @Test("Picking MIDI note edge zones for resize")
    func pickingMIDINoteResizeZones() {
        let midiNote = MIDINoteEvent(pitch: 64, startBeat: 0, duration: 2)
        let container = Container(
            name: "Clip",
            startBar: 1.0,
            lengthBars: 4.0,
            midiSequence: MIDISequence(notes: [midiNote])
        )
        let track = Track(name: "MIDI 1", kind: .midi, containers: [container])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            inlineMIDILaneHeights: [track.id: 220],
            defaultTrackHeight: 80,
            gridMode: .adaptive,
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let builder = PlaybackGridSceneBuilder()
        builder.resolvedMIDISequenceProvider = { $0.midiSequence }
        let scene = builder.build(snapshot: snapshot)
        let picker = PlaybackGridPickingRenderer()

        let noteRect = midiNoteRect(
            note: midiNote,
            container: container,
            trackID: track.id,
            snapshot: snapshot
        )

        let leftPick = picker.pick(
            at: CGPoint(x: noteRect.minX + 1, y: noteRect.midY),
            scene: scene,
            snapshot: snapshot,
            visibleRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
            canvasWidth: 1000
        )
        #expect(leftPick.kind == .midiNote)
        #expect(leftPick.zone == .resizeLeft)

        let rightPick = picker.pick(
            at: CGPoint(x: noteRect.maxX - 1, y: noteRect.midY),
            scene: scene,
            snapshot: snapshot,
            visibleRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
            canvasWidth: 1000
        )
        #expect(rightPick.kind == .midiNote)
        #expect(rightPick.zone == .resizeRight)
    }

    @Test("Picking short MIDI notes still exposes resize zones")
    func pickingShortMIDINoteResizeZones() {
        let midiNote = MIDINoteEvent(pitch: 64, startBeat: 0, duration: 0.25)
        let container = Container(
            name: "Clip",
            startBar: 1.0,
            lengthBars: 4.0,
            midiSequence: MIDISequence(notes: [midiNote])
        )
        let track = Track(name: "MIDI 1", kind: .midi, containers: [container])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            inlineMIDILaneHeights: [track.id: 220],
            defaultTrackHeight: 80,
            gridMode: .adaptive,
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let builder = PlaybackGridSceneBuilder()
        builder.resolvedMIDISequenceProvider = { $0.midiSequence }
        let scene = builder.build(snapshot: snapshot)
        let picker = PlaybackGridPickingRenderer()
        let noteRect = midiNoteRect(
            note: midiNote,
            container: container,
            trackID: track.id,
            snapshot: snapshot
        )

        let leftPick = picker.pick(
            at: CGPoint(x: noteRect.minX + 0.6, y: noteRect.midY),
            scene: scene,
            snapshot: snapshot,
            visibleRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
            canvasWidth: 1000
        )
        let rightPick = picker.pick(
            at: CGPoint(x: noteRect.maxX - 0.6, y: noteRect.midY),
            scene: scene,
            snapshot: snapshot,
            visibleRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
            canvasWidth: 1000
        )

        #expect(leftPick.kind == .midiNote)
        #expect(leftPick.zone == .resizeLeft)
        #expect(rightPick.kind == .midiNote)
        #expect(rightPick.zone == .resizeRight)
    }

    @Test("MIDI note right-edge drag resizes duration")
    func midiNoteRightEdgeDragResizesDuration() {
        let midiNote = MIDINoteEvent(pitch: 64, startBeat: 0, duration: 0.25)
        let container = Container(
            name: "Clip",
            startBar: 1.0,
            lengthBars: 4.0,
            midiSequence: MIDISequence(notes: [midiNote])
        )
        let track = Track(name: "MIDI 1", kind: .midi, containers: [container])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            inlineMIDILaneHeights: [track.id: 220],
            defaultTrackHeight: 80,
            gridMode: .fixed(.quarter),
            selectedContainerIDs: [container.id],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            isSnapEnabled: true,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let sink = CommandSinkSpy()
        let controller = PlaybackGridInteractionController(sink: sink)
        let noteRect = midiNoteRect(
            note: midiNote,
            container: container,
            trackID: track.id,
            snapshot: snapshot
        )

        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: CGPoint(x: noteRect.maxX - 0.6, y: noteRect.midY),
            pick: GridPickObject(
                id: 251,
                kind: .midiNote,
                containerID: container.id,
                trackID: track.id,
                midiNoteID: midiNote.id,
                zone: .resizeRight
            ),
            snapshot: snapshot
        )
        controller.handleMouseDragged(
            point: CGPoint(x: noteRect.maxX + 48, y: noteRect.midY),
            snapshot: snapshot
        )
        #expect(sink.lastUpdatedMIDINote == nil)
        controller.handleMouseUp(
            point: CGPoint(x: noteRect.maxX + 48, y: noteRect.midY),
            snapshot: snapshot
        )

        #expect(sink.lastUpdatedMIDINote != nil)
        #expect(sink.lastUpdatedMIDINote?.containerID == container.id)
        #expect((sink.lastUpdatedMIDINote?.note.duration ?? 0) > midiNote.duration)
    }

    @Test("Interaction controller emits playhead, range, move, clone and editor commands")
    func interactionControllerCommands() {
        let container = Container(name: "Clip", startBar: 1.0, lengthBars: 4.0)
        let track = Track(name: "Audio 1", kind: .audio, containers: [container])

        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .adaptive,
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let sink = CommandSinkSpy()
        let controller = PlaybackGridInteractionController(sink: sink)

        // Scrub from ruler click
        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: CGPoint(x: 240, y: 4),
            pick: GridPickObject(id: 1, kind: .ruler),
            snapshot: snapshot
        )
        #expect(sink.lastPlayheadBar != nil)

        // Shift-range select on ruler
        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: [.shift]),
            point: CGPoint(x: 120, y: 4),
            pick: GridPickObject(id: 2, kind: .ruler),
            snapshot: snapshot
        )
        controller.handleMouseUp(
            point: CGPoint(x: 360, y: 4),
            snapshot: snapshot
        )
        #expect(sink.lastRange != nil)

        // Container move drag by +1 bar
        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: CGPoint(x: 240, y: PlaybackGridLayout.trackAreaTop + 50),
            pick: GridPickObject(
                id: 3,
                kind: .containerZone,
                containerID: container.id,
                trackID: track.id,
                zone: .move
            ),
            snapshot: snapshot
        )
        controller.handleMouseDragged(
            point: CGPoint(x: 360, y: PlaybackGridLayout.trackAreaTop + 50),
            snapshot: snapshot
        )

        #expect(sink.lastMove != nil)
        if let move = sink.lastMove {
            #expect(move.containerID == container.id)
            #expect(move.trackID == track.id)
            #expect(abs(move.newStartBar - 2.0) < 0.01)
        }

        // Option-drag clones instead of moving the source container.
        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: [.option]),
            point: CGPoint(x: 240, y: PlaybackGridLayout.trackAreaTop + 50),
            pick: GridPickObject(
                id: 4,
                kind: .containerZone,
                containerID: container.id,
                trackID: track.id,
                zone: .move
            ),
            snapshot: snapshot
        )
        controller.handleMouseUp(
            point: CGPoint(x: 360, y: PlaybackGridLayout.trackAreaTop + 50),
            snapshot: snapshot
        )
        #expect(sink.lastClone != nil)
        if let clone = sink.lastClone {
            #expect(clone.containerID == container.id)
            #expect(clone.trackID == track.id)
            #expect(abs(clone.newStartBar - 2.0) < 0.01)
        }

        // Double-click opens the selected container editor.
        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: [], clickCount: 2),
            point: CGPoint(x: 240, y: PlaybackGridLayout.trackAreaTop + 50),
            pick: GridPickObject(
                id: 5,
                kind: .containerZone,
                containerID: container.id,
                trackID: track.id,
                zone: .move
            ),
            snapshot: snapshot
        )
        #expect(sink.lastOpenEditor != nil)
        if let editor = sink.lastOpenEditor {
            #expect(editor.containerID == container.id)
            #expect(editor.trackID == track.id)
        }

        // Track background taps snap playhead to timeline grid.
        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: CGPoint(x: 170, y: PlaybackGridLayout.trackAreaTop + 50),
            pick: GridPickObject(id: 6, kind: .trackBackground, trackID: track.id),
            snapshot: snapshot
        )
        #expect(sink.lastPlayheadBar == 2.0)
    }

    @Test("Interaction controller respects global snap settings")
    func interactionControllerRespectsGlobalSnap() {
        let container = Container(name: "Clip", startBar: 1.0, lengthBars: 4.0)
        let track = Track(name: "Audio 1", kind: .audio, containers: [container])

        let snapOffSnapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .fixed(.quarter),
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            isSnapEnabled: false,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let sink = CommandSinkSpy()
        let controller = PlaybackGridInteractionController(sink: sink)
        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: CGPoint(x: 123, y: PlaybackGridLayout.trackAreaTop + 50),
            pick: GridPickObject(id: 10, kind: .trackBackground, trackID: track.id),
            snapshot: snapOffSnapshot
        )

        // Raw bar when snapping is disabled.
        #expect(abs((sink.lastPlayheadBar ?? 0) - 2.025) < 0.0001)

        let snapOnSnapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .fixed(.quarter),
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            isSnapEnabled: true,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: CGPoint(x: 123, y: PlaybackGridLayout.trackAreaTop + 50),
            pick: GridPickObject(id: 11, kind: .trackBackground, trackID: track.id),
            snapshot: snapOnSnapshot
        )

        // Quarter-note snap in 4/4 => 0.25 bars.
        #expect(abs((sink.lastPlayheadBar ?? 0) - 2.0) < 0.0001)
    }

    @Test("Fade drag preserves curve and uses drag delta")
    func fadeDragPreservesCurveAndUsesDelta() {
        let container = Container(
            name: "Clip",
            startBar: 1.0,
            lengthBars: 4.0,
            enterFade: FadeSettings(duration: 1.0, curve: .exponential)
        )
        let track = Track(name: "Audio 1", kind: .audio, containers: [container])

        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .fixed(.quarter),
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            isSnapEnabled: true,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let sink = CommandSinkSpy()
        let controller = PlaybackGridInteractionController(sink: sink)
        let y = PlaybackGridLayout.trackAreaTop + 10

        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: CGPoint(x: 2, y: y),
            pick: GridPickObject(
                id: 20,
                kind: .containerZone,
                containerID: container.id,
                trackID: track.id,
                zone: .fadeLeft
            ),
            snapshot: snapshot
        )
        // +0.5 bars
        controller.handleMouseDragged(
            point: CGPoint(x: 62, y: y),
            snapshot: snapshot
        )

        #expect(sink.lastEnterFade != nil)
        #expect(abs((sink.lastEnterFade?.duration ?? 0) - 1.5) < 0.0001)
        #expect(sink.lastEnterFade?.curve == .exponential)
    }

    @Test("Option click deletes MIDI notes and automation breakpoints")
    func optionClickDeletesMIDINoteAndAutomationBreakpoint() {
        let note = MIDINoteEvent(pitch: 60, startBeat: 0, duration: 1)
        let lane = AutomationLane(
            targetPath: .trackVolume(trackID: ID()),
            breakpoints: [AutomationBreakpoint(position: 1.0, value: 0.5)]
        )
        let container = Container(
            name: "Clip",
            startBar: 1.0,
            lengthBars: 4.0,
            automationLanes: [lane],
            midiSequence: MIDISequence(notes: [note])
        )
        let track = Track(name: "MIDI 1", kind: .midi, containers: [container])

        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .adaptive,
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let sink = CommandSinkSpy()
        let controller = PlaybackGridInteractionController(sink: sink)
        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: [.option]),
            point: CGPoint(x: 10, y: PlaybackGridLayout.trackAreaTop + 70),
            pick: GridPickObject(
                id: 100,
                kind: .midiNote,
                containerID: container.id,
                trackID: track.id,
                midiNoteID: note.id
            ),
            snapshot: snapshot
        )

        #expect(sink.lastRemovedMIDINote?.containerID == container.id)
        #expect(sink.lastRemovedMIDINote?.noteID == note.id)

        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: [.option]),
            point: CGPoint(x: 120, y: PlaybackGridLayout.trackAreaTop + 40),
            pick: GridPickObject(
                id: 101,
                kind: .automationBreakpoint,
                containerID: container.id,
                trackID: track.id,
                automationLaneID: lane.id,
                automationBreakpointID: lane.breakpoints[0].id
            ),
            snapshot: snapshot
        )

        #expect(sink.lastRemovedAutomationBreakpoint?.containerID == container.id)
        #expect(sink.lastRemovedAutomationBreakpoint?.laneID == lane.id)
        #expect(sink.lastRemovedAutomationBreakpoint?.breakpointID == lane.breakpoints[0].id)
    }

    @Test("Track background drag creates container in free segment")
    func trackBackgroundDragCreatesContainer() {
        let track = Track(name: "Audio 1", kind: .audio, containers: [])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .adaptive,
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let sink = CommandSinkSpy()
        let controller = PlaybackGridInteractionController(sink: sink)

        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: CGPoint(x: 240, y: PlaybackGridLayout.trackAreaTop + 40),
            pick: GridPickObject(id: 200, kind: .trackBackground, trackID: track.id),
            snapshot: snapshot
        )
        controller.handleMouseDragged(
            point: CGPoint(x: 600, y: PlaybackGridLayout.trackAreaTop + 40),
            snapshot: snapshot
        )
        controller.handleMouseUp(
            point: CGPoint(x: 600, y: PlaybackGridLayout.trackAreaTop + 40),
            snapshot: snapshot
        )

        #expect(sink.lastCreatedContainer != nil)
        #expect(sink.lastCreatedContainer?.trackID == track.id)
        #expect(abs((sink.lastCreatedContainer?.startBar ?? 0) - 3.0) < 0.0001)
        #expect(abs((sink.lastCreatedContainer?.lengthBars ?? 0) - 3.0) < 0.0001)
    }

    @Test("Track background double click creates up to 4 bars and fills remaining free space")
    func trackBackgroundDoubleClickCreatesContainerWithGapClamp() {
        let existing = Container(name: "Existing", startBar: 7.0, lengthBars: 4.0)
        let track = Track(name: "Audio 1", kind: .audio, containers: [existing])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .adaptive,
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let sink = CommandSinkSpy()
        let controller = PlaybackGridInteractionController(sink: sink)

        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: [], clickCount: 2),
            point: CGPoint(x: 480, y: PlaybackGridLayout.trackAreaTop + 40),
            pick: GridPickObject(id: 201, kind: .trackBackground, trackID: track.id),
            snapshot: snapshot
        )

        #expect(sink.lastCreatedContainer != nil)
        #expect(sink.lastCreatedContainer?.trackID == track.id)
        #expect(abs((sink.lastCreatedContainer?.startBar ?? 0) - 5.0) < 0.0001)
        #expect(abs((sink.lastCreatedContainer?.lengthBars ?? 0) - 2.0) < 0.0001)
    }

    @Test("MIDI container drag in note-draw region creates snapped note")
    func midiContainerDragCreatesNote() {
        let container = Container(name: "MIDI", startBar: 1.0, lengthBars: 4.0, midiSequence: MIDISequence())
        let track = Track(name: "MIDI 1", kind: .midi, containers: [container])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .fixed(.quarter),
            selectedContainerIDs: [container.id],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            isSnapEnabled: true,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let sink = CommandSinkSpy()
        let controller = PlaybackGridInteractionController(sink: sink)

        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: CGPoint(x: 120, y: PlaybackGridLayout.trackAreaTop + 60),
            pick: GridPickObject(
                id: 300,
                kind: .containerZone,
                containerID: container.id,
                trackID: track.id,
                zone: .move
            ),
            snapshot: snapshot
        )
        controller.handleMouseUp(
            point: CGPoint(x: 240, y: PlaybackGridLayout.trackAreaTop + 60),
            snapshot: snapshot
        )

        #expect(sink.lastAddedMIDINote != nil)
        #expect(sink.lastAddedMIDINote?.containerID == container.id)
        #expect(abs((sink.lastAddedMIDINote?.note.startBeat ?? 0) - 4.0) < 0.0001)
        #expect(abs((sink.lastAddedMIDINote?.note.duration ?? 0) - 4.0) < 0.0001)
    }

    @Test("MIDI create emits preview note on/off")
    func midiCreateEmitsPreviewCallbacks() {
        let container = Container(name: "MIDI", startBar: 1.0, lengthBars: 4.0, midiSequence: MIDISequence())
        let track = Track(name: "MIDI 1", kind: .midi, containers: [container])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .fixed(.quarter),
            selectedContainerIDs: [container.id],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            isSnapEnabled: true,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let sink = CommandSinkSpy()
        let controller = PlaybackGridInteractionController(sink: sink)
        let startPoint = CGPoint(x: 120, y: PlaybackGridLayout.trackAreaTop + 60)
        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: startPoint,
            pick: GridPickObject(
                id: 301,
                kind: .containerZone,
                containerID: container.id,
                trackID: track.id,
                zone: .move
            ),
            snapshot: snapshot
        )
        controller.handleMouseUp(point: CGPoint(x: 240, y: startPoint.y), snapshot: snapshot)

        #expect(sink.midiPreviewEvents.count >= 2)
        #expect(sink.midiPreviewEvents.first?.isNoteOn == true)
        #expect(sink.midiPreviewEvents.last?.isNoteOn == false)
        #expect(sink.midiPreviewEvents.first?.pitch == sink.midiPreviewEvents.last?.pitch)
    }

    @Test("MIDI note create anchors to clicked snap cell at mouse-down")
    func midiCreateAnchorsToClickedSnapCell() {
        let container = Container(name: "MIDI", startBar: 1.0, lengthBars: 4.0, midiSequence: MIDISequence())
        let track = Track(name: "MIDI 1", kind: .midi, containers: [container])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .fixed(.quarter),
            selectedContainerIDs: [container.id],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            isSnapEnabled: true,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let sink = CommandSinkSpy()
        let controller = PlaybackGridInteractionController(sink: sink)

        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: CGPoint(x: 135, y: PlaybackGridLayout.trackAreaTop + 60),
            pick: GridPickObject(
                id: 350,
                kind: .containerZone,
                containerID: container.id,
                trackID: track.id,
                zone: .move
            ),
            snapshot: snapshot
        )
        controller.handleMouseUp(
            point: CGPoint(x: 240, y: PlaybackGridLayout.trackAreaTop + 60),
            snapshot: snapshot
        )

        #expect(sink.lastAddedMIDINote != nil)
        #expect(abs((sink.lastAddedMIDINote?.note.startBeat ?? 0) - 5.0) < 0.0001)
        #expect(abs((sink.lastAddedMIDINote?.note.duration ?? 0) - 3.0) < 0.0001)
    }

    @MainActor
    @Test("Expanded automation lane picks segment in pointer mode")
    func expandedAutomationSegmentPickPointerMode() {
        let path = EffectPath.trackVolume(trackID: ID())
        let lane = AutomationLane(targetPath: path, breakpoints: [])
        let track = Track(name: "Audio 1", kind: .audio, containers: [], trackAutomationLanes: [lane])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            automationExpandedTrackIDs: [track.id],
            automationSubLaneHeight: TimelineViewModel.automationSubLaneHeight,
            automationToolbarHeight: TimelineViewModel.automationToolbarHeight,
            defaultTrackHeight: 80,
            gridMode: .fixed(.quarter),
            selectedAutomationTool: .pointer,
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            isSnapEnabled: true,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )
        let scene = PlaybackGridSceneBuilder().build(snapshot: snapshot)
        let picker = PlaybackGridPickingRenderer()
        let y = PlaybackGridLayout.trackAreaTop
            + 80
            + TimelineViewModel.automationToolbarHeight
            + 8
        let pick = picker.pick(
            at: CGPoint(x: 240, y: y),
            scene: scene,
            snapshot: snapshot,
            visibleRect: CGRect(x: 0, y: 0, width: 1200, height: 900),
            canvasWidth: 1200
        )
        #expect(pick.kind == GridPickObjectKind.automationSegment)
        #expect(pick.containerID == nil)
        #expect(pick.automationLaneID == lane.id)
    }

    @Test("MIDI resolver keeps explicit pitch window stable across note sets")
    func midiResolverStableForExplicitConfig() {
        let trackID = ID<Track>()
        let snapshot = PlaybackGridSnapshot(
            tracks: [],
            sections: [],
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            inlineMIDIConfigs: [trackID: PlaybackGridMIDIConfig(lowPitch: 24, highPitch: 108, rowHeight: 12)],
            defaultTrackHeight: 80,
            gridMode: .fixed(.sixteenth),
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            isSnapEnabled: true,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let lowNotes = [MIDINoteEvent(pitch: 36, startBeat: 0, duration: 1)]
        let highNotes = [MIDINoteEvent(pitch: 84, startBeat: 0, duration: 1)]

        let layoutA = PlaybackGridMIDIViewResolver.resolveLayout(
            notes: lowNotes,
            trackID: trackID,
            laneHeight: 120,
            snapshot: snapshot
        )
        let layoutB = PlaybackGridMIDIViewResolver.resolveLayout(
            notes: highNotes,
            trackID: trackID,
            laneHeight: 120,
            snapshot: snapshot
        )

        #expect(layoutA.lowPitch == layoutB.lowPitch)
        #expect(layoutA.highPitch == layoutB.highPitch)
        #expect(layoutA.rows == layoutB.rows)
        #expect(abs(layoutA.rowHeight - layoutB.rowHeight) < 0.0001)
        #expect(abs(layoutA.rowHeight - 12) < 0.0001)
        #expect(abs(layoutB.rowHeight - 12) < 0.0001)
        #expect(layoutA.rows <= 10) // laneHeight(120) / rowHeight(12)
        #expect(layoutA.lowPitch == 99)
        #expect(layoutA.highPitch == 108)
        #expect(layoutB.rows <= 10)
        #expect(layoutB.lowPitch == 99)
        #expect(layoutB.highPitch == 108)
    }

    @Test("MIDI resolver auto mode keeps existing note pitches visible")
    func midiResolverAutoModeKeepsNotesVisible() {
        let trackID = ID<Track>()
        let snapshot = PlaybackGridSnapshot(
            tracks: [],
            sections: [],
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .fixed(.sixteenth),
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            isSnapEnabled: true,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let notes = [
            MIDINoteEvent(pitch: 64, startBeat: 0, duration: 1),
            MIDINoteEvent(pitch: 67, startBeat: 2, duration: 1)
        ]
        let layout = PlaybackGridMIDIViewResolver.resolveLayout(
            notes: notes,
            trackID: trackID,
            laneHeight: 80,
            snapshot: snapshot
        )

        #expect(Int(layout.lowPitch) <= 64)
        #expect(Int(layout.highPitch) >= 67)
    }

    @Test("Picking ignores MIDI notes outside configured lane range")
    func pickingIgnoresOutOfRangeMIDINotes() {
        let outOfRangeNote = MIDINoteEvent(pitch: 98, startBeat: 0, duration: 1)
        let container = Container(
            name: "Clip",
            startBar: 1.0,
            lengthBars: 4.0,
            midiSequence: MIDISequence(notes: [outOfRangeNote])
        )
        let track = Track(name: "MIDI 1", kind: .midi, containers: [container])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            inlineMIDILaneHeights: [track.id: 220],
            inlineMIDIConfigs: [track.id: PlaybackGridMIDIConfig(lowPitch: 48, highPitch: 72, rowHeight: 12)],
            defaultTrackHeight: 80,
            gridMode: .adaptive,
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let builder = PlaybackGridSceneBuilder()
        builder.resolvedMIDISequenceProvider = { $0.midiSequence }
        let scene = builder.build(snapshot: snapshot)
        let picker = PlaybackGridPickingRenderer()

        let point = midiNoteRect(
            note: outOfRangeNote,
            container: container,
            trackID: track.id,
            snapshot: snapshot
        ).center

        let pick = picker.pick(
            at: point,
            scene: scene,
            snapshot: snapshot,
            visibleRect: CGRect(x: 0, y: 0, width: 1200, height: 900),
            canvasWidth: 1200
        )

        #expect(pick.kind != .midiNote)
    }

    @Test("MIDI note rects are clipped to lane bounds")
    func midiNoteRectsAreClippedToLaneBounds() {
        let laneRect = CGRect(x: 120, y: 300, width: 480, height: 180)
        let resolved = PlaybackGridMIDIResolvedLayout(
            lowPitch: 60,
            highPitch: 72,
            rowHeight: laneRect.height / 13.0,
            rows: 13
        )
        let inRange = MIDINoteEvent(pitch: 66, startBeat: 1, duration: 2)
        let belowRange = MIDINoteEvent(pitch: 40, startBeat: 1, duration: 2)

        let inRangeRect = PlaybackGridMIDIViewResolver.noteRect(
            note: inRange,
            containerLengthBars: 4,
            laneRect: laneRect,
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            resolved: resolved
        )
        let belowRangeRect = PlaybackGridMIDIViewResolver.noteRect(
            note: belowRange,
            containerLengthBars: 4,
            laneRect: laneRect,
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            resolved: resolved
        )

        #expect(inRangeRect != nil)
        #expect((inRangeRect?.minY ?? 0) >= laneRect.minY)
        #expect((inRangeRect?.maxY ?? 0) <= laneRect.maxY)
        #expect((inRangeRect?.minX ?? 0) >= laneRect.minX)
        #expect((inRangeRect?.maxX ?? 0) <= laneRect.maxX)
        #expect(belowRangeRect == nil)
    }

    @Test("MIDI track background drag in inline lane creates note in selected container")
    func midiTrackBackgroundDragCreatesNote() {
        let container = Container(name: "MIDI", startBar: 1.0, lengthBars: 4.0, midiSequence: MIDISequence())
        let track = Track(name: "MIDI 1", kind: .midi, containers: [container])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            inlineMIDILaneHeights: [track.id: 220],
            defaultTrackHeight: 80,
            gridMode: .fixed(.quarter),
            selectedContainerIDs: [container.id],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            isSnapEnabled: true,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let sink = CommandSinkSpy()
        let controller = PlaybackGridInteractionController(sink: sink)

        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: CGPoint(x: 120, y: PlaybackGridLayout.trackAreaTop + 180),
            pick: GridPickObject(id: 301, kind: .trackBackground, trackID: track.id),
            snapshot: snapshot
        )
        controller.handleMouseUp(
            point: CGPoint(x: 180, y: PlaybackGridLayout.trackAreaTop + 180),
            snapshot: snapshot
        )

        #expect(sink.lastAddedMIDINote != nil)
        #expect(sink.lastAddedMIDINote?.containerID == container.id)
        #expect(abs((sink.lastAddedMIDINote?.note.startBeat ?? 0) - 4.0) < 0.0001)
        #expect(abs((sink.lastAddedMIDINote?.note.duration ?? 0) - 2.0) < 0.0001)
    }

    @Test("Inline MIDI lane empty-space drag does not create audio-style container")
    func midiInlineLaneEmptySpaceDoesNotCreateContainer() {
        let container = Container(name: "MIDI", startBar: 1.0, lengthBars: 2.0, midiSequence: MIDISequence())
        let track = Track(name: "MIDI 1", kind: .midi, containers: [container])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            inlineMIDILaneHeights: [track.id: 220],
            defaultTrackHeight: 80,
            gridMode: .fixed(.quarter),
            selectedContainerIDs: [container.id],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            isSnapEnabled: true,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let sink = CommandSinkSpy()
        let controller = PlaybackGridInteractionController(sink: sink)

        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: CGPoint(x: 420, y: PlaybackGridLayout.trackAreaTop + 180),
            pick: GridPickObject(id: 302, kind: .trackBackground, trackID: track.id),
            snapshot: snapshot
        )
        controller.handleMouseDragged(
            point: CGPoint(x: 600, y: PlaybackGridLayout.trackAreaTop + 180),
            snapshot: snapshot
        )
        controller.handleMouseUp(
            point: CGPoint(x: 600, y: PlaybackGridLayout.trackAreaTop + 180),
            snapshot: snapshot
        )

        #expect(sink.lastCreatedContainer == nil)
        #expect(sink.lastAddedMIDINote == nil)
    }

    @Test("Inline MIDI lane bottom-edge drag resizes lane height")
    func midiInlineLaneResizeDragChangesHeight() {
        let container = Container(name: "MIDI", startBar: 1.0, lengthBars: 2.0, midiSequence: MIDISequence())
        let track = Track(name: "MIDI 1", kind: .midi, containers: [container])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            inlineMIDILaneHeights: [track.id: 220],
            defaultTrackHeight: 80,
            gridMode: .fixed(.quarter),
            selectedContainerIDs: [container.id],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            isSnapEnabled: true,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let sink = CommandSinkSpy()
        let controller = PlaybackGridInteractionController(sink: sink)
        let laneBottomY = PlaybackGridLayout.trackAreaTop + 80 + 220

        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: CGPoint(x: 420, y: laneBottomY),
            pick: GridPickObject(id: 303, kind: .trackBackground, trackID: track.id),
            snapshot: snapshot
        )
        controller.handleMouseDragged(
            point: CGPoint(x: 420, y: laneBottomY + 60),
            snapshot: snapshot
        )
        controller.handleMouseUp(
            point: CGPoint(x: 420, y: laneBottomY + 60),
            snapshot: snapshot
        )

        #expect(sink.lastInlineMIDILaneHeight != nil)
        #expect(sink.lastInlineMIDILaneHeight?.trackID == track.id)
        #expect(abs((sink.lastInlineMIDILaneHeight?.height ?? 0) - 280) < 0.001)
    }

    @Test("Automation breakpoint drag supports command snap inversion and shift fine mode")
    func automationBreakpointDragSupportsModifierBehavior() {
        let breakpoint = AutomationBreakpoint(position: 1.0, value: 0.5)
        let lane = AutomationLane(
            targetPath: .trackVolume(trackID: ID()),
            breakpoints: [breakpoint]
        )
        let container = Container(
            name: "Auto",
            startBar: 1.0,
            lengthBars: 4.0,
            automationLanes: [lane]
        )
        let track = Track(name: "Audio 1", kind: .audio, containers: [container])
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            defaultTrackHeight: 80,
            gridMode: .fixed(.quarter),
            selectedAutomationTool: .pointer,
            selectedContainerIDs: [container.id],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            isSnapEnabled: true,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let sink = CommandSinkSpy()
        let controller = PlaybackGridInteractionController(sink: sink)
        let startPoint = CGPoint(x: 120, y: PlaybackGridLayout.trackAreaTop + 12)
        let dragPoint = CGPoint(x: 168, y: PlaybackGridLayout.trackAreaTop)

        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: startPoint,
            pick: GridPickObject(
                id: 400,
                kind: .automationBreakpoint,
                containerID: container.id,
                trackID: track.id,
                automationLaneID: lane.id,
                automationBreakpointID: breakpoint.id
            ),
            snapshot: snapshot
        )
        controller.handleMouseDragged(
            point: dragPoint,
            snapshot: snapshot,
            modifiers: [.command]
        )
        let unsnappedPosition = sink.lastUpdatedAutomationBreakpoint?.breakpoint.position
        #expect(unsnappedPosition != nil)
        #expect(abs((unsnappedPosition ?? 0) - 1.4) < 0.001)

        controller.handleMouseDragged(
            point: dragPoint,
            snapshot: snapshot,
            modifiers: [.shift, .command]
        )
        let fineValue = sink.lastUpdatedAutomationBreakpoint?.breakpoint.value
        #expect(fineValue != nil)
        #expect((fineValue ?? 0) > 0.5)
        #expect((fineValue ?? 0) < 0.7)
    }

    @Test("Track automation segment click adds breakpoint and drag updates it")
    func trackAutomationSegmentAddAndDrag() {
        let trackID = ID<Track>()
        let lane = AutomationLane(
            targetPath: .trackVolume(trackID: trackID),
            breakpoints: []
        )
        let track = Track(
            id: trackID,
            name: "Audio 1",
            kind: .audio,
            containers: [],
            trackAutomationLanes: [lane]
        )
        let snapshot = PlaybackGridSnapshot(
            tracks: [track],
            sections: [],
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            pixelsPerBar: 120,
            totalBars: 64,
            trackHeights: [:],
            automationExpandedTrackIDs: [trackID],
            automationSubLaneHeight: 40,
            automationToolbarHeight: 26,
            defaultTrackHeight: 80,
            gridMode: .fixed(.quarter),
            selectedAutomationTool: .pointer,
            selectedContainerIDs: [],
            selectedSectionID: nil,
            selectedRange: nil,
            rangeSelection: nil,
            isSnapEnabled: true,
            showRulerAndSections: true,
            playheadBar: 1,
            cursorX: nil
        )

        let laneY = PlaybackGridLayout.trackAreaTop + 80 + 26 + 20
        let addPoint = CGPoint(x: 240, y: laneY)
        let dragPoint = CGPoint(x: 300, y: laneY - 8)
        let sink = CommandSinkSpy()
        let controller = PlaybackGridInteractionController(sink: sink)

        controller.handleMouseDown(
            event: makeMouseEvent(type: .leftMouseDown, modifiers: []),
            point: addPoint,
            pick: GridPickObject(
                id: 500,
                kind: .automationSegment,
                containerID: nil,
                trackID: trackID,
                automationLaneID: lane.id
            ),
            snapshot: snapshot
        )

        #expect(sink.lastAddedTrackAutomationBreakpoint != nil)
        #expect(sink.lastAddedTrackAutomationBreakpoint?.trackID == trackID)
        #expect(sink.lastAddedTrackAutomationBreakpoint?.laneID == lane.id)

        controller.handleMouseDragged(
            point: dragPoint,
            snapshot: snapshot,
            modifiers: [.command]
        )

        #expect(sink.lastUpdatedTrackAutomationBreakpoint != nil)
        #expect(sink.lastUpdatedTrackAutomationBreakpoint?.trackID == trackID)
        #expect(sink.lastUpdatedTrackAutomationBreakpoint?.laneID == lane.id)
        #expect((sink.lastUpdatedTrackAutomationBreakpoint?.breakpoint.position ?? 0) > 2.0)
        #expect((sink.lastUpdatedTrackAutomationBreakpoint?.breakpoint.value ?? 0) > 0.55)
    }

    private func makeMouseEvent(
        type: NSEvent.EventType,
        modifiers: NSEvent.ModifierFlags,
        clickCount: Int = 1
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        )!
    }

    private func midiNoteRect(
        note: MIDINoteEvent,
        container: Container,
        trackID: ID<Track>,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect {
        var yOffset: CGFloat = snapshot.showRulerAndSections ? PlaybackGridLayout.trackAreaTop : 0
        var baseRect = CGRect.zero

        for track in snapshot.tracks {
            let baseHeight = snapshot.trackHeights[track.id] ?? snapshot.defaultTrackHeight
            let automationExtra: CGFloat = {
                guard snapshot.automationExpandedTrackIDs.contains(track.id) else { return 0 }
                var seen = Set<EffectPath>()
                var count = 0
                for lane in track.trackAutomationLanes where seen.insert(lane.targetPath).inserted {
                    count += 1
                }
                for container in track.containers {
                    for lane in container.automationLanes where seen.insert(lane.targetPath).inserted {
                        count += 1
                    }
                }
                guard count > 0 else { return 0 }
                return snapshot.automationToolbarHeight + (CGFloat(count) * snapshot.automationSubLaneHeight)
            }()
            let inlineHeight = snapshot.inlineMIDILaneHeights[track.id] ?? 0
            defer { yOffset += baseHeight + automationExtra + inlineHeight }
            guard track.id == trackID else { continue }
            baseRect = CGRect(
                x: CGFloat(container.startBar - 1.0) * snapshot.pixelsPerBar,
                y: yOffset,
                width: CGFloat(container.lengthBars) * snapshot.pixelsPerBar,
                height: baseHeight
            )
            if inlineHeight > 0 {
                baseRect = CGRect(
                    x: baseRect.minX,
                    y: baseRect.maxY + automationExtra,
                    width: baseRect.width,
                    height: inlineHeight
                )
            }
            break
        }

        let track = snapshot.tracks.first { $0.id == trackID }
        let resolved = track.map {
            PlaybackGridMIDIViewResolver.resolveTrackLayout(
                track: $0,
                laneHeight: baseRect.height,
                snapshot: snapshot
            )
        } ?? PlaybackGridMIDIViewResolver.resolveLayout(
            notes: [],
            trackID: trackID,
            laneHeight: baseRect.height,
            snapshot: snapshot
        )
        return PlaybackGridMIDIViewResolver.noteRect(
            note: note,
            containerLengthBars: container.lengthBars,
            laneRect: baseRect,
            timeSignature: snapshot.timeSignature,
            resolved: resolved,
            minimumWidth: 8
        ) ?? .zero
    }
}

private final class CommandSinkSpy: PlaybackGridCommandSink {
    var lastPlayheadBar: Double?
    var lastRange: ClosedRange<Int>?
    var lastMove: (containerID: ID<Container>, trackID: ID<Track>, newStartBar: Double)?
    var lastClone: (containerID: ID<Container>, trackID: ID<Track>, newStartBar: Double)?
    var lastSelection: (containerID: ID<Container>, trackID: ID<Track>, modifiers: NSEvent.ModifierFlags)?
    var lastOpenEditor: (containerID: ID<Container>, trackID: ID<Track>)?
    var lastEnterFade: FadeSettings?
    var lastExitFade: FadeSettings?
    var lastRemovedMIDINote: (containerID: ID<Container>, noteID: ID<MIDINoteEvent>)?
    var lastRemovedAutomationBreakpoint: (containerID: ID<Container>, laneID: ID<AutomationLane>, breakpointID: ID<AutomationBreakpoint>)?
    var lastCreatedContainer: (trackID: ID<Track>, startBar: Double, lengthBars: Double)?
    var lastAddedMIDINote: (containerID: ID<Container>, note: MIDINoteEvent)?
    var lastInlineMIDILaneHeight: (trackID: ID<Track>, height: CGFloat)?
    var lastUpdatedAutomationBreakpoint: (containerID: ID<Container>, laneID: ID<AutomationLane>, breakpoint: AutomationBreakpoint)?
    var lastAddedTrackAutomationBreakpoint: (trackID: ID<Track>, laneID: ID<AutomationLane>, breakpoint: AutomationBreakpoint)?
    var lastUpdatedTrackAutomationBreakpoint: (trackID: ID<Track>, laneID: ID<AutomationLane>, breakpoint: AutomationBreakpoint)?
    var lastRemovedTrackAutomationBreakpoint: (trackID: ID<Track>, laneID: ID<AutomationLane>, breakpointID: ID<AutomationBreakpoint>)?
    var lastReplacedTrackAutomationBreakpoints: (trackID: ID<Track>, laneID: ID<AutomationLane>, start: Double, end: Double, breakpoints: [AutomationBreakpoint])?
    var lastUpdatedMIDINote: (containerID: ID<Container>, note: MIDINoteEvent)?
    var midiPreviewEvents: [(pitch: UInt8, isNoteOn: Bool)] = []
    var createContainerResult = true

    func setPlayhead(bar: Double) {
        lastPlayheadBar = bar
    }

    func selectRange(_ range: ClosedRange<Int>) {
        lastRange = range
    }

    func moveContainer(_ containerID: ID<Container>, trackID: ID<Track>, newStartBar: Double) {
        lastMove = (containerID, trackID, newStartBar)
    }

    func cloneContainer(_ containerID: ID<Container>, trackID: ID<Track>, newStartBar: Double) {
        lastClone = (containerID, trackID, newStartBar)
    }

    func selectContainer(_ containerID: ID<Container>, trackID: ID<Track>, modifiers: NSEvent.ModifierFlags) {
        lastSelection = (containerID, trackID, modifiers)
    }

    func openContainerEditor(_ containerID: ID<Container>, trackID: ID<Track>) {
        lastOpenEditor = (containerID, trackID)
    }

    func setContainerEnterFade(_ containerID: ID<Container>, fade: FadeSettings?) {
        lastEnterFade = fade
    }

    func setContainerExitFade(_ containerID: ID<Container>, fade: FadeSettings?) {
        lastExitFade = fade
    }

    func createContainer(trackID: ID<Track>, startBar: Double, lengthBars: Double) -> Bool {
        lastCreatedContainer = (trackID, startBar, lengthBars)
        return createContainerResult
    }

    func addMIDINote(_ containerID: ID<Container>, note: MIDINoteEvent) {
        lastAddedMIDINote = (containerID, note)
    }

    func updateMIDINote(_ containerID: ID<Container>, note: MIDINoteEvent) {
        lastUpdatedMIDINote = (containerID, note)
    }

    func setInlineMIDILaneHeight(trackID: ID<Track>, height: CGFloat) {
        lastInlineMIDILaneHeight = (trackID, height)
    }

    func removeMIDINote(_ containerID: ID<Container>, noteID: ID<MIDINoteEvent>) {
        lastRemovedMIDINote = (containerID, noteID)
    }

    func previewMIDINote(pitch: UInt8, isNoteOn: Bool) {
        midiPreviewEvents.append((pitch: pitch, isNoteOn: isNoteOn))
    }

    func removeAutomationBreakpoint(_ containerID: ID<Container>, laneID: ID<AutomationLane>, breakpointID: ID<AutomationBreakpoint>) {
        lastRemovedAutomationBreakpoint = (containerID, laneID, breakpointID)
    }

    func updateAutomationBreakpoint(_ containerID: ID<Container>, laneID: ID<AutomationLane>, breakpoint: AutomationBreakpoint) {
        lastUpdatedAutomationBreakpoint = (containerID, laneID, breakpoint)
    }

    func addTrackAutomationBreakpoint(trackID: ID<Track>, laneID: ID<AutomationLane>, breakpoint: AutomationBreakpoint) {
        lastAddedTrackAutomationBreakpoint = (trackID, laneID, breakpoint)
    }

    func updateTrackAutomationBreakpoint(trackID: ID<Track>, laneID: ID<AutomationLane>, breakpoint: AutomationBreakpoint) {
        lastUpdatedTrackAutomationBreakpoint = (trackID, laneID, breakpoint)
    }

    func removeTrackAutomationBreakpoint(trackID: ID<Track>, laneID: ID<AutomationLane>, breakpointID: ID<AutomationBreakpoint>) {
        lastRemovedTrackAutomationBreakpoint = (trackID, laneID, breakpointID)
    }

    func replaceTrackAutomationBreakpoints(
        trackID: ID<Track>,
        laneID: ID<AutomationLane>,
        startPosition: Double,
        endPosition: Double,
        breakpoints: [AutomationBreakpoint]
    ) {
        lastReplacedTrackAutomationBreakpoints = (trackID, laneID, startPosition, endPosition, breakpoints)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
