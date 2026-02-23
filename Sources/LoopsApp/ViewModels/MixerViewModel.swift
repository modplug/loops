import SwiftUI
import LoopsCore
import LoopsEngine

/// Per-track observable state for level metering.
/// Each MixerStripView observes only its own MixerStripState,
/// so level changes on one track don't re-evaluate other strips.
@Observable
@MainActor
public final class MixerStripState {
    public var level: Float = 0.0

    /// Timestamp of the last accepted level update, for ~30fps throttling.
    private var lastUpdateTime: CFAbsoluteTime = 0.0

    /// Minimum interval between level updates (~30fps).
    private static let throttleInterval: CFAbsoluteTime = 1.0 / 30.0

    public init() {}

    /// Updates the level if enough time has elapsed since the last update.
    public func updateLevel(_ peak: Float) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastUpdateTime >= Self.throttleInterval else { return }
        lastUpdateTime = now
        level = peak
    }
}

/// View model for the mixer, managing track levels and metering.
@Observable
@MainActor
public final class MixerViewModel {
    /// Per-track meter states — each strip observes only its own state.
    public private(set) var stripStates: [ID<Track>: MixerStripState] = [:]

    /// Master output meter state.
    public let masterStripState = MixerStripState()

    public init() {}

    /// Returns or creates the MixerStripState for a given track.
    public func stripState(for trackID: ID<Track>) -> MixerStripState {
        if let existing = stripStates[trackID] {
            return existing
        }
        let state = MixerStripState()
        stripStates[trackID] = state
        return state
    }

    /// Updates level meter data for a track (throttled at ~30fps).
    public func updateLevel(trackID: ID<Track>, peak: Float) {
        stripState(for: trackID).updateLevel(peak)
    }

    /// Updates the master output level (throttled at ~30fps).
    public func updateMasterLevel(_ peak: Float) {
        masterStripState.updateLevel(peak)
    }

    /// Removes per-track state for tracks that no longer exist.
    public func removeStripState(for trackID: ID<Track>) {
        stripStates.removeValue(forKey: trackID)
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
