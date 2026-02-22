import Testing
@testable import LoopsCore

@Suite("MIDILogEntry Tests")
struct MIDILogEntryTests {

    @Test("Note name C4 for MIDI note 60")
    func noteNameC4() {
        let name = MIDILogMessage.noteName(60)
        #expect(name == "C4")
    }

    @Test("Note name D#5 for MIDI note 75")
    func noteNameDSharp5() {
        let name = MIDILogMessage.noteName(75)
        #expect(name == "D#5")
    }

    @Test("Note name A0 for MIDI note 21")
    func noteNameA0() {
        let name = MIDILogMessage.noteName(21)
        #expect(name == "A0")
    }

    @Test("Note name C-1 for MIDI note 0")
    func noteNameLowest() {
        let name = MIDILogMessage.noteName(0)
        #expect(name == "C-1")
    }

    @Test("Note name G9 for MIDI note 127")
    func noteNameHighest() {
        let name = MIDILogMessage.noteName(127)
        #expect(name == "G9")
    }

    @Test("CC name Sustain for CC 64")
    func ccNameSustain() {
        let name = MIDILogMessage.ccName(64)
        #expect(name == "Sustain")
    }

    @Test("CC name Modulation for CC 1")
    func ccNameModulation() {
        let name = MIDILogMessage.ccName(1)
        #expect(name == "Modulation")
    }

    @Test("CC name Volume for CC 7")
    func ccNameVolume() {
        let name = MIDILogMessage.ccName(7)
        #expect(name == "Volume")
    }

    @Test("CC name Expression for CC 11")
    func ccNameExpression() {
        let name = MIDILogMessage.ccName(11)
        #expect(name == "Expression")
    }

    @Test("CC name defaults to CC number for unknown controller")
    func ccNameUnknown() {
        let name = MIDILogMessage.ccName(42)
        #expect(name == "CC42")
    }

    @Test("Display string for noteOn")
    func displayStringNoteOn() {
        let msg = MIDILogMessage.noteOn(note: 60, velocity: 100)
        #expect(msg.displayString == "Note On C4 v=100")
    }

    @Test("Display string for noteOff")
    func displayStringNoteOff() {
        let msg = MIDILogMessage.noteOff(note: 60, velocity: 0)
        #expect(msg.displayString == "Note Off C4 v=0")
    }

    @Test("Display string for controlChange")
    func displayStringCC() {
        let msg = MIDILogMessage.controlChange(controller: 64, value: 127)
        #expect(msg.displayString == "CC64 (Sustain) 127")
    }

    @Test("Display string for programChange")
    func displayStringPC() {
        let msg = MIDILogMessage.programChange(program: 5)
        #expect(msg.displayString == "PC 5")
    }

    @Test("Display string for pitchBend")
    func displayStringPitchBend() {
        let msg = MIDILogMessage.pitchBend(value: 8192)
        #expect(msg.displayString == "Pitch Bend 8192")
    }

    @Test("fromRawWord parses NoteOn correctly")
    func fromRawWordNoteOn() {
        // Status 0x90 (NoteOn ch 0), note 60, velocity 100
        let word: UInt32 = 0x00_90_3C_64
        let entry = MIDILogEntry.fromRawWord(word, deviceID: "dev1", deviceName: "My Device")
        #expect(entry.channel == 0)
        #expect(entry.deviceID == "dev1")
        #expect(entry.deviceName == "My Device")
        if case .noteOn(let note, let velocity) = entry.message {
            #expect(note == 60)
            #expect(velocity == 100)
        } else {
            Issue.record("Expected noteOn message")
        }
    }

    @Test("fromRawWord parses NoteOff correctly")
    func fromRawWordNoteOff() {
        // Status 0x80 (NoteOff ch 1), note 60, velocity 64
        let word: UInt32 = 0x00_81_3C_40
        let entry = MIDILogEntry.fromRawWord(word, deviceID: nil)
        #expect(entry.channel == 1)
        if case .noteOff(let note, let velocity) = entry.message {
            #expect(note == 60)
            #expect(velocity == 64)
        } else {
            Issue.record("Expected noteOff message")
        }
    }

    @Test("fromRawWord parses NoteOn with velocity 0 as NoteOff")
    func fromRawWordNoteOnVel0() {
        // Status 0x90 (NoteOn ch 0), note 60, velocity 0
        let word: UInt32 = 0x00_90_3C_00
        let entry = MIDILogEntry.fromRawWord(word, deviceID: nil)
        if case .noteOff(let note, let velocity) = entry.message {
            #expect(note == 60)
            #expect(velocity == 0)
        } else {
            Issue.record("Expected noteOff for velocity=0 noteOn")
        }
    }

    @Test("fromRawWord parses CC correctly")
    func fromRawWordCC() {
        // Status 0xB0 (CC ch 0), controller 64, value 127
        let word: UInt32 = 0x00_B0_40_7F
        let entry = MIDILogEntry.fromRawWord(word, deviceID: nil)
        #expect(entry.channel == 0)
        if case .controlChange(let controller, let value) = entry.message {
            #expect(controller == 64)
            #expect(value == 127)
        } else {
            Issue.record("Expected controlChange message")
        }
    }

    @Test("fromRawWord parses ProgramChange correctly")
    func fromRawWordPC() {
        // Status 0xC0 (PC ch 2), program 5
        let word: UInt32 = 0x00_C2_05_00
        let entry = MIDILogEntry.fromRawWord(word, deviceID: nil)
        #expect(entry.channel == 2)
        if case .programChange(let program) = entry.message {
            #expect(program == 5)
        } else {
            Issue.record("Expected programChange message")
        }
    }

    @Test("fromRawWord parses PitchBend correctly")
    func fromRawWordPitchBend() {
        // Status 0xE0 (PitchBend ch 0), LSB 0, MSB 64 → value = 0 | (64 << 7) = 8192
        let word: UInt32 = 0x00_E0_00_40
        let entry = MIDILogEntry.fromRawWord(word, deviceID: nil)
        #expect(entry.channel == 0)
        if case .pitchBend(let value) = entry.message {
            #expect(value == 8192)
        } else {
            Issue.record("Expected pitchBend message")
        }
    }
}
