import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore
@testable import LoopsEngine

@Suite("MIDI Editor Tests")
struct MIDIEditorTests {

    /// Helper: adds a MIDI track with a container and returns (trackID, containerID).
    @MainActor
    private func makeVM() -> (ProjectViewModel, ID<Track>, ID<Container>) {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id
        return (vm, trackID, containerID)
    }

    // MARK: - ProjectViewModel MIDI Sequence Editing

    @Test("setContainerMIDISequence sets sequence on container")
    @MainActor
    func setMIDISequence() {
        let (vm, _, containerID) = makeVM()

        let seq = MIDISequence(notes: [
            MIDINoteEvent(pitch: 60, velocity: 100, startBeat: 0.0, duration: 1.0),
        ])
        vm.setContainerMIDISequence(containerID: containerID, sequence: seq)

        let container = vm.project.songs[0].tracks[0].containers[0]
        #expect(container.midiSequence != nil)
        #expect(container.midiSequence?.notes.count == 1)
        #expect(container.midiSequence?.notes[0].pitch == 60)
    }

    @Test("addMIDINote creates sequence if needed")
    @MainActor
    func addNoteCreatesSequence() {
        let (vm, _, containerID) = makeVM()

        // Container starts with no MIDI sequence
        #expect(vm.project.songs[0].tracks[0].containers[0].midiSequence == nil)

        let note = MIDINoteEvent(pitch: 64, velocity: 80, startBeat: 1.0, duration: 0.5)
        vm.addMIDINote(containerID: containerID, note: note)

        let container = vm.project.songs[0].tracks[0].containers[0]
        #expect(container.midiSequence != nil)
        #expect(container.midiSequence?.notes.count == 1)
        #expect(container.midiSequence?.notes[0].pitch == 64)
    }

    @Test("addMIDINote appends to existing sequence")
    @MainActor
    func addNoteAppendsToExisting() {
        let (vm, _, containerID) = makeVM()

        let note1 = MIDINoteEvent(pitch: 60, startBeat: 0.0)
        let note2 = MIDINoteEvent(pitch: 64, startBeat: 1.0)
        vm.addMIDINote(containerID: containerID, note: note1)
        vm.addMIDINote(containerID: containerID, note: note2)

        #expect(vm.project.songs[0].tracks[0].containers[0].midiSequence?.notes.count == 2)
    }

    @Test("removeMIDINote removes specific note")
    @MainActor
    func removeMIDINote() {
        let (vm, _, containerID) = makeVM()

        let note1 = MIDINoteEvent(pitch: 60, startBeat: 0.0)
        let note2 = MIDINoteEvent(pitch: 64, startBeat: 1.0)
        vm.addMIDINote(containerID: containerID, note: note1)
        vm.addMIDINote(containerID: containerID, note: note2)

        vm.removeMIDINote(containerID: containerID, noteID: note1.id)

        let notes = vm.project.songs[0].tracks[0].containers[0].midiSequence?.notes
        #expect(notes?.count == 1)
        #expect(notes?[0].pitch == 64)
    }

    @Test("updateMIDINote modifies existing note")
    @MainActor
    func updateMIDINote() {
        let (vm, _, containerID) = makeVM()

        var note = MIDINoteEvent(pitch: 60, velocity: 100, startBeat: 0.0, duration: 1.0)
        vm.addMIDINote(containerID: containerID, note: note)

        // Move the note
        note.pitch = 72
        note.startBeat = 2.0
        note.velocity = 80
        vm.updateMIDINote(containerID: containerID, note: note)

        let updated = vm.project.songs[0].tracks[0].containers[0].midiSequence?.notes[0]
        #expect(updated?.pitch == 72)
        #expect(updated?.startBeat == 2.0)
        #expect(updated?.velocity == 80)
    }

    @Test("MIDI editing marks field as overridden on clones")
    @MainActor
    func midiEditMarksOverridden() {
        let (vm, trackID, containerID) = makeVM()

        // Set sequence
        let seq = MIDISequence(notes: [MIDINoteEvent(pitch: 60, startBeat: 0)])
        vm.setContainerMIDISequence(containerID: containerID, sequence: seq)

        // Create a clone
        vm.cloneContainer(trackID: trackID, containerID: containerID, newStartBar: 5)
        let clone = vm.project.songs[0].tracks[0].containers.first(where: { $0.startBar == 5 })!

        // Initially, midiSequence is not overridden
        #expect(!clone.overriddenFields.contains(.midiSequence))

        // Add a note to the clone — should mark as overridden
        let note = MIDINoteEvent(pitch: 72, startBeat: 0)
        vm.addMIDINote(containerID: clone.id, note: note)

        let updatedClone = vm.project.songs[0].tracks[0].containers.first(where: { $0.id == clone.id })!
        #expect(updatedClone.overriddenFields.contains(.midiSequence))
    }

    @Test("setContainerMIDISequence undo/redo")
    @MainActor
    func setMIDISequenceUndoRedo() {
        let (vm, _, containerID) = makeVM()

        let seq = MIDISequence(notes: [MIDINoteEvent(pitch: 60, startBeat: 0)])
        vm.setContainerMIDISequence(containerID: containerID, sequence: seq)
        #expect(vm.project.songs[0].tracks[0].containers[0].midiSequence?.notes.count == 1)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].containers[0].midiSequence == nil)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].containers[0].midiSequence?.notes.count == 1)
    }

    @Test("addMIDINote undo/redo")
    @MainActor
    func addNoteUndoRedo() {
        let (vm, _, containerID) = makeVM()

        let note = MIDINoteEvent(pitch: 60, startBeat: 0)
        vm.addMIDINote(containerID: containerID, note: note)
        #expect(vm.project.songs[0].tracks[0].containers[0].midiSequence?.notes.count == 1)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].containers[0].midiSequence == nil)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].containers[0].midiSequence?.notes.count == 1)
    }

    // MARK: - PianoRollLayout coordinate mapping

    @Test("PianoRollLayout yPosition maps higher pitch to lower Y")
    func yPositionMapping() {
        let lowPitch: UInt8 = 36
        let highPitch: UInt8 = 96

        let yHigh = PianoRollLayout.yPosition(forPitch: 96, lowPitch: lowPitch, highPitch: highPitch)
        let yLow = PianoRollLayout.yPosition(forPitch: 36, lowPitch: lowPitch, highPitch: highPitch)
        #expect(yHigh == 0)
        #expect(yLow == CGFloat(96 - 36) * PianoRollLayout.defaultRowHeight)
    }

    @Test("PianoRollLayout pitch round-trip from Y position")
    func pitchYRoundTrip() {
        let lowPitch: UInt8 = 36
        let highPitch: UInt8 = 96
        let testPitch: UInt8 = 60

        let y = PianoRollLayout.yPosition(forPitch: testPitch, lowPitch: lowPitch, highPitch: highPitch)
        let recovered = PianoRollLayout.pitch(forY: y, lowPitch: lowPitch, highPitch: highPitch)
        #expect(recovered == testPitch)
    }

    @Test("PianoRollLayout beat/X round-trip")
    func beatXRoundTrip() {
        let pxPerBeat: CGFloat = 40
        let beat: Double = 3.5
        let x = PianoRollLayout.xPosition(forBeat: beat, pixelsPerBeat: pxPerBeat)
        let recovered = PianoRollLayout.beat(forX: x, pixelsPerBeat: pxPerBeat)
        #expect(abs(recovered - beat) < 0.001)
    }

    @Test("PianoRollLayout totalHeight calculation")
    func totalHeight() {
        let h = PianoRollLayout.totalHeight(lowPitch: 36, highPitch: 96)
        #expect(h == CGFloat(96 - 36 + 1) * PianoRollLayout.defaultRowHeight)
    }

    @Test("PianoRollLayout negative X clamps to 0")
    func negativeXClamps() {
        let beat = PianoRollLayout.beat(forX: -100, pixelsPerBeat: 40)
        #expect(beat == 0)
    }
}
