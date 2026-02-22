import Foundation
import LoopsCore

/// Protocol for sending MIDI messages, enabling testability with mock implementations.
public protocol MIDIOutput: Sendable {
    /// Sends a MIDI message to an external port identified by name.
    func send(_ message: MIDIActionMessage, toExternalPort name: String)
    /// Sends a MIDI message to an internal AU instrument on a track.
    func send(_ message: MIDIActionMessage, toTrack trackID: ID<Track>)
}
