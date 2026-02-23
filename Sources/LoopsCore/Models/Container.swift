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

    /// If non-nil, this container is a linked clone of the parent.
    /// Non-overridden fields are inherited from the parent at resolution time.
    public var parentContainerID: ID<Container>?

    /// Which fields have been locally overridden on this clone.
    /// Empty for original containers. Only meaningful when `parentContainerID` is set.
    public var overriddenFields: Set<ContainerField>

    /// MIDI note sequence for MIDI containers (nil for audio containers).
    public var midiSequence: MIDISequence?

    /// Metronome settings for master track containers (defines click behavior for this bar range).
    public var metronomeSettings: MetronomeSettings?

    /// Bars into the source recording where playback begins (0.0 = from start).
    /// Used for non-destructive trim/crop of the left edge.
    public var audioStartOffset: Double

    public var endBar: Int { startBar + lengthBars }

    /// Whether this container has MIDI content.
    public var hasMIDI: Bool { midiSequence != nil }

    /// Whether this container is a linked clone.
    public var isClone: Bool { parentContainerID != nil }

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
        automationLanes: [AutomationLane] = [],
        parentContainerID: ID<Container>? = nil,
        overriddenFields: Set<ContainerField> = [],
        midiSequence: MIDISequence? = nil,
        metronomeSettings: MetronomeSettings? = nil,
        audioStartOffset: Double = 0.0
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
        self.parentContainerID = parentContainerID
        self.overriddenFields = overriddenFields
        self.midiSequence = midiSequence
        self.metronomeSettings = metronomeSettings
        self.audioStartOffset = audioStartOffset
    }

    // MARK: - Backward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case id, name, startBar, lengthBars, sourceRecordingID, linkGroupID
        case loopSettings, isRecordArmed, volumeOverride, panOverride
        case insertEffects, isEffectChainBypassed, instrumentOverride
        case enterFade, exitFade, onEnterActions, onExitActions
        case automationLanes, parentContainerID, overriddenFields
        case midiSequence, metronomeSettings, audioStartOffset
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
        parentContainerID = try c.decodeIfPresent(LoopsCore.ID<Container>.self, forKey: .parentContainerID)
        overriddenFields = try c.decodeIfPresent(Set<ContainerField>.self, forKey: .overriddenFields) ?? []
        midiSequence = try c.decodeIfPresent(MIDISequence.self, forKey: .midiSequence)
        metronomeSettings = try c.decodeIfPresent(MetronomeSettings.self, forKey: .metronomeSettings)
        audioStartOffset = try c.decodeIfPresent(Double.self, forKey: .audioStartOffset) ?? 0.0
    }

    // MARK: - Per-field Operations

    /// Copies a single field's value from the given source container into this container.
    public mutating func copyField(from source: Container, field: ContainerField) {
        switch field {
        case .name:
            name = source.name
        case .effects:
            insertEffects = source.insertEffects
            isEffectChainBypassed = source.isEffectChainBypassed
        case .automation:
            automationLanes = source.automationLanes
        case .fades:
            enterFade = source.enterFade
            exitFade = source.exitFade
        case .enterActions:
            onEnterActions = source.onEnterActions
        case .exitActions:
            onExitActions = source.onExitActions
        case .loopSettings:
            loopSettings = source.loopSettings
        case .instrumentOverride:
            instrumentOverride = source.instrumentOverride
        case .sourceRecording:
            sourceRecordingID = source.sourceRecordingID
        case .midiSequence:
            midiSequence = source.midiSequence
        case .audioStartOffset:
            audioStartOffset = source.audioStartOffset
        }
    }

    // MARK: - Clone Resolution

    /// Returns a new container with all fields resolved against the given parent.
    /// For each field: if the field is in `overriddenFields`, the local value is used;
    /// otherwise, the parent's value is inherited. Position fields (startBar, lengthBars)
    /// are always local.
    public func resolved(parent: Container) -> Container {
        var result = self
        if !overriddenFields.contains(.name) {
            result.name = parent.name
        }
        if !overriddenFields.contains(.effects) {
            result.insertEffects = parent.insertEffects
            result.isEffectChainBypassed = parent.isEffectChainBypassed
        }
        if !overriddenFields.contains(.automation) {
            result.automationLanes = parent.automationLanes
        }
        if !overriddenFields.contains(.fades) {
            result.enterFade = parent.enterFade
            result.exitFade = parent.exitFade
        }
        if !overriddenFields.contains(.enterActions) {
            result.onEnterActions = parent.onEnterActions
        }
        if !overriddenFields.contains(.exitActions) {
            result.onExitActions = parent.onExitActions
        }
        if !overriddenFields.contains(.loopSettings) {
            result.loopSettings = parent.loopSettings
        }
        if !overriddenFields.contains(.instrumentOverride) {
            result.instrumentOverride = parent.instrumentOverride
        }
        if !overriddenFields.contains(.sourceRecording) {
            result.sourceRecordingID = parent.sourceRecordingID
        }
        if !overriddenFields.contains(.midiSequence) {
            result.midiSequence = parent.midiSequence
        }
        return result
    }

    /// Returns a resolved container given a lookup function for finding parent containers.
    /// If this is not a clone (parentContainerID is nil), returns self unchanged.
    public func resolved(using lookup: (ID) -> Container?) -> Container {
        guard let parentID = parentContainerID,
              let parent = lookup(parentID) else {
            return self
        }
        return resolved(parent: parent)
    }
}
