import Foundation
import AVFoundation
import LoopsCore

/// Manages bus/send routing in the audio engine graph.
/// Each bus track has an input mixer that receives sends from other tracks.
public final class BusRouter: @unchecked Sendable {
    private let engine: AVAudioEngine
    private var busMixers: [ID<Track>: AVAudioMixerNode] = [:]

    public init(engine: AVAudioEngine) {
        self.engine = engine
    }

    /// Creates a bus input mixer for a bus track and connects it to the main mixer.
    public func createBus(trackID: ID<Track>) -> AVAudioMixerNode {
        let mixer = AVAudioMixerNode()
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        busMixers[trackID] = mixer
        return mixer
    }

    /// Removes a bus mixer.
    public func removeBus(trackID: ID<Track>) {
        guard let mixer = busMixers[trackID] else { return }
        engine.disconnectNodeOutput(mixer)
        engine.detach(mixer)
        busMixers.removeValue(forKey: trackID)
    }

    /// Returns the bus mixer for a given bus track.
    public func busMixer(for trackID: ID<Track>) -> AVAudioMixerNode? {
        busMixers[trackID]
    }

    /// Sets the send level from a source node to a bus.
    public func setSendLevel(busTrackID: ID<Track>, level: Float) {
        busMixers[busTrackID]?.volume = level
    }

    /// Cleans up all bus mixers.
    public func cleanup() {
        for (_, mixer) in busMixers {
            engine.disconnectNodeOutput(mixer)
            engine.detach(mixer)
        }
        busMixers.removeAll()
    }
}
