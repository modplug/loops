import Foundation

/// Type of gain curve used for audio fades.
public enum CurveType: String, Codable, Sendable, CaseIterable {
    case linear
    case exponential
    case sCurve

    /// Returns gain value for a normalized position in `0...1`.
    /// For fade-in the position goes 0 → 1 and so does the gain.
    /// For fade-out, callers should pass `1 - t`.
    public func gain(at t: Double) -> Double {
        let clamped = max(0, min(t, 1))
        switch self {
        case .linear:
            return clamped
        case .exponential:
            return clamped * clamped * clamped
        case .sCurve:
            // Hermite smoothstep: 3t² − 2t³
            return 3 * clamped * clamped - 2 * clamped * clamped * clamped
        }
    }
}

/// Configurable fade settings for container enter/exit audio fades.
public struct FadeSettings: Codable, Equatable, Sendable {
    /// Duration of the fade in bars.
    public var duration: Double
    /// Gain curve shape.
    public var curve: CurveType

    public init(duration: Double = 1.0, curve: CurveType = .linear) {
        self.duration = duration
        self.curve = curve
    }
}
