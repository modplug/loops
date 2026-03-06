import Foundation
import AVFoundation
import LoopsCore

public struct LowLatencyModePolicy: Sendable, Equatable {
    public var enabled: Bool
    public var preferredMonitoringMode: RecordingMonitoringMode
    public var highLatencyThresholdSeconds: Double

    public init(
        enabled: Bool = true,
        preferredMonitoringMode: RecordingMonitoringMode = .splitFastMonitor,
        highLatencyThresholdSeconds: Double = 0.012
    ) {
        self.enabled = enabled
        self.preferredMonitoringMode = preferredMonitoringMode
        self.highLatencyThresholdSeconds = highLatencyThresholdSeconds
    }
}

public struct MonitorPathDescriptor: Sendable, Equatable {
    public let trackID: ID<Track>
    public let mode: RecordingMonitoringMode
    public let usesFastPath: Bool
    public let insertedEffectCount: Int
    public let estimatedLatencySeconds: Double

    public init(
        trackID: ID<Track>,
        mode: RecordingMonitoringMode,
        usesFastPath: Bool,
        insertedEffectCount: Int,
        estimatedLatencySeconds: Double
    ) {
        self.trackID = trackID
        self.mode = mode
        self.usesFastPath = usesFastPath
        self.insertedEffectCount = insertedEffectCount
        self.estimatedLatencySeconds = estimatedLatencySeconds
    }
}

final class LatencyCoordinator {
    struct PlaybackFingerprint: Hashable {
        let containerID: ID<Container>
        let instrumentID: ObjectIdentifier?
        let containerEffectIDs: [ObjectIdentifier]
        let trackEffectIDs: [ObjectIdentifier]
        let masterEffectIDs: [ObjectIdentifier]
    }

    struct MonitorFingerprint: Hashable {
        let trackID: ID<Track>
        let mode: RecordingMonitoringMode
        let policyEnabled: Bool
        let effectComponents: [AudioComponentInfo]
    }

    private let lock = NSLock()
    private var playbackCache: [PlaybackFingerprint: Double] = [:]
    private var monitorCache: [MonitorFingerprint: MonitorPathDescriptor] = [:]

    func playbackLatencySeconds(for fingerprint: PlaybackFingerprint, compute: () -> Double) -> Double {
        lock.lock()
        if let cached = playbackCache[fingerprint] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let latency = compute()

        lock.lock()
        playbackCache[fingerprint] = latency
        lock.unlock()
        return latency
    }

    func monitorDescriptor(
        for fingerprint: MonitorFingerprint,
        policy: LowLatencyModePolicy,
        computeExactLatency: () -> Double
    ) -> MonitorPathDescriptor {
        lock.lock()
        if let cached = monitorCache[fingerprint] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let exactLatency = max(0, computeExactLatency())
        let requestedFastPath = policy.enabled && fingerprint.mode == .splitFastMonitor
        let usesFastPath = requestedFastPath && exactLatency > policy.highLatencyThresholdSeconds
        let descriptor = MonitorPathDescriptor(
            trackID: fingerprint.trackID,
            mode: fingerprint.mode,
            usesFastPath: usesFastPath,
            insertedEffectCount: usesFastPath ? 0 : fingerprint.effectComponents.count,
            estimatedLatencySeconds: usesFastPath ? 0 : exactLatency
        )

        lock.lock()
        monitorCache[fingerprint] = descriptor
        lock.unlock()
        return descriptor
    }

    func updateMonitorDescriptor(_ descriptor: MonitorPathDescriptor, for fingerprint: MonitorFingerprint) {
        lock.lock()
        monitorCache[fingerprint] = descriptor
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        playbackCache.removeAll(keepingCapacity: true)
        monitorCache.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
