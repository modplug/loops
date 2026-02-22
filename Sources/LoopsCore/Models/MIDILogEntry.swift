import Foundation

/// The type of MIDI message in a log entry.
public enum MIDILogMessage: Equatable, Sendable {
    case noteOn(note: UInt8, velocity: UInt8)
    case noteOff(note: UInt8, velocity: UInt8)
    case controlChange(controller: UInt8, value: UInt8)
    case programChange(program: UInt8)
    case pitchBend(value: UInt16)
    case other(status: UInt8)

    /// Human-readable display string.
    public var displayString: String {
        switch self {
        case .noteOn(let note, let velocity):
            return "Note On \(Self.noteName(note)) v=\(velocity)"
        case .noteOff(let note, let velocity):
            return "Note Off \(Self.noteName(note)) v=\(velocity)"
        case .controlChange(let controller, let value):
            return "CC\(controller) (\(Self.ccName(controller))) \(value)"
        case .programChange(let program):
            return "PC \(program)"
        case .pitchBend(let value):
            return "Pitch Bend \(value)"
        case .other(let status):
            return "Status 0x\(String(status, radix: 16, uppercase: true))"
        }
    }

    /// Converts a MIDI note number (0-127) to a human-readable name like "C4" or "D#5".
    public static func noteName(_ note: UInt8) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = Int(note) / 12 - 1
        let name = noteNames[Int(note) % 12]
        return "\(name)\(octave)"
    }

    /// Returns a human-readable name for common MIDI CC numbers.
    public static func ccName(_ controller: UInt8) -> String {
        switch controller {
        case 0: return "Bank Select"
        case 1: return "Modulation"
        case 2: return "Breath"
        case 4: return "Foot"
        case 7: return "Volume"
        case 10: return "Pan"
        case 11: return "Expression"
        case 64: return "Sustain"
        case 65: return "Portamento"
        case 91: return "Reverb"
        case 93: return "Chorus"
        default: return "CC\(controller)"
        }
    }
}

/// A single MIDI message log entry for the MIDI activity monitor.
public struct MIDILogEntry: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let deviceID: String?
    public let deviceName: String?
    public let channel: UInt8
    public let message: MIDILogMessage

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        deviceID: String? = nil,
        deviceName: String? = nil,
        channel: UInt8,
        message: MIDILogMessage
    ) {
        self.id = id
        self.timestamp = timestamp
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.channel = channel
        self.message = message
    }

    /// Parses a raw MIDI word into a log entry.
    public static func fromRawWord(_ word: UInt32, deviceID: String?, deviceName: String? = nil) -> MIDILogEntry {
        let status = UInt8((word >> 16) & 0xF0)
        let channel = UInt8((word >> 16) & 0x0F)
        let data1 = UInt8((word >> 8) & 0xFF)
        let data2 = UInt8(word & 0xFF)

        let message: MIDILogMessage
        switch status {
        case 0x80:
            message = .noteOff(note: data1, velocity: data2)
        case 0x90:
            if data2 == 0 {
                message = .noteOff(note: data1, velocity: 0)
            } else {
                message = .noteOn(note: data1, velocity: data2)
            }
        case 0xB0:
            message = .controlChange(controller: data1, value: data2)
        case 0xC0:
            message = .programChange(program: data1)
        case 0xE0:
            let value = UInt16(data1) | (UInt16(data2) << 7)
            message = .pitchBend(value: value)
        default:
            message = .other(status: status)
        }

        return MIDILogEntry(
            deviceID: deviceID,
            deviceName: deviceName,
            channel: channel,
            message: message
        )
    }
}
