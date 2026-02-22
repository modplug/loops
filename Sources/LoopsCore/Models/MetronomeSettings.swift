import Foundation

/// Metronome subdivision options for controlling click density.
public enum MetronomeSubdivision: String, Codable, Sendable, CaseIterable, Equatable {
    /// One click per beat (default).
    case quarter
    /// Two clicks per beat.
    case eighth
    /// Four clicks per beat.
    case sixteenth
    /// Clicks every 1.5 beats (dotted quarter note).
    case dottedQuarter
    /// Three clicks per beat (triplet).
    case triplet

    public var displayName: String {
        switch self {
        case .quarter: return "1/4"
        case .eighth: return "1/8"
        case .sixteenth: return "1/16"
        case .dottedQuarter: return "Dotted 1/4"
        case .triplet: return "Triplet"
        }
    }

    /// Number of clicks per beat for this subdivision.
    public var clicksPerBeat: Double {
        switch self {
        case .quarter: return 1.0
        case .eighth: return 2.0
        case .sixteenth: return 4.0
        case .dottedQuarter: return 2.0 / 3.0
        case .triplet: return 3.0
        }
    }
}

/// Metronome settings carried by master track containers to define click behavior for a bar range.
public struct MetronomeSettings: Codable, Equatable, Sendable {
    public var subdivision: MetronomeSubdivision

    public init(subdivision: MetronomeSubdivision = .quarter) {
        self.subdivision = subdivision
    }
}

/// Global metronome configuration stored per-song.
public struct MetronomeConfig: Codable, Equatable, Sendable {
    /// Volume level (0.0–1.0).
    public var volume: Float
    /// Default subdivision when no master track container overrides.
    public var subdivision: MetronomeSubdivision
    /// Output port ID for routing metronome to a specific output (e.g., headphones).
    /// When nil, routes to main mixer.
    public var outputPortID: String?

    public init(
        volume: Float = 0.8,
        subdivision: MetronomeSubdivision = .quarter,
        outputPortID: String? = nil
    ) {
        self.volume = min(max(volume, 0.0), 1.0)
        self.subdivision = subdivision
        self.outputPortID = outputPortID
    }
}
