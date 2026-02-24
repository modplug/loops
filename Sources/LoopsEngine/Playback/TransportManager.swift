import Foundation
import AVFoundation
import LoopsCore

/// Transport state: stopped, playing, recording, or counting in before recording.
public enum TransportState: Sendable, Equatable {
    case stopped
    case playing
    case recording
    case countingIn
}

/// Manages transport state machine: play, pause, stop, record arm, count-in.
/// Tracks playhead position based on BPM and drives the metronome.
public final class TransportManager: @unchecked Sendable {
    public private(set) var state: TransportState = .stopped
    public var isRecordArmed: Bool = false
    public var isMetronomeEnabled: Bool = false

    /// Number of count-in bars before recording (0, 1, 2, or 4).
    public var countInBars: Int = 0

    /// Current playhead position in bars (1-based, fractional).
    public private(set) var playheadBar: Double = 1.0

    /// Remaining count-in bars (counts down during count-in phase).
    public private(set) var countInBarsRemaining: Int = 0

    /// Tempo in BPM.
    public var bpm: Double = 120.0 {
        didSet { bpm = min(max(bpm, 20.0), 300.0) }
    }

    /// Time signature.
    public var timeSignature: TimeSignature = TimeSignature()

    /// Callback fired on each position update (called from timer thread).
    public var onPositionUpdate: ((Double) -> Void)?

    /// Callback fired when count-in completes and recording begins.
    public var onCountInComplete: (() -> Void)?

    /// Callback fired each tick during count-in with bars remaining.
    public var onCountInTick: ((Int) -> Void)?

    /// When true, stopping returns playhead to where play was last pressed
    /// instead of bar 1. A second stop at that position returns to bar 1.
    public var returnToStartEnabled: Bool = true

    /// The bar position where the user last pressed play.
    /// Used by return-to-start to restore position on stop.
    public private(set) var userPlayStartBar: Double = 1.0

    /// When true, the timer runs but the playhead holds at its current position
    /// until `completeAudioSync()` is called. This prevents the playhead from
    /// advancing before audio player nodes have actually started rendering.
    public private(set) var isWaitingForAudioSync: Bool = false

    private var displayLink: Timer?
    private var playbackStartTime: CFAbsoluteTime = 0
    private var playbackStartBar: Double = 1.0
    private var countInStartTime: CFAbsoluteTime = 0
    private var countInDurationSeconds: Double = 0

    public init() {}

    deinit {
        stop()
    }

    /// Starts or resumes playback. If record-armed with countInBars > 0,
    /// enters count-in phase first.
    ///
    /// When `waitForAudioSync` is true, the timer starts but the playhead
    /// holds its position until `completeAudioSync()` is called. Use this
    /// when audio playback is scheduled asynchronously so the playhead
    /// only advances once audio is actually rendering.
    public func play(waitForAudioSync: Bool = false) {
        guard state == .stopped else { return }
        userPlayStartBar = playheadBar
        if isRecordArmed && countInBars > 0 {
            state = .countingIn
            countInBarsRemaining = countInBars
            countInDurationSeconds = Double(countInBars) * barDurationSeconds
            countInStartTime = CFAbsoluteTimeGetCurrent()
            isWaitingForAudioSync = false
            startTimer()
        } else {
            state = isRecordArmed ? .recording : .playing
            isWaitingForAudioSync = waitForAudioSync
            if !waitForAudioSync {
                playbackStartTime = CFAbsoluteTimeGetCurrent()
            }
            playbackStartBar = playheadBar
            startTimer()
        }
    }

    /// Tells the transport to hold the playhead at its current position
    /// until `completeAudioSync()` is called. Use when transitioning from
    /// count-in to recording while audio is being scheduled asynchronously.
    public func beginWaitForAudioSync() {
        isWaitingForAudioSync = true
    }

    /// Resumes playhead tracking, calibrated to the current moment plus
    /// any audio output latency compensation. Call after audio player nodes
    /// have actually started rendering.
    ///
    /// - Parameter audioOutputLatency: The hardware output latency in seconds
    ///   (e.g. from `AVAudioNode.presentationLatency`). The playhead will wait
    ///   this long before advancing, matching audible output timing.
    public func completeAudioSync(audioOutputLatency: Double = 0) {
        guard isWaitingForAudioSync else { return }
        playbackStartTime = CFAbsoluteTimeGetCurrent() + audioOutputLatency
        playbackStartBar = playheadBar
        isWaitingForAudioSync = false
    }

    /// Pauses playback at the current position.
    public func pause() {
        guard state == .playing || state == .recording || state == .countingIn else { return }
        stopTimer()
        state = .stopped
        countInBarsRemaining = 0
        isWaitingForAudioSync = false
    }

    /// Stops playback. When `returnToStartEnabled` is true, returns playhead
    /// to where play was last pressed; pressing stop again returns to bar 1.
    /// When disabled, playhead stays at its current position.
    public func stop() {
        stopTimer()
        state = .stopped
        countInBarsRemaining = 0
        isWaitingForAudioSync = false

        if returnToStartEnabled {
            if abs(playheadBar - userPlayStartBar) > 0.001 {
                playheadBar = userPlayStartBar
            } else {
                playheadBar = 1.0
            }
        }

        onPositionUpdate?(playheadBar)
    }

    /// Toggles global record arm.
    public func toggleRecordArm() {
        isRecordArmed.toggle()
        // If currently playing and record arm toggled, update state
        if state == .playing && isRecordArmed {
            state = .recording
        } else if state == .recording && !isRecordArmed {
            state = .playing
        }
    }

    /// Toggles the metronome on/off.
    public func toggleMetronome() {
        isMetronomeEnabled.toggle()
    }

    /// Sets the playhead position (1-based bars).
    public func setPlayheadPosition(_ bar: Double) {
        let wasPlaying = state == .playing || state == .recording
        if wasPlaying {
            playbackStartTime = CFAbsoluteTimeGetCurrent()
            playbackStartBar = max(bar, 1.0)
        }
        playheadBar = max(bar, 1.0)
        onPositionUpdate?(playheadBar)
    }

    /// Returns the duration of one bar in seconds at current BPM/time signature.
    public var barDurationSeconds: Double {
        let beatsPerBar = Double(timeSignature.beatsPerBar)
        let beatDuration = 60.0 / bpm
        return beatsPerBar * beatDuration
    }

    /// Returns the count-in duration in seconds for N bars at current BPM/time signature.
    public func countInDuration(bars: Int) -> Double {
        return Double(bars) * barDurationSeconds
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        // ~60fps position updates
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        displayLink = timer
    }

    private func stopTimer() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func tick() {
        guard state != .stopped else { return }

        if state == .countingIn {
            let elapsed = CFAbsoluteTimeGetCurrent() - countInStartTime
            let barsElapsed = elapsed / barDurationSeconds
            let remaining = countInBars - Int(barsElapsed)
            countInBarsRemaining = max(remaining, 0)
            onCountInTick?(countInBarsRemaining)

            if elapsed >= countInDurationSeconds {
                // Count-in complete — transition to recording
                state = .recording
                countInBarsRemaining = 0
                playbackStartTime = CFAbsoluteTimeGetCurrent()
                playbackStartBar = playheadBar
                onCountInComplete?()
            }
            return
        }

        // When waiting for audio sync, hold playhead at current position.
        // The timer keeps running so callbacks still fire, but position
        // doesn't advance until completeAudioSync() is called.
        if isWaitingForAudioSync {
            onPositionUpdate?(playheadBar)
            return
        }

        // Clamp to non-negative: when audioOutputLatency pushes
        // playbackStartTime into the future, the playhead holds at
        // playbackStartBar until audio reaches the speakers.
        let elapsed = max(0, CFAbsoluteTimeGetCurrent() - playbackStartTime)
        let barsElapsed = elapsed / barDurationSeconds
        playheadBar = playbackStartBar + barsElapsed
        onPositionUpdate?(playheadBar)
    }
}
