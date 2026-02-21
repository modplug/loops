import Testing
import Foundation
@testable import LoopsEngine
@testable import LoopsCore

@Suite("TransportManager Tests")
struct TransportManagerTests {

    @Test("Initial state is stopped at bar 1")
    func initialState() {
        let transport = TransportManager()
        #expect(transport.state == .stopped)
        #expect(transport.playheadBar == 1.0)
        #expect(!transport.isRecordArmed)
        #expect(!transport.isMetronomeEnabled)
    }

    @Test("Play transitions to playing state")
    func playState() {
        let transport = TransportManager()
        transport.play()
        #expect(transport.state == .playing)
        transport.stop()
    }

    @Test("Play with record arm transitions to recording")
    func recordState() {
        let transport = TransportManager()
        transport.toggleRecordArm()
        transport.play()
        #expect(transport.state == .recording)
        transport.stop()
    }

    @Test("Pause preserves position")
    func pausePreservesPosition() {
        let transport = TransportManager()
        transport.setPlayheadPosition(5.0)
        transport.play()
        transport.pause()
        #expect(transport.state == .stopped)
        #expect(transport.playheadBar >= 5.0)
    }

    @Test("Stop returns to bar 1")
    func stopReturnsToBar1() {
        let transport = TransportManager()
        transport.setPlayheadPosition(10.0)
        transport.play()
        transport.stop()
        #expect(transport.state == .stopped)
        #expect(transport.playheadBar == 1.0)
    }

    @Test("Toggle record arm")
    func toggleRecordArm() {
        let transport = TransportManager()
        #expect(!transport.isRecordArmed)
        transport.toggleRecordArm()
        #expect(transport.isRecordArmed)
        transport.toggleRecordArm()
        #expect(!transport.isRecordArmed)
    }

    @Test("Toggle metronome")
    func toggleMetronome() {
        let transport = TransportManager()
        #expect(!transport.isMetronomeEnabled)
        transport.toggleMetronome()
        #expect(transport.isMetronomeEnabled)
        transport.toggleMetronome()
        #expect(!transport.isMetronomeEnabled)
    }

    @Test("Set playhead position")
    func setPlayheadPosition() {
        let transport = TransportManager()
        transport.setPlayheadPosition(8.5)
        #expect(transport.playheadBar == 8.5)
    }

    @Test("Playhead position clamps to minimum 1")
    func playheadPositionClamp() {
        let transport = TransportManager()
        transport.setPlayheadPosition(-5.0)
        #expect(transport.playheadBar == 1.0)
    }

    @Test("BPM clamps to valid range")
    func bpmClamp() {
        let transport = TransportManager()
        transport.bpm = 500.0
        #expect(transport.bpm == 300.0)
        transport.bpm = 5.0
        #expect(transport.bpm == 20.0)
    }

    @Test("Bar duration calculation")
    func barDuration() {
        let transport = TransportManager()
        transport.bpm = 120.0
        transport.timeSignature = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        // At 120 BPM, each beat is 0.5s, so 4 beats = 2.0s per bar
        #expect(transport.barDurationSeconds == 2.0)
    }

    @Test("Rapid play/stop cycles don't crash")
    func rapidPlayStop() {
        let transport = TransportManager()
        for _ in 0..<100 {
            transport.play()
            transport.stop()
        }
        #expect(transport.state == .stopped)
    }

    @Test("Record arm toggle during playback changes state")
    func recordArmDuringPlayback() {
        let transport = TransportManager()
        transport.play()
        #expect(transport.state == .playing)
        transport.toggleRecordArm()
        #expect(transport.state == .recording)
        transport.toggleRecordArm()
        #expect(transport.state == .playing)
        transport.stop()
    }

    @Test("Play is idempotent when already playing")
    func playIdempotent() {
        let transport = TransportManager()
        transport.play()
        transport.play() // second play should be no-op
        #expect(transport.state == .playing)
        transport.stop()
    }

    @Test("Position update callback fires")
    func positionUpdateCallback() {
        let transport = TransportManager()
        var callbackFired = false
        transport.onPositionUpdate = { _ in
            callbackFired = true
        }
        transport.setPlayheadPosition(5.0)
        #expect(callbackFired)
    }
}
