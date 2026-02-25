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
            at: CGPoint(x: 12, y: PlaybackGridLayout.trackAreaTop + 79),
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

    func removeMIDINote(_ containerID: ID<Container>, noteID: ID<MIDINoteEvent>) {
        lastRemovedMIDINote = (containerID, noteID)
    }

    func removeAutomationBreakpoint(_ containerID: ID<Container>, laneID: ID<AutomationLane>, breakpointID: ID<AutomationBreakpoint>) {
        lastRemovedAutomationBreakpoint = (containerID, laneID, breakpointID)
    }
}
