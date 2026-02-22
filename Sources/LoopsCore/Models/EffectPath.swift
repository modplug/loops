import Foundation

/// Identifies a specific AU parameter on an effect in the song.
///
/// The path can target:
/// - A container-level effect: `trackID` + `containerID` + `effectIndex` + `parameterAddress`
/// - A track-level effect: `trackID` + nil `containerID` + `effectIndex` + `parameterAddress`
public struct EffectPath: Codable, Equatable, Sendable, Hashable {
    /// The track containing the target effect.
    public var trackID: ID<Track>
    /// The container containing the target effect. `nil` means a track-level effect.
    public var containerID: ID<Container>?
    /// Index of the effect in the insert chain (ordered by `orderIndex`).
    public var effectIndex: Int
    /// The AU parameter address to target.
    public var parameterAddress: UInt64

    public init(
        trackID: ID<Track>,
        containerID: ID<Container>? = nil,
        effectIndex: Int,
        parameterAddress: UInt64
    ) {
        self.trackID = trackID
        self.containerID = containerID
        self.effectIndex = effectIndex
        self.parameterAddress = parameterAddress
    }
}
