import Foundation
import LoopsCore

/// The kind of target being learned: either a transport control or an effect parameter.
public enum MIDILearnTarget: Sendable {
    case control(MappableControl)
    case parameter(EffectPath, minValue: Float, maxValue: Float)
}

/// Manages the MIDI learn workflow: start learning for a control or parameter,
/// receive a MIDI event, create the mapping.
public final class MIDILearnController: @unchecked Sendable {
    private let lock = NSLock()
    private let dispatcher: MIDIDispatcher
    public private(set) var learningControl: MappableControl?
    public private(set) var learningTarget: MIDILearnTarget?

    /// Callback when a new transport control mapping is learned.
    public var onMappingLearned: ((MIDIMapping) -> Void)?

    /// Callback when a new parameter mapping is learned.
    public var onParameterMappingLearned: ((MIDIParameterMapping) -> Void)?

    public init(dispatcher: MIDIDispatcher) {
        self.dispatcher = dispatcher
        dispatcher.onMIDILearnEvent = { [weak self] trigger in
            self?.handleLearnedEvent(trigger)
        }
    }

    /// Starts learning mode for the specified transport control.
    public func startLearning(for control: MappableControl) {
        lock.lock()
        learningControl = control
        learningTarget = .control(control)
        lock.unlock()
        dispatcher.isLearning = true
    }

    /// Starts learning mode for a parameter target (effect path with value range).
    public func startParameterLearning(for targetPath: EffectPath, minValue: Float = 0.0, maxValue: Float = 1.0) {
        lock.lock()
        learningControl = nil
        learningTarget = .parameter(targetPath, minValue: minValue, maxValue: maxValue)
        lock.unlock()
        dispatcher.isLearning = true
    }

    /// Cancels learn mode without creating a mapping.
    public func cancelLearning() {
        lock.lock()
        learningControl = nil
        learningTarget = nil
        lock.unlock()
        dispatcher.isLearning = false
    }

    private func handleLearnedEvent(_ trigger: MIDITrigger) {
        lock.lock()
        guard let target = learningTarget else {
            lock.unlock()
            return
        }
        learningControl = nil
        learningTarget = nil
        lock.unlock()
        dispatcher.isLearning = false

        switch target {
        case .control(let control):
            let mapping = MIDIMapping(
                control: control,
                trigger: trigger
            )
            onMappingLearned?(mapping)

        case .parameter(let path, let minValue, let maxValue):
            let mapping = MIDIParameterMapping(
                trigger: trigger,
                targetPath: path,
                minValue: minValue,
                maxValue: maxValue
            )
            onParameterMappingLearned?(mapping)
        }
    }
}
