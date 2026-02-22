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
    /// Optional fade-in applied at the container start (gain ramp 0→1).
    public var enterFade: FadeSettings?
    /// Optional fade-out applied at the container end (gain ramp 1→0).
    public var exitFade: FadeSettings?
    /// Actions to fire when this container enters (starts playing).
    public var onEnterActions: [ContainerAction]
    /// Actions to fire when this container exits (stops playing).
    public var onExitActions: [ContainerAction]
    /// Automation lanes controlling AU parameters over this container's duration.
    public var automationLanes: [AutomationLane]

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
        instrumentOverride: AudioComponentInfo? = nil,
        enterFade: FadeSettings? = nil,
        exitFade: FadeSettings? = nil,
        onEnterActions: [ContainerAction] = [],
        onExitActions: [ContainerAction] = [],
        automationLanes: [AutomationLane] = []
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
        self.enterFade = enterFade
        self.exitFade = exitFade
        self.onEnterActions = onEnterActions
        self.onExitActions = onExitActions
        self.automationLanes = automationLanes
    }

    // MARK: - Backward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case id, name, startBar, lengthBars, sourceRecordingID, linkGroupID
        case loopSettings, isRecordArmed, volumeOverride, panOverride
        case insertEffects, isEffectChainBypassed, instrumentOverride
        case enterFade, exitFade, onEnterActions, onExitActions
        case automationLanes
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
        enterFade = try c.decodeIfPresent(FadeSettings.self, forKey: .enterFade)
        exitFade = try c.decodeIfPresent(FadeSettings.self, forKey: .exitFade)
        onEnterActions = try c.decodeIfPresent([ContainerAction].self, forKey: .onEnterActions) ?? []
        onExitActions = try c.decodeIfPresent([ContainerAction].self, forKey: .onExitActions) ?? []
        automationLanes = try c.decodeIfPresent([AutomationLane].self, forKey: .automationLanes) ?? []
    }
}
