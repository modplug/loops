import Foundation

/// Curve type specifically for crossfades between overlapping containers.
public enum CrossfadeCurveType: String, Codable, Sendable, CaseIterable {
    case linear
    case equalPower
    case sCurve

    /// Display name for UI.
    public var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .equalPower: return "Equal Power"
        case .sCurve: return "S-Curve"
        }
    }

    /// Returns the fade-out gain (1→0) for the leading container at normalized position `t` (0→1).
    public func gainOut(at t: Double) -> Double {
        let clamped = max(0, min(t, 1))
        switch self {
        case .linear:
            return 1.0 - clamped
        case .equalPower:
            return cos(clamped * .pi / 2)
        case .sCurve:
            let fadeIn = 3 * clamped * clamped - 2 * clamped * clamped * clamped
            return 1.0 - fadeIn
        }
    }

    /// Returns the fade-in gain (0→1) for the trailing container at normalized position `t` (0→1).
    public func gainIn(at t: Double) -> Double {
        let clamped = max(0, min(t, 1))
        switch self {
        case .linear:
            return clamped
        case .equalPower:
            return sin(clamped * .pi / 2)
        case .sCurve:
            return 3 * clamped * clamped - 2 * clamped * clamped * clamped
        }
    }

    /// Maps to the equivalent `CurveType` for use with container enter/exit fades.
    public var toCurveType: CurveType {
        switch self {
        case .linear: return .linear
        case .equalPower: return .equalPower
        case .sCurve: return .sCurve
        }
    }
}

/// Represents a crossfade between two overlapping containers on the same track.
/// The crossfade region is the overlap: from containerB's startBar to containerA's endBar.
public struct Crossfade: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<Crossfade>
    /// The earlier container whose tail fades out in the overlap region.
    public var containerAID: ID<Container>
    /// The later container whose head fades in in the overlap region.
    public var containerBID: ID<Container>
    /// The curve type for this crossfade.
    public var curveType: CrossfadeCurveType

    public init(
        id: ID<Crossfade> = ID(),
        containerAID: ID<Container>,
        containerBID: ID<Container>,
        curveType: CrossfadeCurveType = .equalPower
    ) {
        self.id = id
        self.containerAID = containerAID
        self.containerBID = containerBID
        self.curveType = curveType
    }

    /// Computes the crossfade duration in bars from the two containers' positions.
    /// Returns 0 if the containers don't overlap.
    public func duration(containerA: Container, containerB: Container) -> Double {
        max(containerA.endBar - containerB.startBar, 0)
    }
}
