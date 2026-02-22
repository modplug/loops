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
        Set(trackSubgraphs.keys)
    }

    /// Whether a given track is actively being monitored.
    public func isMonitoring(trackID: ID<Track>) -> Bool {
        trackSubgraphs[trackID] != nil
    }

    /// Whether a given track's monitoring is suppressed due to container playback.
    public func isSuppressed(trackID: ID<Track>) -> Bool {
        trackSubgraphs[trackID]?.isSuppressed ?? false
    }

    // MARK: - Enable / Disable

    /// Enables input monitoring for a track, routing through its AU effect chain.
    /// Starts the audio engine if not already running.
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

        // Load AU effects for the track's insert chain
        var effectUnits: [AVAudioUnit] = []
        for effect in insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            guard !effect.isBypassed else { continue }
            if let unit = try? await audioUnitHost.loadAudioUnit(component: effect.component) {
                engine.attach(unit)
                if let presetData = effect.presetData {
                    try? audioUnitHost.restoreState(audioUnit: unit, data: presetData)
                }
                effectUnits.append(unit)
            }
        }

        // Build chain: inputDistributor → [effects...] → monitorMixer → mainMixer
        if effectUnits.isEmpty {
            engine.connect(inputDistributor, to: monitorMixer, format: nil)
        } else {
            engine.connect(inputDistributor, to: effectUnits[0], format: nil)
            for i in 0..<(effectUnits.count - 1) {
                engine.connect(effectUnits[i], to: effectUnits[i + 1], format: nil)
            }
            engine.connect(effectUnits[effectUnits.count - 1], to: monitorMixer, format: nil)
        }
        engine.connect(monitorMixer, to: engine.mainMixerNode, format: nil)

        trackSubgraphs[trackID] = TrackMonitorSubgraph(
            monitorMixer: monitorMixer,
            effectUnits: effectUnits,
            isSuppressed: false,
            volume: volume,
            pan: pan
        )
    }

    /// Disables input monitoring for a track, tearing down its audio subgraph.
    public func disableMonitoring(trackID: ID<Track>) {
        guard let subgraph = trackSubgraphs.removeValue(forKey: trackID) else { return }
        teardownSubgraph(subgraph)
        disconnectDistributorIfUnused()
    }

    // MARK: - Playback Suppression

    /// Suppresses monitoring on a track (sets volume to 0) to avoid doubling
    /// when containers are playing on that track.
    public func suppressMonitoring(trackID: ID<Track>) {
        guard var subgraph = trackSubgraphs[trackID], !subgraph.isSuppressed else { return }
        subgraph.isSuppressed = true
        subgraph.monitorMixer.volume = 0
        trackSubgraphs[trackID] = subgraph
    }

    /// Re-enables monitoring on a track after container playback stops.
    public func unsuppressMonitoring(trackID: ID<Track>) {
        guard var subgraph = trackSubgraphs[trackID], subgraph.isSuppressed else { return }
        subgraph.isSuppressed = false
        subgraph.monitorMixer.volume = subgraph.volume
        trackSubgraphs[trackID] = subgraph
    }

    // MARK: - Cleanup

    /// Tears down all monitoring subgraphs.
    public func cleanup() {
        for (_, subgraph) in trackSubgraphs {
            teardownSubgraph(subgraph)
        }
        trackSubgraphs.removeAll()
        disconnectDistributorIfUnused()
    }

    // MARK: - Private

    private func connectDistributorIfNeeded() {
        guard !isDistributorConnected else { return }
        engine.attach(inputDistributor)
        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        engine.connect(engine.inputNode, to: inputDistributor, format: inputFormat)
        isDistributorConnected = true
    }

    private func disconnectDistributorIfUnused() {
        guard isDistributorConnected, trackSubgraphs.isEmpty else { return }
        engine.disconnectNodeOutput(inputDistributor)
        engine.detach(inputDistributor)
        isDistributorConnected = false
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
