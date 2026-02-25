import Foundation

/// The tool mode selected in the automation toolbar.
public enum AutomationTool: String, CaseIterable, Sendable, Equatable {
    case pointer
    case line
    case exponential
    case ramp
    case sCurve
    case sine
    case triangle
    case square

    /// SF Symbol name for each tool.
    public var iconName: String {
        switch self {
        case .pointer: return "cursorarrow"
        case .line: return "line.diagonal"
        case .exponential: return "point.topleft.down.to.point.bottomright.curvepath"
        case .ramp: return "chart.line.uptrend.xyaxis"
        case .sCurve: return "s.circle"
        case .sine: return "waveform.path"
        case .triangle: return "triangle"
        case .square: return "square.grid.2x2"
        }
    }

    /// Human-readable label.
    public var label: String {
        switch self {
        case .pointer: return "Pointer"
        case .line: return "Line"
        case .exponential: return "Curve"
        case .ramp: return "Ramp"
        case .sCurve: return "S-Curve"
        case .sine: return "Sine"
        case .triangle: return "Triangle"
        case .square: return "Square"
        }
    }

    /// Whether this tool generates periodic shapes.
    public var isPeriodic: Bool {
        switch self {
        case .sine, .triangle, .square: return true
        default: return false
        }
    }
}

/// Generates automation breakpoints for various shape tools.
public enum AutomationShapeGenerator {

    /// Generates breakpoints for a line/ramp between two positions.
    /// - Parameters:
    ///   - startPosition: Start position in bars (0-based offset).
    ///   - endPosition: End position in bars.
    ///   - startValue: Normalized value (0-1) at start.
    ///   - endValue: Normalized value (0-1) at end.
    ///   - gridSpacing: Grid spacing in bars for breakpoint density.
    /// - Returns: Array of breakpoints evenly spaced at grid intervals.
    public static func generateLine(
        startPosition: Double,
        endPosition: Double,
        startValue: Float,
        endValue: Float,
        gridSpacing: Double
    ) -> [AutomationBreakpoint] {
        let span = endPosition - startPosition
        guard span > 0, gridSpacing > 0 else { return [] }
        let steps = max(Int(span / gridSpacing), 1)
        return (0...steps).map { step in
            let t = Double(step) / Double(steps)
            let position = startPosition + t * span
            let value = startValue + Float(t) * (endValue - startValue)
            return AutomationBreakpoint(position: position, value: value)
        }
    }

    /// Generates breakpoints for an exponential curve (power = 3).
    public static func generateExponential(
        startPosition: Double,
        endPosition: Double,
        startValue: Float,
        endValue: Float,
        gridSpacing: Double
    ) -> [AutomationBreakpoint] {
        let span = endPosition - startPosition
        guard span > 0, gridSpacing > 0 else { return [] }
        let steps = max(Int(span / gridSpacing), 1)
        return (0...steps).map { step in
            let t = Double(step) / Double(steps)
            let curved = t * t * t
            let position = startPosition + t * span
            let value = startValue + Float(curved) * (endValue - startValue)
            return AutomationBreakpoint(position: position, value: value)
        }
    }

    /// Generates breakpoints for an S-curve (Hermite smoothstep: 3t^2 - 2t^3).
    public static func generateSCurve(
        startPosition: Double,
        endPosition: Double,
        startValue: Float,
        endValue: Float,
        gridSpacing: Double
    ) -> [AutomationBreakpoint] {
        let span = endPosition - startPosition
        guard span > 0, gridSpacing > 0 else { return [] }
        let steps = max(Int(span / gridSpacing), 1)
        return (0...steps).map { step in
            let t = Double(step) / Double(steps)
            let curved = 3 * t * t - 2 * t * t * t
            let position = startPosition + t * span
            let value = startValue + Float(curved) * (endValue - startValue)
            return AutomationBreakpoint(position: position, value: value)
        }
    }

    /// Generates breakpoints for a sine wave.
    /// - Parameters:
    ///   - startPosition: Start position in bars.
    ///   - endPosition: End position in bars.
    ///   - period: Period in bars (one full cycle).
    ///   - gridSpacing: Grid spacing for breakpoint density.
    /// - Returns: Sine wave breakpoints with values in 0-1.
    public static func generateSine(
        startPosition: Double,
        endPosition: Double,
        period: Double,
        gridSpacing: Double
    ) -> [AutomationBreakpoint] {
        let span = endPosition - startPosition
        guard span > 0, gridSpacing > 0, period > 0 else { return [] }
        let steps = max(Int(span / gridSpacing), 1)
        return (0...steps).map { step in
            let t = Double(step) / Double(steps) * span
            let position = startPosition + t
            let value = Float(0.5 + 0.5 * sin(2 * .pi * t / period))
            return AutomationBreakpoint(position: position, value: value)
        }
    }

    /// Generates breakpoints for a triangle wave.
    public static func generateTriangle(
        startPosition: Double,
        endPosition: Double,
        period: Double,
        gridSpacing: Double
    ) -> [AutomationBreakpoint] {
        let span = endPosition - startPosition
        guard span > 0, gridSpacing > 0, period > 0 else { return [] }
        let steps = max(Int(span / gridSpacing), 1)
        return (0...steps).map { step in
            let t = Double(step) / Double(steps) * span
            let position = startPosition + t
            let phase = t / period
            let value = Float(abs(2.0 * (phase - floor(phase + 0.5))))
            return AutomationBreakpoint(position: position, value: value)
        }
    }

    /// Generates breakpoints for a square wave.
    public static func generateSquare(
        startPosition: Double,
        endPosition: Double,
        period: Double,
        gridSpacing: Double
    ) -> [AutomationBreakpoint] {
        let span = endPosition - startPosition
        guard span > 0, gridSpacing > 0, period > 0 else { return [] }
        let steps = max(Int(span / gridSpacing), 1)
        return (0...steps).map { step in
            let t = Double(step) / Double(steps) * span
            let position = startPosition + t
            let phase = t.truncatingRemainder(dividingBy: period)
            let value: Float = phase < period / 2 ? 1.0 : 0.0
            return AutomationBreakpoint(position: position, value: value)
        }
    }

    /// Generates breakpoints for the given tool type.
    /// For non-periodic tools (line, exponential, ramp, sCurve), uses startValue/endValue.
    /// For periodic tools (sine, triangle, square), uses gridSpacing as the period.
    public static func generate(
        tool: AutomationTool,
        startPosition: Double,
        endPosition: Double,
        startValue: Float,
        endValue: Float,
        gridSpacing: Double
    ) -> [AutomationBreakpoint] {
        switch tool {
        case .pointer:
            return []
        case .line, .ramp:
            return generateLine(
                startPosition: startPosition,
                endPosition: endPosition,
                startValue: startValue,
                endValue: endValue,
                gridSpacing: gridSpacing
            )
        case .exponential:
            return generateExponential(
                startPosition: startPosition,
                endPosition: endPosition,
                startValue: startValue,
                endValue: endValue,
                gridSpacing: gridSpacing
            )
        case .sCurve:
            return generateSCurve(
                startPosition: startPosition,
                endPosition: endPosition,
                startValue: startValue,
                endValue: endValue,
                gridSpacing: gridSpacing
            )
        case .sine:
            // Period = 1 bar (4 grid beats at 1/4 grid), breakpoints at grid resolution
            return generateSine(
                startPosition: startPosition,
                endPosition: endPosition,
                period: gridSpacing * 4,
                gridSpacing: gridSpacing
            )
        case .triangle:
            // Period = 1 bar, breakpoints at grid resolution (triangle only needs endpoints + peaks)
            return generateTriangle(
                startPosition: startPosition,
                endPosition: endPosition,
                period: gridSpacing * 4,
                gridSpacing: gridSpacing
            )
        case .square:
            // Period = 1 bar, breakpoints at grid resolution
            return generateSquare(
                startPosition: startPosition,
                endPosition: endPosition,
                period: gridSpacing * 4,
                gridSpacing: gridSpacing
            )
        }
    }
}
