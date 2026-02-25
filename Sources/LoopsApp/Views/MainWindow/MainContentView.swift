import SwiftUI
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
    @State private var pianoRollEditorState = PianoRollEditorState()
    @State private var scrollSynchronizer = HorizontalScrollSynchronizer()
    @State private var ghostDropState = GhostTrackDropState()
    @State private var showTempoImportAlert = false
    @State private var pendingTempoImport: PendingTempoImport?
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

    public init(projectViewModel: ProjectViewModel, timelineViewModel: TimelineViewModel, selectionState: SelectionState? = nil, clipboardState: ClipboardState? = nil, transportViewModel: TransportViewModel? = nil, setlistViewModel: SetlistViewModel? = nil, engineManager: AudioEngineManager? = nil, settingsViewModel: SettingsViewModel? = nil, mixerViewModel: MixerViewModel? = nil, midiActivityMonitor: MIDIActivityMonitor? = nil, isVirtualKeyboardVisible: Binding<Bool> = .constant(false)) {
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

    public var body: some View {
        mainSplitView
        .sheet(isPresented: $showContainerDetailEditor) {
            containerDetailEditorSheet
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
        .onAppear { focusedField = .main }
        .onKeyPress(.space) {
            guard !isTextFieldFocused else { return .ignored }
            transportViewModel?.togglePlayPause()
            return .handled
        }
        .onKeyPress(.return) {
            guard !isTextFieldFocused else { return .ignored }
            if projectViewModel.selectedContainer != nil {
                openContainerEditor()
                return .handled
            }
            return .ignored
        }
        // Cmd+Return: open piano roll in pop-out sheet window
        .onKeyPress(.return, phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            guard !isTextFieldFocused else { return .ignored }
            openPianoRollSheet()
            return .handled
        }
        .onKeyPress("c", phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            handleCopy()
            return .handled
        }
        .onKeyPress("v", phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            handlePaste()
            return .handled
        }
        // R: toggle record arm on selected track
        .onKeyPress("r") {
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
            guard !isTextFieldFocused else { return .ignored }
            transportViewModel?.toggleMetronome()
            return .handled
        }
        // Left arrow: nudge playhead -1 bar (defers to piano roll when focused)
        .onKeyPress(.leftArrow) {
            guard !isTextFieldFocused, !isPianoRollFocused else { return .ignored }
            guard let tv = transportViewModel else { return .ignored }
            tv.setPlayheadPosition(max(tv.playheadBar - 1.0, 1.0))
            return .handled
        }
        // Right arrow: nudge playhead +1 bar (defers to piano roll when focused)
        .onKeyPress(.rightArrow) {
            guard !isTextFieldFocused, !isPianoRollFocused else { return .ignored }
            guard let tv = transportViewModel else { return .ignored }
            tv.setPlayheadPosition(tv.playheadBar + 1.0)
            return .handled
        }
        // Home (Fn+Left): jump to bar 1
        .onKeyPress(.home) {
            guard !isTextFieldFocused else { return .ignored }
            transportViewModel?.setPlayheadPosition(1.0)
            return .handled
        }
        // End (Fn+Right): jump to last bar with content
        .onKeyPress(.end) {
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
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            handleSplitAtPlayhead()
            return .handled
        }
        // Cmd+Shift+X: split selected container at range selection boundaries
        .onKeyPress("x", phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.command),
                  keyPress.modifiers.contains(.shift) else { return .ignored }
            handleSplitAtRange()
            return .handled
        }
        // Cmd+J: glue selected containers
        .onKeyPress("j", phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            projectViewModel.glueContainers(containerIDs: projectViewModel.selectedContainerIDs)
            return .handled
        }
        // Cmd+D: duplicate selected container (or track if no container selected)
        .onKeyPress("d", phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            handleDuplicate()
            return .handled
        }
        // Cmd+A: select all containers
        .onKeyPress("a", phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            projectViewModel.selectAllContainers()
            return .handled
        }
        // Escape: unfocus piano roll → deselect all + restore focus to main area
        .onKeyPress(.escape) {
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
            guard !isTextFieldFocused else { return .ignored }
            cycleInspectorMode()
            return .handled
        }
        // Cmd+Shift+M: toggle mixer view
        .onKeyPress("m", phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.shift) else { return .ignored }
            contentMode = contentMode == .timeline ? .mixer : .timeline
            return .handled
        }
        // Cmd+Shift+L: toggle MIDI log window
        .onKeyPress("l", phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.shift) else { return .ignored }
            if let monitor = midiActivityMonitor {
                MIDILogWindowManager.shared.toggle(monitor: monitor)
            }
            return .handled
        }
        // Cmd+Shift+K: toggle virtual MIDI keyboard
        .onKeyPress("k", phases: .down) { keyPress in
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
        // Track area — grid fills available space, scrollbar at bottom.
        // Ruler and section lane are docked at the top (outside the vertical scroll).
        // All tracks (including master) share a single grid and horizontal ScrollView.
        let regularTracks = song.tracks.filter { $0.kind != .master }
        // Ensure canvas and header column use identical track order:
        // regular tracks first, master always last.
        let masterTrack = song.tracks.first { $0.kind == .master }
        let allTracksOrdered = regularTracks + (masterTrack.map { [$0] } ?? [])

        // Fixed ruler + section header — not vertically scrollable.
        // When Metal rendering is active, the ruler is drawn inside the Metal view
        // (via TimelineTextOverlayLayer) to eliminate scroll synchronization drift.
        let metalActive = timelineViewModel.useNSViewTimeline && timelineViewModel.useMetalTimeline
        if !metalActive {
            rulerHeader(song: song)
        }

        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // Track headers — fixed width, scroll vertically with tracks (lazy)
                    // When Metal rendering is active, the ruler is drawn inside the Metal
                    // view (pinned to viewport top). A matching pinned Section header keeps
                    // the sidebar's "Sections" label aligned with the Metal ruler.
                    LazyVStack(spacing: 0, pinnedViews: metalActive ? [.sectionHeaders] : []) {
                      Section {
                        ForEach(regularTracks) { track in
                            VStack(spacing: 0) {
                                trackHeaderWithActions(track: track)
                                // Extra space to match inline piano roll height on timeline side
                                let prExtra = pianoRollEditorState.extraHeight(forTrackID: track.id)
                                if prExtra > 0 {
                                    inlinePianoRollKeyboardLabels
                                        .frame(height: prExtra)
                                }
                            }
                            .opacity(draggingTrackID == track.id ? 0.4 : 1.0)
                            .onDrag {
                                draggingTrackID = track.id
                                return NSItemProvider(object: track.id.rawValue.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: TrackDropDelegate(
                                targetTrack: track,
                                draggingTrackID: $draggingTrackID,
                                song: song,
                                onReorder: { source, destination in
                                    projectViewModel.moveTrack(from: source, to: destination)
                                }
                            ))
                        }
                        // Master track header — always at bottom, not draggable
                        if let master = song.tracks.first(where: { $0.kind == .master }) {
                            trackHeaderWithActions(track: master)
                        }
                        // Ghost track headers (shown during file drop over empty space)
                        if ghostDropState.isActive {
                            ForEach(ghostDropState.ghostTracks) { ghost in
                                ghostTrackHeader(ghost: ghost)
                            }
                        }
                        // Empty space at bottom for context menu target and file drop zone
                        Color.clear
                            .frame(height: max(80, geo.size.height - regularTrackListContentHeight(song: song)))
                            .contentShape(Rectangle())
                            .onDrop(of: [.fileURL], delegate: EmptyAreaFileDropDelegate(
                                ghostDropState: ghostDropState,
                                timelineViewModel: timelineViewModel,
                                projectViewModel: projectViewModel,
                                onPerformDrop: { urls, bar in
                                    handleEmptyAreaDrop(urls: urls, startBar: bar, song: song)
                                }
                            ))
                            .contextMenu {
                                ForEach(TrackKind.creatableKinds, id: \.self) { kind in
                                    Button("Insert \(kind.displayName) Track") {
                                        let insertIndex = song.tracks.filter({ $0.kind != .master }).count
                                        projectViewModel.insertTrack(kind: kind, atIndex: insertIndex)
                                    }
                                }
                            }
                      } header: {
                        // Pinned sidebar header when Metal is active — matches the
                        // pinned Metal ruler so track headers stay vertically aligned.
                        if metalActive {
                            VStack(spacing: 0) {
                                Color.clear.frame(height: TimelineCanvasView.rulerHeight)
                                Text("Sections")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .frame(height: TimelineCanvasView.trackAreaTop)
                            .background(Color(nsColor: .controlBackgroundColor))
                        }
                      }
                    }
                    .frame(width: timelineViewModel.trackHeaderWidth)
                    .frame(minHeight: geo.size.height)
                    .background(Color(nsColor: .controlBackgroundColor))

                    headerColumnResizeHandle

                    // Timeline — all tracks in one canvas, one horizontal ScrollView.
                    // Scrollbar is at the very bottom.
                    ScrollView(.horizontal, showsIndicators: true) {
                        TimelineView(
                            viewModel: timelineViewModel,
                            projectViewModel: projectViewModel,
                            selectionState: selectionState,
                            song: song,
                            tracks: allTracksOrdered,
                            minHeight: geo.size.height,
                            pianoRollState: pianoRollEditorState,
                            ghostDropState: ghostDropState,
                            showRulerAndSections: metalActive,
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
                            }
                        )
                    }
                }
                .frame(minHeight: geo.size.height)
                .onAppear {
                    timelineViewModel.setViewportWidth(geo.size.width - timelineViewModel.trackHeaderWidth - 4)
                }
                .onChange(of: geo.size.width) { _, newWidth in
                    timelineViewModel.setViewportWidth(newWidth - timelineViewModel.trackHeaderWidth - 4)
                }
            }
        }
        .scrollWheelHandler(
            onCmdScroll: { delta, mouseXInWindow in
                let zoomingIn = delta > 0
                guard let scrollView = findTimelineScrollView() else {
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
                scrollSynchronizer.isZooming = true
                scrollSynchronizer.setAllScrollOffsets(newScrollOffset)
                // Clear isZooming asynchronously: the document view resize
                // happens in the next SwiftUI layout pass, which can trigger
                // boundsDidChange → syncFrom() with a clamped offset.
                // pendingZoomOffset in syncFrom() re-applies the correct offset.
                DispatchQueue.main.async {
                    scrollSynchronizer.isZooming = false
                    scrollSynchronizer.pendingZoomOffset = nil
                }
            },
            onMagnify: { magnification, mouseXInWindow in
                guard let scrollView = findTimelineScrollView() else { return }
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
                scrollSynchronizer.isZooming = true
                scrollSynchronizer.setAllScrollOffsets(newScrollOffset)
                DispatchQueue.main.async {
                    scrollSynchronizer.isZooming = false
                    scrollSynchronizer.pendingZoomOffset = nil
                }
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
        .onAppear {
            scrollSynchronizer.onScroll = { [timelineViewModel] offsetX, viewportWidth in
                timelineViewModel.updateVisibleXRange(scrollOffsetX: offsetX, viewportWidth: viewportWidth)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                scrollSynchronizer.setup(expectedWidth: timelineViewModel.quantizedFrameWidth)
                scrollSynchronizer.setAllScrollOffsets(0)
                scrollSynchronizer.reportCurrentPosition()
            }
        }
        .onDisappear {
            scrollSynchronizer.teardown()
        }
        .onChange(of: timelineViewModel.quantizedFrameWidth) {
            guard !scrollSynchronizer.hasScrollViews else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scrollSynchronizer.setup(expectedWidth: timelineViewModel.quantizedFrameWidth)
            }
        }
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
        let isExpanded = timelineViewModel.automationExpanded.contains(track.id)
        let laneLabels = automationLaneLabels(for: track)
        let baseHeight = timelineViewModel.baseTrackHeight(for: track.id)
        let perTrackHeight = timelineViewModel.trackHeight(for: track, baseHeight: baseHeight)
        let isSelected = selectionState.selectedTrackID == track.id
        return TrackHeaderView(
            track: track,
            height: perTrackHeight,
            inputPortName: inputPortName(for: track.inputPortID),
            outputPortName: outputPortName(for: track.outputPortID),
            midiDeviceName: midiDeviceName(for: track.midiInputDeviceID),
            midiChannelLabel: midiChannelLabel(for: track.midiInputChannel),
            isAutomationExpanded: isExpanded,
            automationLaneLabels: laneLabels,
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
            onResizeTrack: { newHeight in
                timelineViewModel.setTrackHeight(newHeight, for: track.id)
            },
            onResetTrackHeight: {
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
            // Match toolbar + divider space (measured dynamically)
            Color(nsColor: .controlBackgroundColor).opacity(0.5)
                .frame(height: state.toolbarHeight)
                .overlay(alignment: .bottom) {
                    Divider()
                }

            // Pitch label rows — offset synced with piano roll vertical scroll
            VStack(spacing: 0) {
                // Match PianoRollContentView ruler (20pt) + divider (1pt)
                Color.clear.frame(height: 21)
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
                        : Color(white: 0.92).opacity(0.15))
                    .overlay(alignment: .bottom) {
                        if isC {
                            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 0.5)
                        }
                    }
                }
            }
            .offset(y: state.verticalScrollOffset)
            .frame(height: state.inlineHeight, alignment: .topLeading)
            .clipped()

            // Match resize handle space
            Color.secondary.opacity(0.3)
                .frame(height: PianoRollEditorState.resizeHandleHeight)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
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
            ForEach(TrackKind.creatableKinds, id: \.self) { kind in
                Button(kind.displayName) {
                    projectViewModel.addTrack(kind: kind)
                }
            }
        } label: {
            Label("Add Track", systemImage: "plus")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
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

    private func regularTrackListContentHeight(song: Song) -> CGFloat {
        song.tracks.filter { $0.kind != .master }.reduce(CGFloat(0)) { total, track in
            let trackH = timelineViewModel.trackHeight(for: track, baseHeight: timelineViewModel.baseTrackHeight(for: track.id))
            return total + trackH + pianoRollEditorState.extraHeight(forTrackID: track.id)
        }
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
            transportViewModel: transportViewModel
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
            availableInputPorts: settingsViewModel?.inputPorts ?? [],
            availableOutputPorts: settingsViewModel?.outputPorts ?? [],
            availableMIDIDevices: engineManager?.midiManager.availableInputDevices() ?? [],
            liveTrackEffectUnit: { index in
                transportViewModel?.liveTrackEffectUnit(trackID: track.id, effectIndex: index)
            }
        )
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
}

/// Finds the NSScrollView backing the timeline's horizontal scroll.
/// Walks the NSApp key window's view hierarchy looking for the timeline scroll view.
private func findTimelineScrollView() -> NSScrollView? {
    guard let window = NSApp.keyWindow else { return nil }
    let candidates = collectTimelineScrollViews(in: window.contentView)
    guard !candidates.isEmpty else { return nil }
    return candidates.max { lhs, rhs in
        let lhsDoc = lhs.documentView?.frame.width ?? 0
        let rhsDoc = rhs.documentView?.frame.width ?? 0
        if lhsDoc == rhsDoc {
            return lhs.contentView.bounds.width < rhs.contentView.bounds.width
        }
        return lhsDoc < rhsDoc
    }
}

private func collectTimelineScrollViews(in view: NSView?) -> [NSScrollView] {
    guard let view else { return [] }
    var result: [NSScrollView] = []
    if let scrollView = view as? NSScrollView,
       let documentWidth = scrollView.documentView?.frame.width,
       documentWidth > 1000,
       (scrollView.hasHorizontalScroller || scrollView.horizontalScroller != nil) {
        result.append(scrollView)
    }
    for subview in view.subviews {
        result.append(contentsOf: collectTimelineScrollViews(in: subview))
    }
    return result
}

// MARK: - Horizontal Scroll Synchronization

/// Synchronizes horizontal scroll views whose document width matches
/// the timeline's total width. With ruler and section lane now drawn
/// inside the canvas, this only syncs the track timeline and master track.
final class HorizontalScrollSynchronizer {
    private var observers: [NSObjectProtocol] = []
    private var scrollViews: [NSScrollView] = []
    private var isSyncing = false
    /// Set during zoom to suppress re-entrant boundsDidChange callbacks.
    var isZooming = false
    /// Offset to re-apply when NSScrollView fires boundsDidChange during zoom layout.
    var pendingZoomOffset: CGFloat?
    /// Whether scroll views have been discovered and are being tracked.
    var hasScrollViews: Bool { !scrollViews.isEmpty }
    var onScroll: ((_ offsetX: CGFloat, _ viewportWidth: CGFloat) -> Void)?
    /// Current scroll offset snapshot — read by ruler Canvas for viewport culling.
    /// Not @Observable: reading this does NOT cause SwiftUI re-evaluation.
    private(set) var currentScrollOffset: CGFloat = 0
    /// Current viewport width snapshot.
    private(set) var currentViewportWidth: CGFloat = 1400

    func setup(expectedWidth: CGFloat) {
        teardown()
        guard let window = NSApp.keyWindow else { return }
        scrollViews = Self.findTimelineScrollViews(in: window.contentView, expectedWidth: expectedWidth)
        guard !scrollViews.isEmpty else { return }

        for sv in scrollViews {
            sv.contentView.postsBoundsChangedNotifications = true
            let observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: sv.contentView,
                queue: .main
            ) { [weak self] notification in
                guard let self, !self.isSyncing, !self.isZooming,
                      let clipView = notification.object as? NSClipView,
                      let source = clipView.enclosingScrollView else {
                    return
                }
                self.syncFrom(source)
            }
            observers.append(observer)
        }
    }

    func teardown() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        scrollViews.removeAll()
    }

    private func syncFrom(_ source: NSScrollView) {
        // During zoom, the document view resize triggers boundsDidChange with a
        // clamped offset. Re-apply the pending zoom offset instead.
        if let pending = pendingZoomOffset {
            isSyncing = true
            for sv in scrollViews {
                if abs(sv.contentView.bounds.origin.x - pending) > 0.5 {
                    sv.contentView.setBoundsOrigin(NSPoint(x: pending, y: sv.contentView.bounds.origin.y))
                    sv.reflectScrolledClipView(sv.contentView)
                }
            }
            currentScrollOffset = pending
            if let sv = scrollViews.first {
                currentViewportWidth = sv.contentView.bounds.width
                onScroll?(pending, currentViewportWidth)
            }
            isSyncing = false
            return
        }

        isSyncing = true
        let offsetX = source.contentView.bounds.origin.x
        for sv in scrollViews where sv !== source {
            if abs(sv.contentView.bounds.origin.x - offsetX) > 0.5 {
                sv.contentView.setBoundsOrigin(NSPoint(x: offsetX, y: sv.contentView.bounds.origin.y))
                sv.reflectScrolledClipView(sv.contentView)
            }
        }
        let viewportWidth = source.contentView.bounds.width
        currentScrollOffset = offsetX
        currentViewportWidth = viewportWidth
        onScroll?(offsetX, viewportWidth)
        isSyncing = false
    }

    /// Sets all tracked scroll views to the given horizontal offset.
    /// Used during zoom to keep ruler, section, timeline, and master in sync.
    func setAllScrollOffsets(_ offsetX: CGFloat) {
        pendingZoomOffset = offsetX
        isSyncing = true
        for sv in scrollViews {
            if abs(sv.contentView.bounds.origin.x - offsetX) > 0.5 {
                sv.contentView.setBoundsOrigin(NSPoint(x: offsetX, y: sv.contentView.bounds.origin.y))
                sv.reflectScrolledClipView(sv.contentView)
            }
        }
        currentScrollOffset = offsetX
        if let sv = scrollViews.first {
            let viewportWidth = sv.contentView.bounds.width
            currentViewportWidth = viewportWidth
            onScroll?(offsetX, viewportWidth)
        }
        isSyncing = false
    }

    /// Reports the current scroll position. Call after setup to populate initial visible range.
    func reportCurrentPosition() {
        guard let sv = scrollViews.first else { return }
        let offsetX = sv.contentView.bounds.origin.x
        let width = sv.contentView.bounds.width
        currentScrollOffset = offsetX
        currentViewportWidth = width
        onScroll?(offsetX, width)
    }

    /// Finds all horizontal NSScrollViews whose document width is close to expectedWidth.
    private static func findTimelineScrollViews(in view: NSView?, expectedWidth: CGFloat) -> [NSScrollView] {
        guard let view else { return [] }
        var result: [NSScrollView] = []
        if let sv = view as? NSScrollView,
           let docWidth = sv.documentView?.frame.width,
           abs(docWidth - expectedWidth) < 20 {
            result.append(sv)
        }
        for subview in view.subviews {
            result.append(contentsOf: findTimelineScrollViews(in: subview, expectedWidth: expectedWidth))
        }
        return result
    }
}
