import Foundation
import LoopsCore

/// Dispatches MIDI events to mapped controls or the learn controller.
public final class MIDIDispatcher: @unchecked Sendable {
    private var mappings: [MIDITrigger: MappableControl] = [:]

    /// Callback when a mapped control is triggered.
    public var onControlTriggered: ((MappableControl) -> Void)?

    /// Callback for MIDI learn mode.
    public var onMIDILearnEvent: ((MIDITrigger) -> Void)?

    /// Whether we're in learn mode.
    public var isLearning: Bool = false

    public init() {}

    /// Updates the mapping table from an array of MIDIMapping values.
    public func updateMappings(_ mappings: [MIDIMapping]) {
        self.mappings.removeAll()
        for mapping in mappings {
            self.mappings[mapping.trigger] = mapping.control
        }
    }

    /// Processes a received MIDI trigger.
    public func dispatch(_ trigger: MIDITrigger) {
        if isLearning {
            onMIDILearnEvent?(trigger)
            return
        }

        if let control = mappings[trigger] {
            onControlTriggered?(control)
        }
    }
}
