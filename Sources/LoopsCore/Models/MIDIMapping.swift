import Foundation

public enum MappableControl: Codable, Equatable, Hashable, Sendable {
    // Transport
    case playPause
    case stop
    case recordArm
    case nextSong
    case previousSong
    case metronomeToggle

    // Mixer (track-indexed)
    case trackVolume(trackIndex: Int)
    case trackPan(trackIndex: Int)
    case trackMute(trackIndex: Int)
    case trackSolo(trackIndex: Int)
    case trackSend(trackIndex: Int, sendIndex: Int)

    // Navigation
    case trackSelect(trackIndex: Int)
    case songSelect(songIndex: Int)

    /// Whether this control requires a continuous CC value (0–127 scaled to a range).
    public var isContinuous: Bool {
        switch self {
        case .trackVolume, .trackPan, .trackSend: return true
        default: return false
        }
    }

    /// The value range for continuous controls: (min, max).
    public var valueRange: (min: Float, max: Float) {
        switch self {
        case .trackVolume: return (0.0, 2.0)
        case .trackPan: return (-1.0, 1.0)
        case .trackSend: return (0.0, 1.0)
        default: return (0.0, 1.0)
        }
    }

    /// The transport-only controls (no associated values).
    public static var transportControls: [MappableControl] {
        [.playPause, .stop, .recordArm, .nextSong, .previousSong, .metronomeToggle]
    }

    /// Mixer controls for a given number of tracks.
    public static func mixerControls(trackCount: Int) -> [MappableControl] {
        (0..<trackCount).flatMap { idx in
            [MappableControl.trackVolume(trackIndex: idx),
             .trackPan(trackIndex: idx),
             .trackMute(trackIndex: idx),
             .trackSolo(trackIndex: idx)]
        }
    }

    /// Navigation controls for given track and song counts.
    public static func navigationControls(trackCount: Int, songCount: Int) -> [MappableControl] {
        (0..<trackCount).map { MappableControl.trackSelect(trackIndex: $0) } +
        (0..<songCount).map { MappableControl.songSelect(songIndex: $0) }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, trackIndex, sendIndex, songIndex
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .playPause: try container.encode("playPause", forKey: .type)
        case .stop: try container.encode("stop", forKey: .type)
        case .recordArm: try container.encode("recordArm", forKey: .type)
        case .nextSong: try container.encode("nextSong", forKey: .type)
        case .previousSong: try container.encode("previousSong", forKey: .type)
        case .metronomeToggle: try container.encode("metronomeToggle", forKey: .type)
        case .trackVolume(let idx):
            try container.encode("trackVolume", forKey: .type)
            try container.encode(idx, forKey: .trackIndex)
        case .trackPan(let idx):
            try container.encode("trackPan", forKey: .type)
            try container.encode(idx, forKey: .trackIndex)
        case .trackMute(let idx):
            try container.encode("trackMute", forKey: .type)
            try container.encode(idx, forKey: .trackIndex)
        case .trackSolo(let idx):
            try container.encode("trackSolo", forKey: .type)
            try container.encode(idx, forKey: .trackIndex)
        case .trackSend(let trackIdx, let sendIdx):
            try container.encode("trackSend", forKey: .type)
            try container.encode(trackIdx, forKey: .trackIndex)
            try container.encode(sendIdx, forKey: .sendIndex)
        case .trackSelect(let idx):
            try container.encode("trackSelect", forKey: .type)
            try container.encode(idx, forKey: .trackIndex)
        case .songSelect(let idx):
            try container.encode("songSelect", forKey: .type)
            try container.encode(idx, forKey: .songIndex)
        }
    }

    public init(from decoder: Decoder) throws {
        // Try new keyed format first
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let type = try? container.decode(String.self, forKey: .type) {
            switch type {
            case "playPause": self = .playPause
            case "stop": self = .stop
            case "recordArm": self = .recordArm
            case "nextSong": self = .nextSong
            case "previousSong": self = .previousSong
            case "metronomeToggle": self = .metronomeToggle
            case "trackVolume":
                self = .trackVolume(trackIndex: try container.decode(Int.self, forKey: .trackIndex))
            case "trackPan":
                self = .trackPan(trackIndex: try container.decode(Int.self, forKey: .trackIndex))
            case "trackMute":
                self = .trackMute(trackIndex: try container.decode(Int.self, forKey: .trackIndex))
            case "trackSolo":
                self = .trackSolo(trackIndex: try container.decode(Int.self, forKey: .trackIndex))
            case "trackSend":
                self = .trackSend(
                    trackIndex: try container.decode(Int.self, forKey: .trackIndex),
                    sendIndex: try container.decode(Int.self, forKey: .sendIndex)
                )
            case "trackSelect":
                self = .trackSelect(trackIndex: try container.decode(Int.self, forKey: .trackIndex))
            case "songSelect":
                self = .songSelect(songIndex: try container.decode(Int.self, forKey: .songIndex))
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown MappableControl type: \(type)")
            }
            return
        }

        // Fall back to legacy plain-string format
        let singleContainer = try decoder.singleValueContainer()
        let raw = try singleContainer.decode(String.self)
        switch raw {
        case "playPause": self = .playPause
        case "stop": self = .stop
        case "recordArm": self = .recordArm
        case "nextSong": self = .nextSong
        case "previousSong": self = .previousSong
        case "metronomeToggle": self = .metronomeToggle
        default:
            throw DecodingError.dataCorruptedError(in: singleContainer, debugDescription: "Unknown legacy MappableControl: \(raw)")
        }
    }
}

public enum MIDITrigger: Codable, Equatable, Hashable, Sendable {
    case controlChange(channel: UInt8, controller: UInt8)
    case noteOn(channel: UInt8, note: UInt8)
}

public struct MIDIMapping: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<MIDIMapping>
    public var control: MappableControl
    public var trigger: MIDITrigger
    public var sourceDeviceName: String?

    public init(
        id: ID<MIDIMapping> = ID(),
        control: MappableControl,
        trigger: MIDITrigger,
        sourceDeviceName: String? = nil
    ) {
        self.id = id
        self.control = control
        self.trigger = trigger
        self.sourceDeviceName = sourceDeviceName
    }
}

/// Maps a MIDI CC trigger to an effect parameter, with value scaling.
public struct MIDIParameterMapping: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<MIDIParameterMapping>
    public var trigger: MIDITrigger
    public var targetPath: EffectPath
    public var minValue: Float
    public var maxValue: Float

    public init(
        id: ID<MIDIParameterMapping> = ID(),
        trigger: MIDITrigger,
        targetPath: EffectPath,
        minValue: Float = 0.0,
        maxValue: Float = 1.0
    ) {
        self.id = id
        self.trigger = trigger
        self.targetPath = targetPath
        self.minValue = minValue
        self.maxValue = maxValue
    }

    /// Scales a CC value (0–127) to the parameter's min–max range.
    public func scaledValue(ccValue: UInt8) -> Float {
        minValue + (Float(ccValue) / 127.0) * (maxValue - minValue)
    }
}
