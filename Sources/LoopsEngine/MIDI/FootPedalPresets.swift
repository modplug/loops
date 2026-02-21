import Foundation
import LoopsCore

/// Pre-configured MIDI mapping presets for common foot pedal configurations.
public enum FootPedalPreset: String, CaseIterable, Sendable {
    case generic2Button = "Generic 2-Button Pedal"
    case generic4Button = "Generic 4-Button Pedal"

    /// Returns the pre-configured mappings for this preset.
    public var mappings: [MIDIMapping] {
        switch self {
        case .generic2Button:
            return [
                MIDIMapping(control: .playPause, trigger: .controlChange(channel: 0, controller: 64)),
                MIDIMapping(control: .recordArm, trigger: .controlChange(channel: 0, controller: 65)),
            ]
        case .generic4Button:
            return [
                MIDIMapping(control: .playPause, trigger: .controlChange(channel: 0, controller: 64)),
                MIDIMapping(control: .stop, trigger: .controlChange(channel: 0, controller: 65)),
                MIDIMapping(control: .recordArm, trigger: .controlChange(channel: 0, controller: 66)),
                MIDIMapping(control: .nextSong, trigger: .controlChange(channel: 0, controller: 67)),
            ]
        }
    }
}
