import Foundation
import AVFoundation
import LoopsCore

/// Transport state: stopped, playing, or recording (playing + record armed).
public enum TransportState: Sendable, Equatable {
    case stopped
    case playing
    case recording
}

/// Manages transport state machine: play, pause, stop, record arm.
/// Tracks playhead position based on BPM and drives the metronome.
public final class TransportManager: @unchecked Sendable {
    public private(set) var state: TransportState = .stopped
    public var isRecordArmed: Bool = false
    public var isMetronomeEnabled: Bool = false

    /// Current playhead position in bars (1-based, fractional).
    public private(set) var playheadBar: Double = 1.0

    /// Tempo in BPM.
    public var bpm: Double = 120.0 {
        didSet { bpm = min(max(bpm, 20.0), 300.0) }
    }

    /// Time signature.
    public var timeSignature: TimeSignature = TimeSignature()

    /// Callback fired on each position update (called from timer thread).
    public var onPositionUpdate: ((Double) -> Void)?

    private var displayLink: Timer?
    private var playbackStartTime: CFAbsoluteTime = 0
    private var playbackStartBar: Double = 1.0

    public init() {}

    deinit {
        stop()
    }

    /// Starts or resumes playback.
    public func play() {
        guard state == .stopped else { return }
        state = isRecordArmed ? .recording : .playing
        playbackStartTime = CFAbsoluteTimeGetCurrent()
        playbackStartBar = playheadBar
        startTimer()
    }

    /// Pauses playback at the current position.
    public func pause() {
        guard state == .playing || state == .recording else { return }
        stopTimer()
        // Keep playheadBar at current position
        state = .stopped
    }

    /// Stops playback and returns playhead to bar 1.
    public func stop() {
        stopTimer()
        state = .stopped
        playheadBar = 1.0
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
        let wasPlaying = state != .stopped
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
        let elapsed = CFAbsoluteTimeGetCurrent() - playbackStartTime
        let barsElapsed = elapsed / barDurationSeconds
        playheadBar = playbackStartBar + barsElapsed
        onPositionUpdate?(playheadBar)
    }
}
