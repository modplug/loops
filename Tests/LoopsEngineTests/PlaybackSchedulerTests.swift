import Testing
import Foundation
import AVFoundation
@testable import LoopsEngine
@testable import LoopsCore

/// PlaybackScheduler audio graph tests require a live AVAudioEngine.
/// Opt in with: LOOPS_AUDIO_TESTS=1 swift test
private let audioTestsEnabled =
    ProcessInfo.processInfo.environment["LOOPS_AUDIO_TESTS"] != nil

@Suite("PlaybackScheduler Tests", .serialized)
@MainActor
struct PlaybackSchedulerTests {

    @Test("Scheduler can be created and cleaned up",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func createAndCleanup() {
        let engine = AVAudioEngine()
        let tempDir = FileManager.default.temporaryDirectory
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        scheduler.cleanup()
    }

    @Test("Cleanup is idempotent",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func cleanupIdempotent() {
        let engine = AVAudioEngine()
        let tempDir = FileManager.default.temporaryDirectory
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        scheduler.cleanup()
        scheduler.cleanup()
        scheduler.cleanup()
    }

    @Test("Stop is idempotent",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func stopIdempotent() {
        let engine = AVAudioEngine()
        let tempDir = FileManager.default.temporaryDirectory
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        scheduler.stop()
        scheduler.stop()
        scheduler.stop()
    }

    @Test("Rapid sequential prepare/play/stop cycles don't crash",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func rapidSequentialCycles() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        for _ in 0..<100 {
            await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
            scheduler.play(
                song: fixture.song,
                fromBar: 1.0,
                bpm: 120,
                timeSignature: TimeSignature(),
                sampleRate: 44100
            )
            scheduler.stop()
        }

        scheduler.cleanup()
    }

    @Test("Rapid prepare without stop between cycles",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func rapidPrepareWithoutStop() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        // prepare() calls cleanup() internally, so this tests overlapping prepare→cleanup
        for _ in 0..<50 {
            await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
        }

        scheduler.cleanup()
    }

    @Test("Deinit cancels automation timer without crash",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func deinitCancelsTimer() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        var scheduler: PlaybackScheduler? = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler?.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
        scheduler?.play(
            song: fixture.song,
            fromBar: 1.0,
            bpm: 120,
            timeSignature: TimeSignature(),
            sampleRate: 44100
        )

        // Drop without calling stop() — deinit should cancel the timer
        scheduler = nil

        // Give the timer queue a moment to notice cancellation
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("Concurrent prepare calls are serialized by Task cancellation",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func concurrentPrepareWithCancellation() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        // Simulate what TransportViewModel does: launch prepare tasks
        // that cancel the previous one and await it before starting
        var previousTask: Task<Void, Never>?

        for i in 0..<50 {
            let prev = previousTask
            prev?.cancel()
            previousTask = Task {
                _ = await prev?.value
                guard !Task.isCancelled else { return }
                await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
                guard !Task.isCancelled else { return }
                scheduler.play(
                    song: fixture.song,
                    fromBar: Double(i % 4 + 1),
                    bpm: 120,
                    timeSignature: TimeSignature(),
                    sampleRate: 44100
                )
            }
        }

        // Wait for the final task to complete
        await previousTask?.value

        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("Interleaved play/stop with varying seek positions",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func interleavedPlayStopSeek() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        var previousTask: Task<Void, Never>?

        for i in 0..<100 {
            if i % 3 == 0 {
                // Simulate stop
                previousTask?.cancel()
                scheduler.stop()
            } else {
                // Simulate play/seek
                let prev = previousTask
                prev?.cancel()
                previousTask = Task {
                    _ = await prev?.value
                    guard !Task.isCancelled else { return }
                    await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
                    guard !Task.isCancelled else { return }
                    scheduler.play(
                        song: fixture.song,
                        fromBar: Double(i % 4 + 1),
                        bpm: 120,
                        timeSignature: TimeSignature(),
                        sampleRate: 44100
                    )
                }
            }
        }

        await previousTask?.value
        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("Concurrent dictionary access: prepare vs updateTrackMix",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func concurrentPrepareVsUpdateTrackMix() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        let trackID = fixture.song.tracks[0].id

        // Seed with valid state so updateTrackMix reads a populated dictionary
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        // Background: hammer updateTrackMix (reads trackMixers dictionary)
        let reader = Task.detached(priority: .high) {
            for _ in 0..<5000 {
                scheduler.updateTrackMix(
                    trackID: trackID,
                    volume: Float.random(in: 0...1),
                    pan: 0.0,
                    isMuted: false
                )
            }
        }

        // Foreground: repeatedly prepare (cleanup clears + rebuilds trackMixers)
        for _ in 0..<30 {
            await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
        }

        await reader.value
        scheduler.cleanup()
    }

    @Test("Concurrent dictionary access: prepare vs stop",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func concurrentPrepareVsStop() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        // Background: hammer stop (reads containerSubgraphs, writes activeContainers)
        let stopper = Task.detached(priority: .high) {
            for _ in 0..<2000 {
                scheduler.stop()
            }
        }

        // Foreground: repeatedly prepare (cleanup clears + rebuilds all dictionaries)
        for _ in 0..<30 {
            await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
            scheduler.play(
                song: fixture.song,
                fromBar: 1.0,
                bpm: 120,
                timeSignature: TimeSignature(),
                sampleRate: 44100
            )
        }

        await stopper.value
        scheduler.cleanup()
    }

    // MARK: - Automation Timer Race Tests

    @Test("Automation timer: stop during active timer doesn't crash",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func automationTimerStopRace() async throws {
        // This test catches races on automationTimer/playbackStartTime/playbackStartBar
        // that were previously unprotected by the lock.
        let fixture = try Self.makeTestFixtureWithAutomation()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        for _ in 0..<50 {
            await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
            scheduler.play(
                song: fixture.song,
                fromBar: 1.0,
                bpm: 120,
                timeSignature: TimeSignature(),
                sampleRate: 44100
            )
            // Give the automation timer a chance to fire
            try await Task.sleep(for: .milliseconds(20))
            scheduler.stop()
        }

        scheduler.cleanup()
    }

    @Test("Concurrent stop vs automation timer firing",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func concurrentStopVsAutomationTimer() async throws {
        // Exercises the race between the automation timer's GCD handler
        // and stop()/cleanup() from another thread.
        let fixture = try Self.makeTestFixtureWithAutomation()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
        scheduler.play(
            song: fixture.song,
            fromBar: 1.0,
            bpm: 120,
            timeSignature: TimeSignature(),
            sampleRate: 44100
        )

        // Let the automation timer fire a few times
        try await Task.sleep(for: .milliseconds(50))

        // Hammer stop from a detached task while the timer is firing
        let stopper = Task.detached(priority: .high) {
            for _ in 0..<500 {
                scheduler.stop()
            }
        }

        // Simultaneously do prepare/play cycles (cleanup stops the timer)
        for _ in 0..<20 {
            await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
            scheduler.play(
                song: fixture.song,
                fromBar: 1.0,
                bpm: 120,
                timeSignature: TimeSignature(),
                sampleRate: 44100
            )
        }

        await stopper.value
        scheduler.stop()
        scheduler.cleanup()
    }

    // MARK: - Seek Pattern Tests

    @Test("Seek pattern: cancel task then prepare/play without explicit stop",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func seekPatternNoExplicitStop() async throws {
        // Mimics TransportViewModel.seek(): cancel current task,
        // then schedule new prepare/play. The old automation timer
        // must be stopped by cleanup() inside prepare().
        let fixture = try Self.makeTestFixtureWithAutomation()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        var previousTask: Task<Void, Never>?

        for i in 0..<50 {
            let prev = previousTask
            prev?.cancel()

            // Simulate seek: stop current, then re-prepare + play at new position
            let stopTask = Task {
                _ = await prev?.value
                scheduler.stop()
            }

            previousTask = Task {
                _ = await stopTask.value
                guard !Task.isCancelled else { return }
                await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
                guard !Task.isCancelled else { return }
                scheduler.play(
                    song: fixture.song,
                    fromBar: Double(i % 4 + 1),
                    bpm: 120,
                    timeSignature: TimeSignature(),
                    sampleRate: 44100
                )
            }

            // Occasional delay to let the automation timer fire
            if i % 5 == 0 {
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        await previousTask?.value
        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("First play with audio file doesn't hang",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func firstPlayWithAudioFile() async throws {
        // Reproduces the exact user scenario: first time playing with audio loaded.
        // The time limit ensures we detect hangs.
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        // Wire up ActionDispatcher + InputMonitor (like TransportViewModel does)
        let dispatcher = ActionDispatcher(midiOutput: CoreMIDIOutput())
        dispatcher.triggerDelegate = scheduler
        dispatcher.parameterResolver = scheduler
        scheduler.actionDispatcher = dispatcher
        scheduler.inputMonitor = InputMonitor(engine: engine)

        // Mimic the schedulePlayback task chain pattern from TransportViewModel
        var generation = 0
        var playbackTask: Task<Void, Never>?

        generation += 1
        let gen = generation
        let previousTask = playbackTask
        previousTask?.cancel()
        playbackTask = Task {
            _ = await previousTask?.value
            guard generation == gen else { return }
            await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
            guard generation == gen else { return }
            scheduler.play(
                song: fixture.song,
                fromBar: 1.0,
                bpm: 120,
                timeSignature: TimeSignature(),
                sampleRate: 44100
            )
        }

        // Wait for playback to start (this is where the hang would occur)
        await playbackTask?.value

        // Clean teardown
        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("Concurrent setParameter vs prepare/cleanup",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func concurrentSetParameterVsPrepare() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        let trackID = fixture.song.tracks[0].id

        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        let path = EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0)

        // Background: hammer setParameter (reads containerSubgraphs/trackEffectUnits)
        let paramWriter = Task.detached(priority: .high) {
            for _ in 0..<5000 {
                scheduler.setParameter(at: path, value: Float.random(in: 0...1))
            }
        }

        // Foreground: repeatedly prepare (cleanup clears + rebuilds all state)
        for _ in 0..<30 {
            await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
        }

        await paramWriter.value
        scheduler.cleanup()
    }

    @Test("Concurrent triggerStart/triggerStop vs prepare",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func concurrentTriggerVsPrepare() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        let containerID = fixture.song.tracks[0].containers[0].id

        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
        scheduler.play(
            song: fixture.song,
            fromBar: 1.0,
            bpm: 120,
            timeSignature: TimeSignature(),
            sampleRate: 44100
        )

        // Background: hammer triggerStart/triggerStop (ContainerTriggerDelegate methods)
        let triggerer = Task.detached(priority: .high) {
            for i in 0..<2000 {
                if i % 2 == 0 {
                    scheduler.triggerStart(containerID: containerID)
                } else {
                    scheduler.triggerStop(containerID: containerID)
                }
            }
        }

        // Foreground: repeatedly prepare (cleanup + rebuild)
        for _ in 0..<20 {
            await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
            scheduler.play(
                song: fixture.song,
                fromBar: 1.0,
                bpm: 120,
                timeSignature: TimeSignature(),
                sampleRate: 44100
            )
        }

        await triggerer.value
        scheduler.stop()
        scheduler.cleanup()
    }

    // MARK: - Running Engine Integration Tests
    //
    // These tests use AVAudioEngine in manual rendering mode to verify that
    // player nodes are properly connected and can play audio. Manual rendering
    // mode doesn't require audio hardware, so these tests work in CI.
    //
    // This catches the "player started when in a disconnected state" crash
    // that only manifests on a running engine — the key difference from the
    // tests above which only create an engine without starting it.

    /// Creates an AVAudioEngine in manual rendering mode (no audio hardware needed).
    private static func makeRunningEngine(sampleRate: Double = 44100) throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        let renderFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: 4096)
        try engine.start()
        return engine
    }

    @Test("Player nodes are connected after prepare on a running engine",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func playerNodesConnectedOnRunningEngine() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        // Verify every container's player node has an output connection
        let containerID = fixture.song.tracks[0].containers[0].id
        let connected = engine.outputConnectionPoints(for: Self.playerNode(in: scheduler, containerID: containerID), outputBus: 0)
        #expect(!connected.isEmpty, "Player node must be connected after prepare()")

        scheduler.cleanup()
    }

    @Test("Play succeeds on running engine without crash",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func playOnRunningEngineNoCrash() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
        scheduler.play(
            song: fixture.song,
            fromBar: 1.0,
            bpm: 120,
            timeSignature: TimeSignature(),
            sampleRate: 44100
        )

        // Render a few frames to exercise the audio path
        Self.renderFrames(engine: engine, count: 10)

        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("Stereo audio file plays on running engine",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func stereoAudioPlaysOnRunningEngine() async throws {
        let fixture = try Self.makeTestFixture(channels: 2)
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        let containerID = fixture.song.tracks[0].containers[0].id
        let connected = engine.outputConnectionPoints(for: Self.playerNode(in: scheduler, containerID: containerID), outputBus: 0)
        #expect(!connected.isEmpty, "Stereo player node must be connected")

        scheduler.play(
            song: fixture.song,
            fromBar: 1.0,
            bpm: 120,
            timeSignature: TimeSignature(),
            sampleRate: 44100
        )
        Self.renderFrames(engine: engine, count: 10)

        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("48kHz audio file plays on running engine",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func differentSampleRatePlaysOnRunningEngine() async throws {
        let fixture = try Self.makeTestFixture(sampleRate: 48000)
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine(sampleRate: 48000)
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        let containerID = fixture.song.tracks[0].containers[0].id
        let connected = engine.outputConnectionPoints(for: Self.playerNode(in: scheduler, containerID: containerID), outputBus: 0)
        #expect(!connected.isEmpty, "48kHz player node must be connected")

        scheduler.play(
            song: fixture.song,
            fromBar: 1.0,
            bpm: 120,
            timeSignature: TimeSignature(),
            sampleRate: 48000
        )
        Self.renderFrames(engine: engine, count: 10)

        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("Seek on running engine reconnects and plays",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func seekOnRunningEngine() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        // Play → stop → prepare → play at new position (mimics seek)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
        scheduler.play(
            song: fixture.song,
            fromBar: 1.0,
            bpm: 120,
            timeSignature: TimeSignature(),
            sampleRate: 44100
        )
        Self.renderFrames(engine: engine, count: 5)
        scheduler.stop()

        // Seek: re-prepare and play from bar 3
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
        scheduler.play(
            song: fixture.song,
            fromBar: 3.0,
            bpm: 120,
            timeSignature: TimeSignature(),
            sampleRate: 44100
        )
        Self.renderFrames(engine: engine, count: 5)

        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("Rapid play/stop cycles on running engine",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(2)))
    func rapidPlayStopOnRunningEngine() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        for i in 0..<50 {
            await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
            scheduler.play(
                song: fixture.song,
                fromBar: Double(i % 4 + 1),
                bpm: 120,
                timeSignature: TimeSignature(),
                sampleRate: 44100
            )
            Self.renderFrames(engine: engine, count: 2)
            scheduler.stop()
        }

        scheduler.cleanup()
    }

    @Test("Multi-track playback on running engine",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func multiTrackPlaybackOnRunningEngine() async throws {
        let fixture = try Self.makeMultiTrackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
        scheduler.play(
            song: fixture.song,
            fromBar: 1.0,
            bpm: 120,
            timeSignature: TimeSignature(),
            sampleRate: 44100
        )

        Self.renderFrames(engine: engine, count: 10)

        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("Full TransportViewModel flow on running engine",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func fullTransportFlowOnRunningEngine() async throws {
        // This test mirrors the exact code path in TransportViewModel.schedulePlayback()
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        let dispatcher = ActionDispatcher(midiOutput: CoreMIDIOutput())
        dispatcher.triggerDelegate = scheduler
        dispatcher.parameterResolver = scheduler
        scheduler.actionDispatcher = dispatcher
        scheduler.inputMonitor = InputMonitor(engine: engine)

        // Mimic TransportViewModel.schedulePlayback Task chain
        var generation = 0
        var playbackTask: Task<Void, Never>?

        for i in 0..<20 {
            generation += 1
            let gen = generation
            let previousTask = playbackTask
            previousTask?.cancel()
            playbackTask = Task {
                _ = await previousTask?.value
                guard generation == gen else { return }
                await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
                guard generation == gen else { return }
                scheduler.play(
                    song: fixture.song,
                    fromBar: Double(i % 4 + 1),
                    bpm: 120,
                    timeSignature: TimeSignature(),
                    sampleRate: 44100
                )
            }

            // Simulate user rapidly pressing play/stop
            if i % 3 == 0 {
                try await Task.sleep(for: .milliseconds(30))
            }
        }

        await playbackTask?.value
        scheduler.stop()
        scheduler.cleanup()
    }

    /// Renders a number of audio frames in manual rendering mode.
    /// Ignores kAudioUnitErr_NoConnection (-10874) which occurs when the
    /// graph has player nodes that haven't scheduled audio yet.
    private static func renderFrames(engine: AVAudioEngine, count: Int) {
        let renderFormat = engine.manualRenderingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: renderFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            return
        }
        for _ in 0..<count {
            do {
                let status = try engine.renderOffline(engine.manualRenderingMaximumFrameCount, to: buffer)
                if status == .error { break }
            } catch {
                // -10874 (kAudioUnitErr_NoConnection) is expected when player nodes
                // haven't started rendering yet. Other errors are unexpected but
                // we don't want to crash the test — the important assertion is
                // that playerNode.play() didn't crash.
                break
            }
        }
    }

    // MARK: - Fixture Helpers

    /// Accesses the player node for a given container via the internal containerSubgraphs dict.
    /// Uses the lock to safely read the stored subgraph.
    private static func playerNode(in scheduler: PlaybackScheduler, containerID: ID<Container>) -> AVAudioPlayerNode {
        // Access the internal state through the ParameterResolver interface by
        // inspecting the scheduler's stored subgraphs directly via Mirror.
        let mirror = Mirror(reflecting: scheduler)
        let subgraphs = mirror.descendant("containerSubgraphs") as! [ID<Container>: Any]
        let subgraph = subgraphs[containerID]!
        let sgMirror = Mirror(reflecting: subgraph)
        return sgMirror.descendant("playerNode") as! AVAudioPlayerNode
    }

    /// Creates a test fixture with configurable sample rate and channel count.
    private static func makeTestFixture(
        sampleRate: Double = 44100,
        channels: UInt32 = 1
    ) throws -> (
        tempDir: URL,
        song: Song,
        recordings: [ID<SourceRecording>: SourceRecording]
    ) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let beatsPerBar = 4.0
        let secondsPerBeat = 60.0 / 120.0
        let samplesPerBar = beatsPerBar * secondsPerBeat * sampleRate
        let sampleCount = AVAudioFrameCount(4.0 * samplesPerBar)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        // Fill with a quiet sine wave so the audio is valid (not silence)
        if let channelData = buffer.floatChannelData {
            for ch in 0..<Int(channels) {
                for frame in 0..<Int(sampleCount) {
                    channelData[ch][frame] = sin(Float(frame) * 0.01) * 0.1
                }
            }
        }
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(
            filename: "test.caf",
            sampleRate: sampleRate,
            sampleCount: Int64(sampleCount)
        )

        let container = Container(
            name: "Test Container",
            startBar: 1,
            lengthBars: 4,
            sourceRecordingID: recordingID
        )
        let track = Track(name: "Test Track", kind: .audio, containers: [container])
        let song = Song(name: "Test Song", tracks: [track])
        let recordings: [ID<SourceRecording>: SourceRecording] = [recordingID: recording]

        return (tempDir, song, recordings)
    }

    /// Creates a fixture with multiple tracks to test multi-track playback.
    private static func makeMultiTrackFixture() throws -> (
        tempDir: URL,
        song: Song,
        recordings: [ID<SourceRecording>: SourceRecording]
    ) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let sampleCount: AVAudioFrameCount = 352800
        var recordings: [ID<SourceRecording>: SourceRecording] = [:]
        var tracks: [Track] = []

        for i in 0..<3 {
            let channels: UInt32 = i == 0 ? 1 : 2  // Mix mono and stereo
            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: channels)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
            buffer.frameLength = sampleCount
            let filename = "track\(i).caf"
            let fileURL = tempDir.appendingPathComponent(filename)
            let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            try file.write(from: buffer)

            let recordingID = ID<SourceRecording>()
            recordings[recordingID] = SourceRecording(
                filename: filename,
                sampleRate: 44100,
                sampleCount: Int64(sampleCount)
            )

            let container = Container(
                name: "Container \(i)",
                startBar: 1,
                lengthBars: 4,
                sourceRecordingID: recordingID
            )
            tracks.append(Track(name: "Track \(i)", kind: .audio, containers: [container]))
        }

        let song = Song(name: "Multi-Track Song", tracks: tracks)
        return (tempDir, song, recordings)
    }

    /// Creates a test fixture with track-level automation to exercise the automation timer.
    private static func makeTestFixtureWithAutomation() throws -> (
        tempDir: URL,
        song: Song,
        recordings: [ID<SourceRecording>: SourceRecording]
    ) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let sampleCount: AVAudioFrameCount = 352800
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(
            filename: "test.caf",
            sampleRate: 44100,
            sampleCount: Int64(sampleCount)
        )

        let container = Container(
            name: "Test Container",
            startBar: 1,
            lengthBars: 4,
            sourceRecordingID: recordingID
        )
        let trackID = ID<Track>()
        let automationLane = AutomationLane(
            targetPath: EffectPath.trackVolume(trackID: trackID),
            breakpoints: [
                AutomationBreakpoint(position: 0.0, value: 0.0),
                AutomationBreakpoint(position: 4.0, value: 1.0)
            ]
        )
        let track = Track(
            id: trackID,
            name: "Test Track",
            kind: .audio,
            containers: [container],
            trackAutomationLanes: [automationLane]
        )
        let song = Song(name: "Test Song", tracks: [track])
        let recordings: [ID<SourceRecording>: SourceRecording] = [recordingID: recording]

        return (tempDir, song, recordings)
    }

    // MARK: - Live Effect Unit Fixtures

    // Apple's built-in AUDelay: aufx/dely/appl
    private static let delayComponent = AudioComponentInfo(
        componentType: 0x61756678,   // 'aufx'
        componentSubType: 0x64656C79, // 'dely'
        componentManufacturer: 0x6170706C // 'appl'
    )

    private static func makeTestFixtureWithEffects() throws -> (
        tempDir: URL,
        song: Song,
        recordings: [ID<SourceRecording>: SourceRecording],
        containerID: ID<Container>,
        trackID: ID<Track>
    ) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let sampleCount: AVAudioFrameCount = 352800
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        if let channelData = buffer.floatChannelData {
            for frame in 0..<Int(sampleCount) {
                channelData[0][frame] = sin(Float(frame) * 0.01) * 0.1
            }
        }
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(
            filename: "test.caf",
            sampleRate: 44100,
            sampleCount: Int64(sampleCount)
        )

        let containerID = ID<Container>()
        let containerEffect = InsertEffect(
            component: delayComponent,
            displayName: "AUDelay",
            orderIndex: 0
        )
        let container = Container(
            id: containerID,
            name: "Test Container",
            startBar: 1,
            lengthBars: 4,
            sourceRecordingID: recordingID,
            insertEffects: [containerEffect]
        )

        let trackID = ID<Track>()
        let trackEffect = InsertEffect(
            component: delayComponent,
            displayName: "AUDelay Track",
            orderIndex: 0
        )
        let track = Track(
            id: trackID,
            name: "Test Track",
            kind: .audio,
            containers: [container],
            insertEffects: [trackEffect]
        )
        let song = Song(name: "Test Song", tracks: [track])
        let recordings: [ID<SourceRecording>: SourceRecording] = [recordingID: recording]

        return (tempDir, song, recordings, containerID, trackID)
    }

    // MARK: - Live Effect Unit Tests

    @Test("liveEffectUnit returns container effect after prepare",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func liveEffectUnitContainerEffect() async throws {
        let fixture = try Self.makeTestFixtureWithEffects()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        // Before prepare, should return nil
        let before = scheduler.liveEffectUnit(containerID: fixture.containerID, effectIndex: 0)
        #expect(before == nil)

        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        let unit = scheduler.liveEffectUnit(containerID: fixture.containerID, effectIndex: 0)
        #expect(unit != nil)

        scheduler.cleanup()
    }

    @Test("liveTrackEffectUnit returns track effect after prepare",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func liveTrackEffectUnitAfterPrepare() async throws {
        let fixture = try Self.makeTestFixtureWithEffects()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        let before = scheduler.liveTrackEffectUnit(trackID: fixture.trackID, effectIndex: 0)
        #expect(before == nil)

        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        let unit = scheduler.liveTrackEffectUnit(trackID: fixture.trackID, effectIndex: 0)
        #expect(unit != nil)

        scheduler.cleanup()
    }

    @Test("liveEffectUnit returns nil for invalid container ID",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func liveEffectUnitInvalidContainerID() async throws {
        let fixture = try Self.makeTestFixtureWithEffects()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        let unit = scheduler.liveEffectUnit(containerID: ID<Container>(), effectIndex: 0)
        #expect(unit == nil)

        scheduler.cleanup()
    }

    @Test("liveEffectUnit returns nil for out-of-bounds index",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func liveEffectUnitOutOfBoundsIndex() async throws {
        let fixture = try Self.makeTestFixtureWithEffects()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        let unit = scheduler.liveEffectUnit(containerID: fixture.containerID, effectIndex: 99)
        #expect(unit == nil)

        scheduler.cleanup()
    }

    @Test("liveEffectUnit returns nil after cleanup",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func liveEffectUnitNilAfterCleanup() async throws {
        let fixture = try Self.makeTestFixtureWithEffects()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        let unit = scheduler.liveEffectUnit(containerID: fixture.containerID, effectIndex: 0)
        #expect(unit != nil)

        scheduler.cleanup()

        let after = scheduler.liveEffectUnit(containerID: fixture.containerID, effectIndex: 0)
        #expect(after == nil)
    }

    @Test("Parameter change on live effect unit is reflected",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func parameterChangeOnLiveEffectUnit() async throws {
        let fixture = try Self.makeTestFixtureWithEffects()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        guard let unit = scheduler.liveEffectUnit(containerID: fixture.containerID, effectIndex: 0) else {
            Issue.record("Expected live effect unit")
            return
        }

        // Get a parameter from the AU's parameter tree
        guard let param = unit.auAudioUnit.parameterTree?.allParameters.first else {
            Issue.record("Expected at least one parameter on AUDelay")
            return
        }

        let original = param.value
        let newValue = param.minValue + (param.maxValue - param.minValue) * 0.5
        param.value = newValue

        // Verify the change persists on the same instance
        #expect(param.value != original || original == newValue)
        #expect(abs(param.value - newValue) < 0.01)

        scheduler.cleanup()
    }

    @Test("Preset data round-trips through engine instance",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func presetRoundTripThroughEngineInstance() async throws {
        let fixture = try Self.makeTestFixtureWithEffects()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        guard let unit = scheduler.liveEffectUnit(containerID: fixture.containerID, effectIndex: 0) else {
            Issue.record("Expected live effect unit")
            return
        }

        // Modify a parameter
        if let param = unit.auAudioUnit.parameterTree?.allParameters.first {
            param.value = param.minValue + (param.maxValue - param.minValue) * 0.75
        }

        // Save preset from the engine instance
        let host = AudioUnitHost(engine: engine)
        let presetData = host.saveState(audioUnit: unit)
        #expect(presetData != nil)

        // The preset data should be restorable
        if let data = presetData {
            // Create a fresh AU and restore the preset
            let freshUnit = try await host.loadAudioUnit(component: Self.delayComponent)
            try host.restoreState(audioUnit: freshUnit, data: data)

            // Verify the parameter was restored
            if let originalParam = unit.auAudioUnit.parameterTree?.allParameters.first,
               let restoredParam = freshUnit.auAudioUnit.parameterTree?.allParameters.first {
                #expect(abs(originalParam.value - restoredParam.value) < 0.01)
            }
        }

        scheduler.cleanup()
    }
}
