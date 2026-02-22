import Testing
import Foundation
import AVFoundation
@testable import LoopsApp
@testable import LoopsCore
@testable import LoopsEngine

@Suite("Virtual Keyboard Tests")
struct VirtualKeyboardTests {

    // MARK: - PianoLayout.isBlackKey

    @Test("isBlackKey correctly identifies black keys")
    func isBlackKey() {
        // C, D, E, F, G, A, B are white keys (pitch classes 0,2,4,5,7,9,11)
        #expect(!PianoLayout.isBlackKey(note: 60))  // C4
        #expect(!PianoLayout.isBlackKey(note: 62))  // D4
        #expect(!PianoLayout.isBlackKey(note: 64))  // E4
        #expect(!PianoLayout.isBlackKey(note: 65))  // F4
        #expect(!PianoLayout.isBlackKey(note: 67))  // G4
        #expect(!PianoLayout.isBlackKey(note: 69))  // A4
        #expect(!PianoLayout.isBlackKey(note: 71))  // B4

        // C#, D#, F#, G#, A# are black keys (pitch classes 1,3,6,8,10)
        #expect(PianoLayout.isBlackKey(note: 61))  // C#4
        #expect(PianoLayout.isBlackKey(note: 63))  // D#4
        #expect(PianoLayout.isBlackKey(note: 66))  // F#4
        #expect(PianoLayout.isBlackKey(note: 68))  // G#4
        #expect(PianoLayout.isBlackKey(note: 70))  // A#4
    }

    // MARK: - PianoLayout.velocity

    @Test("Velocity at top of key is soft (1)")
    func velocityTop() {
        let vel = PianoLayout.velocity(yFraction: 0.0)
        #expect(vel == 1)
    }

    @Test("Velocity at bottom of key is loud (127)")
    func velocityBottom() {
        let vel = PianoLayout.velocity(yFraction: 1.0)
        #expect(vel == 127)
    }

    @Test("Velocity at midpoint is approximately 64")
    func velocityMid() {
        let vel = PianoLayout.velocity(yFraction: 0.5)
        #expect(vel == 64)
    }

    @Test("Velocity clamps above 1.0")
    func velocityClampHigh() {
        let vel = PianoLayout.velocity(yFraction: 2.0)
        #expect(vel == 127)
    }

    @Test("Velocity clamps below 0.0")
    func velocityClampLow() {
        let vel = PianoLayout.velocity(yFraction: -1.0)
        #expect(vel == 1)
    }

    // MARK: - PianoLayout.noteName

    @Test("Note names are correct")
    func noteNames() {
        #expect(PianoLayout.noteName(60) == "C4")
        #expect(PianoLayout.noteName(61) == "C#4")
        #expect(PianoLayout.noteName(69) == "A4")
        #expect(PianoLayout.noteName(48) == "C3")
        #expect(PianoLayout.noteName(71) == "B4")
        #expect(PianoLayout.noteName(0) == "C-1")
        #expect(PianoLayout.noteName(127) == "G9")
    }

    // MARK: - PianoLayout.whiteKeyIndex

    @Test("White key index within octave")
    func whiteKeyIndex() {
        #expect(PianoLayout.whiteKeyIndex(note: 60) == 0)  // C → 0
        #expect(PianoLayout.whiteKeyIndex(note: 62) == 1)  // D → 1
        #expect(PianoLayout.whiteKeyIndex(note: 64) == 2)  // E → 2
        #expect(PianoLayout.whiteKeyIndex(note: 65) == 3)  // F → 3
        #expect(PianoLayout.whiteKeyIndex(note: 67) == 4)  // G → 4
        #expect(PianoLayout.whiteKeyIndex(note: 69) == 5)  // A → 5
        #expect(PianoLayout.whiteKeyIndex(note: 71) == 6)  // B → 6
    }

    // MARK: - PianoLayout.blackKeyWhiteIndex

    @Test("Black key positions relative to white keys")
    func blackKeyPosition() {
        #expect(PianoLayout.blackKeyWhiteIndex(note: 61) == 0)  // C# sits after C (index 0)
        #expect(PianoLayout.blackKeyWhiteIndex(note: 63) == 1)  // D# sits after D (index 1)
        #expect(PianoLayout.blackKeyWhiteIndex(note: 66) == 3)  // F# sits after F (index 3)
        #expect(PianoLayout.blackKeyWhiteIndex(note: 68) == 4)  // G# sits after G (index 4)
        #expect(PianoLayout.blackKeyWhiteIndex(note: 70) == 5)  // A# sits after A (index 5)
    }

    // MARK: - Note range calculation

    @Test("Default octave 3 produces C3-B4 range (notes 48-71)")
    func defaultNoteRange() {
        // baseOctave = 3 → lowestNote = (3+1)*12 = 48 (C3), highestNote = (3+1+2)*12 = 72
        let lowestNote = UInt8((3 + 1) * 12)
        let highestNote = UInt8((3 + 1 + 2) * 12)
        #expect(lowestNote == 48)
        #expect(highestNote == 72)
        // The range is [48, 72) = C3 to B4
        #expect(PianoLayout.noteName(lowestNote) == "C3")
        #expect(PianoLayout.noteName(highestNote - 1) == "B4")
    }

    @Test("Octave shift changes the note range")
    func octaveShift() {
        // baseOctave = 4 → lowestNote = (4+1)*12 = 60 (C4), highestNote = (4+1+2)*12 = 84
        let lowestNote = UInt8((4 + 1) * 12)
        let highestNote = UInt8((4 + 1 + 2) * 12)
        #expect(lowestNote == 60)
        #expect(highestNote == 84)
        #expect(PianoLayout.noteName(lowestNote) == "C4")
        #expect(PianoLayout.noteName(highestNote - 1) == "B5")
    }

    @Test("Octave shift down from default")
    func octaveShiftDown() {
        // baseOctave = 2 → lowestNote = (2+1)*12 = 36 (C2)
        let lowestNote = UInt8((2 + 1) * 12)
        #expect(lowestNote == 36)
        #expect(PianoLayout.noteName(lowestNote) == "C2")
    }

    // MARK: - Note event generation

    @Test("Note-on event has correct MIDI bytes")
    func noteOnMessage() {
        let message = MIDIActionMessage.noteOn(channel: 0, note: 60, velocity: 100)
        let bytes = message.midiBytes
        #expect(bytes == [0x90, 60, 100])
    }

    @Test("Note-off event has correct MIDI bytes")
    func noteOffMessage() {
        let message = MIDIActionMessage.noteOff(channel: 0, note: 60, velocity: 0)
        let bytes = message.midiBytes
        #expect(bytes == [0x80, 60, 0])
    }

    @Test("Note-on on channel 1 has correct status byte")
    func noteOnChannel1() {
        let message = MIDIActionMessage.noteOn(channel: 1, note: 48, velocity: 127)
        let bytes = message.midiBytes
        #expect(bytes == [0x91, 48, 127])
    }

    // MARK: - PlaybackScheduler sendMIDINoteToTrack

    @Test("sendMIDINoteToTrack is no-op when no subgraphs exist")
    func sendNoteNoSubgraphs() throws {
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(
            .offline, format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!,
            maximumFrameCount: 4096
        )
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: URL(fileURLWithPath: "/tmp"))
        let trackID = ID<Track>()
        // Should not crash — just silently does nothing
        scheduler.sendMIDINoteToTrack(trackID, message: .noteOn(channel: 0, note: 60, velocity: 100))
    }

    // MARK: - TransportViewModel sendVirtualNote

    @Test("sendVirtualNote is no-op when scheduler is nil")
    @MainActor
    func sendVirtualNoteNoScheduler() {
        let transport = TransportManager()
        let vm = TransportViewModel(transport: transport)
        let trackID = ID<Track>()
        // Should not crash
        vm.sendVirtualNote(trackID: trackID, message: .noteOn(channel: 0, note: 60, velocity: 100))
    }

    // MARK: - White key count per 2 octaves

    @Test("Two octaves contain exactly 14 white keys")
    func whiteKeyCount() {
        let notes = Array(UInt8(48)..<UInt8(72))  // C3 to B4
        let whiteKeys = notes.filter { !PianoLayout.isBlackKey(note: $0) }
        #expect(whiteKeys.count == 14)
    }

    @Test("Two octaves contain exactly 10 black keys")
    func blackKeyCount() {
        let notes = Array(UInt8(48)..<UInt8(72))
        let blackKeys = notes.filter { PianoLayout.isBlackKey(note: $0) }
        #expect(blackKeys.count == 10)
    }
}
