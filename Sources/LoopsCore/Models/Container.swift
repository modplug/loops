import Foundation

/// Phantom type for link group identification.
public enum LinkGroup {}

public struct Container: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<Container>
    public var name: String
    /// 1-based
    public var startBar: Int
    public var lengthBars: Int
    public var sourceRecordingID: ID<SourceRecording>?
    /// All containers with same linkGroupID share a recording.
    public var linkGroupID: ID<LinkGroup>?
    public var loopSettings: LoopSettings
    public var isRecordArmed: Bool
    public var volumeOverride: Float?
    public var panOverride: Float?
    public var insertEffects: [InsertEffect]
    public var isEffectChainBypassed: Bool
    /// Optional AU instrument override. When set, this container routes through
    /// this instrument instead of the track's default instrument.
    public var instrumentOverride: AudioComponentInfo?

    public var endBar: Int { startBar + lengthBars }

    public init(
        id: ID<Container> = ID(),
        name: String = "Container",
        startBar: Int = 1,
        lengthBars: Int = 4,
        sourceRecordingID: ID<SourceRecording>? = nil,
        linkGroupID: ID<LinkGroup>? = nil,
        loopSettings: LoopSettings = LoopSettings(),
        isRecordArmed: Bool = false,
        volumeOverride: Float? = nil,
        panOverride: Float? = nil,
        insertEffects: [InsertEffect] = [],
        isEffectChainBypassed: Bool = false,
        instrumentOverride: AudioComponentInfo? = nil
    ) {
        self.id = id
        self.name = name
        self.startBar = startBar
        self.lengthBars = lengthBars
        self.sourceRecordingID = sourceRecordingID
        self.linkGroupID = linkGroupID
        self.loopSettings = loopSettings
        self.isRecordArmed = isRecordArmed
        self.volumeOverride = volumeOverride
        self.panOverride = panOverride
        self.insertEffects = insertEffects
        self.isEffectChainBypassed = isEffectChainBypassed
        self.instrumentOverride = instrumentOverride
    }

    // MARK: - Backward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case id, name, startBar, lengthBars, sourceRecordingID, linkGroupID
        case loopSettings, isRecordArmed, volumeOverride, panOverride
        case insertEffects, isEffectChainBypassed, instrumentOverride
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        startBar = try c.decode(Int.self, forKey: .startBar)
        lengthBars = try c.decode(Int.self, forKey: .lengthBars)
        sourceRecordingID = try c.decodeIfPresent(LoopsCore.ID<SourceRecording>.self, forKey: .sourceRecordingID)
        linkGroupID = try c.decodeIfPresent(LoopsCore.ID<LinkGroup>.self, forKey: .linkGroupID)
        loopSettings = try c.decode(LoopSettings.self, forKey: .loopSettings)
        isRecordArmed = try c.decode(Bool.self, forKey: .isRecordArmed)
        volumeOverride = try c.decodeIfPresent(Float.self, forKey: .volumeOverride)
        panOverride = try c.decodeIfPresent(Float.self, forKey: .panOverride)
        insertEffects = try c.decodeIfPresent([InsertEffect].self, forKey: .insertEffects) ?? []
        isEffectChainBypassed = try c.decodeIfPresent(Bool.self, forKey: .isEffectChainBypassed) ?? false
        instrumentOverride = try c.decodeIfPresent(AudioComponentInfo.self, forKey: .instrumentOverride)
    }
}
