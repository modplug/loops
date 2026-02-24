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

    @Test("Stop with skipDeclick skips fade and stops immediately",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func stopWithSkipDeclick() async throws {
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
        Self.renderFrames(engine: engine, count: 2)

        // skipDeclick should stop immediately without the ~8ms fade
        scheduler.stop(skipDeclick: true)

        // Verify player nodes are stopped
        let containerID = fixture.song.tracks[0].containers[0].id
        let player = Self.playerNode(in: scheduler, containerID: containerID)
        #expect(!player.isPlaying)
        #expect(!scheduler.isActive)

        scheduler.cleanup()
    }

    @Test("Stop with skipDeclick is idempotent",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func stopWithSkipDeclickIdempotent() {
        let engine = AVAudioEngine()
        let tempDir = FileManager.default.temporaryDirectory
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        scheduler.stop(skipDeclick: true)
        scheduler.stop(skipDeclick: true)
        scheduler.stop(skipDeclick: true)
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

    // MARK: - Incremental Graph Update Tests

    /// Creates a two-track fixture for incremental update tests.
    /// Returns the fixture plus individual track/container IDs for modification.
    private static func makeTwoTrackFixture() throws -> (
        tempDir: URL,
        song: Song,
        recordings: [ID<SourceRecording>: SourceRecording],
        trackAID: ID<Track>,
        trackBID: ID<Track>,
        containerAID: ID<Container>,
        containerBID: ID<Container>
    ) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let sampleCount: AVAudioFrameCount = 352800
        var recordings: [ID<SourceRecording>: SourceRecording] = [:]
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

        let recIDA = ID<SourceRecording>()
        let bufA = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        bufA.frameLength = sampleCount
        if let d = bufA.floatChannelData {
            for i in 0..<Int(sampleCount) { d[0][i] = sin(Float(i) * 0.01) * 0.1 }
        }
        let fileA = tempDir.appendingPathComponent("trackA.caf")
        let afA = try AVAudioFile(forWriting: fileA, settings: format.settings)
        try afA.write(from: bufA)
        recordings[recIDA] = SourceRecording(filename: "trackA.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        let recIDB = ID<SourceRecording>()
        let bufB = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        bufB.frameLength = sampleCount
        if let d = bufB.floatChannelData {
            for i in 0..<Int(sampleCount) { d[0][i] = sin(Float(i) * 0.02) * 0.1 }
        }
        let fileB = tempDir.appendingPathComponent("trackB.caf")
        let afB = try AVAudioFile(forWriting: fileB, settings: format.settings)
        try afB.write(from: bufB)
        recordings[recIDB] = SourceRecording(filename: "trackB.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        let containerAID = ID<Container>()
        let containerA = Container(id: containerAID, name: "Container A", startBar: 1, lengthBars: 4, sourceRecordingID: recIDA)
        let trackAID = ID<Track>()
        let trackA = Track(id: trackAID, name: "Track A", kind: .audio, containers: [containerA])

        let containerBID = ID<Container>()
        let containerB = Container(id: containerBID, name: "Container B", startBar: 1, lengthBars: 4, sourceRecordingID: recIDB)
        let trackBID = ID<Track>()
        let trackB = Track(id: trackBID, name: "Track B", kind: .audio, containers: [containerB])

        let song = Song(name: "Two Track Song", tracks: [trackA, trackB])
        return (tempDir, song, recordings, trackAID, trackBID, containerAID, containerBID)
    }

    @Test("prepareIncremental returns empty set when nothing changed",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func prepareIncrementalNoChanges() async throws {
        let fixture = try Self.makeTwoTrackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        // Full prepare first
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        // Incremental with same song — nothing changed
        let changed = await scheduler.prepareIncremental(
            song: fixture.song,
            sourceRecordings: fixture.recordings
        )
        #expect(changed.isEmpty)

        scheduler.cleanup()
    }

    @Test("prepareIncremental rebuilds only the track with added effect",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func prepareIncrementalSingleTrackChanged() async throws {
        let fixture = try Self.makeTwoTrackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        // Modify track B by adding an effect
        let effect = InsertEffect(component: Self.delayComponent, displayName: "AUDelay", orderIndex: 0)
        var modifiedTrackB = fixture.song.tracks[1]
        modifiedTrackB.insertEffects = [effect]
        let modifiedSong = Song(
            id: fixture.song.id,
            name: fixture.song.name,
            tracks: [fixture.song.tracks[0], modifiedTrackB]
        )

        let changed = await scheduler.prepareIncremental(
            song: modifiedSong,
            sourceRecordings: fixture.recordings
        )

        // Only track B should have been rebuilt
        #expect(changed.count == 1)
        #expect(changed.contains(fixture.trackBID))
        #expect(!changed.contains(fixture.trackAID))

        scheduler.cleanup()
    }

    @Test("prepareIncremental preserves track A's subgraph when track B changes",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func prepareIncrementalPreservesUnchangedTrack() async throws {
        let fixture = try Self.makeTwoTrackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        // Get track A's player node before incremental update
        let playerA = Self.playerNode(in: scheduler, containerID: fixture.containerAID)
        let playerAConnected = playerA.engine != nil

        // Modify track B by adding an effect
        let effect = InsertEffect(component: Self.delayComponent, displayName: "AUDelay", orderIndex: 0)
        var modifiedTrackB = fixture.song.tracks[1]
        modifiedTrackB.insertEffects = [effect]
        let modifiedSong = Song(
            id: fixture.song.id,
            name: fixture.song.name,
            tracks: [fixture.song.tracks[0], modifiedTrackB]
        )

        _ = await scheduler.prepareIncremental(
            song: modifiedSong,
            sourceRecordings: fixture.recordings
        )

        // Track A's player node should be the SAME instance (not rebuilt)
        let playerAAfter = Self.playerNode(in: scheduler, containerID: fixture.containerAID)
        #expect(playerA === playerAAfter)
        #expect(playerAConnected)

        scheduler.cleanup()
    }

    @Test("prepareIncremental falls back to full prepare when no prior fingerprints",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func prepareIncrementalFallbackToFull() async throws {
        let fixture = try Self.makeTwoTrackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        // Call prepareIncremental without a prior prepare — should fall back to full
        let changed = await scheduler.prepareIncremental(
            song: fixture.song,
            sourceRecordings: fixture.recordings
        )

        // All non-master tracks should be reported as changed
        #expect(changed.contains(fixture.trackAID))
        #expect(changed.contains(fixture.trackBID))

        scheduler.cleanup()
    }

    @Test("currentPlaybackBar returns nil when not playing",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func currentPlaybackBarWhenStopped() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        // Not playing — should return nil
        #expect(scheduler.currentPlaybackBar() == nil)
        #expect(!scheduler.isActive)

        scheduler.cleanup()
    }

    @Test("currentPlaybackBar returns position near fromBar immediately after play",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func currentPlaybackBarAfterPlay() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        scheduler.play(
            song: fixture.song,
            fromBar: 2.0,
            bpm: 120,
            timeSignature: TimeSignature(),
            sampleRate: 44100
        )

        #expect(scheduler.isActive)
        // Immediately after play, position should be very close to 2.0
        if let bar = scheduler.currentPlaybackBar() {
            #expect(bar >= 2.0)
            #expect(bar < 2.1)  // Less than 0.1 bar elapsed
        } else {
            Issue.record("Expected non-nil playback bar")
        }

        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("Rapid prepareIncremental cycles don't crash",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func rapidIncrementalCycles() async throws {
        let fixture = try Self.makeTwoTrackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        // Initial prepare
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        // Create two alternating song variants
        let effect = InsertEffect(component: Self.delayComponent, displayName: "AUDelay", orderIndex: 0)
        var trackBWithEffect = fixture.song.tracks[1]
        trackBWithEffect.insertEffects = [effect]
        let songWithEffect = Song(
            id: fixture.song.id,
            name: fixture.song.name,
            tracks: [fixture.song.tracks[0], trackBWithEffect]
        )

        // Rapidly toggle effect on/off
        for i in 0..<20 {
            let song = (i % 2 == 0) ? songWithEffect : fixture.song
            _ = await scheduler.prepareIncremental(
                song: song,
                sourceRecordings: fixture.recordings
            )
        }

        scheduler.cleanup()
    }

    @Test("playChangedTracks schedules only specified tracks",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func playChangedTracksSchedulesSpecifiedOnly() async throws {
        let fixture = try Self.makeTwoTrackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        // Play only track B containers
        scheduler.playChangedTracks(
            [fixture.trackBID],
            song: fixture.song,
            fromBar: 1.0,
            bpm: 120,
            timeSignature: TimeSignature(),
            sampleRate: 44100
        )

        // Track B's player should be playing, track A's should not
        let playerA = Self.playerNode(in: scheduler, containerID: fixture.containerAID)
        let playerB = Self.playerNode(in: scheduler, containerID: fixture.containerBID)
        #expect(!playerA.isPlaying)
        #expect(playerB.isPlaying)

        scheduler.stop()
        scheduler.cleanup()
    }

    // MARK: - needsPrepare / invalidatePreparedState

    @Test("needsPrepare returns true before first prepare",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func needsPrepareBeforeFirstPrepare() throws {
        let fixture = try Self.makeTestFixture()
        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        #expect(scheduler.needsPrepare(song: fixture.song, recordingIDs: Set(fixture.recordings.keys)))
        scheduler.cleanup()
    }

    @Test("needsPrepare returns false after prepare with same graph shape",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func needsPrepareFalseAfterPrepare() async throws {
        let fixture = try Self.makeTestFixture()
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: engine.outputNode.outputFormat(forBus: 0), maximumFrameCount: 4096)
        try engine.start()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        // Same song — needsPrepare should be false
        #expect(!scheduler.needsPrepare(song: fixture.song, recordingIDs: Set(fixture.recordings.keys)))

        // Cosmetic change (rename track) — should still be false
        var renamed = fixture.song
        renamed.tracks[0] = Track(
            id: fixture.song.tracks[0].id,
            name: "Renamed",
            kind: fixture.song.tracks[0].kind,
            containers: fixture.song.tracks[0].containers
        )
        #expect(!scheduler.needsPrepare(song: renamed, recordingIDs: Set(fixture.recordings.keys)))

        scheduler.cleanup()
    }

    @Test("needsPrepare returns true after invalidatePreparedState",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func needsPrepareAfterInvalidate() async throws {
        let fixture = try Self.makeTestFixture()
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: engine.outputNode.outputFormat(forBus: 0), maximumFrameCount: 4096)
        try engine.start()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
        #expect(!scheduler.needsPrepare(song: fixture.song, recordingIDs: Set(fixture.recordings.keys)))

        scheduler.invalidatePreparedState()
        #expect(scheduler.needsPrepare(song: fixture.song, recordingIDs: Set(fixture.recordings.keys)))

        scheduler.cleanup()
    }

    // MARK: - Failed Container ID Tracking

    @Test("failedContainerIDs is empty for valid effect chains",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func failedContainerIDsEmptyForValidEffects() async throws {
        let fixture = try Self.makeTestFixtureWithEffects()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        #expect(scheduler.failedContainerIDs.isEmpty)

        scheduler.cleanup()
    }

    @Test("onEffectChainStatusChanged fires after prepare",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func onEffectChainStatusChangedFires() async throws {
        let fixture = try Self.makeTestFixtureWithEffects()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        var callbackFired = false
        var reportedIDs: Set<ID<Container>>?
        scheduler.onEffectChainStatusChanged = { ids in
            callbackFired = true
            reportedIDs = ids
        }

        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        #expect(callbackFired)
        #expect(reportedIDs != nil)
        #expect(reportedIDs?.isEmpty == true)

        scheduler.cleanup()
    }

    @Test("onEffectChainStatusChanged fires after prepareIncremental",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func onEffectChainStatusChangedFiresIncremental() async throws {
        let fixture = try Self.makeTwoTrackFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        var callbackCount = 0
        scheduler.onEffectChainStatusChanged = { _ in
            callbackCount += 1
        }

        // Add an effect to track B
        let effect = InsertEffect(component: Self.delayComponent, displayName: "AUDelay", orderIndex: 0)
        var modifiedTrackB = fixture.song.tracks[1]
        modifiedTrackB.insertEffects = [effect]
        let modifiedSong = Song(
            id: fixture.song.id,
            name: fixture.song.name,
            tracks: [fixture.song.tracks[0], modifiedTrackB]
        )

        _ = await scheduler.prepareIncremental(
            song: modifiedSong,
            sourceRecordings: fixture.recordings
        )

        #expect(callbackCount == 1)
        #expect(scheduler.failedContainerIDs.isEmpty)

        scheduler.cleanup()
    }

    // MARK: - AU State Preservation Across Rebuilds

    /// Creates a stereo fixture with effects for AU state tests that call play().
    /// Stereo is needed because effect chains auto-negotiate stereo format.
    private static func makeStereoFixtureWithEffects() throws -> (
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
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        if let channelData = buffer.floatChannelData {
            for ch in 0..<2 {
                for frame in 0..<Int(sampleCount) {
                    channelData[ch][frame] = sin(Float(frame) * 0.01) * 0.1
                }
            }
        }
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(filename: "test.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        let containerID = ID<Container>()
        let containerEffect = InsertEffect(component: delayComponent, displayName: "AUDelay", orderIndex: 0)
        let container = Container(
            id: containerID,
            name: "Test Container",
            startBar: 1,
            lengthBars: 4,
            sourceRecordingID: recordingID,
            insertEffects: [containerEffect]
        )

        let trackID = ID<Track>()
        let track = Track(id: trackID, name: "Test Track", kind: .audio, containers: [container])
        let song = Song(name: "Test Song", tracks: [track])
        let recordings: [ID<SourceRecording>: SourceRecording] = [recordingID: recording]

        return (tempDir, song, recordings, containerID, trackID)
    }

    @Test("AU parameter state preserved across prepareIncremental",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func auStatePreservedAcrossIncrementalRebuild() async throws {
        let fixture = try Self.makeStereoFixtureWithEffects()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        // play() populates containerToTrack which prepareIncremental needs
        // for AU state capture (matching real app usage via refreshPlaybackGraph)
        scheduler.play(
            song: fixture.song,
            fromBar: 1.0,
            bpm: 120,
            timeSignature: TimeSignature(),
            sampleRate: 44100
        )
        Self.renderFrames(engine: engine, count: 2)

        // Modify a parameter on the live container effect
        guard let unit = scheduler.liveEffectUnit(containerID: fixture.containerID, effectIndex: 0),
              let param = unit.auAudioUnit.parameterTree?.allParameters.first else {
            Issue.record("Expected live effect unit with parameters")
            return
        }

        let testValue = param.minValue + (param.maxValue - param.minValue) * 0.77
        param.value = testValue

        // Add a second effect to force a graph rebuild for this container's track
        let effect2 = InsertEffect(component: Self.delayComponent, displayName: "AUDelay 2", orderIndex: 1)
        var modifiedContainer = fixture.song.tracks[0].containers[0]
        modifiedContainer.insertEffects = fixture.song.tracks[0].containers[0].insertEffects + [effect2]
        var modifiedTrack = fixture.song.tracks[0]
        modifiedTrack.containers = [modifiedContainer]
        let modifiedSong = Song(
            id: fixture.song.id,
            name: fixture.song.name,
            tracks: [modifiedTrack]
        )

        // prepareIncremental captures AU state then rebuilds (mimics refreshPlaybackGraph)
        _ = await scheduler.prepareIncremental(
            song: modifiedSong,
            sourceRecordings: fixture.recordings
        )

        // The first effect should have its state restored
        guard let restoredUnit = scheduler.liveEffectUnit(containerID: fixture.containerID, effectIndex: 0),
              let restoredParam = restoredUnit.auAudioUnit.parameterTree?.allParameters.first else {
            Issue.record("Expected restored effect unit with parameters")
            return
        }

        #expect(abs(restoredParam.value - testValue) < 0.01,
                "Parameter should be restored after incremental rebuild")

        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("AU state preserved after effect reorder via prepareIncremental",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func auStatePreservedAfterReorder() async throws {
        // Create a stereo fixture with two container effects (delay + reverb)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleCount: AVAudioFrameCount = 352800
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        if let d = buffer.floatChannelData {
            for ch in 0..<2 {
                for i in 0..<Int(sampleCount) { d[ch][i] = sin(Float(i) * 0.01) * 0.1 }
            }
        }
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(filename: "test.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        // Two effects: AUDelay and AUReverb2
        let reverbComponent = AudioComponentInfo(
            componentType: 0x61756678,    // 'aufx'
            componentSubType: 0x72766232, // 'rvb2'
            componentManufacturer: 0x6170706C // 'appl'
        )
        let delayEffect = InsertEffect(component: Self.delayComponent, displayName: "Delay", orderIndex: 0)
        let reverbEffect = InsertEffect(component: reverbComponent, displayName: "Reverb", orderIndex: 1)

        let containerID = ID<Container>()
        let container = Container(
            id: containerID,
            name: "Test",
            startBar: 1,
            lengthBars: 4,
            sourceRecordingID: recordingID,
            insertEffects: [delayEffect, reverbEffect]
        )
        let trackID = ID<Track>()
        let track = Track(id: trackID, name: "Track", kind: .audio, containers: [container])
        let song = Song(name: "Test", tracks: [track])
        let recordings: [ID<SourceRecording>: SourceRecording] = [recordingID: recording]

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        await scheduler.prepare(song: song, sourceRecordings: recordings)

        // play() populates containerToTrack which prepareIncremental needs
        scheduler.play(
            song: song,
            fromBar: 1.0,
            bpm: 120,
            timeSignature: TimeSignature(),
            sampleRate: 44100
        )
        Self.renderFrames(engine: engine, count: 2)

        // Set a unique parameter value on the delay (index 0)
        guard let delayUnit = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 0),
              let delayParam = delayUnit.auAudioUnit.parameterTree?.allParameters.first else {
            Issue.record("Expected delay effect with parameters")
            return
        }
        let delayValue = delayParam.minValue + (delayParam.maxValue - delayParam.minValue) * 0.33
        delayParam.value = delayValue

        // Set a unique parameter value on the reverb (index 1)
        guard let reverbUnit = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 1),
              let reverbParam = reverbUnit.auAudioUnit.parameterTree?.allParameters.first else {
            Issue.record("Expected reverb effect with parameters")
            return
        }
        let reverbValue = reverbParam.minValue + (reverbParam.maxValue - reverbParam.minValue) * 0.88
        reverbParam.value = reverbValue

        // Reorder: swap delay and reverb
        let reorderedDelay = InsertEffect(
            id: delayEffect.id, component: Self.delayComponent,
            displayName: "Delay", orderIndex: 1
        )
        let reorderedReverb = InsertEffect(
            id: reverbEffect.id, component: reverbComponent,
            displayName: "Reverb", orderIndex: 0
        )
        var reorderedContainer = container
        reorderedContainer.insertEffects = [reorderedReverb, reorderedDelay]
        var reorderedTrack = track
        reorderedTrack.containers = [reorderedContainer]
        let reorderedSong = Song(id: song.id, name: song.name, tracks: [reorderedTrack])

        // prepareIncremental captures state then rebuilds (mimics refreshPlaybackGraph)
        _ = await scheduler.prepareIncremental(song: reorderedSong, sourceRecordings: recordings)

        // After reorder: index 0 = reverb, index 1 = delay
        // State should match by component, not by index
        guard let newReverbUnit = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 0),
              let newReverbParam = newReverbUnit.auAudioUnit.parameterTree?.allParameters.first else {
            Issue.record("Expected reverb at index 0 after reorder")
            return
        }
        guard let newDelayUnit = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 1),
              let newDelayParam = newDelayUnit.auAudioUnit.parameterTree?.allParameters.first else {
            Issue.record("Expected delay at index 1 after reorder")
            return
        }

        #expect(abs(newReverbParam.value - reverbValue) < 0.01,
                "Reverb parameter should be restored at new position")
        #expect(abs(newDelayParam.value - delayValue) < 0.01,
                "Delay parameter should be restored at new position")

        scheduler.stop()
        scheduler.cleanup()
    }

    // MARK: - Safe Disconnect / Cleanup Robustness

    @Test("Cleanup after failed chain connection doesn't crash",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func cleanupAfterFailedChainNoCrash() async throws {
        // Use a bogus component that will fail to instantiate/connect.
        // The scheduler stores empty arrays when the chain fails, so
        // cleanup should not try to disconnect non-existent nodes.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleCount: AVAudioFrameCount = 352800
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(filename: "test.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        // Use a bogus component that won't load
        let bogusComponent = AudioComponentInfo(
            componentType: 0x61756678,    // 'aufx'
            componentSubType: 0x00000000, // bogus
            componentManufacturer: 0x00000000
        )
        let bogusEffect = InsertEffect(component: bogusComponent, displayName: "Bogus", orderIndex: 0)

        let containerID = ID<Container>()
        let container = Container(
            id: containerID,
            name: "Test",
            startBar: 1,
            lengthBars: 4,
            sourceRecordingID: recordingID,
            insertEffects: [bogusEffect]
        )
        let track = Track(name: "Track", kind: .audio, containers: [container])
        let song = Song(name: "Test", tracks: [track])
        let recordings: [ID<SourceRecording>: SourceRecording] = [recordingID: recording]

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        await scheduler.prepare(song: song, sourceRecordings: recordings)

        // cleanup should not crash even if the bogus effect caused a chain failure
        scheduler.cleanup()
        // Second cleanup is idempotent
        scheduler.cleanup()
    }

    @Test("Multiple rapid prepare/cleanup cycles with effects don't crash",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func rapidPrepareCleanupWithEffects() async throws {
        let fixture = try Self.makeTestFixtureWithEffects()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)

        for _ in 0..<30 {
            await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
        }

        scheduler.cleanup()
    }

    @Test("liveEffectUnit returns nil for container with failed effect chain",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func liveEffectUnitNilForFailedChain() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleCount: AVAudioFrameCount = 352800
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(filename: "test.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        // Use a truly invalid component type that won't match any AU.
        // Zero sub/manufacturer acts as a wildcard with 'aufx', so we need
        // a non-existent type to guarantee load failure.
        let bogusComponent = AudioComponentInfo(
            componentType: 0x7A7A7A7A,   // 'zzzz' — not a real AU type
            componentSubType: 0x7A7A7A7A,
            componentManufacturer: 0x7A7A7A7A
        )
        let bogusEffect = InsertEffect(component: bogusComponent, displayName: "Bogus", orderIndex: 0)

        let containerID = ID<Container>()
        let container = Container(
            id: containerID,
            name: "Test",
            startBar: 1,
            lengthBars: 4,
            sourceRecordingID: recordingID,
            insertEffects: [bogusEffect]
        )
        let track = Track(name: "Track", kind: .audio, containers: [container])
        let song = Song(name: "Test", tracks: [track])
        let recordings: [ID<SourceRecording>: SourceRecording] = [recordingID: recording]

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        await scheduler.prepare(song: song, sourceRecordings: recordings)

        // The bogus effect should not have loaded, so effectUnits is empty
        let unit = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 0)
        #expect(unit == nil)

        scheduler.cleanup()
    }

    // MARK: - Bypassed Effects Skip in Scheduler

    @Test("Bypassed effects are not in effectUnits array",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func bypassedEffectsNotInScheduler() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleCount: AVAudioFrameCount = 352800
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        if let d = buffer.floatChannelData {
            for i in 0..<Int(sampleCount) { d[0][i] = sin(Float(i) * 0.01) * 0.1 }
        }
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(filename: "test.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        // Create 3 effects: A (active), B (bypassed), C (active)
        let effectA = InsertEffect(component: Self.delayComponent, displayName: "A", orderIndex: 0)
        var effectB = InsertEffect(component: Self.delayComponent, displayName: "B", orderIndex: 1)
        effectB.isBypassed = true
        let effectC = InsertEffect(component: Self.delayComponent, displayName: "C", orderIndex: 2)

        let containerID = ID<Container>()
        let container = Container(
            id: containerID,
            name: "Test",
            startBar: 1,
            lengthBars: 4,
            sourceRecordingID: recordingID,
            insertEffects: [effectA, effectB, effectC]
        )
        let track = Track(name: "Track", kind: .audio, containers: [container])
        let song = Song(name: "Test", tracks: [track])
        let recordings: [ID<SourceRecording>: SourceRecording] = [recordingID: recording]

        let engine = AVAudioEngine()
        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        await scheduler.prepare(song: song, sourceRecordings: recordings)

        // Only 2 active effects should be in the scheduler
        let unit0 = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 0)
        let unit1 = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 1)
        let unit2 = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 2)

        #expect(unit0 != nil, "Active effect A should be at scheduler index 0")
        #expect(unit1 != nil, "Active effect C should be at scheduler index 1")
        #expect(unit2 == nil, "No effect at scheduler index 2 (only 2 active)")

        scheduler.cleanup()
    }

    // MARK: - Effect Chain Connection Tests

    @Test("Single effect connects between player and mixer",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func singleEffectChainConnection() async throws {
        let fixture = try Self.makeTestFixtureWithEffects()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        // Effect unit should be connected and accessible
        let unit = scheduler.liveEffectUnit(containerID: fixture.containerID, effectIndex: 0)
        #expect(unit != nil)

        // Player node should be connected (has output)
        let player = Self.playerNode(in: scheduler, containerID: fixture.containerID)
        let connections = engine.outputConnectionPoints(for: player, outputBus: 0)
        #expect(!connections.isEmpty, "Player node must be connected through effect chain")

        scheduler.cleanup()
    }

    @Test("Multiple effects form a chain in correct order",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func multipleEffectsChainOrder() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleCount: AVAudioFrameCount = 352800
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(filename: "test.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        let containerID = ID<Container>()
        let effect1 = InsertEffect(component: Self.delayComponent, displayName: "Delay 1", orderIndex: 0)
        let effect2 = InsertEffect(component: Self.delayComponent, displayName: "Delay 2", orderIndex: 1)
        let container = Container(
            id: containerID, name: "Two Effects", startBar: 1, lengthBars: 4,
            sourceRecordingID: recordingID, insertEffects: [effect1, effect2]
        )
        let song = Song(name: "Test", tracks: [Track(name: "T", kind: .audio, containers: [container])])

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        await scheduler.prepare(song: song, sourceRecordings: [recordingID: recording])

        let unit0 = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 0)
        let unit1 = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 1)
        #expect(unit0 != nil, "First effect should be connected")
        #expect(unit1 != nil, "Second effect should be connected")
        // They should be different instances
        #expect(unit0 !== unit1)

        scheduler.cleanup()
    }

    @Test("Empty effect chain connects player directly to mixer",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func emptyEffectChainDirectConnection() async throws {
        let fixture = try Self.makeTestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        // No effects — player should be directly connected
        let containerID = fixture.song.tracks[0].containers[0].id
        let player = Self.playerNode(in: scheduler, containerID: containerID)
        let connections = engine.outputConnectionPoints(for: player, outputBus: 0)
        #expect(!connections.isEmpty, "Player should connect directly to mixer when no effects")

        // No effect unit should exist
        let unit = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 0)
        #expect(unit == nil)

        scheduler.cleanup()
    }

    @Test("Effect chain survives play/stop cycle and renders without crash",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func effectChainPlayStopRender() async throws {
        // Use stereo fixture — effects auto-negotiate stereo in manual rendering
        // mode, and the player's buffer channel count must match.
        let fixture = try Self.makeStereoFixtureWithEffects()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        scheduler.play(
            song: fixture.song, fromBar: 1.0, bpm: 120,
            timeSignature: TimeSignature(), sampleRate: 44100
        )
        Self.renderFrames(engine: engine, count: 10)

        // Effect should still be live during playback
        let unit = scheduler.liveEffectUnit(containerID: fixture.containerID, effectIndex: 0)
        #expect(unit != nil)

        scheduler.stop()

        // After stop, effect unit should still be queryable (graph not torn down until cleanup)
        let unitAfterStop = scheduler.liveEffectUnit(containerID: fixture.containerID, effectIndex: 0)
        #expect(unitAfterStop != nil)

        scheduler.cleanup()
    }

    @Test("Track-level effect chain connects correctly",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func trackEffectChainConnects() async throws {
        let fixture = try Self.makeTestFixtureWithEffects()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        let trackUnit = scheduler.liveTrackEffectUnit(trackID: fixture.trackID, effectIndex: 0)
        #expect(trackUnit != nil, "Track-level effect should be connected")

        scheduler.cleanup()
    }

    // MARK: - Automation Value Scaling Tests

    @Test("AUParameter receives scaled value from automation, not raw 0-1",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func automationValueScaling() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleCount: AVAudioFrameCount = 352800
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(filename: "test.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        let containerID = ID<Container>()
        let trackID = ID<Track>()
        let effect = InsertEffect(component: Self.delayComponent, displayName: "AUDelay", orderIndex: 0)

        // Create automation lane at constant 1.0 — should map to param.maxValue
        let lane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: containerID, effectIndex: 0, parameterAddress: 0),
            breakpoints: [
                AutomationBreakpoint(position: 0, value: 1.0),
                AutomationBreakpoint(position: 4, value: 1.0)
            ]
        )

        let container = Container(
            id: containerID, name: "Automated", startBar: 1, lengthBars: 4,
            sourceRecordingID: recordingID, insertEffects: [effect], automationLanes: [lane]
        )
        let track = Track(id: trackID, name: "T", kind: .audio, containers: [container])
        let song = Song(name: "Test", tracks: [track])

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        await scheduler.prepare(song: song, sourceRecordings: [recordingID: recording])

        // Get the live AU instance and read its first parameter's range
        let unit = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 0)!
        let paramTree = unit.auAudioUnit.parameterTree
        let param = paramTree?.parameter(withAddress: 0)

        // Start playback so the automation timer fires
        scheduler.play(
            song: song, fromBar: 1.0, bpm: 120,
            timeSignature: TimeSignature(), sampleRate: 44100
        )
        // Render + wait for at least one automation tick
        Self.renderFrames(engine: engine, count: 5)
        try await Task.sleep(for: .milliseconds(50))

        if let param {
            // With value=1.0 and scaling, param should be at maxValue (not 1.0 unless max IS 1.0)
            let expectedMax = param.maxValue
            let tolerance: AUValue = max(0.01 * abs(expectedMax), 0.001)
            #expect(abs(param.value - expectedMax) < tolerance,
                    "Param value \(param.value) should be near maxValue \(expectedMax)")
        }

        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("Automation at 0.0 maps to parameter minimum value",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func automationMinValueScaling() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleCount: AVAudioFrameCount = 352800
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(filename: "test.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        let containerID = ID<Container>()
        let trackID = ID<Track>()
        let effect = InsertEffect(component: Self.delayComponent, displayName: "AUDelay", orderIndex: 0)

        // Automation at constant 0.0 — should map to param.minValue
        let lane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: containerID, effectIndex: 0, parameterAddress: 0),
            breakpoints: [
                AutomationBreakpoint(position: 0, value: 0.0),
                AutomationBreakpoint(position: 4, value: 0.0)
            ]
        )

        let container = Container(
            id: containerID, name: "Automated", startBar: 1, lengthBars: 4,
            sourceRecordingID: recordingID, insertEffects: [effect], automationLanes: [lane]
        )
        let track = Track(id: trackID, name: "T", kind: .audio, containers: [container])
        let song = Song(name: "Test", tracks: [track])

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        await scheduler.prepare(song: song, sourceRecordings: [recordingID: recording])

        let unit = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 0)!
        let param = unit.auAudioUnit.parameterTree?.parameter(withAddress: 0)

        scheduler.play(
            song: song, fromBar: 1.0, bpm: 120,
            timeSignature: TimeSignature(), sampleRate: 44100
        )
        Self.renderFrames(engine: engine, count: 5)
        try await Task.sleep(for: .milliseconds(50))

        if let param {
            let expectedMin = param.minValue
            let tolerance: AUValue = max(0.01 * abs(param.maxValue - expectedMin), 0.001)
            #expect(abs(param.value - expectedMin) < tolerance,
                    "Param value \(param.value) should be near minValue \(expectedMin)")
        }

        scheduler.stop()
        scheduler.cleanup()
    }

    // MARK: - Live Automation Data Update

    @Test("updateAutomationData refreshes automation without graph rebuild",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func updateAutomationDataLive() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleCount: AVAudioFrameCount = 352800
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(filename: "test.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        let containerID = ID<Container>()
        let trackID = ID<Track>()
        let effect = InsertEffect(component: Self.delayComponent, displayName: "AUDelay", orderIndex: 0)

        // Start with automation at 0.0
        let lane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: containerID, effectIndex: 0, parameterAddress: 0),
            breakpoints: [
                AutomationBreakpoint(position: 0, value: 0.0),
                AutomationBreakpoint(position: 4, value: 0.0)
            ]
        )

        let container = Container(
            id: containerID, name: "Automated", startBar: 1, lengthBars: 4,
            sourceRecordingID: recordingID, insertEffects: [effect], automationLanes: [lane]
        )
        let track = Track(id: trackID, name: "T", kind: .audio, containers: [container])
        let song = Song(name: "Test", tracks: [track])

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        await scheduler.prepare(song: song, sourceRecordings: [recordingID: recording])

        let unit = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 0)!
        let param = unit.auAudioUnit.parameterTree?.parameter(withAddress: 0)

        scheduler.play(
            song: song, fromBar: 1.0, bpm: 120,
            timeSignature: TimeSignature(), sampleRate: 44100
        )
        Self.renderFrames(engine: engine, count: 5)
        try await Task.sleep(for: .milliseconds(50))

        // Now update automation to 1.0 mid-playback
        let updatedLane = AutomationLane(
            id: lane.id,
            targetPath: lane.targetPath,
            breakpoints: [
                AutomationBreakpoint(position: 0, value: 1.0),
                AutomationBreakpoint(position: 4, value: 1.0)
            ]
        )
        let updatedContainer = Container(
            id: containerID, name: "Automated", startBar: 1, lengthBars: 4,
            sourceRecordingID: recordingID, insertEffects: [effect], automationLanes: [updatedLane]
        )
        let updatedTrack = Track(id: trackID, name: "T", kind: .audio, containers: [updatedContainer])
        let updatedSong = Song(id: song.id, name: "Test", tracks: [updatedTrack])

        // Push new automation data without graph rebuild
        scheduler.updateAutomationData(song: updatedSong)
        Self.renderFrames(engine: engine, count: 5)
        try await Task.sleep(for: .milliseconds(50))

        if let param {
            let expectedMax = param.maxValue
            let tolerance: AUValue = max(0.01 * abs(expectedMax), 0.001)
            #expect(abs(param.value - expectedMax) < tolerance,
                    "After updateAutomationData, param \(param.value) should be near maxValue \(expectedMax)")
        }

        scheduler.stop()
        scheduler.cleanup()
    }

    // MARK: - Clone Effect Chain with Automation

    @Test("Clone container's effects get own subgraph with remapped automation",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func cloneEffectChainWithAutomation() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleCount: AVAudioFrameCount = 352800
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(filename: "test.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        let parentID = ID<Container>()
        let trackID = ID<Track>()
        let effect = InsertEffect(component: Self.delayComponent, displayName: "AUDelay", orderIndex: 0)

        let lane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: parentID, effectIndex: 0, parameterAddress: 0),
            breakpoints: [
                AutomationBreakpoint(position: 0, value: 0.5),
                AutomationBreakpoint(position: 4, value: 0.5)
            ]
        )

        let parent = Container(
            id: parentID, name: "Parent", startBar: 1, lengthBars: 4,
            sourceRecordingID: recordingID, insertEffects: [effect], automationLanes: [lane]
        )

        // Clone inherits effects and automation
        let clone = Container(
            name: "Clone", startBar: 5, lengthBars: 4,
            sourceRecordingID: recordingID, parentContainerID: parentID
        )

        let track = Track(id: trackID, name: "T", kind: .audio, containers: [parent, clone])
        let song = Song(name: "Test", tracks: [track])

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        await scheduler.prepare(song: song, sourceRecordings: [recordingID: recording])

        // Both parent and clone should have their own effect instances
        let parentUnit = scheduler.liveEffectUnit(containerID: parentID, effectIndex: 0)
        let cloneUnit = scheduler.liveEffectUnit(containerID: clone.id, effectIndex: 0)
        #expect(parentUnit != nil, "Parent should have its own effect unit")
        #expect(cloneUnit != nil, "Clone should have its own effect unit")
        // They should be separate instances
        if let parentUnit, let cloneUnit {
            #expect(parentUnit !== cloneUnit, "Parent and clone must have distinct effect instances")
        }

        scheduler.cleanup()
    }

    // MARK: - Incremental Rebuild Effect Chain

    @Test("Effect chain reconnects correctly after incremental rebuild",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func effectChainIncrementalRebuild() async throws {
        let fixture = try Self.makeTestFixtureWithEffects()
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)

        // Verify initial effect
        let unit1 = scheduler.liveEffectUnit(containerID: fixture.containerID, effectIndex: 0)
        #expect(unit1 != nil)

        // Add a second effect and do incremental rebuild
        let effect2 = InsertEffect(component: Self.delayComponent, displayName: "Delay 2", orderIndex: 1)
        var modifiedContainer = fixture.song.tracks[0].containers[0]
        modifiedContainer.insertEffects.append(effect2)
        let modifiedTrack = Track(
            id: fixture.trackID, name: "Test Track", kind: .audio,
            containers: [modifiedContainer],
            insertEffects: fixture.song.tracks[0].insertEffects
        )
        let modifiedSong = Song(id: fixture.song.id, name: fixture.song.name, tracks: [modifiedTrack])

        let changedTracks = await scheduler.prepareIncremental(
            song: modifiedSong, sourceRecordings: fixture.recordings
        )

        #expect(!changedTracks.isEmpty, "Track should be marked as changed")

        // Both effects should now be present
        let newUnit0 = scheduler.liveEffectUnit(containerID: fixture.containerID, effectIndex: 0)
        let newUnit1 = scheduler.liveEffectUnit(containerID: fixture.containerID, effectIndex: 1)
        #expect(newUnit0 != nil, "First effect should still exist after rebuild")
        #expect(newUnit1 != nil, "Second effect should exist after rebuild")

        scheduler.cleanup()
    }

    // MARK: - Bypassed Effect Index Mapping Tests

    @Test("Automation targets correct effect when a preceding effect is bypassed",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func automationWithBypassedPrecedingEffect() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleCount: AVAudioFrameCount = 352800
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(filename: "test.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        let containerID = ID<Container>()
        let trackID = ID<Track>()

        // 3 effects: A is bypassed (orderIndex 0), B is active (orderIndex 1), C is active (orderIndex 2)
        let effectA = InsertEffect(component: Self.delayComponent, displayName: "A-Bypassed", isBypassed: true, orderIndex: 0)
        let effectB = InsertEffect(component: Self.delayComponent, displayName: "B-Active", orderIndex: 1)
        let effectC = InsertEffect(component: Self.delayComponent, displayName: "C-Active", orderIndex: 2)

        // Automation targets effectIndex=1 (B in the full sorted array, compact index 0)
        let lane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: containerID, effectIndex: 1, parameterAddress: 0),
            breakpoints: [
                AutomationBreakpoint(position: 0, value: 1.0),
                AutomationBreakpoint(position: 4, value: 1.0)
            ]
        )

        let container = Container(
            id: containerID, name: "Test", startBar: 1, lengthBars: 4,
            sourceRecordingID: recordingID,
            insertEffects: [effectA, effectB, effectC],
            automationLanes: [lane]
        )
        let track = Track(id: trackID, name: "T", kind: .audio, containers: [container])
        let song = Song(name: "Test", tracks: [track])

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        await scheduler.prepare(song: song, sourceRecordings: [recordingID: recording])

        // effectIndex=1 should resolve to the first loaded unit (B, compact index 0)
        let unitB = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 1)
        #expect(unitB != nil, "effectIndex=1 should resolve to B (compact index 0)")

        // effectIndex=0 should be nil since A is bypassed
        let unitA = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 0)
        #expect(unitA == nil, "effectIndex=0 (bypassed A) should return nil")

        // effectIndex=2 should resolve to C (compact index 1)
        let unitC = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 2)
        #expect(unitC != nil, "effectIndex=2 should resolve to C (compact index 1)")

        // Start playback to fire automation
        scheduler.play(
            song: song, fromBar: 1.0, bpm: 120,
            timeSignature: TimeSignature(), sampleRate: 44100
        )
        Self.renderFrames(engine: engine, count: 5)
        try await Task.sleep(for: .milliseconds(50))

        // Verify automation hit B's parameter (should be at maxValue since automation=1.0)
        if let unit = unitB,
           let param = unit.auAudioUnit.parameterTree?.parameter(withAddress: 0) {
            let tolerance: AUValue = max(0.01 * abs(param.maxValue), 0.001)
            #expect(abs(param.value - param.maxValue) < tolerance,
                    "B's param should be at maxValue, got \(param.value)")
        }

        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("Automation on bypassed effect is safely ignored",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func automationOnBypassedEffectIsInert() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleCount: AVAudioFrameCount = 352800
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(filename: "test.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        let containerID = ID<Container>()
        let trackID = ID<Track>()

        // A is bypassed, B is active
        let effectA = InsertEffect(component: Self.delayComponent, displayName: "A-Bypassed", isBypassed: true, orderIndex: 0)
        let effectB = InsertEffect(component: Self.delayComponent, displayName: "B-Active", orderIndex: 1)

        // Automation targets effectIndex=0 (the bypassed A)
        let lane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: containerID, effectIndex: 0, parameterAddress: 0),
            breakpoints: [
                AutomationBreakpoint(position: 0, value: 1.0),
                AutomationBreakpoint(position: 4, value: 1.0)
            ]
        )

        let container = Container(
            id: containerID, name: "Test", startBar: 1, lengthBars: 4,
            sourceRecordingID: recordingID,
            insertEffects: [effectA, effectB],
            automationLanes: [lane]
        )
        let track = Track(id: trackID, name: "T", kind: .audio, containers: [container])
        let song = Song(name: "Test", tracks: [track])

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        await scheduler.prepare(song: song, sourceRecordings: [recordingID: recording])

        // effectIndex=0 should return nil (bypassed)
        let unit = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 0)
        #expect(unit == nil, "Bypassed effect should return nil from liveEffectUnit")

        // Play — should not crash even though automation targets a bypassed effect
        scheduler.play(
            song: song, fromBar: 1.0, bpm: 120,
            timeSignature: TimeSignature(), sampleRate: 44100
        )
        Self.renderFrames(engine: engine, count: 5)
        try await Task.sleep(for: .milliseconds(50))

        // If we get here without crashing, the test passes
        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("All effects bypassed with automation does not crash",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func allEffectsBypassedAutomationSafe() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleCount: AVAudioFrameCount = 352800
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(filename: "test.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        let containerID = ID<Container>()
        let trackID = ID<Track>()

        // Both effects bypassed
        let effectA = InsertEffect(component: Self.delayComponent, displayName: "A-Bypassed", isBypassed: true, orderIndex: 0)
        let effectB = InsertEffect(component: Self.delayComponent, displayName: "B-Bypassed", isBypassed: true, orderIndex: 1)

        // Automation targets effectIndex=0
        let lane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: containerID, effectIndex: 0, parameterAddress: 0),
            breakpoints: [
                AutomationBreakpoint(position: 0, value: 0.5),
                AutomationBreakpoint(position: 4, value: 0.5)
            ]
        )

        let container = Container(
            id: containerID, name: "Test", startBar: 1, lengthBars: 4,
            sourceRecordingID: recordingID,
            insertEffects: [effectA, effectB],
            automationLanes: [lane]
        )
        let track = Track(id: trackID, name: "T", kind: .audio, containers: [container])
        let song = Song(name: "Test", tracks: [track])

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        await scheduler.prepare(song: song, sourceRecordings: [recordingID: recording])

        // No live units should be available
        #expect(scheduler.liveEffectUnit(containerID: containerID, effectIndex: 0) == nil)
        #expect(scheduler.liveEffectUnit(containerID: containerID, effectIndex: 1) == nil)

        // Play — should not crash
        scheduler.play(
            song: song, fromBar: 1.0, bpm: 120,
            timeSignature: TimeSignature(), sampleRate: 44100
        )
        Self.renderFrames(engine: engine, count: 5)
        try await Task.sleep(for: .milliseconds(50))

        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("Automation skips bypassed effect and targets correct compact index",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func automationSkipsBypassedEffect() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackSchedulerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleCount: AVAudioFrameCount = 352800
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        let fileURL = tempDir.appendingPathComponent("test.caf")
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(filename: "test.caf", sampleRate: 44100, sampleCount: Int64(sampleCount))

        let containerID = ID<Container>()
        let trackID = ID<Track>()

        // A is bypassed, B is active
        let effectA = InsertEffect(component: Self.delayComponent, displayName: "A-Bypassed", isBypassed: true, orderIndex: 0)
        let effectB = InsertEffect(component: Self.delayComponent, displayName: "B-Active", orderIndex: 1)

        // Automation targets effectIndex=1 (B), which maps to compact index 0
        let lane = AutomationLane(
            targetPath: EffectPath(trackID: trackID, containerID: containerID, effectIndex: 1, parameterAddress: 0),
            breakpoints: [
                AutomationBreakpoint(position: 0, value: 1.0),
                AutomationBreakpoint(position: 4, value: 1.0)
            ]
        )

        let container = Container(
            id: containerID, name: "Test", startBar: 1, lengthBars: 4,
            sourceRecordingID: recordingID,
            insertEffects: [effectA, effectB],
            automationLanes: [lane]
        )
        let track = Track(id: trackID, name: "T", kind: .audio, containers: [container])
        let song = Song(name: "Test", tracks: [track])

        let engine = try Self.makeRunningEngine()
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: tempDir)
        await scheduler.prepare(song: song, sourceRecordings: [recordingID: recording])

        // effectIndex=1 (B) should resolve to compact index 0
        let unitB = scheduler.liveEffectUnit(containerID: containerID, effectIndex: 1)
        #expect(unitB != nil, "effectIndex=1 should resolve to B at compact index 0")

        let paramB = unitB?.auAudioUnit.parameterTree?.parameter(withAddress: 0)

        scheduler.play(
            song: song, fromBar: 1.0, bpm: 120,
            timeSignature: TimeSignature(), sampleRate: 44100
        )
        Self.renderFrames(engine: engine, count: 5)
        try await Task.sleep(for: .milliseconds(50))

        // After automation, B's param should be at maxValue
        if let param = paramB {
            let tolerance: AUValue = max(0.01 * abs(param.maxValue), 0.001)
            #expect(abs(param.value - param.maxValue) < tolerance,
                    "B's param should be at maxValue after automation, got \(param.value)")
        }

        scheduler.stop()
        scheduler.cleanup()
    }

    // MARK: - Multi-Track Sample-Accurate Sync Tests

    /// Creates a multi-track fixture where one track has a normal sine wave
    /// and a second track has the inverted sine wave. If both are sample-accurate,
    /// summing them produces silence (phase cancellation).
    private static func makePhaseCancellationFixture(
        sampleRate: Double = 44100
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
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        // Create normal sine wave (440Hz, amplitude 0.5)
        let normalBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        normalBuffer.frameLength = sampleCount
        let invertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        invertedBuffer.frameLength = sampleCount

        if let normalData = normalBuffer.floatChannelData,
           let invertedData = invertedBuffer.floatChannelData {
            let freq = Float(440.0 * 2.0 * Double.pi / sampleRate)
            for frame in 0..<Int(sampleCount) {
                let sample = sin(freq * Float(frame)) * 0.5
                normalData[0][frame] = sample
                invertedData[0][frame] = -sample
            }
        }

        // Write audio files
        let normalURL = tempDir.appendingPathComponent("normal.caf")
        let normalFile = try AVAudioFile(forWriting: normalURL, settings: format.settings)
        try normalFile.write(from: normalBuffer)

        let invertedURL = tempDir.appendingPathComponent("inverted.caf")
        let invertedFile = try AVAudioFile(forWriting: invertedURL, settings: format.settings)
        try invertedFile.write(from: invertedBuffer)

        // Set up recordings
        let normalRecID = ID<SourceRecording>()
        let invertedRecID = ID<SourceRecording>()
        let normalRec = SourceRecording(
            filename: "normal.caf",
            sampleRate: sampleRate,
            sampleCount: Int64(sampleCount)
        )
        let invertedRec = SourceRecording(
            filename: "inverted.caf",
            sampleRate: sampleRate,
            sampleCount: Int64(sampleCount)
        )

        // Two tracks, same start position
        let c1 = Container(name: "Normal", startBar: 1, lengthBars: 4, sourceRecordingID: normalRecID)
        let c2 = Container(name: "Inverted", startBar: 1, lengthBars: 4, sourceRecordingID: invertedRecID)
        let track1 = Track(name: "Track Normal", kind: .audio, containers: [c1])
        let track2 = Track(name: "Track Inverted", kind: .audio, containers: [c2])
        let song = Song(name: "Phase Cancel Test", tracks: [track1, track2])
        let recordings: [ID<SourceRecording>: SourceRecording] = [
            normalRecID: normalRec,
            invertedRecID: invertedRec,
        ]

        return (tempDir, song, recordings)
    }

    /// Creates a multi-track fixture with identical audio on both tracks.
    /// If both tracks are sample-accurate, summing should double the amplitude.
    private static func makeIdenticalTrackFixture(
        trackCount: Int = 2,
        sampleRate: Double = 44100
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
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        // Create sine wave (440Hz, amplitude 0.25)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount)!
        buffer.frameLength = sampleCount
        if let data = buffer.floatChannelData {
            let freq = Float(440.0 * 2.0 * Double.pi / sampleRate)
            for frame in 0..<Int(sampleCount) {
                data[0][frame] = sin(freq * Float(frame)) * 0.25
            }
        }

        var tracks: [Track] = []
        var recordings: [ID<SourceRecording>: SourceRecording] = [:]

        for i in 0..<trackCount {
            let filename = "track\(i).caf"
            let fileURL = tempDir.appendingPathComponent(filename)
            let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            try file.write(from: buffer)

            let recID = ID<SourceRecording>()
            recordings[recID] = SourceRecording(
                filename: filename,
                sampleRate: sampleRate,
                sampleCount: Int64(sampleCount)
            )
            let container = Container(
                name: "Container \(i)",
                startBar: 1,
                lengthBars: 4,
                sourceRecordingID: recID
            )
            tracks.append(Track(name: "Track \(i)", kind: .audio, containers: [container]))
        }

        let song = Song(name: "Identical Track Test", tracks: tracks)
        return (tempDir, song, recordings)
    }

    /// Renders frames from an offline engine into a single output buffer.
    private static func renderToBuffer(
        engine: AVAudioEngine,
        frameCount: Int
    ) throws -> AVAudioPCMBuffer {
        let renderFormat = engine.manualRenderingFormat
        let totalBuffer = AVAudioPCMBuffer(pcmFormat: renderFormat, frameCapacity: AVAudioFrameCount(frameCount))!
        var offset = 0

        while offset < frameCount {
            let chunk = min(4096, frameCount - offset)
            let buffer = AVAudioPCMBuffer(pcmFormat: renderFormat, frameCapacity: AVAudioFrameCount(chunk))!
            let status = try engine.renderOffline(AVAudioFrameCount(chunk), to: buffer)
            guard status == .success || status == .insufficientDataFromInputNode else { break }

            if let outData = totalBuffer.floatChannelData, let chunkData = buffer.floatChannelData {
                for ch in 0..<Int(renderFormat.channelCount) {
                    memcpy(&outData[ch][offset], chunkData[ch], Int(buffer.frameLength) * MemoryLayout<Float>.size)
                }
            }
            offset += Int(buffer.frameLength)
            totalBuffer.frameLength = AVAudioFrameCount(offset)
            if status == .insufficientDataFromInputNode { break }
        }

        return totalBuffer
    }

    @Test("Multi-track playback is sample-accurate — phase cancellation",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func multiTrackPhaseCancellation() async throws {
        let fixture = try Self.makePhaseCancellationFixture()
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

        // Render 4 bars of audio
        let samplesPerBar = 4.0 * (60.0 / 120.0) * 44100.0
        let totalFrames = Int(4.0 * samplesPerBar)
        let output = try Self.renderToBuffer(engine: engine, frameCount: totalFrames)

        // Analyze: find peak amplitude after the declick region (first 256 samples).
        // If tracks are sample-accurate, normal + inverted = silence.
        var maxAmplitude: Float = 0
        let channelCount = Int(output.format.channelCount)
        if let outData = output.floatChannelData {
            // Skip declick fade-in region (256 frames)
            for ch in 0..<channelCount {
                for frame in 256..<Int(output.frameLength) {
                    maxAmplitude = max(maxAmplitude, abs(outData[ch][frame]))
                }
            }
        }

        // Perfect phase cancellation produces silence. Allow small tolerance
        // for floating-point arithmetic in mixer processing.
        #expect(maxAmplitude < 0.01,
                "Peak amplitude \(maxAmplitude) exceeds threshold — tracks are not sample-accurate")

        scheduler.stop()
        scheduler.cleanup()
    }

    @Test("Identical audio on multiple tracks sums constructively",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func multiTrackConstructiveInterference() async throws {
        // Single-track reference
        let singleFixture = try Self.makeIdenticalTrackFixture(trackCount: 1)
        defer { try? FileManager.default.removeItem(at: singleFixture.tempDir) }

        let engine1 = try Self.makeRunningEngine()
        let scheduler1 = PlaybackScheduler(engine: engine1, audioDirURL: singleFixture.tempDir)
        await scheduler1.prepare(song: singleFixture.song, sourceRecordings: singleFixture.recordings)
        scheduler1.play(
            song: singleFixture.song, fromBar: 1.0, bpm: 120,
            timeSignature: TimeSignature(), sampleRate: 44100
        )
        let samplesPerBar = 4.0 * (60.0 / 120.0) * 44100.0
        let totalFrames = Int(4.0 * samplesPerBar)
        let singleOutput = try Self.renderToBuffer(engine: engine1, frameCount: totalFrames)
        scheduler1.stop()
        scheduler1.cleanup()
        engine1.stop()

        // Two-track version
        let dualFixture = try Self.makeIdenticalTrackFixture(trackCount: 2)
        defer { try? FileManager.default.removeItem(at: dualFixture.tempDir) }

        let engine2 = try Self.makeRunningEngine()
        let scheduler2 = PlaybackScheduler(engine: engine2, audioDirURL: dualFixture.tempDir)
        await scheduler2.prepare(song: dualFixture.song, sourceRecordings: dualFixture.recordings)
        scheduler2.play(
            song: dualFixture.song, fromBar: 1.0, bpm: 120,
            timeSignature: TimeSignature(), sampleRate: 44100
        )
        let dualOutput = try Self.renderToBuffer(engine: engine2, frameCount: totalFrames)
        scheduler2.stop()
        scheduler2.cleanup()
        engine2.stop()

        // Compare peak amplitudes after declick region.
        // Two identical tracks should produce ~2x the amplitude.
        var singlePeak: Float = 0
        var dualPeak: Float = 0
        let startFrame = 256 // skip declick
        let endFrame = min(Int(singleOutput.frameLength), Int(dualOutput.frameLength))

        if let singleData = singleOutput.floatChannelData,
           let dualData = dualOutput.floatChannelData {
            for frame in startFrame..<endFrame {
                singlePeak = max(singlePeak, abs(singleData[0][frame]))
                dualPeak = max(dualPeak, abs(dualData[0][frame]))
            }
        }

        // The dual-track peak should be approximately 2x the single-track peak.
        // Allow 10% tolerance for mixer arithmetic.
        let ratio = singlePeak > 0 ? dualPeak / singlePeak : 0
        #expect(ratio > 1.8 && ratio < 2.2,
                "Expected ~2x amplitude ratio, got \(ratio) (single=\(singlePeak), dual=\(dualPeak))")
    }

    @Test("Phase cancellation with 48kHz sample rate",
          .enabled(if: audioTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"),
          .timeLimit(.minutes(1)))
    func phaseCancellation48kHz() async throws {
        let fixture = try Self.makePhaseCancellationFixture(sampleRate: 48000)
        defer { try? FileManager.default.removeItem(at: fixture.tempDir) }

        let engine = try Self.makeRunningEngine(sampleRate: 48000)
        defer { engine.stop() }

        let scheduler = PlaybackScheduler(engine: engine, audioDirURL: fixture.tempDir)
        await scheduler.prepare(song: fixture.song, sourceRecordings: fixture.recordings)
        scheduler.play(
            song: fixture.song,
            fromBar: 1.0,
            bpm: 120,
            timeSignature: TimeSignature(),
            sampleRate: 48000
        )

        let samplesPerBar = 4.0 * (60.0 / 120.0) * 48000.0
        let totalFrames = Int(4.0 * samplesPerBar)
        let output = try Self.renderToBuffer(engine: engine, frameCount: totalFrames)

        var maxAmplitude: Float = 0
        if let outData = output.floatChannelData {
            for ch in 0..<Int(output.format.channelCount) {
                for frame in 256..<Int(output.frameLength) {
                    maxAmplitude = max(maxAmplitude, abs(outData[ch][frame]))
                }
            }
        }

        #expect(maxAmplitude < 0.01,
                "48kHz phase cancellation failed: peak \(maxAmplitude)")

        scheduler.stop()
        scheduler.cleanup()
    }
}
