import Testing
import Foundation
import AVFoundation
@testable import LoopsEngine
@testable import LoopsCore

@Suite("InputMonitor Tests")
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
}
