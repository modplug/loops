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
    private let lock = NSLock()

    /// Shared mixer that receives audio from the input node and distributes
    /// to per-track monitoring chains. Avoids multiple direct connections
    /// from `engine.inputNode`.
    private let inputDistributor: AVAudioMixerNode

    /// Whether the input distributor is currently attached and connected.
    private var isDistributorConnected: Bool = false

    /// Per-track monitoring subgraph.
    private struct TrackMonitorSubgraph {
        let monitorMixer: AVAudioMixerNode
        let effectUnits: [AVAudioUnit]
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
        lock.lock()
        let keys = Set(trackSubgraphs.keys)
        lock.unlock()
        return keys
    }

    /// Whether a given track is actively being monitored.
    public func isMonitoring(trackID: ID<Track>) -> Bool {
        lock.lock()
        let result = trackSubgraphs[trackID] != nil
        lock.unlock()
        return result
    }

    /// Whether a given track's monitoring is suppressed due to container playback.
    public func isSuppressed(trackID: ID<Track>) -> Bool {
        lock.lock()
        let result = trackSubgraphs[trackID]?.isSuppressed ?? false
        lock.unlock()
        return result
    }

    // MARK: - Enable / Disable

    /// Enables input monitoring for a track, routing through its AU effect chain.
    /// Audio passes through immediately (dry); effects are hot-swapped in once loaded.
    public func enableMonitoring(
        trackID: ID<Track>,
        insertEffects: [InsertEffect],
        volume: Float,
        pan: Float
    ) async {
        // Disable first if already monitoring this track
        disableMonitoring(trackID: trackID)

        let monitorMixer = AVAudioMixerNode()
        engine.attach(monitorMixer)
        monitorMixer.volume = volume
        monitorMixer.pan = pan

        // Ensure the shared input distributor is connected
        connectDistributorIfNeeded()

        // Connect dry path immediately so monitoring is instant
        engine.connect(inputDistributor, to: monitorMixer, format: nil)
        engine.connect(monitorMixer, to: engine.mainMixerNode, format: nil)

        lock.lock()
        trackSubgraphs[trackID] = TrackMonitorSubgraph(
            monitorMixer: monitorMixer,
            effectUnits: [],
            isSuppressed: false,
            volume: volume,
            pan: pan
        )
        lock.unlock()

        // Load AU effects in the background, then hot-swap the chain
        let activeEffects = insertEffects
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .filter { !$0.isBypassed }
        guard !activeEffects.isEmpty else { return }

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
        lock.lock()
        let stillMonitoring = trackSubgraphs[trackID] != nil
        lock.unlock()

        guard stillMonitoring, !effectUnits.isEmpty else {
            for unit in effectUnits {
                engine.disconnectNodeOutput(unit)
                engine.detach(unit)
            }
            return
        }

        // Hot-swap: replace dry path with effect chain
        engine.disconnectNodeOutput(inputDistributor)
        engine.connect(inputDistributor, to: effectUnits[0], format: nil)
        for i in 0..<(effectUnits.count - 1) {
            engine.connect(effectUnits[i], to: effectUnits[i + 1], format: nil)
        }
        engine.connect(effectUnits[effectUnits.count - 1], to: monitorMixer, format: nil)

        lock.lock()
        trackSubgraphs[trackID] = TrackMonitorSubgraph(
            monitorMixer: monitorMixer,
            effectUnits: effectUnits,
            isSuppressed: false,
            volume: volume,
            pan: pan
        )
        lock.unlock()
    }

    /// Disables input monitoring for a track, tearing down its audio subgraph.
    public func disableMonitoring(trackID: ID<Track>) {
        lock.lock()
        let subgraph = trackSubgraphs.removeValue(forKey: trackID)
        lock.unlock()
        guard let subgraph else { return }
        teardownSubgraph(subgraph)
        disconnectDistributorIfUnused()
    }

    // MARK: - Playback Suppression

    /// Suppresses monitoring on a track (sets volume to 0) to avoid doubling
    /// when containers are playing on that track.
    public func suppressMonitoring(trackID: ID<Track>) {
        lock.lock()
        guard var subgraph = trackSubgraphs[trackID], !subgraph.isSuppressed else {
            lock.unlock()
            return
        }
        subgraph.isSuppressed = true
        subgraph.monitorMixer.volume = 0
        trackSubgraphs[trackID] = subgraph
        lock.unlock()
    }

    /// Re-enables monitoring on a track after container playback stops.
    public func unsuppressMonitoring(trackID: ID<Track>) {
        lock.lock()
        guard var subgraph = trackSubgraphs[trackID], subgraph.isSuppressed else {
            lock.unlock()
            return
        }
        subgraph.isSuppressed = false
        subgraph.monitorMixer.volume = subgraph.volume
        trackSubgraphs[trackID] = subgraph
        lock.unlock()
    }

    // MARK: - Cleanup

    /// Tears down all monitoring subgraphs.
    public func cleanup() {
        lock.lock()
        let subgraphs = trackSubgraphs
        trackSubgraphs.removeAll()
        lock.unlock()
        for (_, subgraph) in subgraphs {
            teardownSubgraph(subgraph)
        }
        disconnectDistributorIfUnused()
    }

    // MARK: - Private

    private func connectDistributorIfNeeded() {
        lock.lock()
        guard !isDistributorConnected else {
            lock.unlock()
            return
        }
        isDistributorConnected = true
        lock.unlock()
        engine.attach(inputDistributor)
        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        engine.connect(engine.inputNode, to: inputDistributor, format: inputFormat)
    }

    private func disconnectDistributorIfUnused() {
        lock.lock()
        guard isDistributorConnected, trackSubgraphs.isEmpty else {
            lock.unlock()
            return
        }
        isDistributorConnected = false
        lock.unlock()
        engine.disconnectNodeOutput(inputDistributor)
        engine.detach(inputDistributor)
    }

    private func teardownSubgraph(_ subgraph: TrackMonitorSubgraph) {
        for unit in subgraph.effectUnits {
            engine.disconnectNodeOutput(unit)
            engine.detach(unit)
        }
        engine.disconnectNodeOutput(subgraph.monitorMixer)
        engine.detach(subgraph.monitorMixer)
    }
}
