import Foundation
import LoopsCore

/// Observable monitor that taps into MIDIManager's raw message callback
/// and provides a message log (circular buffer) and per-track activity tracking.
@MainActor
@Observable
public final class MIDIActivityMonitor {
    /// Maximum number of log entries retained in the circular buffer.
    public static let maxEntries = 500

    /// Activity window duration — tracks are considered active within this window.
    public static let activityWindowSeconds: TimeInterval = 0.3

    // MARK: - Observable state

    /// Recent MIDI messages (newest last). Capped at `maxEntries`.
    public private(set) var recentMessages: [MIDILogEntry] = []

    /// Whether the log is paused (still tracks activity, but doesn't add to log).
    public var isPaused: Bool = false

    // MARK: - Private state

    /// Per-track last-activity timestamps keyed by track ID raw value.
    private var trackActivity: [ID<Track>: Date] = [:]

    /// Device name lookup for display purposes.
    private var deviceNameLookup: [String: String] = [:]

    /// Tracks supplied for per-track activity matching.
    private var tracks: [Track] = []

    public init() {}

    // MARK: - Public API

    /// Updates the set of tracks used for per-track activity matching.
    public func updateTracks(_ tracks: [Track]) {
        self.tracks = tracks
    }

    /// Updates the device name lookup table from available MIDI input devices.
    public func updateDeviceNames(_ devices: [MIDIInputDevice]) {
        var lookup: [String: String] = [:]
        for device in devices {
            lookup[device.id] = device.displayName
        }
        deviceNameLookup = lookup
    }

    /// Records a raw MIDI word received from MIDIManager.
    /// Called from the main actor via Task dispatch.
    public func recordMessage(word: UInt32, deviceID: String?) {
        let deviceName = deviceID.flatMap { deviceNameLookup[$0] }
        let entry = MIDILogEntry.fromRawWord(word, deviceID: deviceID, deviceName: deviceName)

        // Update per-track activity
        let channel = entry.channel
        for track in tracks where track.kind == .midi {
            if MIDITrackFilter.matches(
                eventDeviceID: deviceID,
                eventChannel: channel,
                trackDeviceID: track.midiInputDeviceID,
                trackChannel: track.midiInputChannel
            ) {
                trackActivity[track.id] = entry.timestamp
            }
        }

        // Add to log unless paused
        if !isPaused {
            recentMessages.append(entry)
            if recentMessages.count > Self.maxEntries {
                recentMessages.removeFirst(recentMessages.count - Self.maxEntries)
            }
        }
    }

    /// Returns whether a track has had MIDI activity within the activity window.
    public func isTrackActive(_ trackID: ID<Track>) -> Bool {
        guard let lastActivity = trackActivity[trackID] else { return false }
        return Date().timeIntervalSince(lastActivity) < Self.activityWindowSeconds
    }

    /// Returns whether a track has had MIDI activity within the activity window,
    /// using a reference date for testability.
    public func isTrackActive(_ trackID: ID<Track>, referenceDate: Date) -> Bool {
        guard let lastActivity = trackActivity[trackID] else { return false }
        return referenceDate.timeIntervalSince(lastActivity) < Self.activityWindowSeconds
    }

    /// Clears all log entries.
    public func clearLog() {
        recentMessages.removeAll()
    }

    /// Clears all log entries and activity state.
    public func clearAll() {
        recentMessages.removeAll()
        trackActivity.removeAll()
    }
}
