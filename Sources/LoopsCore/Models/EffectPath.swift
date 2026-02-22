import Foundation

/// Identifies a specific AU parameter on an effect in the song,
/// or a built-in track parameter (volume/pan).
///
/// The path can target:
/// - A container-level effect: `trackID` + `containerID` + `effectIndex` + `parameterAddress`
/// - A track-level effect: `trackID` + nil `containerID` + `effectIndex` + `parameterAddress`
/// - Track volume: `effectIndex == trackParameterEffectIndex`, `parameterAddress == volumeAddress`
/// - Track pan: `effectIndex == trackParameterEffectIndex`, `parameterAddress == panAddress`
public struct EffectPath: Codable, Equatable, Sendable, Hashable {
    /// The track containing the target effect.
    public var trackID: ID<Track>
    /// The container containing the target effect. `nil` means a track-level effect.
    public var containerID: ID<Container>?
    /// Index of the effect in the insert chain (ordered by `orderIndex`).
    /// Use `trackParameterEffectIndex` (-1) for built-in track parameters (volume/pan).
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

    // MARK: - Track Parameter Sentinels

    /// Sentinel effectIndex indicating a built-in track parameter (not an AU effect).
    public static let trackParameterEffectIndex: Int = -1

    /// Sentinel effectIndex indicating a track instrument parameter (AU instrument on a MIDI track).
    public static let instrumentParameterEffectIndex: Int = -2

    /// Parameter address for track volume automation.
    public static let volumeAddress: UInt64 = 0

    /// Parameter address for track pan automation.
    public static let panAddress: UInt64 = 1

    /// Whether this path targets the built-in track volume.
    public var isTrackVolume: Bool {
        containerID == nil && effectIndex == Self.trackParameterEffectIndex && parameterAddress == Self.volumeAddress
    }

    /// Whether this path targets the built-in track pan.
    public var isTrackPan: Bool {
        containerID == nil && effectIndex == Self.trackParameterEffectIndex && parameterAddress == Self.panAddress
    }

    /// Whether this path targets a built-in track parameter (volume or pan).
    public var isTrackParameter: Bool {
        isTrackVolume || isTrackPan
    }

    /// Whether this path targets a track-level effect parameter (not volume/pan, not instrument, not container-level).
    public var isTrackEffectParameter: Bool {
        containerID == nil && effectIndex >= 0
    }

    /// Whether this path targets a track instrument parameter (MIDI track AU instrument).
    public var isTrackInstrumentParameter: Bool {
        containerID == nil && effectIndex == Self.instrumentParameterEffectIndex
    }

    /// Creates an EffectPath targeting track volume automation.
    public static func trackVolume(trackID: ID<Track>) -> EffectPath {
        EffectPath(trackID: trackID, effectIndex: trackParameterEffectIndex, parameterAddress: volumeAddress)
    }

    /// Creates an EffectPath targeting track pan automation.
    public static func trackPan(trackID: ID<Track>) -> EffectPath {
        EffectPath(trackID: trackID, effectIndex: trackParameterEffectIndex, parameterAddress: panAddress)
    }

    /// Creates an EffectPath targeting a track instrument parameter.
    public static func trackInstrument(trackID: ID<Track>, parameterAddress: UInt64) -> EffectPath {
        EffectPath(trackID: trackID, effectIndex: instrumentParameterEffectIndex, parameterAddress: parameterAddress)
    }
}
