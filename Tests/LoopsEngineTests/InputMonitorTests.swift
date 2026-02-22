import Testing
import Foundation
import AVFoundation
@testable import LoopsEngine
@testable import LoopsCore

@Suite("InputMonitor Tests", .serialized)
struct InputMonitorTests {

    @Test("Monitoring auto-disables during container playback")
    func monitoringAutoDisablesDuringPlayback() async {
        let engine = AVAudioEngine()
        let monitor = InputMonitor(engine: engine)
        let trackID = ID<Track>()

        // Enable monitoring (no AU effects, basic routing)
        await monitor.enableMonitoring(
            trackID: trackID,
            insertEffects: [],
            volume: 1.0,
            pan: 0.0
        )
        #expect(monitor.isMonitoring(trackID: trackID))
        #expect(!monitor.isSuppressed(trackID: trackID))

        // Simulate container playback starting on this track
        monitor.suppressMonitoring(trackID: trackID)
        #expect(monitor.isSuppressed(trackID: trackID))
    }

    @Test("Monitoring re-enables after container playback stops")
    func monitoringReEnablesAfterPlaybackStops() async {
        let engine = AVAudioEngine()
        let monitor = InputMonitor(engine: engine)
        let trackID = ID<Track>()

        // Enable monitoring
        await monitor.enableMonitoring(
            trackID: trackID,
            insertEffects: [],
            volume: 0.8,
            pan: 0.0
        )
        #expect(!monitor.isSuppressed(trackID: trackID))

        // Suppress during playback
        monitor.suppressMonitoring(trackID: trackID)
        #expect(monitor.isSuppressed(trackID: trackID))

        // Unsuppress when playback stops
        monitor.unsuppressMonitoring(trackID: trackID)
        #expect(!monitor.isSuppressed(trackID: trackID))
        #expect(monitor.isMonitoring(trackID: trackID))
    }

    @Test("Suppress has no effect on non-monitored track")
    func suppressNonMonitoredTrack() {
        let engine = AVAudioEngine()
        let monitor = InputMonitor(engine: engine)
        let trackID = ID<Track>()

        // Suppressing a track that isn't monitored is a no-op
        monitor.suppressMonitoring(trackID: trackID)
        #expect(!monitor.isMonitoring(trackID: trackID))
        #expect(!monitor.isSuppressed(trackID: trackID))
    }

    @Test("Disable monitoring removes track")
    func disableMonitoringRemovesTrack() async {
        let engine = AVAudioEngine()
        let monitor = InputMonitor(engine: engine)
        let trackID = ID<Track>()

        await monitor.enableMonitoring(
            trackID: trackID,
            insertEffects: [],
            volume: 1.0,
            pan: 0.0
        )
        #expect(monitor.isMonitoring(trackID: trackID))

        monitor.disableMonitoring(trackID: trackID)
        #expect(!monitor.isMonitoring(trackID: trackID))
        #expect(monitor.monitoredTrackIDs.isEmpty)
    }

    @Test("Cleanup removes all monitored tracks")
    func cleanupRemovesAll() async {
        let engine = AVAudioEngine()
        let monitor = InputMonitor(engine: engine)
        let trackA = ID<Track>()
        let trackB = ID<Track>()

        await monitor.enableMonitoring(trackID: trackA, insertEffects: [], volume: 1.0, pan: 0.0)
        await monitor.enableMonitoring(trackID: trackB, insertEffects: [], volume: 0.5, pan: -0.5)
        #expect(monitor.monitoredTrackIDs.count == 2)

        monitor.cleanup()
        #expect(monitor.monitoredTrackIDs.isEmpty)
    }

    // MARK: - Concurrent Stress Tests

    @Test("Concurrent suppress/unsuppress vs enable/disable")
    func concurrentSuppressVsEnableDisable() async {
        let engine = AVAudioEngine()
        let monitor = InputMonitor(engine: engine)
        let trackID = ID<Track>()

        // Seed with valid state
        await monitor.enableMonitoring(trackID: trackID, insertEffects: [], volume: 1.0, pan: 0.0)

        // Background: hammer suppress/unsuppress (reads + writes trackSubgraphs)
        let suppressor = Task.detached(priority: .high) {
            for i in 0..<5000 {
                if i % 2 == 0 {
                    monitor.suppressMonitoring(trackID: trackID)
                } else {
                    monitor.unsuppressMonitoring(trackID: trackID)
                }
            }
        }

        // Foreground: repeatedly enable (clears + rebuilds trackSubgraphs)
        for _ in 0..<100 {
            await monitor.enableMonitoring(trackID: trackID, insertEffects: [], volume: 1.0, pan: 0.0)
        }

        await suppressor.value
        monitor.cleanup()
    }

    @Test("Concurrent cleanup vs suppress")
    func concurrentCleanupVsSuppress() async {
        let engine = AVAudioEngine()
        let monitor = InputMonitor(engine: engine)
        let trackIDs = (0..<5).map { _ in ID<Track>() }

        // Seed with valid state
        for id in trackIDs {
            await monitor.enableMonitoring(trackID: id, insertEffects: [], volume: 1.0, pan: 0.0)
        }

        // Background: hammer suppress/unsuppress on all tracks
        let suppressor = Task.detached(priority: .high) {
            for i in 0..<5000 {
                let id = trackIDs[i % trackIDs.count]
                if i % 2 == 0 {
                    monitor.suppressMonitoring(trackID: id)
                } else {
                    monitor.unsuppressMonitoring(trackID: id)
                }
            }
        }

        // Foreground: repeatedly cleanup and re-enable
        for _ in 0..<30 {
            monitor.cleanup()
            for id in trackIDs {
                await monitor.enableMonitoring(trackID: id, insertEffects: [], volume: 1.0, pan: 0.0)
            }
        }

        await suppressor.value
        monitor.cleanup()
    }

    @Test("Concurrent disable vs isMonitoring queries")
    func concurrentDisableVsQueries() async {
        let engine = AVAudioEngine()
        let monitor = InputMonitor(engine: engine)
        let trackIDs = (0..<10).map { _ in ID<Track>() }

        for id in trackIDs {
            await monitor.enableMonitoring(trackID: id, insertEffects: [], volume: 1.0, pan: 0.0)
        }

        // Background: hammer query methods (reads trackSubgraphs)
        let reader = Task.detached(priority: .high) {
            for i in 0..<10000 {
                let id = trackIDs[i % trackIDs.count]
                _ = monitor.isMonitoring(trackID: id)
                _ = monitor.isSuppressed(trackID: id)
                _ = monitor.monitoredTrackIDs
            }
        }

        // Foreground: disable and re-enable (writes trackSubgraphs)
        for i in 0..<100 {
            let id = trackIDs[i % trackIDs.count]
            monitor.disableMonitoring(trackID: id)
            await monitor.enableMonitoring(trackID: id, insertEffects: [], volume: 1.0, pan: 0.0)
        }

        await reader.value
        monitor.cleanup()
    }
}
