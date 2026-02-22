import Foundation

/// Destination for a MIDI action message.
public enum MIDIDestination: Codable, Equatable, Sendable, Hashable {
    /// Send to an external CoreMIDI destination by name.
    case externalPort(name: String)
    /// Send to an internal AU instrument on a specific track.
    case internalTrack(trackID: ID<Track>)
}

/// A MIDI message that can be sent as part of a container action.
public enum MIDIActionMessage: Codable, Equatable, Sendable {
    case programChange(channel: UInt8, program: UInt8)
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8, velocity: UInt8)
}

/// An action that fires when a container enters or exits.
public enum ContainerAction: Codable, Equatable, Sendable, Identifiable {
    case sendMIDI(id: ID<ContainerAction>, message: MIDIActionMessage, destination: MIDIDestination)

    public var id: ID<ContainerAction> {
        switch self {
        case .sendMIDI(let id, _, _):
            return id
        }
    }

    public var message: MIDIActionMessage {
        switch self {
        case .sendMIDI(_, let message, _):
            return message
        }
    }

    public var destination: MIDIDestination {
        switch self {
        case .sendMIDI(_, _, let destination):
            return destination
        }
    }

    /// Creates a new sendMIDI action with an auto-generated ID.
    public static func makeSendMIDI(
        message: MIDIActionMessage,
        destination: MIDIDestination
    ) -> ContainerAction {
        .sendMIDI(id: ID(), message: message, destination: destination)
    }
}
