import Testing
import Foundation
@testable import LoopsCore
@testable import LoopsEngine

@Suite("MIDIActivityMonitor Tests")
struct MIDIActivityMonitorTests {

    @MainActor
    @Test("Records messages to circular buffer")
    func recordsMessagesToBuffer() {
        let monitor = MIDIActivityMonitor()
        // NoteOn ch 0, note 60, velocity 100
        let word: UInt32 = 0x00_90_3C_64
        monitor.recordMessage(word: word, deviceID: "dev1")

        #expect(monitor.recentMessages.count == 1)
        #expect(monitor.recentMessages[0].channel == 0)
        if case .noteOn(let note, let velocity) = monitor.recentMessages[0].message {
            #expect(note == 60)
            #expect(velocity == 100)
        } else {
            Issue.record("Expected noteOn message")
        }
    }

    @MainActor
    @Test("Circular buffer evicts oldest entries when full")
    func circularBufferEviction() {
        let monitor = MIDIActivityMonitor()
        let word: UInt32 = 0x00_B0_40_7F // CC64 = 127
        for _ in 0..<(MIDIActivityMonitor.maxEntries + 50) {
            monitor.recordMessage(word: word, deviceID: nil)
        }
        #expect(monitor.recentMessages.count == MIDIActivityMonitor.maxEntries)
    }

    @MainActor
    @Test("Per-track activity matching uses correct device and channel filters")
    func perTrackActivityMatching() {
        let monitor = MIDIActivityMonitor()
        let track1 = Track(name: "MIDI 1", kind: .midi, midiInputDeviceID: "dev1", midiInputChannel: 1)
        let track2 = Track(name: "MIDI 2", kind: .midi, midiInputDeviceID: "dev2", midiInputChannel: nil)
        let audioTrack = Track(name: "Audio 1", kind: .audio)
        monitor.updateTracks([track1, track2, audioTrack])

        // Send event from dev1 ch 0 (matches track1's channel 1 = 0-based 0)
        let word: UInt32 = 0x00_90_3C_64
        monitor.recordMessage(word: word, deviceID: "dev1")

        let now = Date()
        #expect(monitor.isTrackActive(track1.id, referenceDate: now) == true)
        #expect(monitor.isTrackActive(track2.id, referenceDate: now) == false) // wrong device
        #expect(monitor.isTrackActive(audioTrack.id, referenceDate: now) == false) // not MIDI track
    }

    @MainActor
    @Test("Omni channel track receives all channels")
    func omniChannelTrack() {
        let monitor = MIDIActivityMonitor()
        let track = Track(name: "MIDI Omni", kind: .midi, midiInputDeviceID: nil, midiInputChannel: nil)
        monitor.updateTracks([track])

        // Send event from any device, ch 5
        let word: UInt32 = 0x00_95_3C_64 // NoteOn ch 5
        monitor.recordMessage(word: word, deviceID: "anydev")

        let now = Date()
        #expect(monitor.isTrackActive(track.id, referenceDate: now) == true)
    }

    @MainActor
    @Test("Activity expires after window")
    func activityExpires() {
        let monitor = MIDIActivityMonitor()
        let track = Track(name: "MIDI", kind: .midi, midiInputDeviceID: nil, midiInputChannel: nil)
        monitor.updateTracks([track])

        let word: UInt32 = 0x00_90_3C_64
        monitor.recordMessage(word: word, deviceID: nil)

        // Check with a reference date well in the future
        let futureDate = Date().addingTimeInterval(1.0)
        #expect(monitor.isTrackActive(track.id, referenceDate: futureDate) == false)
    }

    @MainActor
    @Test("Pause prevents log accumulation but tracks activity")
    func pauseStopsLogging() {
        let monitor = MIDIActivityMonitor()
        let track = Track(name: "MIDI", kind: .midi, midiInputDeviceID: nil, midiInputChannel: nil)
        monitor.updateTracks([track])

        monitor.isPaused = true
        let word: UInt32 = 0x00_90_3C_64
        monitor.recordMessage(word: word, deviceID: nil)

        #expect(monitor.recentMessages.count == 0)
        // Activity still tracked
        let now = Date()
        #expect(monitor.isTrackActive(track.id, referenceDate: now) == true)
    }

    @MainActor
    @Test("Clear log removes all entries")
    func clearLog() {
        let monitor = MIDIActivityMonitor()
        let word: UInt32 = 0x00_90_3C_64
        monitor.recordMessage(word: word, deviceID: nil)
        monitor.recordMessage(word: word, deviceID: nil)
        #expect(monitor.recentMessages.count == 2)

        monitor.clearLog()
        #expect(monitor.recentMessages.count == 0)
    }

    @MainActor
    @Test("Device name lookup resolves device names")
    func deviceNameLookup() {
        let monitor = MIDIActivityMonitor()
        monitor.updateDeviceNames([MIDIInputDevice(id: "dev1", displayName: "My Controller")])

        let word: UInt32 = 0x00_90_3C_64
        monitor.recordMessage(word: word, deviceID: "dev1")

        #expect(monitor.recentMessages[0].deviceName == "My Controller")
    }

    @MainActor
    @Test("Multiple message types recorded correctly")
    func multipleMessageTypes() {
        let monitor = MIDIActivityMonitor()
        let noteOn: UInt32 = 0x00_90_3C_64  // NoteOn
        let cc: UInt32 = 0x00_B0_40_7F      // CC
        let pc: UInt32 = 0x00_C0_05_00      // PC
        let pb: UInt32 = 0x00_E0_00_40      // PitchBend

        monitor.recordMessage(word: noteOn, deviceID: nil)
        monitor.recordMessage(word: cc, deviceID: nil)
        monitor.recordMessage(word: pc, deviceID: nil)
        monitor.recordMessage(word: pb, deviceID: nil)

        #expect(monitor.recentMessages.count == 4)

        if case .noteOn = monitor.recentMessages[0].message { } else {
            Issue.record("Expected noteOn")
        }
        if case .controlChange = monitor.recentMessages[1].message { } else {
            Issue.record("Expected controlChange")
        }
        if case .programChange = monitor.recentMessages[2].message { } else {
            Issue.record("Expected programChange")
        }
        if case .pitchBend = monitor.recentMessages[3].message { } else {
            Issue.record("Expected pitchBend")
        }
    }
}
