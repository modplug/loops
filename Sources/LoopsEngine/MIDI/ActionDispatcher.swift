import Foundation
import LoopsCore

/// Receives container enter/exit events and executes the associated actions.
/// Uses a `MIDIOutput` protocol for testability.
public final class ActionDispatcher: @unchecked Sendable {
    private let midiOutput: MIDIOutput

    public init(midiOutput: MIDIOutput) {
        self.midiOutput = midiOutput
    }

    /// Called when a container begins playing (enters).
    public func containerDidEnter(_ container: Container) {
        executeActions(container.onEnterActions)
    }

    /// Called when a container stops playing (exits).
    public func containerDidExit(_ container: Container) {
        executeActions(container.onExitActions)
    }

    private func executeActions(_ actions: [ContainerAction]) {
        for action in actions {
            switch action {
            case .sendMIDI(_, let message, let destination):
                switch destination {
                case .externalPort(let name):
                    midiOutput.send(message, toExternalPort: name)
                case .internalTrack(let trackID):
                    midiOutput.send(message, toTrack: trackID)
                }
            }
        }
    }
}
