import SwiftUI
import LoopsCore
import LoopsEngine

/// View model for the mixer, managing track levels and metering.
@Observable
@MainActor
public final class MixerViewModel {
    public var trackLevels: [ID<Track>: Float] = [:]
    public var masterLevel: Float = 0.0

    public init() {}

    /// Updates level meter data for a track.
    public func updateLevel(trackID: ID<Track>, peak: Float) {
        trackLevels[trackID] = peak
    }

    /// Updates the master output level.
    public func updateMasterLevel(_ peak: Float) {
        masterLevel = peak
    }

    /// Converts linear gain (0.0...2.0) to dB string.
    public static func gainToDBString(_ gain: Float) -> String {
        if gain <= 0.0001 { return "-inf" }
        let db = 20.0 * log10(Double(gain))
        return String(format: "%.1f dB", db)
    }

    /// Converts a dB value to linear gain.
    public static func dbToGain(_ db: Double) -> Float {
        if db <= -80.0 { return 0.0 }
        return Float(pow(10.0, db / 20.0))
    }
}
