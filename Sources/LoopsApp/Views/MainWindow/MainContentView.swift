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
    @State private var showPianoRollEditor: Bool = false
    @State private var pianoRollSnapResolution: SnapResolution = .sixteenth
    @State private var editingSectionID: ID<SectionRegion>?
    @State private var editingSectionName: String = ""
    @State private var inspectorMode: InspectorMode = .container
    @State private var draggingTrackID: ID<Track>?
    @State private var headerDragStartWidth: CGFloat = 0
    @State private var pendingTrackAutomationLane: PendingEffectSelection?
    @FocusState private var focusedField: FocusedField?
    @Namespace private var inspectorNamespace
    // isMIDILearning and midiLearnTargetPath are on projectViewModel

    /// Returns true when keyboard focus has moved away from the main content area
    /// (e.g. to a text field in the inspector panel).
    private var isTextFieldFocused: Bool {
        focusedField != .main
    }

    public init(projectViewModel: ProjectViewModel, timelineViewModel: TimelineViewModel, transportViewModel: TransportViewModel? = nil, setlistViewModel: SetlistViewModel? = nil, engineManager: AudioEngineManager? = nil, settingsViewModel: SettingsViewModel? = nil, mixerViewModel: MixerViewModel? = nil, midiActivityMonitor: MIDIActivityMonitor? = nil, isVirtualKeyboardVisible: Binding<Bool> = .constant(false)) {
        self.projectViewModel = projectViewModel
        self.timelineViewModel = timelineViewModel
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
                onDismiss: {
                    showContainerDetailEditor = false
                }
            )
        }
    }

    /// Opens the appropriate editor for the selected container.
    /// MIDI containers on MIDI tracks open the piano roll; others open the detail editor.
    private func openContainerEditor() {
        guard let container = projectViewModel.selectedContainer,
              let track = projectViewModel.selectedContainerTrack else { return }
        if track.kind == .midi {
            // Ensure the container has a MIDI sequence; create one if needed
            if container.midiSequence == nil {
                projectViewModel.setContainerMIDISequence(
                    containerID: container.id,
                    sequence: MIDISequence()
                )
            }
            showPianoRollEditor = true
        } else {
            showContainerDetailEditor = true
        }
    }

    @ViewBuilder
    private var pianoRollEditorSheet: some View {
        if let container = projectViewModel.selectedContainer,
           let song = projectViewModel.currentSong {
            let sequence = container.midiSequence ?? MIDISequence()
            PianoRollView(
                containerID: container.id,
                sequence: sequence,
                lengthBars: container.lengthBars,
                timeSignature: song.timeSignature,
                snapResolution: pianoRollSnapResolution,
                onAddNote: { note in
                    projectViewModel.addMIDINote(containerID: container.id, note: note)
                },
                onUpdateNote: { note in
                    projectViewModel.updateMIDINote(containerID: container.id, note: note)
                },
                onRemoveNote: { noteID in
                    projectViewModel.removeMIDINote(containerID: container.id, noteID: noteID)
                }
            )
            .frame(minWidth: 600, minHeight: 400)
        }
    }

    public var body: some View {
        mainSplitView
        .sheet(isPresented: $showContainerDetailEditor) {
            containerDetailEditorSheet
        }
        .sheet(isPresented: $showPianoRollEditor) {
            pianoRollEditorSheet
        }
        .sheet(item: $pendingTrackAutomationLane) { pending in
            ParameterPickerView(
                pending: pending,
                onPick: { path in
                    let lane = AutomationLane(targetPath: path)
                    projectViewModel.addTrackAutomationLane(trackID: path.trackID, lane: lane)
                    timelineViewModel.automationExpanded.insert(path.trackID)
                    pendingTrackAutomationLane = nil
                },
                onCancel: { pendingTrackAutomationLane = nil }
            )
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
            guard let trackID = projectViewModel.selectedTrackID else { return .ignored }
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
        // Left arrow: nudge playhead -1 bar
        .onKeyPress(.leftArrow) {
            guard !isTextFieldFocused else { return .ignored }
            guard let tv = transportViewModel else { return .ignored }
            tv.setPlayheadPosition(max(tv.playheadBar - 1.0, 1.0))
            return .handled
        }
        // Right arrow: nudge playhead +1 bar
        .onKeyPress(.rightArrow) {
            guard !isTextFieldFocused else { return .ignored }
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
        // Escape: deselect all + restore focus to main area
        .onKeyPress(.escape) {
            if isTextFieldFocused {
                focusedField = .main
                return .handled
            }
            projectViewModel.deselectAll()
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
                    SetlistSidebarView(viewModel: setlistVM, playheadBar: timelineViewModel.playheadBar)
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
                            guard let trackID = projectViewModel.selectedTrackID else { return }
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
                containerInspectorContent
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
        // Ruler row (fixed, not scrollable vertically)
        HStack(spacing: 0) {
            Color.clear.frame(width: timelineViewModel.trackHeaderWidth, height: 20)
            headerColumnResizeHandle
            ScrollView(.horizontal, showsIndicators: false) {
                RulerView(
                    totalBars: timelineViewModel.totalBars,
                    pixelsPerBar: timelineViewModel.pixelsPerBar,
                    timeSignature: song.timeSignature,
                    selectedRange: timelineViewModel.selectedRange,
                    onRangeSelect: { range in
                        timelineViewModel.selectedRange = range
                    },
                    onRangeDeselect: {
                        timelineViewModel.clearSelectedRange()
                    },
                    onPlayheadPosition: { bar in
                        transportViewModel?.seek(toBar: bar)
                    }
                )
            }
        }
        .frame(height: 20)
        Divider()

        // Section lane row (fixed, not scrollable vertically)
        HStack(spacing: 0) {
            Text("Sections")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: timelineViewModel.trackHeaderWidth, height: 24)
                .background(Color(nsColor: .controlBackgroundColor))
            headerColumnResizeHandle
            ScrollView(.horizontal, showsIndicators: false) {
                SectionLaneView(
                    sections: song.sections,
                    pixelsPerBar: timelineViewModel.pixelsPerBar,
                    totalBars: timelineViewModel.totalBars,
                    selectedSectionID: projectViewModel.selectedSectionID,
                    onSectionSelect: { sectionID in
                        projectViewModel.selectedSectionID = sectionID
                    },
                    onSectionCreate: { startBar, lengthBars in
                        projectViewModel.addSection(startBar: startBar, lengthBars: lengthBars)
                    },
                    onSectionMove: { sectionID, newStartBar in
                        projectViewModel.moveSection(sectionID: sectionID, newStartBar: newStartBar)
                    },
                    onSectionResizeLeft: { sectionID, newStart, newLength in
                        projectViewModel.resizeSection(sectionID: sectionID, newStartBar: newStart, newLengthBars: newLength)
                    },
                    onSectionResizeRight: { sectionID, newLength in
                        projectViewModel.resizeSection(sectionID: sectionID, newLengthBars: newLength)
                    },
                    onSectionDoubleClick: { sectionID in
                        editingSectionID = sectionID
                        if let section = song.sections.first(where: { $0.id == sectionID }) {
                            editingSectionName = section.name
                        }
                    },
                    onSectionNavigate: { bar in
                        transportViewModel?.setPlayheadPosition(Double(bar))
                    },
                    onSectionDelete: { sectionID in
                        projectViewModel.removeSection(sectionID: sectionID)
                    },
                    onSectionRecolor: { sectionID, color in
                        projectViewModel.recolorSection(sectionID: sectionID, color: color)
                    },
                    onSectionCopy: { sectionID in
                        projectViewModel.copySectionWithMetadata(sectionID: sectionID)
                    },
                    onSectionSplit: { sectionID in
                        let bar = Int(timelineViewModel.playheadBar)
                        projectViewModel.splitSection(sectionID: sectionID, atBar: bar)
                    }
                )
            }
        }
        .frame(height: 24)
        Divider()

        // Track area — grid fills available space, scrollbar at bottom.
        // Split regular tracks (scrollable) from master track (pinned at bottom).
        let regularTracks = song.tracks.filter { $0.kind != .master }
        let masterTrack = song.tracks.first { $0.kind == .master }

        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // Track headers — fixed width, scroll vertically with tracks
                    VStack(spacing: 0) {
                        ForEach(regularTracks) { track in
                            trackHeaderWithActions(track: track)
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
                        // Empty space at bottom for context menu target (at least one track height)
                        Color.clear
                            .frame(height: max(80, geo.size.height - regularTrackListContentHeight(song: song)))
                            .contentShape(Rectangle())
                            .contextMenu {
                                ForEach(TrackKind.creatableKinds, id: \.self) { kind in
                                    Button("Insert \(kind.displayName) Track") {
                                        let insertIndex = song.tracks.filter({ $0.kind != .master }).count
                                        projectViewModel.insertTrack(kind: kind, atIndex: insertIndex)
                                    }
                                }
                            }
                    }
                    .frame(width: timelineViewModel.trackHeaderWidth)
                    .frame(minHeight: geo.size.height)
                    .background(Color(nsColor: .controlBackgroundColor))

                    headerColumnResizeHandle

                    // Timeline — scrolls horizontally inside, vertically with parent
                    ScrollView(.horizontal, showsIndicators: true) {
                        TimelineView(
                            viewModel: timelineViewModel,
                            projectViewModel: projectViewModel,
                            song: song,
                            tracks: regularTracks,
                            minHeight: geo.size.height,
                            onContainerDoubleClick: {
                                openContainerEditor()
                            },
                            onPlayheadPosition: { bar in
                                transportViewModel?.seek(toBar: bar)
                            }
                        )
                    }
                }
                .frame(minHeight: geo.size.height)
            }
        }
        .scrollWheelHandler(
            onCmdScroll: { delta in
                if delta > 0 {
                    timelineViewModel.zoomIn()
                } else {
                    timelineViewModel.zoomOut()
                }
            }
        )

        // Master track — pinned at bottom, does not scroll vertically
        if let master = masterTrack {
            let masterBaseHeight = timelineViewModel.baseTrackHeight(for: master.id)
            let masterHeight = timelineViewModel.trackHeight(for: master, baseHeight: masterBaseHeight)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                trackHeaderWithActions(track: master)
                    .frame(width: timelineViewModel.trackHeaderWidth, height: masterHeight)
                    .background(Color(nsColor: .controlBackgroundColor))

                headerColumnResizeHandle

                ScrollView(.horizontal, showsIndicators: false) {
                    TimelineView(
                        viewModel: timelineViewModel,
                        projectViewModel: projectViewModel,
                        song: song,
                        tracks: [master],
                        minHeight: 0,
                        onContainerDoubleClick: {
                            openContainerEditor()
                        },
                        onPlayheadPosition: { bar in
                            transportViewModel?.seek(toBar: bar)
                        }
                    )
                }
            }
            .frame(height: masterHeight)
        }

        Divider()

        // Add Track button
        HStack {
            addTrackMenu
                .padding(4)
                .frame(width: timelineViewModel.trackHeaderWidth)
            Spacer()
        }
    }

    // MARK: - Mixer Content

    @ViewBuilder
    private func mixerContent(song: Song) -> some View {
        MixerView(
            tracks: song.tracks,
            mixerViewModel: mixerViewModel ?? MixerViewModel(),
            selectedTrackID: projectViewModel.selectedTrackID,
            onVolumeChange: { trackID, volume in
                projectViewModel.setTrackVolume(trackID: trackID, volume: volume)
            },
            onPanChange: { trackID, pan in
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
                projectViewModel.selectedTrackID = trackID
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

    // MARK: - Inspector Content

    @ViewBuilder
    private var containerInspectorContent: some View {
        if let container = projectViewModel.selectedContainer {
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
                        projectViewModel.selectedContainerID = parentID
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
                playheadBar: transportViewModel?.playheadBar ?? 1.0
            )
        } else if let track = projectViewModel.selectedTrack {
            trackInspectorContent(track: track)
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
    private func trackInspectorContent(track: Track) -> some View {
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
                    onPresetChanged: nil
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
            isMIDILearning: projectViewModel.isMIDIParameterLearning,
            availableInputPorts: settingsViewModel?.inputPorts ?? [],
            availableOutputPorts: settingsViewModel?.outputPorts ?? [],
            availableMIDIDevices: engineManager?.midiManager.availableInputDevices() ?? [],
            liveTrackEffectUnit: { index in
                transportViewModel?.liveTrackEffectUnit(trackID: track.id, effectIndex: index)
            }
        )
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
        let isSelected = projectViewModel.selectedTrackID == track.id
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
                        projectViewModel.selectedTrackID = track.id
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
                startBar: range.lowerBound,
                endBar: range.upperBound + 1,
                trackFilter: timelineViewModel.selectedTrackIDs
            )
        } else if let containerID = projectViewModel.selectedContainerID, let song = currentSong {
            for track in song.tracks {
                if track.containers.contains(where: { $0.id == containerID }) {
                    projectViewModel.copyContainer(trackID: track.id, containerID: containerID)
                    return
                }
            }
        }
    }

    private func handlePaste() {
        guard !projectViewModel.clipboard.isEmpty || projectViewModel.clipboardSectionRegion != nil else { return }
        let playheadBar = Int(timelineViewModel.playheadBar)
        projectViewModel.pasteContainersToOriginalTracks(atBar: playheadBar)
    }

    private func selectTrackByKeyIndex(_ index: Int) -> KeyPress.Result {
        guard !isTextFieldFocused else { return .ignored }
        projectViewModel.selectTrackByIndex(index)
        return .handled
    }

    private func handleDuplicate() {
        // Prefer duplicating selected container first
        if let containerID = projectViewModel.selectedContainerID, let song = currentSong {
            for track in song.tracks {
                if track.containers.contains(where: { $0.id == containerID }) {
                    projectViewModel.duplicateContainer(trackID: track.id, containerID: containerID)
                    return
                }
            }
        }
        // Fall back to duplicating selected track
        if let trackID = projectViewModel.selectedTrackID {
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

    private var headerColumnResizeHandle: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
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
        let trackName = currentSong?.tracks.first(where: { $0.id == path.trackID })?.name ?? "?"
        if let containerID = path.containerID {
            let cName = currentSong?.tracks.flatMap(\.containers).first(where: { $0.id == containerID })?.name ?? "?"
            return "\(trackName)/\(cName) FX\(path.effectIndex)"
        }
        return "\(trackName) FX\(path.effectIndex)"
    }

    private func regularTrackListContentHeight(song: Song) -> CGFloat {
        song.tracks.filter { $0.kind != .master }.reduce(CGFloat(0)) { total, track in
            total + timelineViewModel.trackHeight(for: track, baseHeight: timelineViewModel.baseTrackHeight(for: track.id))
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

// MARK: - Cmd+Scroll Wheel Zoom (non-blocking)

/// Uses a local event monitor to intercept Cmd+scroll events for zoom
/// without blocking normal scroll, scrollbar dragging, or shift+scroll.
private struct ScrollWheelHandlerModifier: ViewModifier {
    let onCmdScroll: (CGFloat) -> Void

    @State private var monitor: AnyObject?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    if event.modifierFlags.contains(.command) {
                        let delta = event.scrollingDeltaY
                        if delta != 0 {
                            onCmdScroll(delta)
                        }
                        return nil // consume the event
                    }
                    return event // pass through
                } as AnyObject
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
    }
}

extension View {
    func scrollWheelHandler(onCmdScroll: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollWheelHandlerModifier(onCmdScroll: onCmdScroll))
    }
}
