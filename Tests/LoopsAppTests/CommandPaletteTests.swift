import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore
@testable import LoopsEngine

@Suite("Command Palette Tests")
struct CommandPaletteTests {

    @Test("Search ranking prefers exact plugin matches before instances and add actions")
    func searchRankingPrefersPluginEntities() {
        let nodes = [
            CommandNode(
                id: "add-nexus",
                kind: .pluginAction,
                title: "Add Nexus to Pad Track",
                subtitle: "Plugin action",
                searchableText: ["nexus", "add", "plugin"]
            ),
            CommandNode(
                id: "nexus-instance",
                kind: .pluginInstance,
                title: "Nexus",
                subtitle: "Track 1 / Chorus Container",
                searchableText: ["nexus", "instance", "track 1", "chorus"]
            ),
            CommandNode(
                id: "nexus-plugin",
                kind: .plugin,
                title: "Nexus",
                subtitle: "Plugin · Installed AU instrument",
                searchableText: ["nexus", "plugin", "instrument"]
            )
        ]

        let ranked = CommandPaletteSearch.rank(nodes: nodes, query: "nexus")

        #expect(ranked.map(\.id) == ["nexus-plugin", "nexus-instance", "add-nexus"])
    }

    @Test("clearOrClose clears query before popping or closing")
    @MainActor
    func clearOrCloseFollowsExpectedOrder() {
        let childLeaf = CommandNode(id: "child-leaf", kind: .utility, title: "Child Leaf")
        let parent = CommandNode(
            id: "parent",
            kind: .utility,
            title: "Parent",
            childrenProvider: { [childLeaf] }
        )
        let viewModel = CommandPaletteViewModel(rootProvider: { [parent] })

        viewModel.open()
        viewModel.activate(node: parent)
        #expect(viewModel.canPop)

        viewModel.query = "nexus"
        viewModel.clearOrClose()
        #expect(viewModel.query.isEmpty)
        #expect(viewModel.isPresented)
        #expect(viewModel.canPop)

        viewModel.clearOrClose()
        #expect(!viewModel.canPop)
        #expect(viewModel.isPresented)

        viewModel.clearOrClose()
        #expect(!viewModel.isPresented)
    }

    @Test("forward navigation reopens the branch after a back navigation")
    @MainActor
    func forwardNavigationRestoresAccidentallyClosedBranch() {
        let childLeaf = CommandNode(id: "child-leaf", kind: .utility, title: "Child Leaf")
        let parent = CommandNode(
            id: "parent",
            kind: .utility,
            title: "Parent",
            childrenProvider: { [childLeaf] }
        )
        let viewModel = CommandPaletteViewModel(rootProvider: { [parent] })

        viewModel.open()
        viewModel.activateSelected()
        #expect(viewModel.stack.count == 2)

        viewModel.pop()
        #expect(viewModel.stack.count == 1)
        #expect(viewModel.selectedNode?.id == "parent")

        viewModel.stepForwardOrActivateSelected()
        #expect(viewModel.stack.count == 2)
        #expect(viewModel.stack.last?.title == "Parent")
    }

    @Test("destructive confirmation blocks execution until confirmed")
    @MainActor
    func confirmationRequiresExplicitConfirm() {
        var executed = false
        let destructive = CommandNode(
            id: "delete-track",
            kind: .track,
            title: "Delete Track",
            confirmation: CommandConfirmation(
                title: "Delete Track?",
                message: "This removes the track and its contents."
            ),
            execute: { executed = true }
        )

        let viewModel = CommandPaletteViewModel(rootProvider: { [destructive] })
        viewModel.open()
        viewModel.activateSelected()

        #expect(viewModel.pendingConfirmationNode?.id == destructive.id)
        #expect(!executed)
        #expect(viewModel.isPresented)

        viewModel.confirmPendingAction()
        #expect(executed)
        #expect(!viewModel.isPresented)
    }

    @Test("keyboard navigation updates the selected semantic node")
    @MainActor
    func keyboardNavigationTracksSelection() {
        let trackID = ID<Track>()
        let containerID = ID<Container>()
        let nodes = [
            CommandNode(
                id: "track",
                kind: .track,
                title: "Lead Vox",
                previewTarget: .track(trackID)
            ),
            CommandNode(
                id: "container",
                kind: .container,
                title: "Chorus Double",
                previewTarget: .container(trackID: trackID, containerID: containerID)
            )
        ]

        let viewModel = CommandPaletteViewModel(rootProvider: { nodes })
        viewModel.open()
        #expect(viewModel.selectedNode?.id == "track")
        #expect(viewModel.selectedNode?.previewTarget == .track(trackID))

        viewModel.moveSelection(delta: 1)
        #expect(viewModel.selectedNode?.id == "container")
        #expect(
            viewModel.selectedNode?.previewTarget
                == .container(trackID: trackID, containerID: containerID)
        )
    }

    @Test("preview state exposes the active semantic target")
    @MainActor
    func previewStateProjectsPluginAndAutomationTargets() {
        let trackID = ID<Track>()
        let containerID = ID<Container>()
        let effectID = ID<InsertEffect>()
        let laneID = ID<AutomationLane>()
        let component = AudioComponentInfo(componentType: 1, componentSubType: 2, componentManufacturer: 3)
        let pluginRef = CommandPalettePluginInstanceReference(
            host: .containerEffect,
            trackID: trackID,
            containerID: containerID,
            effectID: effectID,
            effectIndex: 0,
            component: component,
            displayName: "Nexus"
        )

        let state = PreviewState()
        state.begin(
            target: .pluginInstance(pluginRef),
            style: .focus,
            restoreToken: nil
        )

        #expect(state.previewedTrackID == trackID)
        #expect(state.previewedContainerID == containerID)
        #expect(state.previewedPluginInstance?.insertEffectID == effectID)

        let automationPath = EffectPath(trackID: trackID, containerID: containerID, effectIndex: 0, parameterAddress: 12)
        state.begin(
            target: .automation(trackID: trackID, laneID: laneID, targetPath: automationPath),
            style: .outline,
            restoreToken: nil
        )

        #expect(state.previewedTrackID == trackID)
        #expect(state.previewedAutomationLaneID == laneID)
        #expect(state.previewedAutomationPath == automationPath)
    }

    @Test("root nodes include selected-track context")
    @MainActor
    func rootNodesIncludeSelectionContext() {
        let project = ProjectViewModel()
        project.newProject()
        project.addTrack(kind: .audio)
        let selectedTrack = project.project.songs[0].tracks[0]
        project.selectedTrackID = selectedTrack.id

        let executor = CommandExecutor(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            ui: CommandPaletteUIActions(
                openMixer: {},
                openSetlists: {},
                openSongs: {},
                openSettings: {},
                focusTimeline: {},
                revealTarget: { _ in },
                requestTextInput: { _ in nil },
                inspectTrack: { _ in },
                inspectContainer: { _ in },
                openPianoRoll: { _ in },
                presentTrackAutomationPicker: { _ in },
                presentContainerAutomationPicker: { _ in }
            )
        )

        let builder = CommandPaletteCatalogBuilder(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            shortcutManager: ShortcutManager(userDefaults: UserDefaults(suiteName: #function) ?? .standard),
            executor: executor
        )

        let nodes = builder.rootNodes()
        #expect(nodes.contains(where: { $0.id == "context-selected-track-\(selectedTrack.id.rawValue.uuidString)" }))
        #expect(nodes.contains(where: { $0.id == "context-current-song-\(project.project.songs[0].id.rawValue.uuidString)" }))
    }

    @Test("category filter narrows visible nodes semantically")
    @MainActor
    func categoryFilterNarrowsVisibleNodes() {
        let nodes = [
            CommandNode(
                id: "song",
                kind: .globalAction,
                title: "Add Song",
                badges: ["Song"]
            ),
            CommandNode(
                id: "plugin",
                kind: .plugin,
                title: "Nexus",
                badges: ["Plugin", "Instrument"]
            ),
            CommandNode(
                id: "track",
                kind: .track,
                title: "Lead Vox",
                badges: ["Track"]
            )
        ]

        let viewModel = CommandPaletteViewModel(rootProvider: { nodes })
        viewModel.open()

        #expect(viewModel.availableFilters.contains(.songs))
        #expect(viewModel.availableFilters.contains(.instruments))
        #expect(viewModel.availableFilters.contains(.tracks))

        viewModel.selectedFilter = .instruments
        #expect(viewModel.visibleNodes.map(\.id) == ["plugin"])

        viewModel.selectedFilter = .songs
        #expect(viewModel.visibleNodes.map(\.id) == ["song"])
    }

    @Test("query changes reset selection to the first result")
    @MainActor
    func queryChangesResetSelection() {
        let nodes = [
            CommandNode(id: "track", kind: .track, title: "Lead Vox", searchableText: ["lead"]),
            CommandNode(id: "plugin", kind: .plugin, title: "Nexus", searchableText: ["nexus"]),
            CommandNode(id: "container", kind: .container, title: "Chorus", searchableText: ["chorus"]),
        ]

        let viewModel = CommandPaletteViewModel(rootProvider: { nodes })
        viewModel.open()
        viewModel.moveSelection(delta: 2)
        #expect(viewModel.selectedNode?.id == "container")

        viewModel.query = "nexus"
        #expect(viewModel.selectedIndex == 0)
        #expect(viewModel.selectedNode?.id == "plugin")
    }

    @Test("live parameter priming overrides an in-flight cache load immediately")
    @MainActor
    func liveParameterPrimingOverridesLoadingState() async {
        let component = AudioComponentInfo(componentType: 1, componentSubType: 2, componentManufacturer: 3)
        let cache = CommandPaletteParameterCache(provider: { _ in
            try? await Task.sleep(for: .seconds(5))
            return []
        })

        cache.ensureLoaded(component: component)
        #expect(cache.isLoading(component: component))

        let liveParameters = [
            AudioUnitParameterInfo(address: 42, displayName: "Mix", groupName: "Global", minValue: 0, maxValue: 100, defaultValue: 50, unit: "%")
        ]
        cache.prime(component: component, parameters: liveParameters)

        #expect(cache.isLoading(component: component) == false)
        let resolved = cache.parameters(for: component)
        #expect(resolved?.count == 1)
        #expect(resolved?.first?.address == 42)
        #expect(resolved?.first?.displayName == "Mix")
    }

    @Test("track drill-down exposes actions and containers")
    @MainActor
    func trackDrillDownExposesActionsAndContainers() {
        let project = ProjectViewModel()
        project.newProject()
        project.addTrack(kind: .audio)
        let track = project.project.songs[0].tracks[0]
        _ = project.addContainer(trackID: track.id, startBar: 1, lengthBars: 4)
        let updatedTrack = project.project.songs[0].tracks.first(where: { $0.id == track.id })!

        let executor = CommandExecutor(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            ui: CommandPaletteUIActions(
                openMixer: {},
                openSetlists: {},
                openSongs: {},
                openSettings: {},
                focusTimeline: {},
                revealTarget: { _ in },
                requestTextInput: { _ in nil },
                inspectTrack: { _ in },
                inspectContainer: { _ in },
                openPianoRoll: { _ in },
                presentTrackAutomationPicker: { _ in },
                presentContainerAutomationPicker: { _ in }
            )
        )

        let builder = CommandPaletteCatalogBuilder(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            shortcutManager: ShortcutManager(userDefaults: UserDefaults(suiteName: #function) ?? .standard),
            executor: executor
        )

        let trackNode = builder.rootNodes().first(where: { $0.id == "track-\(updatedTrack.id.rawValue.uuidString)" })
        let trackChildren = trackNode?.childrenProvider?() ?? []

        #expect(trackChildren.contains(where: { $0.title == "Inspect Track" }))
        #expect(trackChildren.contains(where: { $0.title == "Add Effect" }))
        #expect(trackChildren.contains(where: { $0.title == "Effects" }))
        #expect(trackChildren.contains(where: { $0.title == "Add Automation" }))
        #expect(trackChildren.contains(where: { $0.title == "Browse Containers" }))

        let containerBranch = trackChildren.first(where: { $0.title == "Browse Containers" })
        let containerChildren = containerBranch?.childrenProvider?() ?? []
        #expect(containerChildren.contains(where: { $0.title == updatedTrack.containers[0].name }))
    }

    @Test("undo history drill-down exposes current and past actions")
    @MainActor
    func undoHistoryDrillDownExposesEntries() {
        let project = ProjectViewModel()
        project.undoState.undoHistory = [
            UndoHistoryEntry(actionName: "Add Track", isCurrent: false),
            UndoHistoryEntry(actionName: "Add Container", isCurrent: true),
            UndoHistoryEntry(actionName: "Toggle Mute", isCurrent: false),
        ]
        project.undoState.undoHistoryCursor = 1

        let executor = CommandExecutor(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            ui: CommandPaletteUIActions(
                openMixer: {},
                openSetlists: {},
                openSongs: {},
                openSettings: {},
                focusTimeline: {},
                revealTarget: { _ in },
                requestTextInput: { _ in nil },
                inspectTrack: { _ in },
                inspectContainer: { _ in },
                openPianoRoll: { _ in },
                presentTrackAutomationPicker: { _ in },
                presentContainerAutomationPicker: { _ in }
            )
        )

        let builder = CommandPaletteCatalogBuilder(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            shortcutManager: ShortcutManager(userDefaults: UserDefaults(suiteName: #function) ?? .standard),
            executor: executor
        )

        let historyNode = builder.rootNodes().first(where: { $0.id == "global-undo-history" })
        let historyChildren = historyNode?.childrenProvider?() ?? []

        #expect(historyChildren.count == 3)
        #expect(historyChildren.first?.title == "Toggle Mute")
        #expect(historyChildren.contains(where: { $0.title == "Add Container" && $0.badges.contains("Current") }))
    }

    @Test("add track flow drills into quantity and naming choices with defaults first")
    @MainActor
    func addTrackFlowIncludesQuantityChoices() {
        let project = ProjectViewModel()
        project.newProject()

        let executor = CommandExecutor(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            ui: CommandPaletteUIActions(
                openMixer: {},
                openSetlists: {},
                openSongs: {},
                openSettings: {},
                focusTimeline: {},
                revealTarget: { _ in },
                requestTextInput: { _ in nil },
                inspectTrack: { _ in },
                inspectContainer: { _ in },
                openPianoRoll: { _ in },
                presentTrackAutomationPicker: { _ in },
                presentContainerAutomationPicker: { _ in }
            )
        )

        let builder = CommandPaletteCatalogBuilder(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            shortcutManager: ShortcutManager(userDefaults: UserDefaults(suiteName: #function) ?? .standard),
            executor: executor
        )

        let addTrackNode = builder.rootNodes().first(where: { $0.id == "global-add-track" })
        let typeNodes = addTrackNode?.childrenProvider?() ?? []
        let audioTypeNode = typeNodes.first(where: { $0.title == "Add Audio Track" })
        let quantityNodes = audioTypeNode?.childrenProvider?() ?? []
        let oneTrackNode = quantityNodes.first(where: { $0.title == "Create 1 Track" })
        let namingNodes = oneTrackNode?.childEntryBuilder?().nodesProvider() ?? []

        #expect(quantityNodes.first?.title == "Create 1 Track")
        #expect(quantityNodes.first?.badges.contains("Default") == true)
        #expect(quantityNodes.contains(where: { $0.title == "Create 4 Tracks" }))
        #expect(quantityNodes.contains(where: { $0.title == "Custom Count…" }))
        #expect(namingNodes.first?.title == "Use Default Name")
        #expect(namingNodes.first?.badges.contains("Default") == true)
        #expect(namingNodes.contains(where: { $0.title == "Custom Name…" }))
    }

    @Test("global nodes surface configured shortcut labels")
    @MainActor
    func globalNodesShowConfiguredShortcuts() {
        let suiteName = #function
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let shortcutManager = ShortcutManager(userDefaults: defaults)
        _ = shortcutManager.setShortcut(AppKeyboardShortcut(key: "u", modifiers: [.command, .option]), for: .openMixer)

        let project = ProjectViewModel()
        let executor = CommandExecutor(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            ui: CommandPaletteUIActions(
                openMixer: {},
                openSetlists: {},
                openSongs: {},
                openSettings: {},
                focusTimeline: {},
                revealTarget: { _ in },
                requestTextInput: { _ in nil },
                inspectTrack: { _ in },
                inspectContainer: { _ in },
                openPianoRoll: { _ in },
                presentTrackAutomationPicker: { _ in },
                presentContainerAutomationPicker: { _ in }
            )
        )

        let builder = CommandPaletteCatalogBuilder(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            shortcutManager: shortcutManager,
            executor: executor
        )

        let mixerNode = builder.rootNodes().first(where: { $0.id == "global-open-mixer" })
        #expect(mixerNode?.shortcutDisplay == "⌥⌘U")
    }

    @Test("container automation drills into parameter multiselect and skips existing lanes")
    @MainActor
    func containerAutomationUsesInlineParameterMultiselect() {
        let project = ProjectViewModel()
        project.newProject()
        project.addTrack(kind: .audio)
        let track = project.project.songs[0].tracks[0]
        #expect(project.addContainer(trackID: track.id, startBar: 1, lengthBars: 4))
        let containerID = project.project.songs[0].tracks[0].containers[0].id
        let component = AudioComponentInfo(componentType: 1, componentSubType: 2, componentManufacturer: 3)
        project.addContainerEffect(
            containerID: containerID,
            effect: InsertEffect(component: component, displayName: "Filter", orderIndex: 0)
        )

        var existingLane = AutomationLane(
            targetPath: EffectPath(trackID: track.id, containerID: containerID, effectIndex: 0, parameterAddress: 10)
        )
        existingLane.effectName = "Filter"
        existingLane.parameterName = "Cutoff"
        project.addAutomationLane(containerID: containerID, lane: existingLane)

        let parameterCache = CommandPaletteParameterCache(provider: { _ in [] })
        parameterCache.prime(
            component: component,
            parameters: [
                AudioUnitParameterInfo(address: 10, displayName: "Cutoff", groupName: "Filter", minValue: 0, maxValue: 1, defaultValue: 0.5, unit: ""),
                AudioUnitParameterInfo(address: 11, displayName: "Resonance", groupName: "Filter", minValue: 0, maxValue: 1, defaultValue: 0.2, unit: ""),
            ]
        )

        let executor = makeExecutor(project: project)
        let builder = CommandPaletteCatalogBuilder(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            shortcutManager: ShortcutManager(userDefaults: UserDefaults(suiteName: #function) ?? .standard),
            parameterCache: parameterCache,
            executor: executor
        )

        let containerNode = builder.rootNodes().first(where: { $0.id == "container-\(containerID.rawValue.uuidString)" })
        let containerChildren = containerNode?.childrenProvider?() ?? []
        let addAutomationNode = containerChildren.first(where: { $0.title == "Add Automation" })
        let pluginNodes = addAutomationNode?.childrenProvider?() ?? []
        #expect(pluginNodes.first?.title == "Filter")

        let parameterEntry = pluginNodes.first?.childEntryBuilder?()
        let parameterNodes = parameterEntry?.nodesProvider() ?? []
        #expect(parameterEntry?.multiSelection != nil)
        #expect(parameterNodes.map { $0.title }.contains("Cutoff"))
        #expect(parameterNodes.map { $0.title }.contains("Resonance"))
        #expect(parameterNodes.first(where: { $0.title == "Cutoff" })?.badges.contains("Existing") == true)

        parameterEntry?.multiSelection?.commit(parameterNodes)

        let updatedContainer = project.project.songs[0].tracks[0].containers.first(where: { $0.id == containerID })
        #expect(updatedContainer?.automationLanes.count == 2)
        #expect(updatedContainer?.automationLanes.contains(where: { $0.parameterName == "Resonance" }) == true)
    }

    @Test("track automation drills into track effect parameters")
    @MainActor
    func trackAutomationUsesTrackEffectsPath() {
        let project = ProjectViewModel()
        project.newProject()
        project.addTrack(kind: .audio)
        let track = project.project.songs[0].tracks[0]
        let component = AudioComponentInfo(componentType: 101, componentSubType: 202, componentManufacturer: 303)
        project.addTrackEffect(
            trackID: track.id,
            effect: InsertEffect(component: component, displayName: "RVerb", orderIndex: 0)
        )

        let parameterCache = CommandPaletteParameterCache(provider: { _ in [] })
        parameterCache.prime(
            component: component,
            parameters: [
                AudioUnitParameterInfo(address: 1, displayName: "Mix", groupName: "Global", minValue: 0, maxValue: 100, defaultValue: 50, unit: "%"),
                AudioUnitParameterInfo(address: 2, displayName: "Decay", groupName: "Global", minValue: 0, maxValue: 10, defaultValue: 2.5, unit: "Secs"),
            ]
        )

        let builder = CommandPaletteCatalogBuilder(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            shortcutManager: ShortcutManager(userDefaults: UserDefaults(suiteName: #function) ?? .standard),
            parameterCache: parameterCache,
            executor: makeExecutor(project: project)
        )

        let trackNode = builder.rootNodes().first(where: { $0.id == "track-\(track.id.rawValue.uuidString)" })
        let trackChildren = trackNode?.childrenProvider?() ?? []

        let effectsNode = trackChildren.first(where: { $0.title == "Effects" })
        let effectNodes = effectsNode?.childrenProvider?() ?? []
        #expect(effectNodes.map(\.title).contains("RVerb"))

        let addAutomationNode = trackChildren.first(where: { $0.title == "Add Automation" })
        let pluginNodes = addAutomationNode?.childrenProvider?() ?? []
        #expect(pluginNodes.map(\.title).contains("RVerb"))

        let parameterEntry = pluginNodes.first(where: { $0.title == "RVerb" })?.childEntryBuilder?()
        let parameterNodes = parameterEntry?.nodesProvider() ?? []
        #expect(parameterEntry?.multiSelection != nil)
        #expect(parameterNodes.map(\.title).contains("Mix"))
        #expect(parameterNodes.map(\.title).contains("Decay"))
    }

    @Test("instrument destinations include new MIDI targets even when none exist")
    @MainActor
    func instrumentDestinationsIncludeCreateOptions() {
        let project = ProjectViewModel()
        project.newProject()
        project.addTrack(kind: .audio)

        let nexus = AudioUnitInfo(
            name: "Nexus",
            manufacturerName: "reFX",
            componentInfo: AudioComponentInfo(componentType: 1, componentSubType: 2, componentManufacturer: 3),
            componentType: 1
        )

        let builderWithoutMidi = CommandPaletteCatalogBuilder(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            shortcutManager: ShortcutManager(userDefaults: UserDefaults(suiteName: #function + ".withoutMidi") ?? .standard),
            audioUnitProvider: CommandPaletteAudioUnitProvider(
                effects: { [] },
                instruments: { [nexus] }
            ),
            executor: makeExecutor(project: project)
        )

        let nexusNode = builderWithoutMidi.rootNodes().first(where: { $0.id == "plugin-\(nexus.id)" })
        let addToTrackNode = nexusNode?.childrenProvider?().first(where: { $0.title == "Add Nexus to MIDI Track…" })
        let noMidiDestinations = addToTrackNode?.childrenProvider?() ?? []
        #expect(noMidiDestinations.map(\.title).contains("New MIDI Track"))

        project.addTrack(kind: .midi)
        let midiTrack = project.currentSong?.tracks.first(where: { $0.kind == .midi })

        let builderWithMidi = CommandPaletteCatalogBuilder(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            shortcutManager: ShortcutManager(userDefaults: UserDefaults(suiteName: #function + ".withMidi") ?? .standard),
            audioUnitProvider: CommandPaletteAudioUnitProvider(
                effects: { [] },
                instruments: { [nexus] }
            ),
            executor: makeExecutor(project: project)
        )

        let addToTrackNodeWithMidi = builderWithMidi.rootNodes()
            .first(where: { $0.id == "plugin-\(nexus.id)" })?
            .childrenProvider?()
            .first(where: { $0.title == "Add Nexus to MIDI Track…" })
        let midiDestinations = addToTrackNodeWithMidi?.childrenProvider?() ?? []
        #expect(midiDestinations.map(\.title).contains("New MIDI Track"))
        #expect(midiDestinations.map(\.title).contains(midiTrack?.name ?? ""))
    }

    @Test("effect destinations include new track and container creation options")
    @MainActor
    func effectDestinationsIncludeCreateOptions() {
        let project = ProjectViewModel()
        project.newProject()
        project.addTrack(kind: .audio)
        let audioTrack = project.currentSong?.tracks.first(where: { $0.kind == .audio })

        let rVerb = AudioUnitInfo(
            name: "RVerb",
            manufacturerName: "Waves",
            componentInfo: AudioComponentInfo(componentType: 10, componentSubType: 20, componentManufacturer: 30),
            componentType: 10
        )

        let builder = CommandPaletteCatalogBuilder(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            shortcutManager: ShortcutManager(userDefaults: UserDefaults(suiteName: #function) ?? .standard),
            audioUnitProvider: CommandPaletteAudioUnitProvider(
                effects: { [rVerb] },
                instruments: { [] }
            ),
            executor: makeExecutor(project: project)
        )

        let rVerbNode = builder.rootNodes().first(where: { $0.id == "plugin-\(rVerb.id)" })
        let pluginChildren = rVerbNode?.childrenProvider?() ?? []

        let addToTrackNode = pluginChildren.first(where: { $0.title == "Add RVerb to Track…" })
        let trackDestinations = addToTrackNode?.childrenProvider?() ?? []
        #expect(trackDestinations.map(\.title).contains("New Audio Track"))
        #expect(trackDestinations.map(\.title).contains("New MIDI Track"))
        #expect(trackDestinations.map(\.title).contains(audioTrack?.name ?? ""))

        let addToContainerNode = pluginChildren.first(where: { $0.title == "Add RVerb to Container…" })
        let containerDestinations = addToContainerNode?.childrenProvider?() ?? []
        #expect(containerDestinations.map(\.title).contains("New Audio Track + Container"))
        #expect(containerDestinations.map(\.title).contains("New MIDI Track + Container"))
        #expect(containerDestinations.map(\.title).contains("New Container on \(audioTrack?.name ?? "")"))
    }

    @Test("container action branches include enter and exit actions")
    @MainActor
    func containerActionBranchesIncludeLifecycleActions() {
        let project = ProjectViewModel()
        project.newProject()
        project.addTrack(kind: .audio)
        let track = project.project.songs[0].tracks[0]
        #expect(project.addContainer(trackID: track.id, startBar: 1, lengthBars: 4))
        let containerID = project.project.songs[0].tracks[0].containers[0].id

        let executor = makeExecutor(project: project)
        let builder = CommandPaletteCatalogBuilder(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            shortcutManager: ShortcutManager(userDefaults: UserDefaults(suiteName: #function) ?? .standard),
            executor: executor
        )

        let containerNode = builder.rootNodes().first(where: { $0.id == "container-\(containerID.rawValue.uuidString)" })
        let containerChildren = containerNode?.childrenProvider?() ?? []
        #expect(containerChildren.contains(where: { $0.title == "Enter Actions" }))
        #expect(containerChildren.contains(where: { $0.title == "Exit Actions" }))
    }

    @Test("automation parameter branch resolves live cache updates after loading")
    @MainActor
    func automationParameterBranchRefreshesAfterCacheLoad() {
        let project = ProjectViewModel()
        project.newProject()
        project.addTrack(kind: .audio)
        let track = project.project.songs[0].tracks[0]
        #expect(project.addContainer(trackID: track.id, startBar: 1, lengthBars: 4))
        let containerID = project.project.songs[0].tracks[0].containers[0].id
        let component = AudioComponentInfo(componentType: 10, componentSubType: 20, componentManufacturer: 30)
        project.addContainerEffect(
            containerID: containerID,
            effect: InsertEffect(component: component, displayName: "Delay", orderIndex: 0)
        )

        let parameterCache = CommandPaletteParameterCache(provider: { _ in [] })
        let builder = CommandPaletteCatalogBuilder(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            shortcutManager: ShortcutManager(userDefaults: UserDefaults(suiteName: #function) ?? .standard),
            parameterCache: parameterCache,
            executor: makeExecutor(project: project)
        )

        let containerNode = builder.rootNodes().first(where: { $0.id == "container-\(containerID.rawValue.uuidString)" })
        let addAutomationNode = containerNode?.childrenProvider?().first(where: { $0.title == "Add Automation" })
        let pluginNode = addAutomationNode?.childrenProvider?().first(where: { $0.title == "Delay" })
        let parameterEntry = pluginNode?.childEntryBuilder?()

        #expect(parameterEntry?.nodesProvider().first?.title == "Loading Parameters…")

        parameterCache.prime(
            component: component,
            parameters: [
                AudioUnitParameterInfo(address: 1, displayName: "Feedback", groupName: "Delay", minValue: 0, maxValue: 1, defaultValue: 0.5, unit: "")
            ]
        )

        #expect(parameterEntry?.nodesProvider().first?.title == "Feedback")
    }

    @MainActor
    private func makeExecutor(project: ProjectViewModel) -> CommandExecutor {
        CommandExecutor(
            projectViewModel: project,
            timelineViewModel: TimelineViewModel(),
            transportViewModel: nil,
            ui: CommandPaletteUIActions(
                openMixer: {},
                openSetlists: {},
                openSongs: {},
                openSettings: {},
                focusTimeline: {},
                revealTarget: { _ in },
                requestTextInput: { _ in nil },
                inspectTrack: { _ in },
                inspectContainer: { _ in },
                openPianoRoll: { _ in },
                presentTrackAutomationPicker: { _ in },
                presentContainerAutomationPicker: { _ in }
            )
        )
    }
}
