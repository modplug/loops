import Foundation
import LoopsCore

/// Dispatches MIDI events to mapped controls, parameter mappings, or the learn controller.
public final class MIDIDispatcher: @unchecked Sendable {
    private let lock = NSLock()
    private var mappings: [MIDITrigger: MappableControl] = [:]
    private var parameterMappings: [MIDITrigger: [MIDIParameterMapping]] = [:]

    /// Callback when a mapped control is triggered.
    public var onControlTriggered: ((MappableControl) -> Void)?

    /// Callback for MIDI learn mode.
    public var onMIDILearnEvent: ((MIDITrigger) -> Void)?

    /// Callback when a parameter mapping CC is received. Parameters: (EffectPath, scaledValue).
    public var onParameterValue: ((EffectPath, Float) -> Void)?

    /// Whether we're in learn mode.
    public var isLearning: Bool = false

    public init() {}

    /// Updates the transport control mapping table.
    public func updateMappings(_ mappings: [MIDIMapping]) {
        lock.lock()
        self.mappings.removeAll()
        for mapping in mappings {
            self.mappings[mapping.trigger] = mapping.control
        }
        lock.unlock()
    }

    /// Updates the parameter mapping table.
    public func updateParameterMappings(_ mappings: [MIDIParameterMapping]) {
        lock.lock()
        parameterMappings.removeAll()
        for mapping in mappings {
            parameterMappings[mapping.trigger, default: []].append(mapping)
        }
        lock.unlock()
    }

    /// Processes a received MIDI trigger (without CC value — for note/button events).
    public func dispatch(_ trigger: MIDITrigger) {
        if isLearning {
            onMIDILearnEvent?(trigger)
            return
        }

        lock.lock()
        let control = mappings[trigger]
        lock.unlock()

        if let control {
            onControlTriggered?(control)
        }
    }

    /// Processes a received MIDI trigger with CC value for parameter scaling.
    public func dispatch(_ trigger: MIDITrigger, ccValue: UInt8) {
        if isLearning {
            onMIDILearnEvent?(trigger)
            return
        }

        lock.lock()
        let control = mappings[trigger]
        let paramMappings = parameterMappings[trigger]
        lock.unlock()

        if let control {
            onControlTriggered?(control)
        }

        if let paramMappings {
            for mapping in paramMappings {
                let scaled = mapping.scaledValue(ccValue: ccValue)
                onParameterValue?(mapping.targetPath, scaled)
            }
        }
    }
}
