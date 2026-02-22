import SwiftUI
import LoopsCore
import LoopsEngine

/// Bridges TransportManager state to the SwiftUI view layer.
@Observable
@MainActor
public final class TransportViewModel {
    public var isPlaying: Bool = false
    public var isRecordArmed: Bool = false
    public var isMetronomeEnabled: Bool = false
    public var playheadBar: Double = 1.0
    public var bpm: Double = 120.0
    public var timeSignature: TimeSignature = TimeSignature()

    private let transport: TransportManager
    private let engineManager: AudioEngineManager?
    private var playbackScheduler: PlaybackScheduler?

    /// Closure to fetch the current song context for playback.
    /// Set by the view layer so play() always uses the latest data.
    public var songProvider: (() -> (song: Song, recordings: [ID<SourceRecording>: SourceRecording], audioDir: URL)?)?

    public init(transport: TransportManager, engineManager: AudioEngineManager? = nil) {
        self.transport = transport
        self.engineManager = engineManager
        syncFromTransport()
        transport.onPositionUpdate = { [weak self] bar in
            Task { @MainActor [weak self] in
                self?.playheadBar = bar
            }
        }
    }

    public func play() {
        transport.bpm = bpm
        transport.timeSignature = timeSignature

        // Start audio engine when playing (needed for metronome and future playback)
        if let engine = engineManager {
            if !engine.isRunning {
                try? engine.start()
            }
            // Update metronome parameters
            engine.metronome?.update(
                bpm: bpm,
                beatsPerBar: timeSignature.beatsPerBar,
                sampleRate: engine.currentSampleRate
            )
            engine.metronome?.reset()
            engine.metronome?.setEnabled(isMetronomeEnabled)

            // Prepare and schedule audio playback with latest song data
            if let context = songProvider?() {
                if playbackScheduler == nil {
                    let scheduler = PlaybackScheduler(engine: engine.engine, audioDirURL: context.audioDir)
                    let dispatcher = ActionDispatcher(midiOutput: CoreMIDIOutput())
                    dispatcher.triggerDelegate = scheduler
                    scheduler.actionDispatcher = dispatcher
                    playbackScheduler = scheduler
                }
                let scheduler = playbackScheduler
                let bar = playheadBar
                let currentBPM = bpm
                let ts = timeSignature
                let sr = engine.currentSampleRate
                let song = context.song
                let recordings = context.recordings
                Task {
                    await scheduler?.prepare(song: song, sourceRecordings: recordings)
                    scheduler?.play(
                        song: song,
                        fromBar: bar,
                        bpm: currentBPM,
                        timeSignature: ts,
                        sampleRate: sr
                    )
                }
            }
        }

        transport.play()
        syncFromTransport()
    }

    public func pause() {
        playbackScheduler?.stop()
        engineManager?.metronome?.setEnabled(false)
        transport.pause()
        syncFromTransport()
    }

    public func stop() {
        playbackScheduler?.stop()
        engineManager?.metronome?.setEnabled(false)
        engineManager?.metronome?.reset()
        transport.stop()
        syncFromTransport()
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func toggleRecordArm() {
        transport.toggleRecordArm()
        syncFromTransport()
    }

    public func toggleMetronome() {
        transport.toggleMetronome()
        syncFromTransport()

        // If currently playing, immediately update metronome output
        if isPlaying {
            engineManager?.metronome?.setEnabled(isMetronomeEnabled)
        }
    }

    public func setPlayheadPosition(_ bar: Double) {
        transport.setPlayheadPosition(bar)
        syncFromTransport()
    }

    public func updateBPM(_ newBPM: Double) {
        bpm = min(max(newBPM, 20.0), 300.0)
        transport.bpm = bpm
        // Live-update metronome BPM if playing
        if isPlaying {
            engineManager?.metronome?.update(
                bpm: bpm,
                beatsPerBar: timeSignature.beatsPerBar,
                sampleRate: engineManager?.currentSampleRate ?? 44100.0
            )
        }
    }

    private func syncFromTransport() {
        isPlaying = transport.state != .stopped
        isRecordArmed = transport.isRecordArmed
        isMetronomeEnabled = transport.isMetronomeEnabled
        playheadBar = transport.playheadBar
    }
}
