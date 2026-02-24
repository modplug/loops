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

    @Test("Stop leaves playhead at current position when return-to-start disabled")
    func stopLeavesPlayheadWhenDisabled() {
        let transport = TransportManager()
        transport.returnToStartEnabled = false
        transport.setPlayheadPosition(10.0)
        transport.play()
        transport.stop()
        #expect(transport.state == .stopped)
        // When return-to-start is disabled, playhead stays where it was
        #expect(transport.playheadBar == 10.0)
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

    // MARK: - Playhead-Audio Sync (#97)

    @Test("Play with waitForAudioSync enters playing but sets sync flag")
    func playWithAudioSyncHoldsPlayhead() {
        let transport = TransportManager()
        transport.bpm = 120.0
        transport.setPlayheadPosition(3.0)
        transport.play(waitForAudioSync: true)
        #expect(transport.state == .playing)
        #expect(transport.isWaitingForAudioSync)
        // Playhead stays at start position while waiting
        #expect(transport.playheadBar == 3.0)
        transport.stop()
    }

    @Test("completeAudioSync clears sync flag and enables advancement")
    func completeAudioSyncAllowsAdvance() {
        let transport = TransportManager()
        transport.bpm = 120.0
        transport.play(waitForAudioSync: true)
        #expect(transport.isWaitingForAudioSync)
        transport.completeAudioSync()
        #expect(!transport.isWaitingForAudioSync)
        #expect(transport.state == .playing)
        transport.stop()
    }

    @Test("completeAudioSync with latency keeps playhead at start")
    func completeAudioSyncWithLatency() {
        let transport = TransportManager()
        transport.bpm = 60.0 // 1 beat/sec, 4/4 = 4 sec/bar
        transport.play(waitForAudioSync: true)
        // Complete with 0.5s latency — playhead should hold during latency period
        transport.completeAudioSync(audioOutputLatency: 0.5)
        #expect(!transport.isWaitingForAudioSync)
        // Immediately after, playhead should still be at start (latency not yet elapsed)
        #expect(transport.playheadBar == 1.0)
        transport.stop()
    }

    @Test("completeAudioSync is no-op when not waiting")
    func completeAudioSyncNoOpWhenNotWaiting() {
        let transport = TransportManager()
        transport.play()
        #expect(!transport.isWaitingForAudioSync)
        transport.completeAudioSync() // Should be no-op — flag is false
        #expect(!transport.isWaitingForAudioSync)
        #expect(transport.state == .playing)
        transport.stop()
    }

    @Test("Pause clears audio sync wait")
    func pauseClearsAudioSync() {
        let transport = TransportManager()
        transport.play(waitForAudioSync: true)
        #expect(transport.isWaitingForAudioSync)
        transport.pause()
        #expect(!transport.isWaitingForAudioSync)
        #expect(transport.state == .stopped)
    }

    @Test("Stop clears audio sync wait")
    func stopClearsAudioSync() {
        let transport = TransportManager()
        transport.play(waitForAudioSync: true)
        #expect(transport.isWaitingForAudioSync)
        transport.stop()
        #expect(!transport.isWaitingForAudioSync)
        #expect(transport.state == .stopped)
    }

    @Test("beginWaitForAudioSync sets flag during playback")
    func beginWaitForAudioSync() {
        let transport = TransportManager()
        transport.play()
        #expect(!transport.isWaitingForAudioSync)
        transport.beginWaitForAudioSync()
        #expect(transport.isWaitingForAudioSync)
        transport.completeAudioSync()
        #expect(!transport.isWaitingForAudioSync)
        transport.stop()
    }

    @Test("Audio sync preserves arbitrary start position")
    func audioSyncFromArbitraryPosition() {
        let transport = TransportManager()
        transport.bpm = 120.0
        transport.setPlayheadPosition(5.0)
        transport.play(waitForAudioSync: true)
        #expect(transport.playheadBar == 5.0)
        #expect(transport.isWaitingForAudioSync)
        transport.completeAudioSync()
        // After completing sync, playhead starts from the arbitrary position
        #expect(transport.playheadBar == 5.0)
        #expect(!transport.isWaitingForAudioSync)
        transport.stop()
    }

    @Test("Play without waitForAudioSync does not set sync flag (backward compat)")
    func playWithoutSyncAdvancesImmediately() {
        let transport = TransportManager()
        transport.bpm = 120.0
        transport.play()
        #expect(!transport.isWaitingForAudioSync)
        #expect(transport.state == .playing)
        transport.stop()
    }

    @Test("completeAudioSync sets playbackStartBar to current playheadBar")
    func completeAudioSyncSetsStartBar() {
        let transport = TransportManager()
        transport.setPlayheadPosition(7.0)
        transport.play(waitForAudioSync: true)
        #expect(transport.playheadBar == 7.0)
        transport.completeAudioSync()
        // Playhead should be at the position it was when sync completed
        #expect(transport.playheadBar == 7.0)
        transport.stop()
    }

    @Test("Pause during sync wait then play again works correctly")
    func pauseResumeDuringSyncWait() {
        let transport = TransportManager()
        transport.setPlayheadPosition(3.0)
        transport.play(waitForAudioSync: true)
        #expect(transport.isWaitingForAudioSync)
        transport.pause()
        #expect(!transport.isWaitingForAudioSync)
        #expect(transport.playheadBar == 3.0)
        // Play again with sync
        transport.play(waitForAudioSync: true)
        #expect(transport.isWaitingForAudioSync)
        #expect(transport.state == .playing)
        transport.completeAudioSync()
        #expect(!transport.isWaitingForAudioSync)
        transport.stop()
    }

    // MARK: - Return to Start Position (#103)

    @Test("Stop returns to start position when enabled")
    func stopReturnsToStartPosition() {
        let transport = TransportManager()
        // returnToStartEnabled defaults to true
        #expect(transport.returnToStartEnabled)
        transport.setPlayheadPosition(10.0)
        transport.play()
        // Simulate some playback advancement
        transport.setPlayheadPosition(15.0)
        transport.stop()
        // First stop returns to where play was pressed (bar 10)
        #expect(transport.playheadBar == 10.0)
    }

    @Test("Double-stop returns to bar 1 when return-to-start enabled")
    func doubleStopReturnsToBar1() {
        let transport = TransportManager()
        transport.setPlayheadPosition(10.0)
        transport.play()
        transport.setPlayheadPosition(15.0)
        transport.stop()
        // First stop: returns to start position (bar 10)
        #expect(transport.playheadBar == 10.0)
        // Second stop: already at start position, returns to bar 1
        transport.stop()
        #expect(transport.playheadBar == 1.0)
    }

    @Test("Stop leaves playhead at seek position when return-to-start disabled")
    func stopLeavesPlayheadAtSeekWhenDisabled() {
        let transport = TransportManager()
        transport.returnToStartEnabled = false
        transport.setPlayheadPosition(5.0)
        transport.play()
        transport.setPlayheadPosition(8.0)
        transport.stop()
        // When disabled, playhead stays at the position it was when stop was pressed
        #expect(transport.playheadBar == 8.0)
    }

    @Test("Return-to-start default is true")
    func returnToStartDefaultEnabled() {
        let transport = TransportManager()
        #expect(transport.returnToStartEnabled)
    }

    @Test("Stop from bar 1 with return-to-start always goes to bar 1")
    func stopFromBar1WithReturnToStart() {
        let transport = TransportManager()
        // Play from bar 1 (default)
        transport.play()
        transport.stop()
        // userPlayStartBar = 1.0, playhead already there → goes to bar 1
        #expect(transport.playheadBar == 1.0)
    }

    @Test("userPlayStartBar set on play")
    func userPlayStartBarSetOnPlay() {
        let transport = TransportManager()
        transport.setPlayheadPosition(7.0)
        #expect(transport.userPlayStartBar == 1.0) // default
        transport.play()
        #expect(transport.userPlayStartBar == 7.0)
        transport.stop()
    }

    @Test("Pause then play sets new userPlayStartBar")
    func pauseThenPlaySetsNewStartBar() {
        let transport = TransportManager()
        transport.setPlayheadPosition(3.0)
        transport.play()
        #expect(transport.userPlayStartBar == 3.0)
        transport.pause()
        // Playhead stays at 3.0 after pause
        #expect(transport.playheadBar == 3.0)
        // Seek to new position while paused
        transport.setPlayheadPosition(8.0)
        transport.play()
        #expect(transport.userPlayStartBar == 8.0)
        // Advance playhead past start to trigger return-to-start
        transport.setPlayheadPosition(12.0)
        transport.stop()
        #expect(transport.playheadBar == 8.0) // returns to new start
    }

    @Test("Return-to-start bypassed when disabled via property mid-playback")
    func returnToStartBypassedViaProperty() {
        let transport = TransportManager()
        transport.setPlayheadPosition(5.0)
        transport.play()
        transport.setPlayheadPosition(12.0)
        // Disable before stopping — playhead stays at current position
        transport.returnToStartEnabled = false
        transport.stop()
        #expect(transport.playheadBar == 12.0)
    }

    @Test("Seek during playback preserves original start position for return-to-start")
    func seekDuringPlaybackPreservesStartPosition() {
        let transport = TransportManager()
        // Play from bar 5
        transport.setPlayheadPosition(5.0)
        transport.play()
        #expect(transport.userPlayStartBar == 5.0)
        // Seek to bar 20 during playback — original start position should be preserved
        transport.setPlayheadPosition(20.0)
        #expect(transport.userPlayStartBar == 5.0)
        // Stop returns to original play position, not the seek position
        transport.stop()
        #expect(transport.playheadBar == 5.0)
    }

    @Test("Multiple seeks during playback all preserve original start position")
    func multipleSeeksDuringPlayback() {
        let transport = TransportManager()
        transport.setPlayheadPosition(3.0)
        transport.play()
        transport.setPlayheadPosition(10.0)
        transport.setPlayheadPosition(25.0)
        transport.setPlayheadPosition(50.0)
        // All seeks should not change the original start
        #expect(transport.userPlayStartBar == 3.0)
        transport.stop()
        #expect(transport.playheadBar == 3.0)
    }

    @Test("Count-in records userPlayStartBar")
    func countInRecordsUserPlayStartBar() {
        let transport = TransportManager()
        transport.setPlayheadPosition(4.0)
        transport.toggleRecordArm()
        transport.countInBars = 2
        transport.play()
        #expect(transport.state == .countingIn)
        #expect(transport.userPlayStartBar == 4.0)
        // Playhead hasn't advanced, so stop goes to bar 1 (same as start)
        transport.stop()
        #expect(transport.playheadBar == 1.0)
        // Now test with advancement: play from bar 4, advance, stop returns to 4
        transport.setPlayheadPosition(4.0)
        transport.toggleRecordArm() // re-arm
        transport.countInBars = 0   // skip count-in
        transport.play()
        transport.setPlayheadPosition(10.0) // advance playhead
        transport.stop()
        #expect(transport.playheadBar == 4.0) // returns to start position
    }
}
