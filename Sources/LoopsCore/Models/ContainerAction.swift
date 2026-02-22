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

/// What to do to a target container when a trigger fires.
public enum TriggerAction: Codable, Equatable, Sendable, Hashable {
    case start
    case stop
    case armRecord
    case disarmRecord
}

/// An action that fires when a container enters or exits.
public enum ContainerAction: Codable, Equatable, Sendable, Identifiable {
    case sendMIDI(id: ID<ContainerAction>, message: MIDIActionMessage, destination: MIDIDestination)
    case triggerContainer(id: ID<ContainerAction>, targetID: ID<Container>, action: TriggerAction)

    public var id: ID<ContainerAction> {
        switch self {
        case .sendMIDI(let id, _, _):
            return id
        case .triggerContainer(let id, _, _):
            return id
        }
    }

    /// Creates a new sendMIDI action with an auto-generated ID.
    public static func makeSendMIDI(
        message: MIDIActionMessage,
        destination: MIDIDestination
    ) -> ContainerAction {
        .sendMIDI(id: ID(), message: message, destination: destination)
    }

    /// Creates a new triggerContainer action with an auto-generated ID.
    public static func makeTriggerContainer(
        targetID: ID<Container>,
        action: TriggerAction
    ) -> ContainerAction {
        .triggerContainer(id: ID(), targetID: targetID, action: action)
    }
}
