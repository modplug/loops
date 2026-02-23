import Testing
import Foundation
@testable import LoopsCore

@Suite("MIDINoteEvent and MIDISequence Tests")
struct MIDISequenceTests {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - MIDINoteEvent

    @Test("MIDINoteEvent Codable round-trip")
    func noteEventRoundTrip() throws {
        let note = MIDINoteEvent(pitch: 60, velocity: 100, startBeat: 1.5, duration: 0.5, channel: 3)
        let decoded = try roundTrip(note)
        #expect(decoded == note)
        #expect(decoded.pitch == 60)
        #expect(decoded.velocity == 100)
        #expect(decoded.startBeat == 1.5)
        #expect(decoded.duration == 0.5)
        #expect(decoded.channel == 3)
    }

    @Test("MIDINoteEvent endBeat computed property")
    func noteEventEndBeat() {
        let note = MIDINoteEvent(pitch: 60, velocity: 80, startBeat: 2.0, duration: 1.5)
        #expect(note.endBeat == 3.5)
    }

    @Test("MIDINoteEvent default values")
    func noteEventDefaults() {
        let note = MIDINoteEvent(pitch: 48, startBeat: 0)
        #expect(note.velocity == 100)
        #expect(note.duration == 1.0)
        #expect(note.channel == 0)
    }

    // MARK: - MIDISequence

    @Test("MIDISequence Codable round-trip")
    func sequenceRoundTrip() throws {
        let seq = MIDISequence(notes: [
            MIDINoteEvent(pitch: 60, velocity: 100, startBeat: 0.0, duration: 1.0),
            MIDINoteEvent(pitch: 64, velocity: 80, startBeat: 1.0, duration: 0.5),
            MIDINoteEvent(pitch: 67, velocity: 90, startBeat: 2.0, duration: 1.0),
        ])
        let decoded = try roundTrip(seq)
        #expect(decoded == seq)
        #expect(decoded.notes.count == 3)
    }

    @Test("MIDISequence empty round-trip")
    func emptySequenceRoundTrip() throws {
        let seq = MIDISequence()
        let decoded = try roundTrip(seq)
        #expect(decoded == seq)
        #expect(decoded.notes.isEmpty)
    }

    @Test("MIDISequence sortedNotes returns notes by startBeat")
    func sortedNotes() {
        let seq = MIDISequence(notes: [
            MIDINoteEvent(pitch: 67, startBeat: 2.0),
            MIDINoteEvent(pitch: 60, startBeat: 0.0),
            MIDINoteEvent(pitch: 64, startBeat: 1.0),
        ])
        let sorted = seq.sortedNotes
        #expect(sorted[0].pitch == 60)
        #expect(sorted[1].pitch == 64)
        #expect(sorted[2].pitch == 67)
    }

    @Test("MIDISequence notes(inRange:) filters correctly")
    func notesInRange() {
        let seq = MIDISequence(notes: [
            MIDINoteEvent(pitch: 60, startBeat: 0.0, duration: 1.0),  // 0-1
            MIDINoteEvent(pitch: 64, startBeat: 1.0, duration: 1.0),  // 1-2
            MIDINoteEvent(pitch: 67, startBeat: 2.0, duration: 1.0),  // 2-3
            MIDINoteEvent(pitch: 72, startBeat: 3.0, duration: 1.0),  // 3-4
        ])
        // Range 1.5-2.5 should include notes at beats 1-2 and 2-3
        let filtered = seq.notes(inRange: 1.5, endBeat: 2.5)
        #expect(filtered.count == 2)
        #expect(filtered.contains(where: { $0.pitch == 64 }))
        #expect(filtered.contains(where: { $0.pitch == 67 }))
    }

    @Test("MIDISequence pitch range helpers")
    func pitchRangeHelpers() {
        let seq = MIDISequence(notes: [
            MIDINoteEvent(pitch: 48, startBeat: 0),
            MIDINoteEvent(pitch: 72, startBeat: 1),
            MIDINoteEvent(pitch: 60, startBeat: 2),
        ])
        #expect(seq.lowestPitch == 48)
        #expect(seq.highestPitch == 72)
    }

    @Test("MIDISequence durationBeats")
    func durationBeats() {
        let seq = MIDISequence(notes: [
            MIDINoteEvent(pitch: 60, startBeat: 0.0, duration: 1.0),
            MIDINoteEvent(pitch: 64, startBeat: 3.0, duration: 2.0),
        ])
        #expect(seq.durationBeats == 5.0)
    }

    @Test("Empty MIDISequence helpers return nil/0")
    func emptySequenceHelpers() {
        let seq = MIDISequence()
        #expect(seq.lowestPitch == nil)
        #expect(seq.highestPitch == nil)
        #expect(seq.durationBeats == 0)
    }

    // MARK: - SnapResolution

    @Test("SnapResolution snap rounds to nearest grid")
    func snapResolutionRounding() {
        #expect(SnapResolution.quarter.snap(1.3) == 1.0)
        #expect(SnapResolution.quarter.snap(1.6) == 2.0)
        #expect(SnapResolution.eighth.snap(1.3) == 1.5)
        #expect(SnapResolution.sixteenth.snap(1.13) == 1.25)
    }

    @Test("SnapResolution beatsPerUnit values")
    func snapResolutionBeatsPerUnit() {
        #expect(SnapResolution.whole.beatsPerUnit == 4.0)
        #expect(SnapResolution.half.beatsPerUnit == 2.0)
        #expect(SnapResolution.quarter.beatsPerUnit == 1.0)
        #expect(SnapResolution.eighth.beatsPerUnit == 0.5)
        #expect(SnapResolution.sixteenth.beatsPerUnit == 0.25)
        #expect(SnapResolution.thirtySecond.beatsPerUnit == 0.125)
    }

    // MARK: - Container with MIDISequence

    @Test("Container with midiSequence round-trips")
    func containerWithMIDIRoundTrip() throws {
        let seq = MIDISequence(notes: [
            MIDINoteEvent(pitch: 60, velocity: 100, startBeat: 0.0, duration: 1.0),
        ])
        let container = Container(name: "MIDI Clip", startBar: 1, lengthBars: 4, midiSequence: seq)
        let decoded = try roundTrip(container)
        #expect(decoded.midiSequence != nil)
        #expect(decoded.midiSequence?.notes.count == 1)
        #expect(decoded.midiSequence?.notes[0].pitch == 60)
        #expect(decoded.hasMIDI == true)
    }

    @Test("Container without midiSequence backward-compatible decode")
    func containerLegacyDecode() throws {
        // Encode a container without midiSequence, then decode
        let container = Container(name: "Audio Clip", startBar: 1, lengthBars: 4)
        let decoded = try roundTrip(container)
        #expect(decoded.midiSequence == nil)
        #expect(decoded.hasMIDI == false)
    }

    @Test("Container clone resolution inherits midiSequence")
    func cloneResolveMIDI() {
        let seq = MIDISequence(notes: [
            MIDINoteEvent(pitch: 60, startBeat: 0),
        ])
        let parent = Container(id: ID(), name: "Parent", startBar: 1, lengthBars: 4, midiSequence: seq)
        let clone = Container(
            name: "Clone",
            startBar: 5,
            lengthBars: 4,
            parentContainerID: parent.id,
            overriddenFields: []
        )
        let resolved = clone.resolved(parent: parent)
        #expect(resolved.midiSequence?.notes.count == 1)
        #expect(resolved.midiSequence?.notes[0].pitch == 60)
    }

    @Test("Container clone resolution respects midiSequence override")
    func cloneOverrideMIDI() {
        let parentSeq = MIDISequence(notes: [MIDINoteEvent(pitch: 60, startBeat: 0)])
        let cloneSeq = MIDISequence(notes: [MIDINoteEvent(pitch: 72, startBeat: 0)])
        let parent = Container(id: ID(), name: "Parent", startBar: 1, lengthBars: 4, midiSequence: parentSeq)
        let clone = Container(
            name: "Clone",
            startBar: 5,
            lengthBars: 4,
            parentContainerID: parent.id,
            overriddenFields: [.midiSequence],
            midiSequence: cloneSeq
        )
        let resolved = clone.resolved(parent: parent)
        #expect(resolved.midiSequence?.notes[0].pitch == 72)
    }

    @Test("ContainerField.midiSequence has correct display name")
    func containerFieldDisplayName() {
        #expect(ContainerField.midiSequence.displayName == "MIDI Sequence")
    }
}
