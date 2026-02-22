import Foundation

public enum TrackKind: String, Codable, Sendable, CaseIterable {
    case audio, midi, bus, backing

    public var displayName: String {
        switch self {
        case .audio: return "Audio"
        case .midi: return "MIDI"
        case .bus: return "Bus"
        case .backing: return "Backing"
        }
    }
}

public struct Track: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<Track>
    public var name: String
    public var kind: TrackKind
    /// Linear gain 0.0...2.0 (0 = -inf, 1.0 = 0dB, 2.0 ~ +6dB)
    public var volume: Float
    /// -1.0 (full left) to +1.0 (full right)
    public var pan: Float
    public var isMuted: Bool
    public var isSoloed: Bool
    public var containers: [Container]
    public var insertEffects: [InsertEffect]
    public var sendLevels: [SendLevel]
    /// For MIDI tracks only
    public var instrumentComponent: AudioComponentInfo?
    /// Stable ID of the input port assigned to this track (nil = default).
    public var inputPortID: String?
    /// Stable ID of the output port assigned to this track (nil = default).
    public var outputPortID: String?
    public var isRecordArmed: Bool
    public var orderIndex: Int

    public init(
        id: ID<Track> = ID(),
        name: String = "Track",
        kind: TrackKind = .audio,
        volume: Float = 1.0,
        pan: Float = 0.0,
        isMuted: Bool = false,
        isSoloed: Bool = false,
        containers: [Container] = [],
        insertEffects: [InsertEffect] = [],
        sendLevels: [SendLevel] = [],
        instrumentComponent: AudioComponentInfo? = nil,
        inputPortID: String? = nil,
        outputPortID: String? = nil,
        isRecordArmed: Bool = false,
        orderIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.volume = volume
        self.pan = pan
        self.isMuted = isMuted
        self.isSoloed = isSoloed
        self.containers = containers
        self.insertEffects = insertEffects
        self.sendLevels = sendLevels
        self.instrumentComponent = instrumentComponent
        self.inputPortID = inputPortID
        self.outputPortID = outputPortID
        self.isRecordArmed = isRecordArmed
        self.orderIndex = orderIndex
    }

    // MARK: - Backward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, volume, pan, isMuted, isSoloed
        case containers, insertEffects, sendLevels
        case instrumentComponent
        case inputPortID, outputPortID
        case isRecordArmed
        case orderIndex
        // Legacy key
        case inputDeviceUID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(TrackKind.self, forKey: .kind)
        volume = try c.decode(Float.self, forKey: .volume)
        pan = try c.decode(Float.self, forKey: .pan)
        isMuted = try c.decode(Bool.self, forKey: .isMuted)
        isSoloed = try c.decode(Bool.self, forKey: .isSoloed)
        containers = try c.decode([Container].self, forKey: .containers)
        insertEffects = try c.decode([InsertEffect].self, forKey: .insertEffects)
        sendLevels = try c.decode([SendLevel].self, forKey: .sendLevels)
        instrumentComponent = try c.decodeIfPresent(AudioComponentInfo.self, forKey: .instrumentComponent)
        outputPortID = try c.decodeIfPresent(String.self, forKey: .outputPortID)
        isRecordArmed = try c.decodeIfPresent(Bool.self, forKey: .isRecordArmed) ?? false
        orderIndex = try c.decode(Int.self, forKey: .orderIndex)

        // Migrate legacy inputDeviceUID → inputPortID
        if let portID = try c.decodeIfPresent(String.self, forKey: .inputPortID) {
            inputPortID = portID
        } else {
            // Legacy: inputDeviceUID was just a device UID, not a port ID.
            // We discard it since there's no way to map it to a specific port.
            inputPortID = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(volume, forKey: .volume)
        try c.encode(pan, forKey: .pan)
        try c.encode(isMuted, forKey: .isMuted)
        try c.encode(isSoloed, forKey: .isSoloed)
        try c.encode(containers, forKey: .containers)
        try c.encode(insertEffects, forKey: .insertEffects)
        try c.encode(sendLevels, forKey: .sendLevels)
        try c.encodeIfPresent(instrumentComponent, forKey: .instrumentComponent)
        try c.encodeIfPresent(inputPortID, forKey: .inputPortID)
        try c.encodeIfPresent(outputPortID, forKey: .outputPortID)
        try c.encode(isRecordArmed, forKey: .isRecordArmed)
        try c.encode(orderIndex, forKey: .orderIndex)
    }
}
