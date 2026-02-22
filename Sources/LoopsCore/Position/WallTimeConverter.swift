import Foundation

/// Converts bar positions to wall-clock time (seconds) using tempo and time signature.
public enum WallTimeConverter {

    /// Returns the wall-clock time in seconds for a given bar position (1-based, fractional).
    ///
    /// - Parameters:
    ///   - bar: Bar position (1-based). E.g. 1.0 = start, 3.5 = halfway through bar 3.
    ///   - bpm: Beats per minute. Clamped to ≥ 1.0.
    ///   - beatsPerBar: Number of beats per bar (time signature numerator). Clamped to ≥ 1.
    /// - Returns: Time in seconds from bar 1.0. Always ≥ 0.
    public static func seconds(forBar bar: Double, bpm: Double, beatsPerBar: Int) -> Double {
        let safeBPM = max(bpm, 1.0)
        let safeBeatsPerBar = max(beatsPerBar, 1)
        let barsFromStart = max(bar - 1.0, 0.0)
        let beatDuration = 60.0 / safeBPM
        let barDuration = Double(safeBeatsPerBar) * beatDuration
        return barsFromStart * barDuration
    }

    /// Formats a time in seconds as MM:SS.ms (two-digit milliseconds, i.e. hundredths).
    ///
    /// - Parameter seconds: Time in seconds. Negative values are clamped to 0.
    /// - Returns: Formatted string, e.g. "02:35.40".
    public static func formatted(_ seconds: Double) -> String {
        let clamped = max(seconds, 0.0)
        let totalSeconds = Int(clamped)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        let hundredths = Int((clamped - Double(totalSeconds)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, secs, hundredths)
    }

    /// Convenience: returns formatted wall-time string for a bar position.
    public static func formattedTime(forBar bar: Double, bpm: Double, beatsPerBar: Int) -> String {
        formatted(seconds(forBar: bar, bpm: bpm, beatsPerBar: beatsPerBar))
    }
}
