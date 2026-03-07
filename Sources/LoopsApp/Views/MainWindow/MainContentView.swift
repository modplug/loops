import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LoopsCore
import LoopsEngine

/// Sidebar tab selection.
public enum SidebarTab: String, CaseIterable {
    case songs = "Songs"
    case setlists = "Setlists"
}

/// Inspector mode selection.
public enum InspectorMode: String, CaseIterable {
    case container = "Container"
    case storyline = "Storyline"
}

/// Content area mode: timeline (default) or mixer.
public enum ContentMode: String, CaseIterable {
    case timeline = "Timeline"
    case mixer = "Mixer"
}

/// Tracks whether the main content area has keyboard focus.
/// When focus moves to a text field, `focusedField` becomes nil and shortcuts are suppressed.
public enum FocusedField: Hashable {
    case main
}

extension Notification.Name {
    static let loopsRequestMainContentFocus = Notification.Name("loops.requestMainContentFocus")
    static let loopsOpenCommandPalette = Notification.Name("loops.openCommandPalette")
    static let loopsOpenAddTrackFlow = Notification.Name("loops.openAddTrackFlow")
    static let loopsOpenUndoHistory = Notification.Name("loops.openUndoHistory")
    static let loopsOpenMixer = Notification.Name("loops.openMixer")
    static let loopsOpenSetlists = Notification.Name("loops.openSetlists")
    static let loopsGoToCurrentSong = Notification.Name("loops.goToCurrentSong")
    static let loopsOpenSettings = Notification.Name("loops.openSettings")
    static let loopsToggleSelectedContainerArm = Notification.Name("loops.toggleSelectedContainerArm")
}

/// Main content area using HSplitView: sidebar + timeline/mixer + inspector.
public struct MainContentView: View {
    @Bindable var projectViewModel: ProjectViewModel
    @Bindable var timelineViewModel: TimelineViewModel
    var selectionState: SelectionState
    var clipboardState: ClipboardState
    var transportViewModel: TransportViewModel?
    var setlistViewModel: SetlistViewModel?
    var engineManager: AudioEngineManager?
    var settingsViewModel: SettingsViewModel?
    var mixerViewModel: MixerViewModel?
    var midiActivityMonitor: MIDIActivityMonitor?
    var shortcutManager: ShortcutManager
    @Binding var isVirtualKeyboardVisible: Bool
    @State private var contentMode: ContentMode = .timeline
    @State private var trackToDelete: Track?
    @State private var editingTrackID: ID<Track>?
    @State private var editingTrackName: String = ""
    @State private var isSidebarVisible: Bool = true
    @State private var sidebarTab: SidebarTab = .songs
    @State private var showContainerDetailEditor: Bool = false
    @State private var pianoRollSnapResolution: SnapResolution = .sixteenth
    @State private var editingSectionID: ID<SectionRegion>?
    @State private var editingSectionName: String = ""
    @State private var inspectorMode: InspectorMode = .container
    @State private var draggingTrackID: ID<Track>?
    @State private var headerDragStartWidth: CGFloat = 0
    @State private var pendingTrackAutomationLane: PendingEffectSelection?
    @State private var pendingContainerAutomationLane: PendingEffectSelection?
    @State private var pianoRollEditorState = PianoRollEditorState()
    @State private var liveTrackHeightPreviews: [ID<Track>: CGFloat] = [:]
    @State private var horizontalScrollCoordinator = TimelineHorizontalScrollCoordinator()
    @State private var timelineVerticalScrollView: NSScrollView?
    @State private var ghostDropState = GhostTrackDropState()
    @State private var showTempoImportAlert = false
    @State private var pendingTempoImport: PendingTempoImport?
    @State private var showSettingsSheet = false
    @State private var previewState = PreviewState()
    @State private var commandPaletteViewModel: CommandPaletteViewModel?
    @FocusState private var focusedField: FocusedField?
    @Namespace private var inspectorNamespace
    // isMIDILearning and midiLearnTargetPath are on projectViewModel.midiLearnState

    /// Returns true when keyboard focus has moved away from the main content area
    /// (e.g. to a text field in the inspector panel).
    private var isTextFieldFocused: Bool {
        focusedField != .main
    }

    private var isPianoRollFocused: Bool {
        pianoRollEditorState.isFocused
    }

    private var isCommandPalettePresented: Bool {
        commandPaletteViewModel?.isPresented == true
    }

    private var isEditingTextInput: Bool {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        return textView.isEditable
    }

    public init(projectViewModel: ProjectViewModel, timelineViewModel: TimelineViewModel, selectionState: SelectionState? = nil, clipboardState: ClipboardState? = nil, transportViewModel: TransportViewModel? = nil, setlistViewModel: SetlistViewModel? = nil, engineManager: AudioEngineManager? = nil, settingsViewModel: SettingsViewModel? = nil, mixerViewModel: MixerViewModel? = nil, midiActivityMonitor: MIDIActivityMonitor? = nil, shortcutManager: ShortcutManager? = nil, isVirtualKeyboardVisible: Binding<Bool> = .constant(false)) {
        self.projectViewModel = projectViewModel
        self.timelineViewModel = timelineViewModel
        self.selectionState = selectionState ?? projectViewModel.selectionState
        self.clipboardState = clipboardState ?? projectViewModel.clipboardState
        self.transportViewModel = transportViewModel
        self.setlistViewModel = setlistViewModel
        self.engineManager = engineManager
        self.settingsViewModel = settingsViewModel
        self.mixerViewModel = mixerViewModel
        self.midiActivityMonitor = midiActivityMonitor
        self.shortcutManager = shortcutManager ?? ShortcutManager()
        self._isVirtualKeyboardVisible = isVirtualKeyboardVisible
    }

    private var currentSong: Song? {
        projectViewModel.currentSong
    }

    @ViewBuilder
    private var containerDetailEditorSheet: some View {
        if let container = projectViewModel.selectedContainer,
           let track = projectViewModel.selectedContainerTrack {
            let parentContainer = container.parentContainerID.flatMap { projectViewModel.findContainer(id: $0) }
            let displayContainer = parentContainer.map { container.resolved(parent: $0) } ?? container
            ContainerDetailEditor(
                container: displayContainer,
                trackKind: track.kind,
                containerTrack: track,
                allContainers: projectViewModel.allContainersInCurrentSong,
                allTracks: projectViewModel.allTracksInCurrentSong,
                onAddEffect: { effect in
                    projectViewModel.addContainerEffect(containerID: container.id, effect: effect)
                    PluginWindowManager.shared.open(
                        component: effect.component,
                        displayName: effect.displayName,
                        presetData: nil,
                        onPresetChanged: { data in
                            projectViewModel.updateContainerEffectPreset(containerID: container.id, effectID: effect.id, presetData: data)
                        }
                    )
                },
                onRemoveEffect: { effectID in
                    projectViewModel.removeContainerEffect(containerID: container.id, effectID: effectID)
                },
                onToggleEffectBypass: { effectID in
                    projectViewModel.toggleContainerEffectBypass(containerID: container.id, effectID: effectID)
                },
                onToggleChainBypass: {
                    projectViewModel.toggleContainerEffectChainBypass(containerID: container.id)
                },
                onReorderEffects: { source, destination in
                    projectViewModel.reorderContainerEffects(containerID: container.id, from: source, to: destination)
                },
                onSetInstrumentOverride: { override in
                    projectViewModel.setContainerInstrumentOverride(containerID: container.id, override: override)
                },
                onAddEnterAction: { action in
                    projectViewModel.addContainerEnterAction(containerID: container.id, action: action)
                },
                onRemoveEnterAction: { actionID in
                    projectViewModel.removeContainerEnterAction(containerID: container.id, actionID: actionID)
                },
                onAddExitAction: { action in
                    projectViewModel.addContainerExitAction(containerID: container.id, action: action)
                },
                onRemoveExitAction: { actionID in
                    projectViewModel.removeContainerExitAction(containerID: container.id, actionID: actionID)
                },
                onAddAutomationLane: { lane in
                    projectViewModel.addAutomationLane(containerID: container.id, lane: lane)
                },
                onRemoveAutomationLane: { laneID in
                    projectViewModel.removeAutomationLane(containerID: container.id, laneID: laneID)
                },
                onAddBreakpoint: { laneID, breakpoint in
                    projectViewModel.addAutomationBreakpoint(containerID: container.id, laneID: laneID, breakpoint: breakpoint)
                },
                onRemoveBreakpoint: { laneID, breakpointID in
                    projectViewModel.removeAutomationBreakpoint(containerID: container.id, laneID: laneID, breakpointID: breakpointID)
                },
                onUpdateBreakpoint: { laneID, breakpoint in
                    projectViewModel.updateAutomationBreakpoint(containerID: container.id, laneID: laneID, breakpoint: breakpoint)
                },
                onSetEnterFade: { fade in
                    projectViewModel.setContainerEnterFade(containerID: container.id, fade: fade)
                },
                onSetExitFade: { fade in
                    projectViewModel.setContainerExitFade(containerID: container.id, fade: fade)
                },
                onUpdateEffectPreset: { effectID, data in
                    projectViewModel.updateContainerEffectPreset(containerID: container.id, effectID: effectID, presetData: data)
                },
                liveEffectUnit: { index in
                    transportViewModel?.liveEffectUnit(containerID: container.id, effectIndex: index)
                },
                isEffectChainFailed: transportViewModel?.failedContainerIDs.contains(container.id) ?? false,
                onDismiss: {
                    showContainerDetailEditor = false
                }
            )
        }
    }

    /// Opens the appropriate editor for the selected container.
    /// MIDI containers on MIDI tracks toggle inline piano roll; others open the detail editor.
    private func openContainerEditor() {
        guard let container = projectViewModel.selectedContainer,
              let track = projectViewModel.selectedContainerTrack else { return }
        if track.kind == .midi {
            // Resolve clone inheritance before checking for MIDI data
            let resolved = projectViewModel.resolveContainer(container)
            if resolved.midiSequence == nil {
                projectViewModel.setContainerMIDISequence(
                    containerID: container.id,
                    sequence: MIDISequence()
                )
            }
            // Toggle inline piano roll
            pianoRollEditorState.toggle(containerID: container.id, trackID: track.id)
            // Ensure engine is ready for note preview
            transportViewModel?.ensureEngineReadyForPreview()
        } else {
            showContainerDetailEditor = true
        }
    }

    /// Opens the piano roll in a pop-out NSWindow.
    private func openPianoRollSheet() {
        guard let container = projectViewModel.selectedContainer,
              let track = projectViewModel.selectedContainerTrack,
              let song = projectViewModel.currentSong,
              track.kind == .midi else { return }
        // Resolve clone inheritance before checking for MIDI data
        let resolved = projectViewModel.resolveContainer(container)
        if resolved.midiSequence == nil {
            projectViewModel.setContainerMIDISequence(
                containerID: container.id,
                sequence: MIDISequence()
            )
        }
        transportViewModel?.ensureEngineReadyForPreview()
        let content = LivePianoRollWindowContent(
            projectViewModel: projectViewModel,
            containerID: container.id,
            trackID: track.id,
            timeSignature: song.timeSignature,
            snapResolution: pianoRollSnapResolution,
            transportViewModel: transportViewModel,
            onDismiss: {
                PianoRollWindowManager.shared.close()
            }
        )
        PianoRollWindowManager.shared.open(
            content: content,
            title: "Piano Roll — \(container.name)",
            trackID: track.id
        )
    }

    private func buildCommandPaletteNodes() -> [CommandNode] {
        let ui = CommandPaletteUIActions(
            openMixer: {
                contentMode = .mixer
            },
            openSetlists: {
                isSidebarVisible = true
                sidebarTab = .setlists
            },
            openSongs: {
                isSidebarVisible = true
                sidebarTab = .songs
            },
            openSettings: {
                showSettingsSheet = true
            },
            focusTimeline: {
                contentMode = .timeline
            },
            revealTarget: { target in
                makeRevealCoordinator().revealCommitted(target: target)
            },
            requestTextInput: { request in
                promptForTextInput(request)
            },
            inspectTrack: { trackID in
                selectionState.selectedTrackID = trackID
                selectionState.selectedContainerID = nil
                inspectorMode = .container
                contentMode = .timeline
            },
            inspectContainer: { containerID in
                selectionState.selectedContainerID = containerID
                selectionState.selectedTrackID = nil
                inspectorMode = .container
                contentMode = .timeline
            },
            openPianoRoll: { containerID in
                selectionState.selectedContainerID = containerID
                selectionState.selectedTrackID = nil
                openPianoRollSheet()
            },
            presentTrackAutomationPicker: { pending in
                pendingTrackAutomationLane = pending
            },
            presentContainerAutomationPicker: { pending in
                pendingContainerAutomationLane = pending
            }
        )

        let executor = CommandExecutor(
            projectViewModel: projectViewModel,
            timelineViewModel: timelineViewModel,
            transportViewModel: transportViewModel,
            ui: ui
        )
        let builder = CommandPaletteCatalogBuilder(
            projectViewModel: projectViewModel,
            timelineViewModel: timelineViewModel,
            transportViewModel: transportViewModel,
            shortcutManager: shortcutManager,
            executor: executor
        )
        return builder.rootNodes()
    }

    private func makeRevealCoordinator() -> RevealCoordinator {
        RevealCoordinator(
            projectViewModel: projectViewModel,
            timelineViewModel: timelineViewModel,
            previewState: previewState,
            currentContentMode: { contentMode },
            setContentMode: { contentMode = $0 },
            horizontalOffset: { horizontalScrollCoordinator.scrollView?.contentView.bounds.origin.x ?? 0 },
            setHorizontalOffset: { horizontalScrollCoordinator.setOffset($0) },
            verticalOffset: { timelineVerticalScrollView?.contentView.bounds.origin.y ?? 0 },
            setVerticalOffset: { offset in
                guard let scrollView = timelineVerticalScrollView else { return }
                let y = max(0, offset)
                scrollView.contentView.setBoundsOrigin(NSPoint(x: scrollView.contentView.bounds.origin.x, y: y))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        )
    }

    private func requestMainContentFocus() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
            focusedField = .main
        }
    }

    private func openCommandPalette(path nodeIDs: [String] = []) {
        requestMainContentFocus()
        commandPaletteViewModel?.open(path: nodeIDs)
    }

    private func toggleSelectedContainerArm() {
        guard let container = projectViewModel.selectedContainer,
              let track = projectViewModel.selectedContainerTrack else { return }
        projectViewModel.toggleContainerRecordArm(trackID: track.id, containerID: container.id)
    }

    private func promptForTextInput(_ request: CommandPaletteTextInputRequest) -> String? {
        let alert = NSAlert()
        alert.messageText = request.title
        alert.informativeText = request.message
        alert.alertStyle = .informational

        let textField = NSTextField(string: request.initialValue)
        textField.placeholderString = request.placeholder
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = textField
        alert.addButton(withTitle: request.actionTitle)
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return textField.stringValue
    }

    private func shouldShowCommandPaletteToast(for node: CommandNode) -> Bool {
        if node.id == "global-undo" || node.id == "global-redo" || node.id.hasPrefix("undo-history-") {
            return false
        }
        return true
    }

    public var body: some View {
        let _ = PlaybackGridPerfLogger.tick("swiftui.mainContentView.body")
        let baseContent = ZStack {
            mainSplitView
            if let commandPaletteViewModel {
                CommandPaletteView(viewModel: commandPaletteViewModel)
            }
        }
        let presentedContent = baseContent
        .sheet(isPresented: $showContainerDetailEditor) {
            containerDetailEditorSheet
        }
        .sheet(isPresented: $showSettingsSheet) {
            if let settingsViewModel {
                AudioDeviceView(viewModel: settingsViewModel, shortcutManager: shortcutManager)
            } else {
                Text("Settings unavailable")
                    .frame(minWidth: 420, minHeight: 320)
            }
        }
        .sheet(item: $pendingTrackAutomationLane) { pending in
            ParameterPickerView(
                pending: pending,
                onPick: { path, paramInfo in
                    var lane = AutomationLane(targetPath: path)
                    lane.effectName = pending.effectName
                    lane.parameterName = paramInfo.displayName
                    lane.parameterMin = paramInfo.minValue
                    lane.parameterMax = paramInfo.maxValue
                    lane.parameterUnit = paramInfo.unit
                    projectViewModel.addTrackAutomationLane(trackID: path.trackID, lane: lane)
                    timelineViewModel.automationExpanded.insert(path.trackID)
                    pendingTrackAutomationLane = nil
                },
                onCancel: { pendingTrackAutomationLane = nil }
            )
        }
        .sheet(item: $pendingContainerAutomationLane) { pending in
            ParameterPickerView(
                pending: pending,
                onPick: { path, paramInfo in
                    var lane = AutomationLane(targetPath: path)
                    lane.effectName = pending.effectName
                    lane.parameterName = paramInfo.displayName
                    lane.parameterMin = paramInfo.minValue
                    lane.parameterMax = paramInfo.maxValue
                    lane.parameterUnit = paramInfo.unit
                    if let containerID = path.containerID {
                        projectViewModel.addAutomationLane(containerID: containerID, lane: lane)
                    }
                    pendingContainerAutomationLane = nil
                },
                onCancel: { pendingContainerAutomationLane = nil }
            )
        }
        .alert("Import Tempo", isPresented: $showTempoImportAlert) {
            Button("Keep Current", role: .cancel) {
                pendingTempoImport = nil
            }
            Button("Import Tempo") {
                if let pending = pendingTempoImport,
                   let songID = projectViewModel.currentSong?.id {
                    projectViewModel.setBPM(songID: songID, bpm: pending.bpm)
                }
                pendingTempoImport = nil
            }
        } message: {
            if let pending = pendingTempoImport {
                Text("This MIDI file contains tempo information (\(Int(pending.bpm)) BPM). Import tempo?")
            }
        }
        .alert("Delete Track", isPresented: .init(
            get: { trackToDelete != nil },
            set: { if !$0 { trackToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { trackToDelete = nil }
            Button("Delete", role: .destructive) {
                if let track = trackToDelete {
                    projectViewModel.removeTrack(id: track.id)
                    trackToDelete = nil
                }
            }
        } message: {
            if let track = trackToDelete {
                Text("Are you sure you want to delete \"\(track.name)\"?")
            }
        }
        .popover(isPresented: .init(
            get: { editingSectionID != nil },
            set: { if !$0 { commitSectionRename() } }
        )) {
            VStack(spacing: 8) {
                Text("Rename Section")
                    .font(.headline)
                TextField("Section name", text: $editingSectionName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit { commitSectionRename() }
                HStack {
                    Button("Cancel") {
                        editingSectionID = nil
                    }
                    Button("OK") {
                        commitSectionRename()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: { withAnimation { isSidebarVisible.toggle() } }) {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar")
                .keyboardShortcut("s", modifiers: [.command, .option])
            }
            ToolbarItem(placement: .primaryAction) {
                if let setlistVM = setlistViewModel, setlistVM.selectedSetlist != nil {
                    Button(action: { setlistVM.enterPerformMode() }) {
                        Label("Perform", systemImage: "play.rectangle.fill")
                    }
                    .help("Enter Perform Mode")
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focusedField, equals: .main)
        let lifecycleContent = presentedContent
        .onAppear {
            requestMainContentFocus()
            if commandPaletteViewModel == nil {
                let vm = CommandPaletteViewModel(rootProvider: { buildCommandPaletteNodes() })
                vm.onPreviewNode = { node in
                    makeRevealCoordinator().preview(node: node)
                }
                vm.onExecuteNode = { node in
                    guard shouldShowCommandPaletteToast(for: node) else { return }
                    projectViewModel.undoState.showToast(node.title)
                }
                vm.onClose = { committed in
                    makeRevealCoordinator().clear(committed: committed)
                }
                commandPaletteViewModel = vm
            }
        }
        .onChange(of: projectViewModel.currentSongID) { _, _ in
            requestMainContentFocus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .loopsRequestMainContentFocus)) { _ in
            requestMainContentFocus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .loopsOpenCommandPalette)) { _ in
            openCommandPalette()
        }
        .onReceive(NotificationCenter.default.publisher(for: .loopsOpenAddTrackFlow)) { _ in
            openCommandPalette(path: ["global-add-track"])
        }
        .onReceive(NotificationCenter.default.publisher(for: .loopsOpenUndoHistory)) { _ in
            openCommandPalette(path: ["global-undo-history"])
        }
        .onReceive(NotificationCenter.default.publisher(for: .loopsOpenMixer)) { _ in
            contentMode = .mixer
        }
        .onReceive(NotificationCenter.default.publisher(for: .loopsOpenSetlists)) { _ in
            isSidebarVisible = true
            sidebarTab = .setlists
        }
        .onReceive(NotificationCenter.default.publisher(for: .loopsGoToCurrentSong)) { _ in
            isSidebarVisible = true
            sidebarTab = .songs
            if let songID = projectViewModel.currentSongID {
                projectViewModel.selectSong(id: songID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .loopsOpenSettings)) { _ in
            showSettingsSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .loopsToggleSelectedContainerArm)) { _ in
            toggleSelectedContainerArm()
        }
        .onReceive(NotificationCenter.default.publisher(for: .loopsCommandPaletteParametersDidChange)) { _ in
            commandPaletteViewModel?.refresh()
        }
        .inlineMIDIInputMonitor(
            shouldHandle: {
                pianoRollEditorState.isExpanded
                    && pianoRollEditorState.trackID != nil
                    && !isTextFieldFocused
            },
            onZoomIn: {
                guard let trackID = pianoRollEditorState.trackID else { return }
                adjustInlineMIDIRowHeight(for: trackID, delta: 1.5)
            },
            onZoomOut: {
                guard let trackID = pianoRollEditorState.trackID else { return }
                adjustInlineMIDIRowHeight(for: trackID, delta: -1.5)
            },
            onMagnify: { magnification in
                guard let trackID = pianoRollEditorState.trackID else { return }
                adjustInlineMIDIRowHeight(
                    for: trackID,
                    delta: max(-8.0, min(8.0, magnification * 24.0))
                )
            }
        )
        return lifecycleContent
        .globalShortcutMonitor(shortcutManager: shortcutManager) { action in
            switch action {
            case .addSong:
                projectViewModel.addSong()
            case .addTrack:
                openCommandPalette(path: ["global-add-track"])
            case .undo:
                projectViewModel.undoManager?.undo()
            case .redo:
                projectViewModel.undoManager?.redo()
            case .undoHistory:
                openCommandPalette(path: ["global-undo-history"])
            case .findEverything:
                openCommandPalette()
            case .openMixer:
                contentMode = .mixer
            case .openSetlists:
                isSidebarVisible = true
                sidebarTab = .setlists
            case .goToCurrentSong:
                isSidebarVisible = true
                sidebarTab = .songs
                if let songID = projectViewModel.currentSongID {
                    projectViewModel.selectSong(id: songID)
                }
            case .toggleContainerArm:
                toggleSelectedContainerArm()
            case .openSettings:
                showSettingsSheet = true
            default:
                break
            }
        } shouldHandle: { action in
            switch action {
            case .undo, .redo:
                return !isEditingTextInput
            case .newProject, .openProject, .saveProject, .saveProjectAs, .exportAudio:
                return false
            default:
                return true
            }
        }
        .onKeyPress(.space) {
            guard !isCommandPalettePresented else { return .ignored }
            guard !isTextFieldFocused else { return .ignored }
            transportViewModel?.togglePlayPause()
            return .handled
        }
        .onKeyPress(.return) {
            guard !isCommandPalettePresented else { return .ignored }
            guard !isTextFieldFocused else { return .ignored }
            if projectViewModel.selectedContainer != nil {
                openContainerEditor()
                return .handled
            }
            return .ignored
        }
        // Cmd+Return: open piano roll in pop-out sheet window
        .onKeyPress(.return, phases: .down) { keyPress in
            guard !isCommandPalettePresented else { return .ignored }
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            guard !isTextFieldFocused else { return .ignored }
            openPianoRollSheet()
            return .handled
        }
        .onKeyPress("+") {
            guard !isCommandPalettePresented else { return .ignored }
            guard !isTextFieldFocused else { return .ignored }
            if pianoRollEditorState.isExpanded, let trackID = pianoRollEditorState.trackID {
                adjustInlineMIDIRowHeight(for: trackID, delta: 1.5)
                return .handled
            }
            timelineViewModel.zoomIn()
            return .handled
        }
        .onKeyPress("=") {
            guard !isCommandPalettePresented else { return .ignored }
            guard !isTextFieldFocused else { return .ignored }
            if pianoRollEditorState.isExpanded, let trackID = pianoRollEditorState.trackID {
                adjustInlineMIDIRowHeight(for: trackID, delta: 1.5)
                return .handled
            }
            timelineViewModel.zoomIn()
            return .handled
        }
        .onKeyPress("-") {
            guard !isCommandPalettePresented else { return .ignored }
            guard !isTextFieldFocused else { return .ignored }
            if pianoRollEditorState.isExpanded, let trackID = pianoRollEditorState.trackID {
                adjustInlineMIDIRowHeight(for: trackID, delta: -1.5)
                return .handled
            }
            timelineViewModel.zoomOut()
            return .handled
        }
        .onKeyPress("c", phases: .down) { keyPress in
            guard !isCommandPalettePresented else { return .ignored }
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            handleCopy()
            return .handled
        }
        .onKeyPress("v", phases: .down) { keyPress in
            guard !isCommandPalettePresented else { return .ignored }
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            handlePaste()
            return .handled
        }
        // R: toggle record arm on selected track
        .onKeyPress("r") {
            guard !isCommandPalettePresented else { return .ignored }
            guard !isTextFieldFocused else { return .ignored }
            guard let trackID = selectionState.selectedTrackID else { return .ignored }
            if let track = currentSong?.tracks.first(where: { $0.id == trackID }) {
                projectViewModel.setTrackRecordArmed(trackID: trackID, armed: !track.isRecordArmed)
                return .handled
            }
            return .ignored
        }
        // M: toggle metronome
        .onKeyPress("m") {
            guard !isCommandPalettePresented else { return .ignored }
            guard !isTextFieldFocused else { return .ignored }
            transportViewModel?.toggleMetronome()
            return .handled
        }
        // Left arrow: nudge playhead -1 bar (defers to piano roll when focused)
        .onKeyPress(.leftArrow) {
            guard !isCommandPalettePresented else { return .ignored }
            guard !isTextFieldFocused, !isPianoRollFocused else { return .ignored }
            guard let tv = transportViewModel else { return .ignored }
            tv.setPlayheadPosition(max(tv.playheadBar - 1.0, 1.0))
            return .handled
        }
        // Right arrow: nudge playhead +1 bar (defers to piano roll when focused)
        .onKeyPress(.rightArrow) {
            guard !isCommandPalettePresented else { return .ignored }
            guard !isTextFieldFocused, !isPianoRollFocused else { return .ignored }
            guard let tv = transportViewModel else { return .ignored }
            tv.setPlayheadPosition(tv.playheadBar + 1.0)
            return .handled
        }
        // Home (Fn+Left): jump to bar 1
        .onKeyPress(.home) {
            guard !isCommandPalettePresented else { return .ignored }
            guard !isTextFieldFocused else { return .ignored }
            transportViewModel?.setPlayheadPosition(1.0)
            return .handled
        }
        // End (Fn+Right): jump to last bar with content
        .onKeyPress(.end) {
            guard !isCommandPalettePresented else { return .ignored }
            guard !isTextFieldFocused else { return .ignored }
            let lastBar = Double(projectViewModel.lastBarWithContent)
            transportViewModel?.setPlayheadPosition(lastBar)
            return .handled
        }
        // 1-9: select track by index
        .onKeyPress("1") { selectTrackByKeyIndex(0) }
        .onKeyPress("2") { selectTrackByKeyIndex(1) }
        .onKeyPress("3") { selectTrackByKeyIndex(2) }
        .onKeyPress("4") { selectTrackByKeyIndex(3) }
        .onKeyPress("5") { selectTrackByKeyIndex(4) }
        .onKeyPress("6") { selectTrackByKeyIndex(5) }
        .onKeyPress("7") { selectTrackByKeyIndex(6) }
        .onKeyPress("8") { selectTrackByKeyIndex(7) }
        .onKeyPress("9") { selectTrackByKeyIndex(8) }
        // Cmd+E: split selected container at playhead
        .onKeyPress("e", phases: .down) { keyPress in
            guard !isCommandPalettePresented else { return .ignored }
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            handleSplitAtPlayhead()
            return .handled
        }
        // Cmd+Shift+X: split selected container at range selection boundaries
        .onKeyPress("x", phases: .down) { keyPress in
            guard !isCommandPalettePresented else { return .ignored }
            guard keyPress.modifiers.contains(.command),
                  keyPress.modifiers.contains(.shift) else { return .ignored }
            handleSplitAtRange()
            return .handled
        }
        // Cmd+J: glue selected containers
        .onKeyPress("j", phases: .down) { keyPress in
            guard !isCommandPalettePresented else { return .ignored }
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            projectViewModel.glueContainers(containerIDs: projectViewModel.selectedContainerIDs)
            return .handled
        }
        // Cmd+D: duplicate selected container (or track if no container selected)
        .onKeyPress("d", phases: .down) { keyPress in
            guard !isCommandPalettePresented else { return .ignored }
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            handleDuplicate()
            return .handled
        }
        // Cmd+A: select all containers
        .onKeyPress("a", phases: .down) { keyPress in
            guard !isCommandPalettePresented else { return .ignored }
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            projectViewModel.selectAllContainers()
            return .handled
        }
        // Escape: unfocus piano roll → deselect all + restore focus to main area
        .onKeyPress(.escape) {
            guard !isCommandPalettePresented else { return .ignored }
            if isTextFieldFocused {
                focusedField = .main
                return .handled
            }
            if isPianoRollFocused {
                pianoRollEditorState.isFocused = false
                return .handled
            }
            selectionState.deselectAll()
            timelineViewModel.selectedTrackIDs = []
            timelineViewModel.clearSelectedRange()
            return .handled
        }
        // Tab: cycle inspector mode
        .onKeyPress(.tab) {
            guard !isCommandPalettePresented else { return .ignored }
            guard !isTextFieldFocused else { return .ignored }
            cycleInspectorMode()
            return .handled
        }
        // Cmd+Shift+M: toggle mixer view
        .onKeyPress("m", phases: .down) { keyPress in
            guard !isCommandPalettePresented else { return .ignored }
            guard keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.shift) else { return .ignored }
            contentMode = contentMode == .timeline ? .mixer : .timeline
            return .handled
        }
        // Cmd+Shift+L: toggle MIDI log window
        .onKeyPress("l", phases: .down) { keyPress in
            guard !isCommandPalettePresented else { return .ignored }
            guard keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.shift) else { return .ignored }
            if let monitor = midiActivityMonitor {
                MIDILogWindowManager.shared.toggle(monitor: monitor)
            }
            return .handled
        }
        // Cmd+Shift+K: toggle virtual MIDI keyboard
        .onKeyPress("k", phases: .down) { keyPress in
            guard !isCommandPalettePresented else { return .ignored }
            guard keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.shift) else { return .ignored }
            isVirtualKeyboardVisible.toggle()
            return .handled
        }
    }

    // MARK: - Main Split View

    private var mainSplitView: some View {
        HSplitView {
            if isSidebarVisible {
                sidebarContent
            }
            centerContent
            inspectorPanel
        }
    }

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            Picker("", selection: $sidebarTab) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            switch sidebarTab {
            case .songs:
                SongListView(viewModel: projectViewModel)
            case .setlists:
                if let setlistVM = setlistViewModel {
                    SetlistSidebarView(viewModel: setlistVM, timelineViewModel: timelineViewModel)
                } else {
                    Text("Setlists unavailable")
                        .foregroundStyle(.secondary)
                        .padding()
                    Spacer()
                }
            }
        }
        .frame(minWidth: 150, idealWidth: 200, maxWidth: 250)
    }

    @ViewBuilder
    private var centerContent: some View {
        if let song = currentSong {
            VStack(spacing: 0) {
                HStack {
                    Picker("", selection: $contentMode) {
                        ForEach(ContentMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    Spacer()
                }
                Divider()

                switch contentMode {
                case .timeline:
                    timelineContent(song: song)
                case .mixer:
                    mixerContent(song: song)
                }

                // Virtual MIDI keyboard (docked at bottom)
                if isVirtualKeyboardVisible {
                    Divider()
                    VirtualKeyboardView(
                        onNoteEvent: { message in
                            guard let trackID = selectionState.selectedTrackID else { return }
                            transportViewModel?.sendVirtualNote(trackID: trackID, message: message)
                        }
                    )
                }
            }
        } else {
            Text("No song selected")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var inspectorPanel: some View {
        VStack(spacing: 0) {
            Text("Inspector")
                .font(.headline)
                .padding(.top, 8)

            Picker("", selection: $inspectorMode) {
                ForEach(InspectorMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            switch inspectorMode {
            case .container:
                SelectionBasedInspectorView(
                    projectViewModel: projectViewModel,
                    selectionState: selectionState,
                    transportViewModel: transportViewModel,
                    setlistViewModel: setlistViewModel,
                    engineManager: engineManager,
                    settingsViewModel: settingsViewModel,
                    midiActivityMonitor: midiActivityMonitor,
                    previewState: previewState,
                    showContainerDetailEditor: $showContainerDetailEditor
                )
            case .storyline:
                storylineInspectorContent
            }
        }
        .frame(minWidth: 180, idealWidth: 250, maxWidth: 300)
        .focusScope(inspectorNamespace)
    }

    // MARK: - Timeline Content

    @ViewBuilder
    private func timelineContent(song: Song) -> some View {
        let timelineTracks = song.tracks
        GeometryReader { geo in
            let timelineViewportWidth = max(200, geo.size.width - timelineViewModel.trackHeaderWidth - 4)
            let timelineContentWidth = max(timelineViewportWidth, timelineViewModel.totalWidth)
            let inlineMIDILaneHeights = timelineInlineMIDILaneHeights(for: timelineTracks)
            let inlineMIDIConfigs = timelineInlineMIDIConfigs(for: timelineTracks)
            let effectiveTrackHeights = mergedTimelineTrackHeights()
            let snapshot = PlaybackGridSnapshot(
                tracks: timelineTracks,
                sections: song.sections,
                timeSignature: song.timeSignature,
                pixelsPerBar: timelineViewModel.pixelsPerBar,
                totalBars: timelineViewModel.totalBars,
                trackHeights: effectiveTrackHeights,
                inlineMIDILaneHeights: inlineMIDILaneHeights,
                inlineMIDIConfigs: inlineMIDIConfigs,
                automationExpandedTrackIDs: timelineViewModel.automationExpanded,
                automationSubLaneHeight: TimelineViewModel.automationSubLaneHeight,
                automationToolbarHeight: TimelineViewModel.automationToolbarHeight,
                defaultTrackHeight: TimelineViewModel.defaultTrackHeight,
                gridMode: timelineViewModel.gridMode,
                selectedAutomationTool: timelineViewModel.selectedAutomationTool,
                selectedContainerIDs: selectionState.effectiveSelectedContainerIDs,
                previewedTrackID: previewState.previewedTrackID,
                previewedContainerID: previewState.previewedContainerID,
                previewedAutomationLaneID: previewState.previewedAutomationLaneID,
                previewedAutomationPath: previewState.previewedAutomationPath,
                selectedSectionID: selectionState.selectedSectionID,
                selectedRange: timelineViewModel.selectedRange,
                rangeSelection: selectionState.rangeSelection,
                isSnapEnabled: timelineViewModel.isSnapEnabled,
                showRulerAndSections: true,
                playheadBar: timelineViewModel.playheadBar,
                cursorX: timelineViewModel.cursorX,
                bottomPadding: 0,
                minimumContentHeight: max(120, geo.size.height)
            )
            let scene = buildTimelineScene(snapshot: snapshot)
            let headerConfigurations = timelineTrackHeaderConfigurations(
                scene: scene,
                inlineMIDILaneHeights: inlineMIDILaneHeights,
                inlineMIDIConfigs: inlineMIDIConfigs
            )

            VStack(spacing: 0) {
                automationFocusBar
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ScrollViewIntrospector { sv in
                            timelineVerticalScrollView = sv
                        }
                        .frame(height: 0)

                        HStack(alignment: .top, spacing: 0) {
                            TimelineTrackHeaderListRepresentable(
                                configurations: headerConfigurations,
                                scene: scene,
                                headerWidth: timelineViewModel.trackHeaderWidth
                            )
                            .frame(width: timelineViewModel.trackHeaderWidth, height: scene.contentHeight)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .contextMenu {
                                trackCreationContextMenuItems
                            }

                            headerColumnResizeHandle

                            ScrollView(.horizontal, showsIndicators: true) {
                                VStack(alignment: .leading, spacing: 0) {
                                    ScrollViewIntrospector { sv in
                                        horizontalScrollCoordinator.attachScrollView(sv)
                                    }
                                    .frame(height: 0)

                                    PlaybackGridView(
                                        viewModel: timelineViewModel,
                                        projectViewModel: projectViewModel,
                                        selectionState: selectionState,
                                        song: song,
                                        tracks: timelineTracks,
                                        minHeight: scene.contentHeight,
                                        pianoRollState: pianoRollEditorState,
                                        ghostDropState: ghostDropState,
                                        showRulerAndSections: true,
                                        bottomPadding: 0,
                                        prebuiltScene: scene,
                                        onDropFilesToNewTracks: { urls, bar in
                                            handleEmptyAreaDrop(urls: urls, startBar: bar, song: song)
                                        },
                                        onContainerDoubleClick: {
                                            openContainerEditor()
                                        },
                                        onPlayheadPosition: { bar in
                                            pianoRollEditorState.isFocused = false
                                            transportViewModel?.seek(toBar: bar)
                                        },
                                        onNotePreview: { pitch, isNoteOn in
                                            guard let trackID = pianoRollEditorState.trackID else { return }
                                            let message: MIDIActionMessage = isNoteOn
                                                ? .noteOn(channel: 0, note: pitch, velocity: 100)
                                                : .noteOff(channel: 0, note: pitch, velocity: 0)
                                            transportViewModel?.sendVirtualNote(trackID: trackID, message: message)
                                        },
                                        onOpenPianoRollSheet: {
                                            openPianoRollSheet()
                                        },
                                        onSectionSelect: { sectionID in
                                            selectionState.selectedSectionID = sectionID
                                        },
                                        onRangeSelect: { range in
                                            timelineViewModel.selectedRange = range
                                        },
                                        onRangeDeselect: {
                                            timelineViewModel.clearSelectedRange()
                                        },
                                        debugLabel: "timeline"
                                    )
                                    .frame(width: timelineContentWidth, height: scene.contentHeight, alignment: .topLeading)
                                }
                                .frame(width: timelineContentWidth, alignment: .topLeading)
                            }
                        }
                    }
                }
            }
            .onAppear {
                timelineViewModel.setViewportWidth(timelineViewportWidth)
            }
            .onChange(of: geo.size.width) { _, newWidth in
                timelineViewModel.setViewportWidth(max(200, newWidth - timelineViewModel.trackHeaderWidth - 4))
            }
        }
        .scrollWheelHandler(
            onCmdScroll: { delta, mouseXInWindow in
                let zoomingIn = delta > 0
                guard let scrollView = horizontalScrollCoordinator.scrollView else {
                    if zoomingIn { timelineViewModel.zoomIn() } else { timelineViewModel.zoomOut() }
                    return
                }
                // Convert window X to scroll view's local coordinate space.
                // This correctly accounts for sidebar, track headers, resize handles,
                // and any other views to the left of the timeline scroll view.
                let scrollViewOriginX = scrollView.convert(NSPoint.zero, to: nil).x
                let mouseXRelativeToTimeline = mouseXInWindow - scrollViewOriginX
                guard mouseXRelativeToTimeline > 0 else {
                    if zoomingIn { timelineViewModel.zoomIn() } else { timelineViewModel.zoomOut() }
                    return
                }
                let scrollOffset = scrollView.contentView.bounds.origin.x
                let timelineX = mouseXRelativeToTimeline + scrollOffset
                let barUnderCursor = timelineViewModel.bar(forXPosition: timelineX)
                let viewportWidth = scrollView.contentView.bounds.width

                let newScrollOffset = timelineViewModel.zoomAndUpdateViewport(
                    zoomIn: zoomingIn,
                    anchorBar: barUnderCursor,
                    mouseXRelativeToTimeline: mouseXRelativeToTimeline,
                    viewportWidth: viewportWidth
                )
                horizontalScrollCoordinator.setOffset(newScrollOffset)
            },
            onMagnify: pianoRollEditorState.isExpanded ? nil : { magnification, mouseXInWindow in
                guard let scrollView = horizontalScrollCoordinator.scrollView else { return }
                let scrollViewOriginX = scrollView.convert(NSPoint.zero, to: nil).x
                let mouseXRelativeToTimeline = mouseXInWindow - scrollViewOriginX
                guard mouseXRelativeToTimeline > 0 else { return }
                let scrollOffset = scrollView.contentView.bounds.origin.x
                let timelineX = mouseXRelativeToTimeline + scrollOffset
                let barUnderCursor = timelineViewModel.bar(forXPosition: timelineX)
                let viewportWidth = scrollView.contentView.bounds.width

                let factor = 1.0 + magnification
                let newScrollOffset = timelineViewModel.zoomContinuousAndUpdateViewport(
                    factor: factor,
                    anchorBar: barUnderCursor,
                    mouseXRelativeToTimeline: mouseXRelativeToTimeline,
                    viewportWidth: viewportWidth
                )
                horizontalScrollCoordinator.setOffset(newScrollOffset)
            }
        )

        Divider()

        // Add Track button
        HStack {
            addTrackMenu
                .padding(4)
                .frame(width: timelineViewModel.trackHeaderWidth)
            Spacer()
        }
        .contentShape(Rectangle())
        .contextMenu {
            trackCreationContextMenuItems
        }
        .onAppear {
            horizontalScrollCoordinator.onScroll = { [timelineViewModel] offsetX, viewportWidth in
                timelineViewModel.updateVisibleXRange(scrollOffsetX: offsetX, viewportWidth: viewportWidth)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                resetTimelineScrollToStart()
                resetTimelineVerticalScrollToTop()
                horizontalScrollCoordinator.reportCurrentPosition()
            }
        }
        .onDisappear {
            horizontalScrollCoordinator.detach()
        }
        .onChange(of: timelineViewModel.pixelsPerBar) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                horizontalScrollCoordinator.reportCurrentPosition()
            }
        }
        .onChange(of: song.id) { _, _ in
            DispatchQueue.main.async {
                resetTimelineScrollToStart()
                resetTimelineVerticalScrollToTop()
                horizontalScrollCoordinator.reportCurrentPosition()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                resetTimelineScrollToStart()
                resetTimelineVerticalScrollToTop()
                horizontalScrollCoordinator.reportCurrentPosition()
            }
        }
    }

    private func resetTimelineScrollToStart() {
        horizontalScrollCoordinator.setOffset(0)
    }

    private func resetTimelineVerticalScrollToTop() {
        guard let scrollView = timelineVerticalScrollView else { return }
        scrollView.contentView.setBoundsOrigin(NSPoint(x: scrollView.contentView.bounds.origin.x, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Ruler Header (Docked at Top)

    /// Fixed ruler + section lane header that stays visible above the vertical scroll.
    /// Shares horizontal scroll position via the synchronizer.
    @ViewBuilder
    private func rulerHeader(song: Song) -> some View {
        let rulerHeight = TimelineCanvasView.rulerHeight
        let sectionHeight = TimelineCanvasView.sectionLaneHeight
        let totalHeight = rulerHeight + sectionHeight
        let ppb = timelineViewModel.pixelsPerBar
        let ts = song.timeSignature

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Color.clear.frame(height: rulerHeight)
                Text("Sections")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: timelineViewModel.trackHeaderWidth, height: totalHeight)
            .background(Color(nsColor: .controlBackgroundColor))

            headerColumnResizeHandle

            ScrollView(.horizontal, showsIndicators: false) {
                Canvas { context, size in
                    // Ruler background
                    context.fill(
                        Path(CGRect(x: 0, y: 0, width: size.width, height: rulerHeight)),
                        with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                    )

                    // Section lane background
                    context.fill(
                        Path(CGRect(x: 0, y: rulerHeight, width: size.width, height: sectionHeight)),
                        with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.8))
                    )

                    // Ruler bottom border
                    let borderPath = Path { p in
                        p.move(to: CGPoint(x: 0, y: rulerHeight - 0.5))
                        p.addLine(to: CGPoint(x: size.width, y: rulerHeight - 0.5))
                    }
                    context.stroke(borderPath, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)

                    // Section lane bottom border
                    let sectionBorderPath = Path { p in
                        p.move(to: CGPoint(x: 0, y: totalHeight - 0.5))
                        p.addLine(to: CGPoint(x: size.width, y: totalHeight - 0.5))
                    }
                    context.stroke(sectionBorderPath, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)

                    // Label step — avoid too-dense labels at low zoom
                    let minLabelWidth: CGFloat = 30
                    let niceSteps = [1, 2, 4, 5, 8, 10, 16, 20, 25, 32, 50, 64, 100, 200, 500, 1000]
                    let step = niceSteps.first(where: { CGFloat($0) * ppb >= minLabelWidth }) ?? 1000

                    // Bar lines, ticks, and labels
                    let maxBar = max(1, Int(ceil(size.width / ppb)) + 1)
                    var tickPath = Path()
                    for bar in 1...maxBar {
                        let x = CGFloat(bar - 1) * ppb

                        // Bar tick at bottom of ruler
                        if ppb >= 4 {
                            tickPath.move(to: CGPoint(x: x, y: rulerHeight - 6))
                            tickPath.addLine(to: CGPoint(x: x, y: rulerHeight))
                        }

                        // Bar number label
                        if bar % step == 0 {
                            let text = Text("\(bar)").font(.system(size: 9)).foregroundStyle(.secondary)
                            context.draw(text, at: CGPoint(x: x + 12, y: 8))
                        }

                        // Beat ticks
                        if ppb > 50 {
                            let ppBeat = ppb / CGFloat(ts.beatsPerBar)
                            for beat in 1..<ts.beatsPerBar {
                                let beatX = x + CGFloat(beat) * ppBeat
                                tickPath.move(to: CGPoint(x: beatX, y: rulerHeight - 3))
                                tickPath.addLine(to: CGPoint(x: beatX, y: rulerHeight))
                            }
                        }
                    }
                    context.stroke(tickPath, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)

                    // Range selection highlight
                    if let range = timelineViewModel.selectedRange {
                        let rangeX = CGFloat(range.lowerBound - 1) * ppb
                        let rangeW = CGFloat(range.count) * ppb
                        context.fill(
                            Path(CGRect(x: rangeX, y: 0, width: rangeW, height: rulerHeight)),
                            with: .color(.accentColor.opacity(0.25))
                        )
                    }

                    // Section bands
                    for section in song.sections {
                        let sx = CGFloat(section.startBar - 1) * ppb
                        let sw = CGFloat(section.lengthBars) * ppb
                        let bandRect = CGRect(x: sx, y: rulerHeight + 1, width: sw, height: sectionHeight - 2)
                        let sectionColor = rulerSectionColor(hex: section.color)
                        let isSelected = selectionState.selectedSectionID == section.id

                        // Band fill
                        let bandPath = Path(roundedRect: bandRect, cornerRadius: 3)
                        context.fill(bandPath, with: .color(sectionColor.opacity(0.4)))

                        // Band border
                        if isSelected {
                            context.stroke(bandPath, with: .color(.accentColor), lineWidth: 1.5)
                        } else {
                            context.stroke(bandPath, with: .color(sectionColor.opacity(0.7)), lineWidth: 0.5)
                        }

                        // Section name
                        if sw > 20 {
                            let label = Text(section.name).font(.system(size: 10, weight: .medium)).foregroundStyle(sectionColor)
                            context.draw(label, at: CGPoint(x: bandRect.minX + 6 + 30, y: bandRect.midY))
                        }
                    }

                    // Playhead line in ruler
                    let playX = CGFloat(timelineViewModel.playheadBar - 1.0) * ppb
                    let playheadPath = Path { p in
                        p.move(to: CGPoint(x: playX, y: 0))
                        p.addLine(to: CGPoint(x: playX, y: totalHeight))
                    }
                    context.stroke(playheadPath, with: .color(.red), lineWidth: 1)
                }
                .frame(width: timelineViewModel.quantizedFrameWidth, height: totalHeight)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let bar = timelineViewModel.snappedBar(forXPosition: location.x, timeSignature: ts)
                    pianoRollEditorState.isFocused = false
                    transportViewModel?.seek(toBar: bar)
                }
            }
        }
        .frame(height: totalHeight)
    }

    /// Converts a hex color string (e.g. "#E74C3C") to a SwiftUI Color.
    private func rulerSectionColor(hex: String) -> Color {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let rgb = Int(trimmed, radix: 16) else { return .gray }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    // MARK: - Mixer Content

    @ViewBuilder
    private func mixerContent(song: Song) -> some View {
        MixerView(
            tracks: song.tracks,
            mixerViewModel: mixerViewModel ?? MixerViewModel(),
            selectedTrackID: selectionState.selectedTrackID,
            onVolumeChange: { trackID, volume in
                // During drag: only update the live audio graph (no model mutation)
                let pan = song.tracks.first(where: { $0.id == trackID })?.pan ?? 0
                transportViewModel?.updateTrackMixLive(trackID: trackID, volume: volume, pan: pan)
            },
            onPanChange: { trackID, pan in
                // During drag: only update the live audio graph (no model mutation)
                let volume = song.tracks.first(where: { $0.id == trackID })?.volume ?? 1
                transportViewModel?.updateTrackMixLive(trackID: trackID, volume: volume, pan: pan)
            },
            onVolumeCommit: { trackID, volume in
                // On gesture end: persist to model (triggers view re-evaluation once)
                projectViewModel.setTrackVolume(trackID: trackID, volume: volume)
            },
            onPanCommit: { trackID, pan in
                // On gesture end: persist to model (triggers view re-evaluation once)
                projectViewModel.setTrackPan(trackID: trackID, pan: pan)
            },
            onMuteToggle: { trackID in
                projectViewModel.toggleMute(trackID: trackID)
                if let tracks = projectViewModel.currentSong?.tracks {
                    transportViewModel?.updateMuteSoloState(tracks: tracks)
                }
            },
            onSoloToggle: { trackID in
                projectViewModel.toggleSolo(trackID: trackID)
                if let tracks = projectViewModel.currentSong?.tracks {
                    transportViewModel?.updateMuteSoloState(tracks: tracks)
                }
            },
            onRecordArmToggle: { trackID, armed in
                projectViewModel.setTrackRecordArmed(trackID: trackID, armed: armed)
            },
            onMonitorToggle: { trackID, monitoring in
                projectViewModel.setTrackMonitoring(trackID: trackID, monitoring: monitoring)
                if let track = song.tracks.first(where: { $0.id == trackID }) {
                    transportViewModel?.setInputMonitoring(track: track, enabled: monitoring)
                }
            },
            onTrackSelect: { trackID in
                selectionState.selectedTrackID = trackID
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        Divider()

        // Add Track button
        HStack {
            addTrackMenu
                .padding(4)
                .frame(width: timelineViewModel.trackHeaderWidth)
            Spacer()
        }
    }

    // MIDI learn is handled by ProjectViewModel; real-time CC dispatch
    // is wired in LoopsRootView.onAppear via onMIDICCWithValue.

    @ViewBuilder
    private var storylineInspectorContent: some View {
        if let song = currentSong {
            StorylineInspectorView(
                entries: StorylineDerivation.derive(sections: song.sections, tracks: song.tracks),
                onUpdateNotes: { sectionID, notes in
                    projectViewModel.setSectionNotes(sectionID: sectionID, notes: notes)
                }
            )
        } else {
            Text("No song selected")
                .foregroundStyle(.secondary)
                .padding()
            Spacer()
        }
    }

    private func trackHeaderWithActions(track: Track) -> some View {
        trackHeaderWithActions(
            track: track,
            automationLaneLabels: automationLaneLabels(for: track),
            focusedAutomationLaneLabel: focusedAutomationLaneLabel(
                for: track,
                laneLabels: automationLaneLabels(for: track)
            ),
            height: timelineViewModel.trackHeight(
                for: track,
                baseHeight: effectiveBaseTrackHeight(for: track.id)
            )
        )
    }

    private func trackHeaderWithActions(
        track: Track,
        automationLaneLabels: [String],
        focusedAutomationLaneLabel: String?,
        height: CGFloat
    ) -> some View {
        let isExpanded = timelineViewModel.automationExpanded.contains(track.id)
        let isSelected = selectionState.selectedTrackID == track.id
        let isInlineMIDIExpanded = pianoRollEditorState.isExpanded && pianoRollEditorState.trackID == track.id
        return TrackHeaderView(
            track: track,
            height: height,
            inputPortName: inputPortName(for: track.inputPortID),
            outputPortName: outputPortName(for: track.outputPortID),
            midiDeviceName: midiDeviceName(for: track.midiInputDeviceID),
            midiChannelLabel: midiChannelLabel(for: track.midiInputChannel),
            isAutomationExpanded: isExpanded,
            automationLaneLabels: automationLaneLabels,
            onMuteToggle: {
                projectViewModel.toggleMute(trackID: track.id)
                if let tracks = projectViewModel.currentSong?.tracks {
                    transportViewModel?.updateMuteSoloState(tracks: tracks)
                }
            },
            onSoloToggle: {
                projectViewModel.toggleSolo(trackID: track.id)
                if let tracks = projectViewModel.currentSong?.tracks {
                    transportViewModel?.updateMuteSoloState(tracks: tracks)
                }
            },
            onRecordArmToggle: { projectViewModel.setTrackRecordArmed(trackID: track.id, armed: !track.isRecordArmed) },
            onMonitorToggle: {
                let newState = !track.isMonitoring
                projectViewModel.setTrackMonitoring(trackID: track.id, monitoring: newState)
                transportViewModel?.setInputMonitoring(track: track, enabled: newState)
            },
            onAutomationToggle: {
                timelineViewModel.toggleAutomationExpanded(trackID: track.id)
            },
            isTrackSelected: isSelected,
            isMIDIActive: midiActivityMonitor?.isTrackActive(track.id) ?? false,
            headerWidth: timelineViewModel.trackHeaderWidth,
            focusedAutomationLaneLabel: focusedAutomationLaneLabel,
            isInlineMIDIExpanded: isInlineMIDIExpanded,
            inlineMIDIScaleSummary: inlineMIDIScaleSummary(for: track.id),
            selectedMIDITool: pianoRollEditorState.selectedTool,
            onSelectMIDITool: isInlineMIDIExpanded ? { tool in
                pianoRollEditorState.selectedTool = tool
            } : nil,
            onInlineMIDIZoomOut: isInlineMIDIExpanded ? {
                adjustInlineMIDIRowHeight(for: track.id, delta: -1.5)
            } : nil,
            onInlineMIDIZoomIn: isInlineMIDIExpanded ? {
                adjustInlineMIDIRowHeight(for: track.id, delta: 1.5)
            } : nil,
            onInlineMIDIFit: isInlineMIDIExpanded ? {
                fitInlineMIDIRange(for: track.id)
            } : nil,
            onPreviewTrackHeight: { preview in
                if let preview {
                    liveTrackHeightPreviews[track.id] = preview
                } else {
                    liveTrackHeightPreviews.removeValue(forKey: track.id)
                }
            },
            onResizeTrack: { newHeight in
                liveTrackHeightPreviews.removeValue(forKey: track.id)
                timelineViewModel.setTrackHeight(newHeight, for: track.id)
            },
            onResetTrackHeight: {
                liveTrackHeightPreviews.removeValue(forKey: track.id)
                timelineViewModel.resetTrackHeight(for: track.id)
            },
            availableInputPorts: settingsViewModel?.inputPorts ?? [],
            availableOutputPorts: settingsViewModel?.outputPorts ?? [],
            availableMIDIDevices: engineManager?.midiManager.availableInputDevices() ?? [],
            onSetInputPort: { portID in
                projectViewModel.setTrackInputPort(trackID: track.id, portID: portID)
            },
            onSetOutputPort: { portID in
                if track.kind == .master {
                    projectViewModel.setMasterOutputPort(portID: portID)
                } else {
                    projectViewModel.setTrackOutputPort(trackID: track.id, portID: portID)
                }
            },
            onSetMIDIInput: { deviceID, channel in
                projectViewModel.setTrackMIDIInput(trackID: track.id, deviceID: deviceID, channel: channel)
            }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    if NSEvent.modifierFlags.contains(.command) {
                        timelineViewModel.toggleTrackSelection(trackID: track.id)
                    } else {
                        selectionState.selectedTrackID = track.id
                    }
                }
        )
        .contextMenu {
            Button("Rename...") {
                editingTrackID = track.id
                editingTrackName = track.name
            }
            if track.kind != .master {
                Button("Duplicate Track") {
                    projectViewModel.duplicateTrack(trackID: track.id)
                }
                let songs = projectViewModel.otherSongs
                if !songs.isEmpty {
                    Menu("Copy Track to Song\u{2026}") {
                        ForEach(songs, id: \.id) { song in
                            Button(song.name) {
                                projectViewModel.copyTrackToSong(trackID: track.id, targetSongID: song.id)
                            }
                        }
                    }
                }
                Divider()
                Button(track.isRecordArmed ? "Disarm Recording" : "Arm for Recording") {
                    projectViewModel.setTrackRecordArmed(trackID: track.id, armed: !track.isRecordArmed)
                }
            }

            if track.kind == .audio, let svm = settingsViewModel {
                Divider()
                Menu("Input") {
                    Button("Default") {
                        projectViewModel.setTrackInputPort(trackID: track.id, portID: nil)
                    }
                    if !svm.inputPorts.isEmpty { Divider() }
                    ForEach(svm.inputPorts) { port in
                        Button(port.displayName) {
                            projectViewModel.setTrackInputPort(trackID: track.id, portID: port.id)
                        }
                    }
                }
                Menu("Output") {
                    Button("Default") {
                        projectViewModel.setTrackOutputPort(trackID: track.id, portID: nil)
                    }
                    if !svm.outputPorts.isEmpty { Divider() }
                    ForEach(svm.outputPorts) { port in
                        Button(port.displayName) {
                            projectViewModel.setTrackOutputPort(trackID: track.id, portID: port.id)
                        }
                    }
                }
            }

            if track.kind == .master, let svm = settingsViewModel {
                Divider()
                Menu("Output") {
                    Button("Default") {
                        projectViewModel.setMasterOutputPort(portID: nil)
                    }
                    if !svm.outputPorts.isEmpty { Divider() }
                    ForEach(svm.outputPorts) { port in
                        Button(port.displayName) {
                            projectViewModel.setMasterOutputPort(portID: port.id)
                        }
                    }
                }
            }

            if track.kind == .midi {
                Divider()
                Menu("MIDI Device") {
                    Button("All Devices") {
                        projectViewModel.setTrackMIDIInput(trackID: track.id, deviceID: nil, channel: track.midiInputChannel)
                    }
                    let devices = engineManager?.midiManager.availableInputDevices() ?? []
                    if !devices.isEmpty { Divider() }
                    ForEach(devices) { device in
                        Button(device.displayName) {
                            projectViewModel.setTrackMIDIInput(trackID: track.id, deviceID: device.id, channel: track.midiInputChannel)
                        }
                    }
                }
                Menu("MIDI Channel") {
                    Button("Omni") {
                        projectViewModel.setTrackMIDIInput(trackID: track.id, deviceID: track.midiInputDeviceID, channel: nil)
                    }
                    Divider()
                    ForEach(1...16, id: \.self) { ch in
                        Button("Ch \(ch)") {
                            projectViewModel.setTrackMIDIInput(trackID: track.id, deviceID: track.midiInputDeviceID, channel: UInt8(ch))
                        }
                    }
                }
            }

            Divider()
            Menu("Track Automation") {
                let hasVolumeLane = track.trackAutomationLanes.contains { $0.targetPath.isTrackVolume }
                let hasPanLane = track.trackAutomationLanes.contains { $0.targetPath.isTrackPan }
                if !hasVolumeLane {
                    Button("Add Volume Automation") {
                        let lane = AutomationLane(targetPath: .trackVolume(trackID: track.id))
                        projectViewModel.addTrackAutomationLane(trackID: track.id, lane: lane)
                        timelineViewModel.automationExpanded.insert(track.id)
                    }
                } else {
                    Button("Remove Volume Automation") {
                        if let lane = track.trackAutomationLanes.first(where: { $0.targetPath.isTrackVolume }) {
                            projectViewModel.removeTrackAutomationLane(trackID: track.id, laneID: lane.id)
                        }
                    }
                }
                if !hasPanLane {
                    Button("Add Pan Automation") {
                        let lane = AutomationLane(targetPath: .trackPan(trackID: track.id))
                        projectViewModel.addTrackAutomationLane(trackID: track.id, lane: lane)
                        timelineViewModel.automationExpanded.insert(track.id)
                    }
                } else {
                    Button("Remove Pan Automation") {
                        if let lane = track.trackAutomationLanes.first(where: { $0.targetPath.isTrackPan }) {
                            projectViewModel.removeTrackAutomationLane(trackID: track.id, laneID: lane.id)
                        }
                    }
                }
                let sortedEffects = track.insertEffects.sorted { $0.orderIndex < $1.orderIndex }
                if !sortedEffects.isEmpty {
                    Divider()
                    ForEach(Array(sortedEffects.enumerated()), id: \.element.id) { index, effect in
                        let hasLane = track.trackAutomationLanes.contains { $0.targetPath.effectIndex == index && $0.targetPath.isTrackEffectParameter }
                        if hasLane {
                            Menu(effect.displayName) {
                                Button("Add Parameter...") {
                                    pendingTrackAutomationLane = PendingEffectSelection(
                                        trackID: track.id,
                                        containerID: nil,
                                        effectIndex: index,
                                        component: effect.component,
                                        effectName: effect.displayName
                                    )
                                }
                                Divider()
                                let effectLanes = track.trackAutomationLanes.filter { $0.targetPath.effectIndex == index && $0.targetPath.isTrackEffectParameter }
                                ForEach(effectLanes) { lane in
                                    Button("Remove \(automationPathLabel(lane.targetPath))") {
                                        projectViewModel.removeTrackAutomationLane(trackID: track.id, laneID: lane.id)
                                    }
                                }
                            }
                        } else {
                            Button("\(effect.displayName)...") {
                                pendingTrackAutomationLane = PendingEffectSelection(
                                    trackID: track.id,
                                    containerID: nil,
                                    effectIndex: index,
                                    component: effect.component,
                                    effectName: effect.displayName
                                )
                            }
                        }
                    }
                }
                // Instrument parameter automation (MIDI tracks with an instrument)
                if track.kind == .midi, let instrumentComponent = track.instrumentComponent {
                    Divider()
                    let hasInstrumentLane = track.trackAutomationLanes.contains { $0.targetPath.isTrackInstrumentParameter }
                    if hasInstrumentLane {
                        Menu("Instrument") {
                            Button("Add Parameter...") {
                                pendingTrackAutomationLane = PendingEffectSelection(
                                    trackID: track.id,
                                    containerID: nil,
                                    effectIndex: EffectPath.instrumentParameterEffectIndex,
                                    component: instrumentComponent,
                                    effectName: "Instrument"
                                )
                            }
                            Divider()
                            let instrumentLanes = track.trackAutomationLanes.filter { $0.targetPath.isTrackInstrumentParameter }
                            ForEach(instrumentLanes) { lane in
                                Button("Remove \(automationPathLabel(lane.targetPath))") {
                                    projectViewModel.removeTrackAutomationLane(trackID: track.id, laneID: lane.id)
                                }
                            }
                        }
                    } else {
                        Button("Instrument...") {
                            pendingTrackAutomationLane = PendingEffectSelection(
                                trackID: track.id,
                                containerID: nil,
                                effectIndex: EffectPath.instrumentParameterEffectIndex,
                                component: instrumentComponent,
                                effectName: "Instrument"
                            )
                        }
                    }
                }
            }

            if track.kind != .master {
                Divider()
                Button("Delete Track", role: .destructive) {
                    if track.containers.isEmpty {
                        projectViewModel.removeTrack(id: track.id)
                    } else {
                        trackToDelete = track
                    }
                }
            }
        }
        .onTapGesture(count: 2) {
            editingTrackID = track.id
            editingTrackName = track.name
        }
        .popover(isPresented: .init(
            get: { editingTrackID == track.id },
            set: { if !$0 { commitRename() } }
        )) {
            VStack(spacing: 8) {
                Text("Rename Track")
                    .font(.headline)
                TextField("Track name", text: $editingTrackName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit { commitRename() }
                HStack {
                    Button("Cancel") {
                        editingTrackID = nil
                    }
                    Button("OK") {
                        commitRename()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
    }

    private func commitRename() {
        if let id = editingTrackID, !editingTrackName.isEmpty {
            projectViewModel.renameTrack(id: id, newName: editingTrackName)
        }
        editingTrackID = nil
    }

    private func handleCopy() {
        if let range = timelineViewModel.selectedRange {
            projectViewModel.copyContainersInRange(
                startBar: Double(range.lowerBound),
                endBar: Double(range.upperBound + 1),
                trackFilter: timelineViewModel.selectedTrackIDs
            )
        } else if let containerID = selectionState.selectedContainerID, let song = currentSong {
            for track in song.tracks {
                if track.containers.contains(where: { $0.id == containerID }) {
                    projectViewModel.copyContainer(trackID: track.id, containerID: containerID)
                    return
                }
            }
        }
    }

    private func handlePaste() {
        guard clipboardState.hasContent else { return }
        let playheadBar = timelineViewModel.playheadBar
        projectViewModel.pasteContainersToOriginalTracks(atBar: playheadBar)
    }

    private func selectTrackByKeyIndex(_ index: Int) -> KeyPress.Result {
        guard !isCommandPalettePresented else { return .ignored }
        guard !isTextFieldFocused else { return .ignored }
        projectViewModel.selectTrackByIndex(index)
        return .handled
    }

    private func handleSplitAtPlayhead() {
        // If a range selection exists, split at the range boundaries instead of the playhead
        if selectionState.rangeSelection != nil {
            handleSplitAtRange()
            return
        }
        guard let containerID = selectionState.selectedContainerID,
              let song = currentSong else { return }
        let splitBar = timelineViewModel.playheadBar
        for track in song.tracks {
            if track.containers.contains(where: { $0.id == containerID }) {
                projectViewModel.splitContainer(trackID: track.id, containerID: containerID, atBar: splitBar)
                return
            }
        }
    }

    private func handleSplitAtRange() {
        guard let range = selectionState.rangeSelection,
              let song = currentSong else { return }
        for track in song.tracks {
            if track.containers.contains(where: { $0.id == range.containerID }) {
                projectViewModel.splitContainerAtRange(
                    trackID: track.id,
                    containerID: range.containerID,
                    rangeStart: range.startBar,
                    rangeEnd: range.endBar
                )
                selectionState.rangeSelection = nil
                return
            }
        }
    }

    private func handleDuplicate() {
        // Prefer duplicating selected container first
        if let containerID = selectionState.selectedContainerID, let song = currentSong {
            for track in song.tracks {
                if track.containers.contains(where: { $0.id == containerID }) {
                    projectViewModel.duplicateContainer(trackID: track.id, containerID: containerID)
                    return
                }
            }
        }
        // Fall back to duplicating selected track
        if let trackID = selectionState.selectedTrackID {
            projectViewModel.duplicateTrack(trackID: trackID)
        }
    }

    private func cycleInspectorMode() {
        let allModes = InspectorMode.allCases
        guard let currentIndex = allModes.firstIndex(of: inspectorMode) else { return }
        let nextIndex = (currentIndex + 1) % allModes.count
        inspectorMode = allModes[nextIndex]
    }

    private func commitSectionRename() {
        if let id = editingSectionID, !editingSectionName.isEmpty {
            projectViewModel.renameSection(sectionID: id, name: editingSectionName)
        }
        editingSectionID = nil
    }

    /// Pitch labels shown in the track header area when the inline piano roll is expanded.
    /// Styled like a mini piano keyboard with scroll sync to the piano roll.
    private var inlinePianoRollKeyboardLabels: some View {
        let state = pianoRollEditorState
        let low = state.lowPitch
        let high = state.highPitch
        let rh = state.rowHeight

        return VStack(spacing: 0) {
            ForEach((Int(low)...Int(high)).reversed(), id: \.self) { pitch in
                let note = UInt8(pitch)
                let isBlack = PianoLayout.isBlackKey(note: note)
                let isC = note % 12 == 0
                HStack(spacing: 0) {
                    Spacer(minLength: 2)
                    Text(PianoLayout.noteName(note))
                        .font(.system(size: max(7, min(rh - 2, 10)), design: .monospaced))
                        .foregroundStyle(isC ? Color.primary : isBlack ? Color.secondary : Color.secondary.opacity(0.7))
                }
                .padding(.trailing, 4)
                .frame(height: rh)
                .background(isBlack
                    ? Color(white: 0.15)
                    : Color(white: 0.92).opacity(0.14))
                .overlay(alignment: .bottom) {
                    if isC {
                        Rectangle().fill(Color.secondary.opacity(0.18)).frame(height: 0.5)
                    }
                }
            }
        }
        .frame(height: state.inlineHeight, alignment: .top)
        .clipped()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.22))
                .frame(height: 1)
        }
    }

    private var headerColumnResizeHandle: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if headerDragStartWidth == 0 {
                            headerDragStartWidth = timelineViewModel.trackHeaderWidth
                        }
                        let newWidth = headerDragStartWidth + value.translation.width
                        timelineViewModel.setTrackHeaderWidth(newWidth)
                    }
                    .onEnded { _ in
                        headerDragStartWidth = 0
                    }
            )
    }

    private var addTrackMenu: some View {
        Menu {
            trackCreationContextMenuItems
        } label: {
            Label("Add Track", systemImage: "plus")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private var trackCreationContextMenuItems: some View {
        ForEach(TrackKind.creatableKinds, id: \.self) { kind in
            Button(kind.displayName) {
                projectViewModel.addTrack(kind: kind)
            }
        }
    }

    func inputPortName(for portID: String?) -> String {
        guard let portID, let svm = settingsViewModel else { return "Default" }
        return svm.inputPorts.first { $0.id == portID }?.displayName ?? "Default"
    }

    func outputPortName(for portID: String?) -> String {
        guard let portID, let svm = settingsViewModel else { return "Default" }
        return svm.outputPorts.first { $0.id == portID }?.displayName ?? "Default"
    }

    func midiDeviceName(for deviceID: String?) -> String? {
        guard let deviceID else { return nil }
        let devices = engineManager?.midiManager.availableInputDevices() ?? []
        return devices.first { $0.id == deviceID }?.displayName
    }

    func midiChannelLabel(for channel: UInt8?) -> String? {
        guard let ch = channel else { return nil }
        return "Ch \(ch)"
    }

    func automationLaneLabels(for track: Track) -> [String] {
        var seen = Set<EffectPath>()
        var labels: [String] = []
        // Track-level automation lanes first
        for lane in track.trackAutomationLanes {
            if seen.insert(lane.targetPath).inserted {
                labels.append(automationPathLabel(lane.targetPath))
            }
        }
        for container in track.containers {
            for lane in container.automationLanes {
                if seen.insert(lane.targetPath).inserted {
                    labels.append(automationPathLabel(lane.targetPath))
                }
            }
        }
        return labels
    }

    private func automationPathLabel(_ path: EffectPath) -> String {
        if path.isTrackVolume { return "Volume" }
        if path.isTrackPan { return "Pan" }
        if path.isTrackInstrumentParameter {
            return "Instrument P\(path.parameterAddress)"
        }
        if path.isTrackEffectParameter, let track = currentSong?.tracks.first(where: { $0.id == path.trackID }) {
            let sorted = track.insertEffects.sorted { $0.orderIndex < $1.orderIndex }
            if path.effectIndex >= 0 && path.effectIndex < sorted.count {
                return "\(sorted[path.effectIndex].displayName) P\(path.parameterAddress)"
            }
        }
        if let containerID = path.containerID {
            let containers = currentSong?.tracks.flatMap(\.containers) ?? []
            if let container = containers.first(where: { $0.id == containerID }) {
                let sorted = container.insertEffects.sorted { $0.orderIndex < $1.orderIndex }
                if path.effectIndex >= 0, path.effectIndex < sorted.count {
                    return "\(sorted[path.effectIndex].displayName) P\(path.parameterAddress)"
                }
            }
            let trackName = currentSong?.tracks.first(where: { $0.id == path.trackID })?.name ?? "?"
            let cName = currentSong?.tracks.flatMap(\.containers).first(where: { $0.id == containerID })?.name ?? "?"
            return "\(trackName)/\(cName) FX\(path.effectIndex)"
        }
        let trackName = currentSong?.tracks.first(where: { $0.id == path.trackID })?.name ?? "?"
        return "\(trackName) FX\(path.effectIndex)"
    }

    private func adjustInlineMIDIRowHeight(for trackID: ID<Track>, delta: CGFloat) {
        guard pianoRollEditorState.trackID == trackID else { return }
        pianoRollEditorState.rowHeight = min(36, max(10, pianoRollEditorState.rowHeight + delta))
    }

    private func setInlineMIDIDetailLaneHeight(
        lane: MIDINoteExpressionLane,
        height: CGFloat
    ) {
        pianoRollEditorState.setNoteExpressionLaneHeight(height, for: lane)
    }

    private func adjustTimelineTrackHeight(for trackID: ID<Track>, delta: CGFloat) {
        let currentHeight = effectiveBaseTrackHeight(for: trackID)
        liveTrackHeightPreviews.removeValue(forKey: trackID)
        timelineViewModel.setTrackHeight(currentHeight + delta, for: trackID)
    }

    private func shiftInlineMIDIPitchRange(for trackID: ID<Track>, semitoneDelta: Int) {
        guard pianoRollEditorState.trackID == trackID else { return }
        let currentLow = Int(pianoRollEditorState.lowPitch)
        let currentHigh = Int(pianoRollEditorState.highPitch)
        let span = max(1, currentHigh - currentLow)

        var newLow = currentLow + semitoneDelta
        var newHigh = currentHigh + semitoneDelta
        if newLow < 0 {
            newLow = 0
            newHigh = min(127, span)
        } else if newHigh > 127 {
            newHigh = 127
            newLow = max(0, 127 - span)
        }

        pianoRollEditorState.lowPitch = UInt8(clamping: newLow)
        pianoRollEditorState.highPitch = UInt8(clamping: newHigh)
    }

    private func mergedTimelineTrackHeights() -> [ID<Track>: CGFloat] {
        var heights = timelineViewModel.trackHeights
        for (trackID, previewHeight) in liveTrackHeightPreviews {
            heights[trackID] = previewHeight
        }
        return heights
    }

    private func effectiveBaseTrackHeight(for trackID: ID<Track>) -> CGFloat {
        liveTrackHeightPreviews[trackID] ?? timelineViewModel.baseTrackHeight(for: trackID)
    }

    private func fitInlineMIDIRange(for trackID: ID<Track>) {
        guard pianoRollEditorState.trackID == trackID,
              let track = currentSong?.tracks.first(where: { $0.id == trackID }) else { return }
        let notes = track.containers.compactMap { projectViewModel.resolvedMIDISequence($0)?.notes }.flatMap { $0 }
        guard !notes.isEmpty else { return }
        let sequence = MIDISequence(notes: notes)
        pianoRollEditorState.fitToNotes(sequence: sequence)
    }

    private func inlineMIDIScaleSummary(for trackID: ID<Track>) -> String? {
        guard pianoRollEditorState.isExpanded,
              pianoRollEditorState.trackID == trackID else { return nil }
        let visibleRows = Int(pianoRollEditorState.highPitch) - Int(pianoRollEditorState.lowPitch) + 1
        return "\(visibleRows) keys"
    }

    private func timelineInlineMIDILaneHeights(for tracks: [Track]) -> [ID<Track>: CGFloat] {
        var heights: [ID<Track>: CGFloat] = [:]
        for track in tracks {
            let laneHeight = inlinePianoRollLaneHeight(for: track.id)
            if laneHeight > 0 {
                heights[track.id] = laneHeight
            }
        }
        return heights
    }

    private func timelineInlineMIDIConfigs(for tracks: [Track]) -> [ID<Track>: PlaybackGridMIDIConfig] {
        guard pianoRollEditorState.isExpanded,
              let activeTrackID = pianoRollEditorState.trackID,
              tracks.contains(where: { $0.id == activeTrackID }) else {
            return [:]
        }
        return [
            activeTrackID: PlaybackGridMIDIConfig(
                lowPitch: pianoRollEditorState.lowPitch,
                highPitch: pianoRollEditorState.highPitch,
                rowHeight: pianoRollEditorState.rowHeight,
                tool: pianoRollEditorState.selectedTool,
                detailLanes: pianoRollEditorState.visibleExpressionLanes.map { lane in
                    .init(
                        lane: lane,
                        height: pianoRollEditorState.noteExpressionLaneHeight(for: lane)
                    )
                }
            )
        ]
    }

    private var automationFocusBar: some View {
        Group {
            if let focusedPath = projectViewModel.lastTouchedAutomationPath {
                HStack(spacing: 10) {
                    Label("Automation Focus", systemImage: "waveform.path.ecg")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.pink)
                    Text(automationPathLabel(focusedPath))
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Reveal") {
                        revealAutomationPath(focusedPath)
                    }
                    .buttonStyle(.borderless)
                    Button("Clear") {
                        projectViewModel.clearAutomationFocus()
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.06))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 1)
                }
            }
        }
    }

    private func revealAutomationPath(_ path: EffectPath) {
        selectionState.selectedTrackID = path.trackID
        timelineViewModel.automationExpanded.insert(path.trackID)
    }

    private func focusedAutomationLaneLabel(for track: Track, laneLabels: [String]) -> String? {
        let focusedPath = previewState.previewedAutomationPath ?? projectViewModel.lastTouchedAutomationPath
        guard let focusedPath,
              focusedPath.trackID == track.id else { return nil }
        let label = automationPathLabel(focusedPath)
        return laneLabels.contains(label) ? label : nil
    }

    private func timelineTrackHeaderConfigurations(
        scene: PlaybackGridScene,
        inlineMIDILaneHeights: [ID<Track>: CGFloat],
        inlineMIDIConfigs: [ID<Track>: PlaybackGridMIDIConfig]
    ) -> [TimelineTrackHeaderConfiguration] {
        scene.trackLayouts.map { layout in
            let track = layout.track
            let isExpanded = timelineViewModel.automationExpanded.contains(track.id)
            let laneLabels = layout.automationLaneLayouts.map { automationPathLabel($0.targetPath) }
            let headerHeight = layout.height - (inlineMIDILaneHeights[track.id] ?? 0)
            let inlineHeight = inlineMIDILaneHeights[track.id] ?? 0
            let inlineConfig = inlineMIDIConfigs[track.id].map {
                TimelineTrackHeaderConfiguration.InlineMIDIConfiguration(
                    lowPitch: $0.lowPitch,
                    highPitch: $0.highPitch,
                    rowHeight: $0.rowHeight ?? PianoRollLayout.defaultRowHeight,
                    height: inlineHeight,
                    detailLanes: $0.detailLanes.map { detailLane in
                        .init(
                            lane: detailLane.lane,
                            height: detailLane.height,
                            onSetHeight: { newHeight in
                                setInlineMIDIDetailLaneHeight(
                                    lane: detailLane.lane,
                                    height: newHeight
                                )
                            }
                        )
                    },
                    onAdjustRowHeight: { delta in
                        adjustInlineMIDIRowHeight(for: track.id, delta: delta)
                    },
                    onShiftPitchRange: { semitoneDelta in
                        shiftInlineMIDIPitchRange(for: track.id, semitoneDelta: semitoneDelta)
                    }
                )
            }
            return TimelineTrackHeaderConfiguration(
                track: track,
                headerHeight: headerHeight,
                totalHeight: headerHeight + inlineHeight,
                content: AnyView(
                    trackHeaderWithActions(
                        track: track,
                        automationLaneLabels: laneLabels,
                        focusedAutomationLaneLabel: focusedAutomationLaneLabel(
                            for: track,
                            laneLabels: laneLabels
                        ),
                        height: headerHeight
                    )
                ),
                inputPortName: inputPortName(for: track.inputPortID),
                outputPortName: outputPortName(for: track.outputPortID),
                midiDeviceName: midiDeviceName(for: track.midiInputDeviceID),
                midiChannelLabel: midiChannelLabel(for: track.midiInputChannel),
                isAutomationExpanded: isExpanded,
                automationLaneLabels: laneLabels,
                isTrackSelected: selectionState.selectedTrackID == track.id || previewState.previewedTrackID == track.id,
                isMIDIActive: midiActivityMonitor?.isTrackActive(track.id) ?? false,
                headerWidth: timelineViewModel.trackHeaderWidth,
                availableInputPorts: settingsViewModel?.inputPorts ?? [],
                availableOutputPorts: settingsViewModel?.outputPorts ?? [],
                availableMIDIDevices: engineManager?.midiManager.availableInputDevices() ?? [],
                inlineMIDI: inlineConfig,
                onSelect: {
                    selectionState.selectedTrackID = track.id
                }
            )
        }
    }

    private func buildTimelineScene(snapshot: PlaybackGridSnapshot) -> PlaybackGridScene {
        let layoutBuilder = PlaybackGridSceneBuilder()
        layoutBuilder.waveformPeaksProvider = { [projectViewModel] container in
            projectViewModel.waveformPeaks(for: container)
        }
        layoutBuilder.waveformExtremaProvider = { [projectViewModel] container in
            projectViewModel.waveformExtrema(for: container)
        }
        layoutBuilder.waveformRMSProvider = { [projectViewModel] container in
            projectViewModel.waveformRMS(for: container)
        }
        layoutBuilder.audioDurationBarsProvider = { [projectViewModel] container in
            projectViewModel.recordingDurationBars(for: container)
        }
        layoutBuilder.resolvedMIDISequenceProvider = { [projectViewModel] container in
            projectViewModel.resolvedMIDISequence(container)
        }
        return layoutBuilder.build(snapshot: snapshot)
    }

    private func trackListContentHeight(_ tracks: [Track]) -> CGFloat {
        tracks.reduce(CGFloat(0)) { total, track in
            let trackH = timelineViewModel.trackHeight(for: track, baseHeight: timelineViewModel.baseTrackHeight(for: track.id))
            return total + trackH + inlinePianoRollLaneHeight(for: track.id)
        }
    }

    private func inlinePianoRollLaneHeight(for trackID: ID<Track>) -> CGFloat {
        guard pianoRollEditorState.isExpanded,
              pianoRollEditorState.trackID == trackID else { return 0 }
        let detailHeight = pianoRollEditorState.visibleExpressionLanes.reduce(CGFloat(0)) { partial, lane in
            partial + pianoRollEditorState.noteExpressionLaneHeight(for: lane)
        }
        return max(0, pianoRollEditorState.inlineHeight + detailHeight)
    }

    // MARK: - Ghost Track Header

    @ViewBuilder
    private func ghostTrackHeader(ghost: GhostTrackInfo) -> some View {
        HStack {
            Image(systemName: ghost.trackKind == .audio ? "waveform" : "pianokeys")
                .foregroundStyle(ghost.trackColor)
            Text(ghost.fileName)
                .font(.caption)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: TimelineViewModel.defaultTrackHeight)
        .background(ghost.trackColor.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(ghost.trackColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
        )
        .opacity(0.7)
    }

    // MARK: - Empty Area Drop Handler

    private func handleEmptyAreaDrop(urls: [URL], startBar: Double, song: Song) {
        // Check for MIDI files with tempo info — prompt before importing
        let midiURLs = urls.filter { ["mid", "midi"].contains($0.pathExtension.lowercased()) }
        if let firstMIDI = midiURLs.first {
            let importer = MIDIFileImporter()
            if let result = try? importer.importFile(at: firstMIDI),
               let micros = result.tempoMicrosPerQuarterNote {
                let bpm = 60_000_000.0 / Double(micros)
                pendingTempoImport = PendingTempoImport(bpm: bpm, urls: urls, startBar: startBar)
                showTempoImportAlert = true
                // Import will happen after alert response — but for simplicity,
                // proceed with importing tracks now (tempo can be applied separately)
            }
        }

        projectViewModel.importFilesToNewTracks(urls: urls, startBar: startBar)
    }
}

// MARK: - Pending Tempo Import

private struct PendingTempoImport {
    let bpm: Double
    let urls: [URL]
    let startBar: Double
}

// MARK: - Empty Area File Drop Delegate

private struct EmptyAreaFileDropDelegate: DropDelegate {
    let ghostDropState: GhostTrackDropState
    let timelineViewModel: TimelineViewModel
    let projectViewModel: ProjectViewModel
    let onPerformDrop: ([URL], Double) -> Void

    private static let supportedAudioExtensions: Set<String> = ["wav", "aiff", "aif", "caf", "mp3", "m4a"]
    private static let supportedMIDIExtensions: Set<String> = ["mid", "midi"]

    func dropEntered(info: DropInfo) {
        if ghostDropState.activate() {
            resolveGhostTracks(from: info)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        ghostDropState.deactivate()
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else {
            ghostDropState.reset()
            return false
        }

        var resolvedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    let ext = url.pathExtension.lowercased()
                    if Self.supportedMIDIExtensions.contains(ext) || Self.supportedAudioExtensions.contains(ext) {
                        resolvedURLs.append(url)
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let bar = ghostDropState.dropBar
            ghostDropState.reset()
            if !resolvedURLs.isEmpty {
                onPerformDrop(resolvedURLs, bar)
            }
        }

        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    private func resolveGhostTracks(from info: DropInfo) {
        let song = projectViewModel.currentSong
        let beatsPerBar = Double(song?.timeSignature.beatsPerBar ?? 4)
        let tempo = song?.tempo ?? Tempo()
        let timeSignature = song?.timeSignature ?? TimeSignature()
        let state = ghostDropState

        let providers = info.itemProviders(for: [.fileURL])
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                let ext = url.pathExtension.lowercased()

                if Self.supportedMIDIExtensions.contains(ext) {
                    let importer = MIDIFileImporter()
                    if let result = try? importer.importFile(at: url) {
                        let baseName = url.deletingPathExtension().lastPathComponent
                        DispatchQueue.main.async {
                            for (index, sequence) in result.sequences.enumerated() {
                                let totalBeats = sequence.durationBeats
                                let lengthBars = max(1.0, ceil(totalBeats / beatsPerBar))
                                let name = result.sequences.count > 1
                                    ? "\(baseName) - Track \(index + 1)"
                                    : baseName
                                state.ghostTracks.append(GhostTrackInfo(
                                    fileName: name,
                                    lengthBars: lengthBars,
                                    trackKind: .midi,
                                    url: url
                                ))
                            }
                        }
                    }
                } else if Self.supportedAudioExtensions.contains(ext) {
                    let baseName = url.deletingPathExtension().lastPathComponent
                    var lengthBars: Double?
                    if let metadata = try? AudioImporter.readMetadata(from: url) {
                        lengthBars = AudioImporter.barsForDuration(
                            metadata.durationSeconds,
                            tempo: tempo,
                            timeSignature: timeSignature
                        )
                    }
                    DispatchQueue.main.async {
                        state.ghostTracks.append(GhostTrackInfo(
                            fileName: baseName,
                            lengthBars: lengthBars,
                            trackKind: .audio,
                            url: url
                        ))
                    }
                }
            }
        }
    }
}

// MARK: - Track Drag-to-Reorder Drop Delegate

private struct TrackDropDelegate: DropDelegate {
    let targetTrack: Track
    @Binding var draggingTrackID: ID<Track>?
    let song: Song
    let onReorder: (IndexSet, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragID = draggingTrackID,
              dragID != targetTrack.id,
              targetTrack.kind != .master else { return }
        guard let sourceIndex = song.tracks.firstIndex(where: { $0.id == dragID }),
              let destIndex = song.tracks.firstIndex(where: { $0.id == targetTrack.id }) else { return }
        let destination = destIndex > sourceIndex ? destIndex + 1 : destIndex
        onReorder(IndexSet(integer: sourceIndex), destination)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingTrackID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        // Keep draggingTrackID until performDrop
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingTrackID != nil && targetTrack.kind != .master
    }
}

// MARK: - Selection-Based Inspector (isolated from MainContentView)

/// Isolates selection-dependent inspector content from MainContentView so that
/// changes to selectedContainerID / selectedTrackID only re-evaluate this view,
/// not the entire main content tree.
struct SelectionBasedInspectorView: View {
    @Bindable var projectViewModel: ProjectViewModel
    var selectionState: SelectionState
    var transportViewModel: TransportViewModel?
    var setlistViewModel: SetlistViewModel?
    var engineManager: AudioEngineManager?
    var settingsViewModel: SettingsViewModel?
    var midiActivityMonitor: MIDIActivityMonitor?
    var previewState: PreviewState
    @Binding var showContainerDetailEditor: Bool

    var body: some View {
        if let container = projectViewModel.selectedContainer {
            containerInspector(container: container)
        } else if let track = projectViewModel.selectedTrack {
            trackInspector(track: track)
        } else if let setlistVM = setlistViewModel,
                  let entry = setlistVM.selectedSetlistEntry {
            SetlistEntryInspectorView(
                entry: entry,
                songName: setlistVM.songName(for: entry),
                onUpdateTransition: { transition in
                    setlistVM.updateTransition(entryID: entry.id, transition: transition)
                },
                onUpdateFadeIn: { fadeIn in
                    setlistVM.updateFadeIn(entryID: entry.id, fadeIn: fadeIn)
                }
            )
        } else {
            Text("Select a container or track")
                .foregroundStyle(.secondary)
                .padding()
            Spacer()
        }
    }

    @ViewBuilder
    private func containerInspector(container: Container) -> some View {
        let parentContainer = container.parentContainerID.flatMap { projectViewModel.findContainer(id: $0) }
        let displayContainer = parentContainer.map { container.resolved(parent: $0) } ?? container
        ContainerInspector(
            container: displayContainer,
            trackKind: projectViewModel.selectedContainerTrackKind ?? .audio,
            containerTrack: projectViewModel.selectedContainerTrack ?? Track(name: "", kind: .audio),
            allContainers: projectViewModel.allContainersInCurrentSong,
            allTracks: projectViewModel.allTracksInCurrentSong,
            bpm: transportViewModel?.bpm ?? 120.0,
            beatsPerBar: transportViewModel?.timeSignature.beatsPerBar ?? 4,
            showDetailEditor: $showContainerDetailEditor,
            onUpdateLoopSettings: { settings in
                projectViewModel.updateContainerLoopSettings(containerID: container.id, settings: settings)
            },
            onUpdateName: { name in
                projectViewModel.updateContainerName(containerID: container.id, name: name)
            },
            onAddEffect: { effect in
                projectViewModel.addContainerEffect(containerID: container.id, effect: effect)
                PluginWindowManager.shared.open(
                    component: effect.component,
                    displayName: effect.displayName,
                    presetData: nil,
                    onPresetChanged: { data in
                        projectViewModel.updateContainerEffectPreset(containerID: container.id, effectID: effect.id, presetData: data)
                    }
                )
            },
            onRemoveEffect: { effectID in
                projectViewModel.removeContainerEffect(containerID: container.id, effectID: effectID)
            },
            onToggleEffectBypass: { effectID in
                projectViewModel.toggleContainerEffectBypass(containerID: container.id, effectID: effectID)
            },
            onToggleChainBypass: {
                projectViewModel.toggleContainerEffectChainBypass(containerID: container.id)
            },
            onReorderEffects: { source, destination in
                projectViewModel.reorderContainerEffects(containerID: container.id, from: source, to: destination)
            },
            onSetInstrumentOverride: { override in
                projectViewModel.setContainerInstrumentOverride(containerID: container.id, override: override)
            },
            onSetEnterFade: { fade in
                projectViewModel.setContainerEnterFade(containerID: container.id, fade: fade)
            },
            onSetExitFade: { fade in
                projectViewModel.setContainerExitFade(containerID: container.id, fade: fade)
            },
            onAddEnterAction: { action in
                projectViewModel.addContainerEnterAction(containerID: container.id, action: action)
            },
            onRemoveEnterAction: { actionID in
                projectViewModel.removeContainerEnterAction(containerID: container.id, actionID: actionID)
            },
            onAddExitAction: { action in
                projectViewModel.addContainerExitAction(containerID: container.id, action: action)
            },
            onRemoveExitAction: { actionID in
                projectViewModel.removeContainerExitAction(containerID: container.id, actionID: actionID)
            },
            onAddAutomationLane: { lane in
                projectViewModel.addAutomationLane(containerID: container.id, lane: lane)
            },
            onRemoveAutomationLane: { laneID in
                projectViewModel.removeAutomationLane(containerID: container.id, laneID: laneID)
            },
            onAddBreakpoint: { laneID, breakpoint in
                projectViewModel.addAutomationBreakpoint(containerID: container.id, laneID: laneID, breakpoint: breakpoint)
            },
            onRemoveBreakpoint: { laneID, breakpointID in
                projectViewModel.removeAutomationBreakpoint(containerID: container.id, laneID: laneID, breakpointID: breakpointID)
            },
            onUpdateBreakpoint: { laneID, breakpoint in
                projectViewModel.updateAutomationBreakpoint(containerID: container.id, laneID: laneID, breakpoint: breakpoint)
            },
            onUpdateEffectPreset: { effectID, data in
                projectViewModel.updateContainerEffectPreset(containerID: container.id, effectID: effectID, presetData: data)
            },
            liveEffectUnit: { index in
                transportViewModel?.liveEffectUnit(containerID: container.id, effectIndex: index)
            },
            onNavigateToParent: container.parentContainerID != nil ? {
                if let parentID = container.parentContainerID {
                    selectionState.selectedContainerID = parentID
                }
            } : nil,
            onResetField: container.isClone ? { field in
                projectViewModel.resetContainerField(containerID: container.id, field: field)
            } : nil,
            parentContainer: parentContainer,
            isMIDIActive: {
                guard let track = projectViewModel.selectedContainerTrack else { return false }
                return midiActivityMonitor?.isTrackActive(track.id) ?? false
            }(),
            transportViewModel: transportViewModel,
            previewedEffectID: containerPreviewedEffectID(containerID: container.id),
            previewedAutomationPath: containerPreviewedAutomationPath(containerID: container.id)
        )
    }

    @ViewBuilder
    private func trackInspector(track: Track) -> some View {
        TrackInspectorView(
            track: track,
            onRename: { name in
                projectViewModel.renameTrack(id: track.id, newName: name)
            },
            onAddEffect: { effect in
                projectViewModel.addTrackEffect(trackID: track.id, effect: effect)
                PluginWindowManager.shared.open(
                    component: effect.component,
                    displayName: effect.displayName,
                    presetData: nil,
                    onPresetChanged: { data in
                        projectViewModel.updateTrackEffectPreset(trackID: track.id, effectID: effect.id, presetData: data)
                    }
                )
            },
            onRemoveEffect: { effectID in
                projectViewModel.removeTrackEffect(trackID: track.id, effectID: effectID)
            },
            onToggleEffectBypass: { effectID in
                projectViewModel.toggleTrackEffectBypass(trackID: track.id, effectID: effectID)
            },
            onToggleChainBypass: {
                projectViewModel.toggleTrackEffectChainBypass(trackID: track.id)
            },
            onReorderEffects: { source, destination in
                projectViewModel.reorderTrackEffects(trackID: track.id, from: source, to: destination)
            },
            onUpdateEffectPreset: { effectID, data in
                projectViewModel.updateTrackEffectPreset(trackID: track.id, effectID: effectID, presetData: data)
            },
            onSetInputPort: { portID in
                projectViewModel.setTrackInputPort(trackID: track.id, portID: portID)
            },
            onSetOutputPort: { portID in
                if track.kind == .master {
                    projectViewModel.setMasterOutputPort(portID: portID)
                } else {
                    projectViewModel.setTrackOutputPort(trackID: track.id, portID: portID)
                }
            },
            onSetMIDIInput: { deviceID, channel in
                projectViewModel.setTrackMIDIInput(trackID: track.id, deviceID: deviceID, channel: channel)
            },
            onSetRecordingMonitoringMode: { mode in
                projectViewModel.setTrackRecordingMonitoringMode(trackID: track.id, mode: mode)
                if let updatedTrack = projectViewModel.currentSong?.tracks.first(where: { $0.id == track.id }),
                   updatedTrack.isMonitoring {
                    transportViewModel?.setInputMonitoring(track: updatedTrack, enabled: true)
                }
            },
            onVolumeLive: { volume in
                let pan = track.pan
                transportViewModel?.updateTrackMixLive(trackID: track.id, volume: volume, pan: pan)
            },
            onPanLive: { pan in
                let volume = track.volume
                transportViewModel?.updateTrackMixLive(trackID: track.id, volume: volume, pan: pan)
            },
            onSetVolume: { volume in
                projectViewModel.setTrackVolume(trackID: track.id, volume: volume)
            },
            onSetPan: { pan in
                projectViewModel.setTrackPan(trackID: track.id, pan: pan)
            },
            onMIDILearn: { targetPath in
                projectViewModel.startMIDIParameterLearn(targetPath: targetPath)
            },
            onRemoveMIDIMapping: { targetPath in
                projectViewModel.removeMIDIParameterMapping(forTarget: targetPath)
                projectViewModel.onMIDIParameterMappingsChanged?()
            },
            onAssignExpressionPedal: { cc, target in
                projectViewModel.assignExpressionPedal(trackID: track.id, cc: cc, target: target)
            },
            onRemoveExpressionPedal: {
                projectViewModel.removeExpressionPedal(trackID: track.id)
            },
            midiParameterMappings: projectViewModel.project.midiParameterMappings,
            isMIDILearning: projectViewModel.midiLearnState.isMIDIParameterLearning,
            previewedEffectID: trackPreviewedEffectID(trackID: track.id),
            previewedAutomationPath: trackPreviewedAutomationPath(trackID: track.id),
            availableInputPorts: settingsViewModel?.inputPorts ?? [],
            availableOutputPorts: settingsViewModel?.outputPorts ?? [],
            availableMIDIDevices: engineManager?.midiManager.availableInputDevices() ?? [],
            isLowLatencyRecordingEnabled: settingsViewModel?.lowLatencyRecordingEnabled ?? true,
            monitorPathDescriptor: transportViewModel?.monitorPathDescriptor(trackID: track.id),
            liveTrackEffectUnit: { index in
                transportViewModel?.liveTrackEffectUnit(trackID: track.id, effectIndex: index)
            }
        )
    }

    private func trackPreviewedEffectID(trackID: ID<Track>) -> ID<InsertEffect>? {
        guard let ref = previewState.previewedPluginInstance,
              ref.trackID == trackID,
              ref.containerID == nil,
              ref.host == .trackEffect else {
            return nil
        }
        return ref.insertEffectID
    }

    private func trackPreviewedAutomationPath(trackID: ID<Track>) -> EffectPath? {
        guard let path = previewState.previewedAutomationPath,
              path.trackID == trackID,
              path.containerID == nil else {
            return nil
        }
        return path
    }

    private func containerPreviewedEffectID(containerID: ID<Container>) -> ID<InsertEffect>? {
        guard let ref = previewState.previewedPluginInstance,
              ref.containerID == containerID,
              ref.host == .containerEffect else {
            return nil
        }
        return ref.insertEffectID
    }

    private func containerPreviewedAutomationPath(containerID: ID<Container>) -> EffectPath? {
        guard let path = previewState.previewedAutomationPath,
              path.containerID == containerID else {
            return nil
        }
        return path
    }
}

// MARK: - Cmd+Scroll Wheel Zoom (non-blocking)

/// Uses a local event monitor to intercept Cmd+scroll events for zoom
/// without blocking normal scroll, scrollbar dragging, or shift+scroll.
/// Also handles native trackpad pinch-to-zoom (magnify gesture).
private struct ScrollWheelHandlerModifier: ViewModifier {
    let onCmdScroll: (_ delta: CGFloat, _ mouseXInWindow: CGFloat) -> Void
    let onMagnify: ((_ magnification: CGFloat, _ mouseXInWindow: CGFloat) -> Void)?

    @State private var scrollMonitor: AnyObject?
    @State private var magnifyMonitor: AnyObject?

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Cmd+scroll wheel → discrete zoom
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    if event.modifierFlags.contains(.command) {
                        let delta = event.scrollingDeltaY
                        if delta != 0 {
                            let mouseX = event.locationInWindow.x
                            onCmdScroll(delta, mouseX)
                        }
                        return nil // consume the event
                    }
                    return event // pass through
                } as AnyObject

                // Native trackpad pinch-to-zoom (magnify gesture) → continuous zoom
                if let onMagnify {
                    magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { event in
                        let magnification = event.magnification
                        if abs(magnification) > 0.001 {
                            onMagnify(magnification, event.locationInWindow.x)
                        }
                        return event // pass through (don't consume — let other views see it)
                    } as AnyObject
                }
            }
            .onDisappear {
                if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
                if let magnifyMonitor { NSEvent.removeMonitor(magnifyMonitor) }
            }
    }
}

extension View {
    func scrollWheelHandler(
        onCmdScroll: @escaping (_ delta: CGFloat, _ mouseXInWindow: CGFloat) -> Void,
        onMagnify: ((_ magnification: CGFloat, _ mouseXInWindow: CGFloat) -> Void)? = nil
    ) -> some View {
        modifier(ScrollWheelHandlerModifier(onCmdScroll: onCmdScroll, onMagnify: onMagnify))
    }

    func inlineMIDIInputMonitor(
        shouldHandle: @escaping () -> Bool,
        onZoomIn: @escaping () -> Void,
        onZoomOut: @escaping () -> Void,
        onMagnify: @escaping (_ magnification: CGFloat) -> Void
    ) -> some View {
        modifier(InlineMIDIInputMonitorModifier(
            shouldHandle: shouldHandle,
            onZoomIn: onZoomIn,
            onZoomOut: onZoomOut,
            onMagnify: onMagnify
        ))
    }
}

private struct InlineMIDIInputMonitorModifier: ViewModifier {
    let shouldHandle: () -> Bool
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onMagnify: (_ magnification: CGFloat) -> Void

    @State private var keyMonitor: AnyObject?
    @State private var magnifyMonitor: AnyObject?

    func body(content: Content) -> some View {
        content
            .onAppear {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard shouldHandle() else { return event }
                    let blockedModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
                    guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return event }
                    switch event.charactersIgnoringModifiers {
                    case "+", "=":
                        onZoomIn()
                        return nil
                    case "-", "_":
                        onZoomOut()
                        return nil
                    default:
                        return event
                    }
                } as AnyObject

                magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { event in
                    guard shouldHandle() else { return event }
                    let magnification = CGFloat(event.magnification)
                    guard abs(magnification) > 0.001 else { return nil }
                    onMagnify(magnification)
                    return nil
                } as AnyObject
            }
            .onDisappear {
                if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
                if let magnifyMonitor { NSEvent.removeMonitor(magnifyMonitor) }
            }
    }
}

private struct GlobalShortcutMonitorModifier: ViewModifier {
    let shortcutManager: ShortcutManager
    let onAction: (AppShortcutAction) -> Void
    let shouldHandle: (AppShortcutAction) -> Bool

    @State private var keyMonitor: AnyObject?

    func body(content: Content) -> some View {
        content
            .onAppear {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard let shortcut = AppKeyboardShortcut(event: event) else { return event }
                    guard let action = AppShortcutAction.allCases.first(where: { shortcutManager.shortcut(for: $0) == shortcut }) else {
                        return event
                    }
                    guard shouldHandle(action) else { return event }
                    onAction(action)
                    return nil
                } as AnyObject
            }
            .onDisappear {
                if let keyMonitor {
                    NSEvent.removeMonitor(keyMonitor)
                }
            }
    }
}

private extension View {
    func globalShortcutMonitor(
        shortcutManager: ShortcutManager,
        onAction: @escaping (AppShortcutAction) -> Void,
        shouldHandle: @escaping (AppShortcutAction) -> Bool
    ) -> some View {
        modifier(
            GlobalShortcutMonitorModifier(
                shortcutManager: shortcutManager,
                onAction: onAction,
                shouldHandle: shouldHandle
            )
        )
    }
}

private struct ScrollViewIntrospector: NSViewRepresentable {
    let onResolve: (NSScrollView) -> Void

    func makeNSView(context: Context) -> ProbeView {
        ProbeView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolveScrollViewIfNeeded()
    }

    final class ProbeView: NSView {
        var onResolve: (NSScrollView) -> Void
        weak var resolvedScrollView: NSScrollView?

        init(onResolve: @escaping (NSScrollView) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            resolveScrollViewIfNeeded()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolveScrollViewIfNeeded()
        }

        override func layout() {
            super.layout()
            resolveScrollViewIfNeeded()
        }

        func resolveScrollViewIfNeeded() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let scrollView = self.enclosingScrollView else { return }
                if self.resolvedScrollView !== scrollView {
                    self.resolvedScrollView = scrollView
                    self.onResolve(scrollView)
                }
            }
        }
    }
}

final class TimelineHorizontalScrollCoordinator {
    weak var scrollView: NSScrollView?
    var onScroll: ((_ offsetX: CGFloat, _ viewportWidth: CGFloat) -> Void)?

    private var observer: NSObjectProtocol?
    private var isApplyingProgrammaticOffset = false
    private static let debugLogsEnabled: Bool = {
        ProcessInfo.processInfo.environment["LOOPS_GRID_DEBUG"] == "1"
        || UserDefaults.standard.bool(forKey: "PlaybackGridDebugLogs")
    }()

    func attachScrollView(_ scrollView: NSScrollView) {
        if self.scrollView === scrollView { return }
        detach()

        self.scrollView = scrollView
        scrollView.hasVerticalScroller = false
        scrollView.verticalScroller = nil
        scrollView.verticalScrollElasticity = .none
        if scrollView.contentView.bounds.origin.y != 0 {
            scrollView.contentView.setBoundsOrigin(NSPoint(x: scrollView.contentView.bounds.origin.x, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
        if Self.debugLogsEnabled {
            let b = scrollView.contentView.bounds
            print("[GRIDDBG][H] attach bounds=\(NSStringFromRect(b)) doc=\(NSStringFromRect(scrollView.documentView?.frame ?? .zero))")
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isApplyingProgrammaticOffset else { return }
            self.reportCurrentPosition()
        }
        reportCurrentPosition()
    }

    func setOffset(_ offsetX: CGFloat) {
        guard let scrollView else { return }
        let x = max(0, offsetX)
        isApplyingProgrammaticOffset = true
        scrollView.contentView.setBoundsOrigin(NSPoint(x: x, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isApplyingProgrammaticOffset = false
        if Self.debugLogsEnabled {
            print("[GRIDDBG][H] setOffset x=\(String(format: "%.1f", x)) docW=\(String(format: "%.1f", scrollView.documentView?.frame.width ?? 0)) viewW=\(String(format: "%.1f", scrollView.contentView.bounds.width))")
        }
        reportCurrentPosition()
    }

    func reportCurrentPosition() {
        guard let scrollView else { return }
        let x = scrollView.contentView.bounds.origin.x
        let width = scrollView.contentView.bounds.width
        onScroll?(x, width)
    }

    func detach() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        scrollView = nil
    }
}

final class TimelineVerticalScrollCoordinator {
    weak var headerScrollView: NSScrollView?
    weak var gridScrollView: NSScrollView?

    private var headerObserver: NSObjectProtocol?
    private var gridObserver: NSObjectProtocol?
    private var isSyncing = false
    private static let debugLogsEnabled: Bool = {
        ProcessInfo.processInfo.environment["LOOPS_GRID_DEBUG"] == "1"
        || UserDefaults.standard.bool(forKey: "PlaybackGridDebugLogs")
    }()

    func attachHeaderScrollView(_ scrollView: NSScrollView) {
        if headerScrollView === scrollView { return }
        detachHeaderObserver()

        headerScrollView = scrollView
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScroller = nil
        scrollView.horizontalScrollElasticity = .none
        setXOffset(0, for: scrollView)
        if scrollView.contentView.bounds.origin.y != 0 {
            setYOffset(0, for: scrollView)
        }
        if Self.debugLogsEnabled {
            print("[GRIDDBG][V] attach header bounds=\(NSStringFromRect(scrollView.contentView.bounds)) doc=\(NSStringFromRect(scrollView.documentView?.frame ?? .zero))")
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
        headerObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.sync(fromHeader: true)
        }
        alignInitialPosition()
    }

    func attachGridScrollView(_ scrollView: NSScrollView) {
        if gridScrollView === scrollView { return }
        detachGridObserver()

        gridScrollView = scrollView
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScroller = nil
        scrollView.horizontalScrollElasticity = .none
        setXOffset(0, for: scrollView)
        if scrollView.contentView.bounds.origin.y != 0 {
            setYOffset(0, for: scrollView)
        }
        if Self.debugLogsEnabled {
            print("[GRIDDBG][V] attach grid bounds=\(NSStringFromRect(scrollView.contentView.bounds)) doc=\(NSStringFromRect(scrollView.documentView?.frame ?? .zero))")
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
        gridObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.sync(fromHeader: false)
        }
        alignInitialPosition()
    }

    func resetToTop() {
        setVerticalOffset(0)
    }

    func detach() {
        detachHeaderObserver()
        detachGridObserver()
        headerScrollView = nil
        gridScrollView = nil
    }

    private func sync(fromHeader: Bool) {
        guard !isSyncing else { return }
        guard let headerScrollView, let gridScrollView else { return }

        isSyncing = true
        if fromHeader {
            let y = headerScrollView.contentView.bounds.origin.y
            setXOffset(0, for: headerScrollView)
            setYOffset(y, for: gridScrollView)
        } else {
            let y = gridScrollView.contentView.bounds.origin.y
            setXOffset(0, for: gridScrollView)
            setYOffset(y, for: headerScrollView)
        }
        isSyncing = false
    }

    private func alignInitialPosition() {
        guard let headerScrollView, let gridScrollView else { return }
        let y = gridScrollView.contentView.bounds.origin.y
        setXOffset(0, for: headerScrollView)
        setXOffset(0, for: gridScrollView)
        setYOffset(y, for: headerScrollView)
    }

    private func setVerticalOffset(_ y: CGFloat) {
        if let headerScrollView {
            setXOffset(0, for: headerScrollView)
            setYOffset(y, for: headerScrollView)
        }
        if let gridScrollView {
            setXOffset(0, for: gridScrollView)
            setYOffset(y, for: gridScrollView)
        }
    }

    private func setYOffset(_ y: CGFloat, for scrollView: NSScrollView) {
        let x = scrollView.contentView.bounds.origin.x
        if x != 0 {
            scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: max(0, y)))
        } else {
            scrollView.contentView.setBoundsOrigin(NSPoint(x: x, y: max(0, y)))
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func setXOffset(_ x: CGFloat, for scrollView: NSScrollView) {
        let currentX = scrollView.contentView.bounds.origin.x
        if currentX == x { return }
        if Self.debugLogsEnabled {
            let from = String(format: "%.1f", currentX)
            let to = String(format: "%.1f", x)
            print("[GRIDDBG][V] lockX \(from) -> \(to)")
        }
        let y = scrollView.contentView.bounds.origin.y
        scrollView.contentView.setBoundsOrigin(NSPoint(x: x, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func detachHeaderObserver() {
        if let headerObserver {
            NotificationCenter.default.removeObserver(headerObserver)
        }
        headerObserver = nil
    }

    private func detachGridObserver() {
        if let gridObserver {
            NotificationCenter.default.removeObserver(gridObserver)
        }
        gridObserver = nil
    }
}
