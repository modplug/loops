import Foundation
import LoopsCore

/// Delegate protocol for executing container trigger actions.
/// Implemented by PlaybackScheduler (or a mock in tests).
public protocol ContainerTriggerDelegate: AnyObject, Sendable {
    /// Start playback of the target container from its start position.
    func triggerStart(containerID: ID<Container>)
    /// Stop playback of the target container.
    func triggerStop(containerID: ID<Container>)
    /// Set the record-armed flag on the target container.
    func setRecordArmed(containerID: ID<Container>, armed: Bool)
}

/// Receives container enter/exit events and executes the associated actions.
/// Uses a `MIDIOutput` protocol for testability.
public final class ActionDispatcher: @unchecked Sendable {
    private let midiOutput: MIDIOutput

    /// Delegate for handling container trigger actions (start/stop/arm).
    public weak var triggerDelegate: ContainerTriggerDelegate?

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
            case .triggerContainer(_, let targetID, let triggerAction):
                guard let delegate = triggerDelegate else { continue }
                switch triggerAction {
                case .start:
                    delegate.triggerStart(containerID: targetID)
                case .stop:
                    delegate.triggerStop(containerID: targetID)
                case .armRecord:
                    delegate.setRecordArmed(containerID: targetID, armed: true)
                case .disarmRecord:
                    delegate.setRecordArmed(containerID: targetID, armed: false)
                }
            }
        }
    }
}
