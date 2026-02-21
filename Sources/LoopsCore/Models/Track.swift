import Foundation

public enum TrackKind: String, Codable, Sendable, CaseIterable {
    case audio, midi, bus, backing
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
        self.orderIndex = orderIndex
    }
}
