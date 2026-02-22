import Foundation
import LoopsCore

/// Dispatches MIDI events to mapped controls, parameter mappings, or the learn controller.
public final class MIDIDispatcher: @unchecked Sendable {
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
        self.mappings.removeAll()
        for mapping in mappings {
            self.mappings[mapping.trigger] = mapping.control
        }
    }

    /// Updates the parameter mapping table.
    public func updateParameterMappings(_ mappings: [MIDIParameterMapping]) {
        parameterMappings.removeAll()
        for mapping in mappings {
            parameterMappings[mapping.trigger, default: []].append(mapping)
        }
    }

    /// Processes a received MIDI trigger (without CC value — for note/button events).
    public func dispatch(_ trigger: MIDITrigger) {
        if isLearning {
            onMIDILearnEvent?(trigger)
            return
        }

        if let control = mappings[trigger] {
            onControlTriggered?(control)
        }
    }

    /// Processes a received MIDI trigger with CC value for parameter scaling.
    public func dispatch(_ trigger: MIDITrigger, ccValue: UInt8) {
        if isLearning {
            onMIDILearnEvent?(trigger)
            return
        }

        if let control = mappings[trigger] {
            onControlTriggered?(control)
        }

        if let paramMappings = parameterMappings[trigger] {
            for mapping in paramMappings {
                let scaled = mapping.scaledValue(ccValue: ccValue)
                onParameterValue?(mapping.targetPath, scaled)
            }
        }
    }
}
