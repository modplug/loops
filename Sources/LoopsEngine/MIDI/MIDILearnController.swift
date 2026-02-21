import Foundation
import LoopsCore

/// Manages the MIDI learn workflow: start learning for a control,
/// receive a MIDI event, create the mapping.
public final class MIDILearnController: @unchecked Sendable {
    private let dispatcher: MIDIDispatcher
    public private(set) var learningControl: MappableControl?

    /// Callback when a new mapping is learned.
    public var onMappingLearned: ((MIDIMapping) -> Void)?

    public init(dispatcher: MIDIDispatcher) {
        self.dispatcher = dispatcher
        dispatcher.onMIDILearnEvent = { [weak self] trigger in
            self?.handleLearnedEvent(trigger)
        }
    }

    /// Starts learning mode for the specified control.
    public func startLearning(for control: MappableControl) {
        learningControl = control
        dispatcher.isLearning = true
    }

    /// Cancels learn mode without creating a mapping.
    public func cancelLearning() {
        learningControl = nil
        dispatcher.isLearning = false
    }

    private func handleLearnedEvent(_ trigger: MIDITrigger) {
        guard let control = learningControl else { return }

        let mapping = MIDIMapping(
            control: control,
            trigger: trigger
        )

        learningControl = nil
        dispatcher.isLearning = false
        onMappingLearned?(mapping)
    }
}
