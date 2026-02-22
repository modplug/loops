import Foundation

/// Represents an available MIDI input source (device/port).
public struct MIDIInputDevice: Identifiable, Equatable, Sendable {
    /// Unique identifier string derived from the CoreMIDI endpoint unique ID.
    public var id: String
    /// Human-readable display name of the MIDI source.
    public var displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// Determines whether a MIDI event matches a track's device + channel filter.
public enum MIDITrackFilter {
    /// Returns `true` if an event from the given source device and channel
    /// matches the track's MIDI input filter settings.
    ///
    /// - Parameters:
    ///   - eventDeviceID: The unique ID of the device that sent the event (nil if unknown).
    ///   - eventChannel: The MIDI channel of the event (0-15).
    ///   - trackDeviceID: The track's configured MIDI input device ID (nil = no device filter).
    ///   - trackChannel: The track's configured MIDI channel (nil = omni, 1-16 = specific).
    public static func matches(
        eventDeviceID: String?,
        eventChannel: UInt8,
        trackDeviceID: String?,
        trackChannel: UInt8?
    ) -> Bool {
        // Device filter: if track specifies a device, event must come from that device.
        if let requiredDevice = trackDeviceID {
            guard eventDeviceID == requiredDevice else { return false }
        }

        // Channel filter: nil = omni (all channels pass), otherwise must match (1-based vs 0-based).
        if let requiredChannel = trackChannel {
            // trackChannel is 1-16, eventChannel is 0-15
            guard eventChannel == requiredChannel - 1 else { return false }
        }

        return true
    }
}
