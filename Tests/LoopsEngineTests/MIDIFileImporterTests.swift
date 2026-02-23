import Testing
import Foundation
@testable import LoopsEngine
@testable import LoopsCore

@Suite("MIDI File Importer Tests")
struct MIDIFileImporterTests {
    let importer = MIDIFileImporter()

    // Helper to build a minimal standard MIDI file (format 0, single track)
    private func buildMIDIFile(
        ticksPerQuarterNote: UInt16 = 480,
        events: [MIDITestEvent]
    ) -> Data {
        var trackData = Data()

        for event in events {
            // Variable-length delta time
            trackData.append(contentsOf: encodeVariableLength(event.delta))
            trackData.append(contentsOf: event.bytes)
        }

        // End of track meta event
        trackData.append(contentsOf: encodeVariableLength(0))
        trackData.append(contentsOf: [0xFF, 0x2F, 0x00])

        var data = Data()
        // Header chunk: MThd
        data.append(contentsOf: [0x4D, 0x54, 0x68, 0x64]) // "MThd"
        data.append(contentsOf: uint32Bytes(6)) // header length
        data.append(contentsOf: uint16Bytes(0)) // format 0
        data.append(contentsOf: uint16Bytes(1)) // 1 track
        data.append(contentsOf: uint16Bytes(ticksPerQuarterNote))

        // Track chunk: MTrk
        data.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B]) // "MTrk"
        data.append(contentsOf: uint32Bytes(UInt32(trackData.count)))
        data.append(trackData)

        return data
    }

    struct MIDITestEvent {
        let delta: UInt32
        let bytes: [UInt8]
    }

    private func uint32Bytes(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
         UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private func uint16Bytes(_ value: UInt16) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private func encodeVariableLength(_ value: UInt32) -> [UInt8] {
        if value < 0x80 { return [UInt8(value)] }
        var result: [UInt8] = []
        var v = value
        result.append(UInt8(v & 0x7F))
        v >>= 7
        while v > 0 {
            result.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        result.reverse()
        return result
    }

    // MARK: - Tests

    @Test("Parse single note MIDI file")
    func parseSingleNote() throws {
        // Note On C4 (60) vel 100 at tick 0, Note Off at tick 480 (1 beat)
        let data = buildMIDIFile(ticksPerQuarterNote: 480, events: [
            MIDITestEvent(delta: 0, bytes: [0x90, 60, 100]),     // Note On ch0
            MIDITestEvent(delta: 480, bytes: [0x80, 60, 0]),     // Note Off ch0
        ])

        let result = try importer.parse(data: data)
        #expect(result.sequences.count == 1)
        #expect(result.ticksPerQuarterNote == 480)

        let notes = result.sequences[0].notes
        #expect(notes.count == 1)
        #expect(notes[0].pitch == 60)
        #expect(notes[0].velocity == 100)
        #expect(notes[0].startBeat == 0.0)
        #expect(notes[0].duration == 1.0) // 480 ticks / 480 tpq = 1 beat
        #expect(notes[0].channel == 0)
    }

    @Test("Parse note-on velocity 0 as note-off")
    func noteOnVelocityZero() throws {
        let data = buildMIDIFile(ticksPerQuarterNote: 480, events: [
            MIDITestEvent(delta: 0, bytes: [0x90, 60, 100]),     // Note On
            MIDITestEvent(delta: 240, bytes: [0x90, 60, 0]),     // Note On vel=0 = Note Off
        ])

        let result = try importer.parse(data: data)
        let notes = result.sequences[0].notes
        #expect(notes.count == 1)
        #expect(notes[0].duration == 0.5) // 240/480 = 0.5 beats
    }

    @Test("Parse multiple notes on different channels")
    func multiChannelNotes() throws {
        let data = buildMIDIFile(ticksPerQuarterNote: 480, events: [
            MIDITestEvent(delta: 0, bytes: [0x90, 60, 100]),     // Ch0 Note On
            MIDITestEvent(delta: 0, bytes: [0x91, 64, 80]),      // Ch1 Note On
            MIDITestEvent(delta: 480, bytes: [0x80, 60, 0]),     // Ch0 Note Off
            MIDITestEvent(delta: 0, bytes: [0x81, 64, 0]),       // Ch1 Note Off
        ])

        let result = try importer.parse(data: data)
        let notes = result.sequences[0].notes
        #expect(notes.count == 2)

        let ch0 = notes.first(where: { $0.channel == 0 })
        let ch1 = notes.first(where: { $0.channel == 1 })
        #expect(ch0?.pitch == 60)
        #expect(ch0?.velocity == 100)
        #expect(ch1?.pitch == 64)
        #expect(ch1?.velocity == 80)
    }

    @Test("Parse chord (simultaneous notes)")
    func parseChord() throws {
        let data = buildMIDIFile(ticksPerQuarterNote: 480, events: [
            MIDITestEvent(delta: 0, bytes: [0x90, 60, 100]),
            MIDITestEvent(delta: 0, bytes: [0x90, 64, 100]),
            MIDITestEvent(delta: 0, bytes: [0x90, 67, 100]),
            MIDITestEvent(delta: 480, bytes: [0x80, 60, 0]),
            MIDITestEvent(delta: 0, bytes: [0x80, 64, 0]),
            MIDITestEvent(delta: 0, bytes: [0x80, 67, 0]),
        ])

        let result = try importer.parse(data: data)
        let notes = result.sequences[0].notes
        #expect(notes.count == 3)
        #expect(notes.allSatisfy { $0.startBeat == 0.0 })
        #expect(notes.allSatisfy { $0.duration == 1.0 })
    }

    @Test("Parse sequential notes with different durations")
    func sequentialNotes() throws {
        let data = buildMIDIFile(ticksPerQuarterNote: 480, events: [
            MIDITestEvent(delta: 0, bytes: [0x90, 60, 100]),       // Beat 0
            MIDITestEvent(delta: 480, bytes: [0x80, 60, 0]),       // End beat 1
            MIDITestEvent(delta: 0, bytes: [0x90, 64, 80]),        // Beat 1
            MIDITestEvent(delta: 240, bytes: [0x80, 64, 0]),       // End beat 1.5
            MIDITestEvent(delta: 240, bytes: [0x90, 67, 90]),      // Beat 2
            MIDITestEvent(delta: 960, bytes: [0x80, 67, 0]),       // End beat 4
        ])

        let result = try importer.parse(data: data)
        let notes = result.sequences[0].sortedNotes
        #expect(notes.count == 3)
        #expect(notes[0].startBeat == 0.0)
        #expect(notes[0].duration == 1.0)
        #expect(notes[1].startBeat == 1.0)
        #expect(notes[1].duration == 0.5)
        #expect(notes[2].startBeat == 2.0)
        #expect(notes[2].duration == 2.0)
    }

    @Test("Invalid file throws error")
    func invalidFile() {
        let data = Data([0x00, 0x01, 0x02])
        #expect(throws: MIDIImportError.self) {
            try importer.parse(data: data)
        }
    }

    @Test("Empty file throws error")
    func emptyFile() {
        let data = Data()
        #expect(throws: MIDIImportError.self) {
            try importer.parse(data: data)
        }
    }

    @Test("File with no notes returns empty sequences")
    func noNotes() throws {
        // Just a header and empty track
        let data = buildMIDIFile(ticksPerQuarterNote: 480, events: [])
        let result = try importer.parse(data: data)
        #expect(result.sequences.isEmpty)
    }

    @Test("Tempo meta event is parsed")
    func tempoMetaEvent() throws {
        // Tempo = 500000 microseconds per quarter note = 120 BPM
        let data = buildMIDIFile(ticksPerQuarterNote: 480, events: [
            MIDITestEvent(delta: 0, bytes: [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]), // Tempo 500000
            MIDITestEvent(delta: 0, bytes: [0x90, 60, 100]),
            MIDITestEvent(delta: 480, bytes: [0x80, 60, 0]),
        ])

        let result = try importer.parse(data: data)
        #expect(result.tempoMicrosPerQuarterNote == 500000)
    }
}
