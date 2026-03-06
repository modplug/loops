import Foundation
import AVFoundation
import LoopsCore

/// Manages per-track input monitoring: routes the audio input node through
/// a track's AU effect chain to the main mixer output so the musician can
/// hear themselves while recording. Automatically suppresses monitoring
/// when containers are playing on a track to avoid doubling.
public final class InputMonitor: @unchecked Sendable {
    private let engine: AVAudioEngine
    private let audioUnitHost: AudioUnitHost
    private let latencyCoordinator = LatencyCoordinator()
    private let lock = NSLock()

    /// Shared mixer that receives audio from the input node and distributes
    /// to per-track monitoring chains. Avoids multiple direct connections
    /// from `engine.inputNode`.
    private let inputDistributor: AVAudioMixerNode

    /// Whether the input distributor is currently attached and connected.
    private var isDistributorConnected: Bool = false

    /// Per-track monitoring subgraph.
    private struct TrackMonitorSubgraph {
        let feedMixer: AVAudioMixerNode
        let monitorMixer: AVAudioMixerNode
        let effectUnits: [AVAudioUnit]
        let descriptor: MonitorPathDescriptor
        var isSuppressed: Bool
        var volume: Float
        var pan: Float
    }

    private var trackSubgraphs: [ID<Track>: TrackMonitorSubgraph] = [:]

    public init(engine: AVAudioEngine) {
        self.engine = engine
        self.audioUnitHost = AudioUnitHost(engine: engine)
        self.inputDistributor = AVAudioMixerNode()
    }

    // MARK: - State Queries

    /// IDs of all tracks currently being monitored.
    public var monitoredTrackIDs: Set<ID<Track>> {
        lock.withLock {
            Set(trackSubgraphs.keys)
        }
    }

    /// Whether a given track is actively being monitored.
    public func isMonitoring(trackID: ID<Track>) -> Bool {
        lock.withLock {
            trackSubgraphs[trackID] != nil
        }
    }

    /// Whether a given track's monitoring is suppressed due to container playback.
    public func isSuppressed(trackID: ID<Track>) -> Bool {
        lock.withLock {
            trackSubgraphs[trackID]?.isSuppressed ?? false
        }
    }

    public func monitorPathDescriptor(trackID: ID<Track>) -> MonitorPathDescriptor? {
        lock.withLock {
            trackSubgraphs[trackID]?.descriptor
        }
    }

    // MARK: - Enable / Disable

    /// Enables input monitoring for a track, routing through its AU effect chain.
    /// Audio passes through immediately (dry); effects are hot-swapped in once loaded.
    public func enableMonitoring(
        trackID: ID<Track>,
        insertEffects: [InsertEffect],
        volume: Float,
        pan: Float,
        monitoringMode: RecordingMonitoringMode = .splitFastMonitor,
        lowLatencyPolicy: LowLatencyModePolicy = LowLatencyModePolicy()
    ) async -> MonitorPathDescriptor {
        // Disable first if already monitoring this track
        disableMonitoring(trackID: trackID)

        let feedMixer = AVAudioMixerNode()
        let monitorMixer = AVAudioMixerNode()
        engine.attach(feedMixer)
        engine.attach(monitorMixer)
        feedMixer.volume = 1.0
        monitorMixer.volume = volume
        monitorMixer.pan = pan

        // Ensure the shared input distributor is connected
        connectDistributorIfNeeded()

        // Connect dry path immediately so monitoring is instant
        engine.connect(inputDistributor, to: feedMixer, format: nil)
        engine.connect(feedMixer, to: monitorMixer, format: nil)
        engine.connect(monitorMixer, to: engine.mainMixerNode, format: nil)

        let sortedActiveEffects = insertEffects
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .filter { !$0.isBypassed }
        let fingerprint = LatencyCoordinator.MonitorFingerprint(
            trackID: trackID,
            mode: monitoringMode,
            policyEnabled: lowLatencyPolicy.enabled,
            effectComponents: sortedActiveEffects.map(\.component)
        )
        let descriptor = latencyCoordinator.monitorDescriptor(
            for: fingerprint,
            policy: lowLatencyPolicy
        ) {
            // The serialized component model does not expose live AU latency.
            // Use a conservative per-plugin heuristic until units are loaded.
            Double(sortedActiveEffects.count) * 0.004
        }

        lock.withLock {
            trackSubgraphs[trackID] = TrackMonitorSubgraph(
                feedMixer: feedMixer,
                monitorMixer: monitorMixer,
                effectUnits: [],
                descriptor: descriptor,
                isSuppressed: false,
                volume: volume,
                pan: pan
            )
        }

        // Load AU effects in the background, then hot-swap the chain
        let activeEffects = descriptor.usesFastPath ? [] : sortedActiveEffects
        guard !activeEffects.isEmpty else { return descriptor }

        var effectUnits: [AVAudioUnit] = []
        for effect in activeEffects {
            if let unit = try? await audioUnitHost.loadAudioUnit(component: effect.component) {
                engine.attach(unit)
                if let presetData = effect.presetData {
                    try? audioUnitHost.restoreState(audioUnit: unit, data: presetData)
                }
                effectUnits.append(unit)
            }
        }

        // Bail if monitoring was disabled while loading
        let stillMonitoring = lock.withLock {
            trackSubgraphs[trackID] != nil
        }

        guard stillMonitoring, !effectUnits.isEmpty else {
            for unit in effectUnits {
                engine.disconnectNodeOutput(unit)
                engine.detach(unit)
            }
            return descriptor
        }

        // Hot-swap this track only: replace the per-track dry feed with the effect chain.
        engine.disconnectNodeOutput(feedMixer)
        engine.connect(feedMixer, to: effectUnits[0], format: nil)
        for i in 0..<(effectUnits.count - 1) {
            engine.connect(effectUnits[i], to: effectUnits[i + 1], format: nil)
        }
        engine.connect(effectUnits[effectUnits.count - 1], to: monitorMixer, format: nil)

        let exactLatencySeconds = effectUnits.reduce(into: 0.0) { partial, unit in
            partial += unitLatencySeconds(unit)
        }
        let updatedDescriptor = MonitorPathDescriptor(
            trackID: descriptor.trackID,
            mode: descriptor.mode,
            usesFastPath: descriptor.usesFastPath,
            insertedEffectCount: effectUnits.count,
            estimatedLatencySeconds: descriptor.usesFastPath ? 0 : exactLatencySeconds
        )

        latencyCoordinator.updateMonitorDescriptor(updatedDescriptor, for: fingerprint)
        lock.withLock {
            trackSubgraphs[trackID] = TrackMonitorSubgraph(
                feedMixer: feedMixer,
                monitorMixer: monitorMixer,
                effectUnits: effectUnits,
                descriptor: updatedDescriptor,
                isSuppressed: false,
                volume: volume,
                pan: pan
            )
        }
        return updatedDescriptor
    }

    /// Disables input monitoring for a track, tearing down its audio subgraph.
    public func disableMonitoring(trackID: ID<Track>) {
        let subgraph = lock.withLock {
            trackSubgraphs.removeValue(forKey: trackID)
        }
        guard let subgraph else { return }
        teardownSubgraph(subgraph)
        disconnectDistributorIfUnused()
    }

    // MARK: - Playback Suppression

    /// Suppresses monitoring on a track (sets volume to 0) to avoid doubling
    /// when containers are playing on that track.
    public func suppressMonitoring(trackID: ID<Track>) {
        lock.withLock {
            guard var subgraph = trackSubgraphs[trackID], !subgraph.isSuppressed else {
                return
            }
            subgraph.isSuppressed = true
            subgraph.monitorMixer.volume = 0
            trackSubgraphs[trackID] = subgraph
        }
    }

    /// Re-enables monitoring on a track after container playback stops.
    public func unsuppressMonitoring(trackID: ID<Track>) {
        lock.withLock {
            guard var subgraph = trackSubgraphs[trackID], subgraph.isSuppressed else {
                return
            }
            subgraph.isSuppressed = false
            subgraph.monitorMixer.volume = subgraph.volume
            trackSubgraphs[trackID] = subgraph
        }
    }

    // MARK: - Cleanup

    /// Tears down all monitoring subgraphs.
    public func cleanup() {
        let subgraphs = lock.withLock { () -> [ID<Track>: TrackMonitorSubgraph] in
            let current = trackSubgraphs
            trackSubgraphs.removeAll()
            return current
        }
        for (_, subgraph) in subgraphs {
            teardownSubgraph(subgraph)
        }
        disconnectDistributorIfUnused()
    }

    // MARK: - Private

    private func connectDistributorIfNeeded() {
        let shouldConnect = lock.withLock { () -> Bool in
            guard !isDistributorConnected else { return false }
            isDistributorConnected = true
            return true
        }
        guard shouldConnect else { return }
        engine.attach(inputDistributor)
        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        engine.connect(engine.inputNode, to: inputDistributor, format: inputFormat)
    }

    private func disconnectDistributorIfUnused() {
        let shouldDisconnect = lock.withLock { () -> Bool in
            guard isDistributorConnected, trackSubgraphs.isEmpty else { return false }
            isDistributorConnected = false
            return true
        }
        guard shouldDisconnect else { return }
        engine.disconnectNodeOutput(inputDistributor)
        engine.detach(inputDistributor)
    }

    private func teardownSubgraph(_ subgraph: TrackMonitorSubgraph) {
        engine.disconnectNodeOutput(subgraph.feedMixer)
        engine.detach(subgraph.feedMixer)
        for unit in subgraph.effectUnits {
            engine.disconnectNodeOutput(unit)
            engine.detach(unit)
        }
        engine.disconnectNodeOutput(subgraph.monitorMixer)
        engine.detach(subgraph.monitorMixer)
    }

    private func unitLatencySeconds(_ unit: AVAudioUnit) -> Double {
        let latency = max(unit.auAudioUnit.latency, unit.latency)
        guard latency.isFinite, latency > 0 else { return 0 }
        return latency
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
