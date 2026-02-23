import Foundation

/// A single breakpoint in an automation envelope.
public struct AutomationBreakpoint: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<AutomationBreakpoint>
    /// Position within the container in bars (0-based offset from container start).
    public var position: Double
    /// Parameter value at this breakpoint (0.0–1.0 normalized).
    public var value: Float
    /// Interpolation curve from this breakpoint to the next.
    public var curve: CurveType

    public init(
        id: ID<AutomationBreakpoint> = ID(),
        position: Double,
        value: Float,
        curve: CurveType = .linear
    ) {
        self.id = id
        self.position = position
        self.value = value
        self.curve = curve
    }
}

/// An automation lane that controls an AU parameter over a container's duration.
public struct AutomationLane: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<AutomationLane>
    /// The target AU parameter to automate.
    public var targetPath: EffectPath
    /// Ordered breakpoints defining the envelope.
    public var breakpoints: [AutomationBreakpoint]

    /// Display metadata (populated at creation time, purely cosmetic)
    public var effectName: String?
    public var parameterName: String?
    public var parameterMin: Float?
    public var parameterMax: Float?
    public var parameterUnit: String?

    public init(
        id: ID<AutomationLane> = ID(),
        targetPath: EffectPath,
        breakpoints: [AutomationBreakpoint] = []
    ) {
        self.id = id
        self.targetPath = targetPath
        self.breakpoints = breakpoints
    }

    /// Returns the interpolated value at the given bar position within the container.
    ///
    /// - No breakpoints: returns nil (no automation to apply).
    /// - Single breakpoint: returns that breakpoint's value everywhere.
    /// - Position before first breakpoint: returns first breakpoint's value.
    /// - Position after last breakpoint: returns last breakpoint's value.
    /// - Between breakpoints: interpolates using the left breakpoint's curve.
    public func interpolatedValue(atBar position: Double) -> Float? {
        guard !breakpoints.isEmpty else { return nil }

        let sorted = breakpoints.sorted { $0.position < $1.position }

        guard sorted.count > 1 else { return sorted[0].value }

        // Before first breakpoint
        if position <= sorted[0].position {
            return sorted[0].value
        }

        // After last breakpoint
        if position >= sorted[sorted.count - 1].position {
            return sorted[sorted.count - 1].value
        }

        // Find surrounding breakpoints
        for i in 0..<(sorted.count - 1) {
            let left = sorted[i]
            let right = sorted[i + 1]
            if position >= left.position && position <= right.position {
                let span = right.position - left.position
                guard span > 0 else { return left.value }
                let t = (position - left.position) / span
                let curvedT = left.curve.gain(at: t)
                return left.value + Float(curvedT) * (right.value - left.value)
            }
        }

        return sorted[sorted.count - 1].value
    }
}
