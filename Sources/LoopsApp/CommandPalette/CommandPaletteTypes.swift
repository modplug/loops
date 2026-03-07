import Foundation
import CoreGraphics
import LoopsCore
import LoopsEngine

public enum CommandNodeKind: String, Sendable {
    case globalAction
    case track
    case container
    case plugin
    case pluginAction
    case pluginInstance
    case automation
    case destination
    case utility
}

public enum CommandPaletteFilter: String, CaseIterable, Sendable, Hashable {
    case all
    case context
    case tracks
    case containers
    case plugins
    case instruments
    case automation
    case songs
    case settings

    public var title: String {
        switch self {
        case .all: return "All"
        case .context: return "Context"
        case .tracks: return "Tracks"
        case .containers: return "Containers"
        case .plugins: return "Plugins"
        case .instruments: return "Instruments"
        case .automation: return "Automation"
        case .songs: return "Songs"
        case .settings: return "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .all: return "line.3.horizontal.decrease.circle"
        case .context: return "scope"
        case .tracks: return "music.note.list"
        case .containers: return "square.stack.3d.up"
        case .plugins: return "slider.horizontal.3"
        case .instruments: return "pianokeys"
        case .automation: return "waveform.path"
        case .songs: return "music.quarternote.3"
        case .settings: return "gearshape"
        }
    }

    public func matches(_ node: CommandNode) -> Bool {
        let badges = Set(node.badges.map { $0.lowercased() })
        let breadcrumbs = node.breadcrumbs.joined(separator: " ").lowercased()
        let subtitle = node.subtitle.lowercased()

        switch self {
        case .all:
            return true
        case .context:
            return badges.contains("context") || breadcrumbs.contains("context")
        case .tracks:
            return node.kind == .track || badges.contains("track")
        case .containers:
            return node.kind == .container || badges.contains("container")
        case .plugins:
            return node.kind == .plugin
                || node.kind == .pluginAction
                || node.kind == .pluginInstance
                || badges.contains("plugin")
                || badges.contains("effect")
        case .instruments:
            return badges.contains("instrument")
                || subtitle.contains("instrument")
                || node.searchableText.contains(where: { $0.localizedCaseInsensitiveContains("instrument") })
        case .automation:
            return node.kind == .automation || badges.contains("automation")
        case .songs:
            return badges.contains("song")
                || subtitle.contains("song")
                || node.title.localizedCaseInsensitiveContains("song")
        case .settings:
            return badges.contains("settings")
                || subtitle.contains("settings")
                || node.searchableText.contains(where: {
                    let lowered = $0.lowercased()
                    return lowered.contains("settings") || lowered.contains("audio device") || lowered.contains("preferences")
                })
        }
    }
}

public struct CommandConfirmation: Sendable {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

public struct CommandNodeMultiSelection {
    public let commitTitle: String
    public let helperText: String
    public let allowsSelection: (CommandNode) -> Bool
    public let commit: ([CommandNode]) -> Void

    public init(
        commitTitle: String,
        helperText: String,
        allowsSelection: @escaping (CommandNode) -> Bool = { _ in true },
        commit: @escaping ([CommandNode]) -> Void
    ) {
        self.commitTitle = commitTitle
        self.helperText = helperText
        self.allowsSelection = allowsSelection
        self.commit = commit
    }
}

public struct CommandNodeChildEntry {
    public let title: String
    public let breadcrumbTitle: String
    public let query: String
    public let selectedFilter: CommandPaletteFilter
    public let nodesProvider: () -> [CommandNode]
    public let multiSelection: CommandNodeMultiSelection?

    public init(
        title: String,
        breadcrumbTitle: String? = nil,
        query: String = "",
        selectedFilter: CommandPaletteFilter = .all,
        nodesProvider: @escaping () -> [CommandNode],
        multiSelection: CommandNodeMultiSelection? = nil
    ) {
        self.title = title
        self.breadcrumbTitle = breadcrumbTitle ?? title
        self.query = query
        self.selectedFilter = selectedFilter
        self.nodesProvider = nodesProvider
        self.multiSelection = multiSelection
    }
}

public enum CommandPalettePluginHost: String, Sendable, Hashable {
    case trackEffect
    case containerEffect
    case trackInstrument
    case containerInstrument

    public var displayName: String {
        switch self {
        case .trackEffect: return "Track"
        case .containerEffect: return "Container"
        case .trackInstrument: return "Track Instrument"
        case .containerInstrument: return "Container Instrument"
        }
    }

    public var sortRank: Int {
        switch self {
        case .trackEffect, .trackInstrument: return 0
        case .containerEffect, .containerInstrument: return 1
        }
    }
}

public struct CommandPalettePluginInstanceReference: Sendable, Hashable, Identifiable {
    public let id: String
    public let host: CommandPalettePluginHost
    public let trackID: LoopsCore.ID<Track>
    public let containerID: LoopsCore.ID<Container>?
    public let effectID: UUID?
    public let effectIndex: Int
    public let component: AudioComponentInfo
    public let displayName: String
    public let parameterEffectName: String

    public init(
        host: CommandPalettePluginHost,
        trackID: LoopsCore.ID<Track>,
        containerID: LoopsCore.ID<Container>? = nil,
        effectID: LoopsCore.ID<InsertEffect>? = nil,
        effectIndex: Int,
        component: AudioComponentInfo,
        displayName: String,
        parameterEffectName: String? = nil
    ) {
        self.host = host
        self.trackID = trackID
        self.containerID = containerID
        self.effectID = effectID?.rawValue
        self.effectIndex = effectIndex
        self.component = component
        self.displayName = displayName
        self.parameterEffectName = parameterEffectName ?? displayName
        self.id = [
            host.rawValue,
            trackID.rawValue.uuidString,
            containerID?.rawValue.uuidString ?? "track",
            effectID?.rawValue.uuidString ?? "none",
            "\(effectIndex)"
        ].joined(separator: ":")
    }

    public var insertEffectID: LoopsCore.ID<InsertEffect>? {
        effectID.map { LoopsCore.ID<InsertEffect>(rawValue: $0) }
    }

    public var effectPath: EffectPath {
        switch host {
        case .trackEffect:
            return EffectPath(trackID: trackID, effectIndex: effectIndex, parameterAddress: 0)
        case .containerEffect:
            return EffectPath(trackID: trackID, containerID: containerID, effectIndex: effectIndex, parameterAddress: 0)
        case .trackInstrument:
            return EffectPath.trackInstrument(trackID: trackID, parameterAddress: 0)
        case .containerInstrument:
            return EffectPath(trackID: trackID, containerID: containerID, effectIndex: EffectPath.instrumentParameterEffectIndex, parameterAddress: 0)
        }
    }
}

public enum PreviewTarget: Sendable, Equatable {
    case track(ID<Track>)
    case container(trackID: ID<Track>, containerID: ID<Container>)
    case pluginInstance(CommandPalettePluginInstanceReference)
    case automation(trackID: ID<Track>, laneID: ID<AutomationLane>, targetPath: EffectPath)
}

public enum PreviewHighlightStyle: String, Sendable {
    case focus
    case pulse
    case outline
}

public struct PreviewRestoreToken {
    public var contentMode: ContentMode
    public var automationExpanded: Set<ID<Track>>
    public var horizontalOffset: CGFloat
    public var verticalOffset: CGFloat

    public init(
        contentMode: ContentMode,
        automationExpanded: Set<ID<Track>>,
        horizontalOffset: CGFloat,
        verticalOffset: CGFloat
    ) {
        self.contentMode = contentMode
        self.automationExpanded = automationExpanded
        self.horizontalOffset = horizontalOffset
        self.verticalOffset = verticalOffset
    }
}

@MainActor
@Observable
public final class PreviewState {
    public var target: PreviewTarget?
    public var highlightStyle: PreviewHighlightStyle = .focus
    public var restoreToken: PreviewRestoreToken?

    public init() {}

    public func begin(target: PreviewTarget, style: PreviewHighlightStyle, restoreToken: PreviewRestoreToken?) {
        self.target = target
        self.highlightStyle = style
        if self.restoreToken == nil {
            self.restoreToken = restoreToken
        }
    }

    public func clear(resetRestoreToken: Bool = true) {
        target = nil
        highlightStyle = .focus
        if resetRestoreToken {
            restoreToken = nil
        }
    }

    public var previewedTrackID: ID<Track>? {
        switch target {
        case .track(let id):
            return id
        case .container(let trackID, _):
            return trackID
        case .pluginInstance(let ref):
            return ref.trackID
        case .automation(let trackID, _, _):
            return trackID
        case nil:
            return nil
        }
    }

    public var previewedContainerID: ID<Container>? {
        switch target {
        case .container(_, let containerID):
            return containerID
        case .pluginInstance(let ref):
            return ref.containerID
        default:
            return nil
        }
    }

    public var previewedPluginInstance: CommandPalettePluginInstanceReference? {
        switch target {
        case .pluginInstance(let ref):
            return ref
        default:
            return nil
        }
    }

    public var previewedAutomationLaneID: ID<AutomationLane>? {
        switch target {
        case .automation(_, let laneID, _):
            return laneID
        default:
            return nil
        }
    }

    public var previewedAutomationPath: EffectPath? {
        switch target {
        case .automation(_, _, let path):
            return path
        default:
            return nil
        }
    }
}

public struct CommandNode: Identifiable {
    public let id: String
    public let kind: CommandNodeKind
    public let title: String
    public let subtitle: String
    public let breadcrumbs: [String]
    public let badges: [String]
    public let searchableText: [String]
    public let shortcutDisplay: String?
    public let previewTarget: PreviewTarget?
    public let previewStyle: PreviewHighlightStyle
    public let confirmation: CommandConfirmation?
    public let childEntryBuilder: (() -> CommandNodeChildEntry)?
    public let childrenProvider: (() -> [CommandNode])?
    public let execute: (() -> Void)?

    public init(
        id: String,
        kind: CommandNodeKind,
        title: String,
        subtitle: String = "",
        breadcrumbs: [String] = [],
        badges: [String] = [],
        searchableText: [String] = [],
        shortcutDisplay: String? = nil,
        previewTarget: PreviewTarget? = nil,
        previewStyle: PreviewHighlightStyle = .focus,
        confirmation: CommandConfirmation? = nil,
        childEntryBuilder: (() -> CommandNodeChildEntry)? = nil,
        childrenProvider: (() -> [CommandNode])? = nil,
        execute: (() -> Void)? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.breadcrumbs = breadcrumbs
        self.badges = badges
        self.searchableText = searchableText
        self.shortcutDisplay = shortcutDisplay
        self.previewTarget = previewTarget
        self.previewStyle = previewStyle
        self.confirmation = confirmation
        self.childEntryBuilder = childEntryBuilder
        self.childrenProvider = childrenProvider
        self.execute = execute
    }

    public var hasChildren: Bool {
        childEntryBuilder != nil || childrenProvider != nil
    }
}

public struct CommandPaletteAudioUnitProvider {
    public var effects: () -> [AudioUnitInfo]
    public var instruments: () -> [AudioUnitInfo]

    public init(
        effects: @escaping () -> [AudioUnitInfo],
        instruments: @escaping () -> [AudioUnitInfo]
    ) {
        self.effects = effects
        self.instruments = instruments
    }

    public static let live = CommandPaletteAudioUnitProvider(
        effects: { CommandPaletteAudioUnitCache.shared.effects() },
        instruments: { CommandPaletteAudioUnitCache.shared.instruments() }
    )
}

public final class CommandPaletteAudioUnitCache {
    public static let shared = CommandPaletteAudioUnitCache()

    private var cachedEffects: [AudioUnitInfo]?
    private var cachedInstruments: [AudioUnitInfo]?
    private let discovery = AudioUnitDiscovery()

    private init() {}

    public func effects() -> [AudioUnitInfo] {
        if let cachedEffects {
            return cachedEffects
        }
        let discovered = discovery.effects()
        cachedEffects = discovered
        return discovered
    }

    public func instruments() -> [AudioUnitInfo] {
        if let cachedInstruments {
            return cachedInstruments
        }
        let discovered = discovery.instruments()
        cachedInstruments = discovered
        return discovered
    }

    public func invalidate() {
        cachedEffects = nil
        cachedInstruments = nil
    }
}
