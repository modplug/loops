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

    // MARK: - Count-in

    @Test("Count-in timing: N bars at given BPM gives correct delay")
    func countInTimingCalculation() {
        let transport = TransportManager()
        // At 120 BPM, 4/4 time: bar = 4 beats * 0.5s = 2.0s
        transport.bpm = 120.0
        transport.timeSignature = TimeSignature(beatsPerBar: 4, beatUnit: 4)
        #expect(transport.countInDuration(bars: 0) == 0.0)
        #expect(transport.countInDuration(bars: 1) == 2.0)
        #expect(transport.countInDuration(bars: 2) == 4.0)
        #expect(transport.countInDuration(bars: 4) == 8.0)

        // At 60 BPM, 4/4: bar = 4 beats * 1.0s = 4.0s
        transport.bpm = 60.0
        #expect(transport.countInDuration(bars: 2) == 8.0)

        // At 180 BPM, 3/4: bar = 3 beats * (60/180)s = 3 * 1/3 = 1.0s
        transport.bpm = 180.0
        transport.timeSignature = TimeSignature(beatsPerBar: 3, beatUnit: 4)
        #expect(abs(transport.countInDuration(bars: 4) - 4.0) < 1e-10)
    }

    @Test("Count-in = 0 starts recording immediately")
    func countInZeroStartsImmediately() {
        let transport = TransportManager()
        transport.toggleRecordArm()
        transport.countInBars = 0
        transport.play()
        #expect(transport.state == .recording)
        transport.stop()
    }

    @Test("Count-in > 0 with record arm enters countingIn state")
    func countInEntersCountingInState() {
        let transport = TransportManager()
        transport.toggleRecordArm()
        transport.countInBars = 2
        transport.play()
        #expect(transport.state == .countingIn)
        #expect(transport.countInBarsRemaining > 0)
        transport.stop()
    }

    @Test("Count-in without record arm starts normal playback")
    func countInWithoutRecordArmPlaysNormally() {
        let transport = TransportManager()
        transport.countInBars = 4
        transport.play()
        #expect(transport.state == .playing)
        transport.stop()
    }

    @Test("Stop during count-in returns to stopped")
    func stopDuringCountIn() {
        let transport = TransportManager()
        transport.toggleRecordArm()
        transport.countInBars = 4
        transport.play()
        #expect(transport.state == .countingIn)
        transport.stop()
        #expect(transport.state == .stopped)
        #expect(transport.countInBarsRemaining == 0)
        #expect(transport.playheadBar == 1.0)
    }

    @Test("Pause during count-in returns to stopped")
    func pauseDuringCountIn() {
        let transport = TransportManager()
        transport.toggleRecordArm()
        transport.countInBars = 2
        transport.play()
        #expect(transport.state == .countingIn)
        transport.pause()
        #expect(transport.state == .stopped)
        #expect(transport.countInBarsRemaining == 0)
    }

    // MARK: - Click-to-Position (#73)

    @Test("Set playhead position during playback updates position")
    func setPlayheadDuringPlayback() {
        let transport = TransportManager()
        transport.play()
        #expect(transport.state == .playing)
        transport.setPlayheadPosition(5.0)
        #expect(transport.playheadBar == 5.0)
        transport.stop()
    }

    @Test("Set playhead position while stopped sets position directly")
    func setPlayheadWhileStopped() {
        let transport = TransportManager()
        transport.setPlayheadPosition(10.0)
        #expect(transport.playheadBar == 10.0)
        #expect(transport.state == .stopped)
    }

    @Test("Set playhead position fires callback")
    func setPlayheadFiresCallback() {
        let transport = TransportManager()
        var receivedBar: Double?
        transport.onPositionUpdate = { bar in
            receivedBar = bar
        }
        transport.setPlayheadPosition(7.5)
        #expect(receivedBar == 7.5)
    }
}
