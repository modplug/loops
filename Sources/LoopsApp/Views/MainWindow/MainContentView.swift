import SwiftUI
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

/// Main content area using HSplitView: sidebar + timeline/mixer + inspector.
public struct MainContentView: View {
    @Bindable var projectViewModel: ProjectViewModel
    @Bindable var timelineViewModel: TimelineViewModel
    var transportViewModel: TransportViewModel?
    var setlistViewModel: SetlistViewModel?
    var engineManager: AudioEngineManager?
    var settingsViewModel: SettingsViewModel?
    var mixerViewModel: MixerViewModel?
    @State private var contentMode: ContentMode = .timeline
    @State private var trackToDelete: Track?
    @State private var editingTrackID: ID<Track>?
    @State private var editingTrackName: String = ""
    @State private var isSidebarVisible: Bool = true
    @State private var sidebarTab: SidebarTab = .songs
    @State private var showContainerDetailEditor: Bool = false
    @State private var editingSectionID: ID<SectionRegion>?
    @State private var editingSectionName: String = ""
    @State private var inspectorMode: InspectorMode = .container
    @FocusState private var isMainFocused: Bool
    // isMIDILearning and midiLearnTargetPath are on projectViewModel

    public init(projectViewModel: ProjectViewModel, timelineViewModel: TimelineViewModel, transportViewModel: TransportViewModel? = nil, setlistViewModel: SetlistViewModel? = nil, engineManager: AudioEngineManager? = nil, settingsViewModel: SettingsViewModel? = nil, mixerViewModel: MixerViewModel? = nil) {
        self.projectViewModel = projectViewModel
        self.timelineViewModel = timelineViewModel
        self.transportViewModel = transportViewModel
        self.setlistViewModel = setlistViewModel
        self.engineManager = engineManager
        self.settingsViewModel = settingsViewModel
        self.mixerViewModel = mixerViewModel
    }

    private var currentSong: Song? {
        projectViewModel.currentSong
    }

    @ViewBuilder
    private var containerDetailEditorSheet: some View {
        if let container = projectViewModel.selectedContainer,
           let track = projectViewModel.selectedContainerTrack {
            ContainerDetailEditor(
                container: container,
                trackKind: track.kind,
                containerTrack: track,
                allContainers: projectViewModel.allContainersInCurrentSong,
                allTracks: projectViewModel.allTracksInCurrentSong,
                onAddEffect: { effect in
                    projectViewModel.addContainerEffect(containerID: container.id, effect: effect)
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
                onDismiss: {
                    showContainerDetailEditor = false
                }
            )
        }
    }

    public var body: some View {
        mainSplitView
        .sheet(isPresented: $showContainerDetailEditor) {
            containerDetailEditorSheet
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
        .focused($isMainFocused)
        .onAppear { isMainFocused = true }
        .onKeyPress(.space) {
            transportViewModel?.togglePlayPause()
            return .handled
        }
        .onKeyPress(.return) {
            if projectViewModel.selectedContainer != nil {
                showContainerDetailEditor = true
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
            guard let trackID = projectViewModel.selectedTrackID else { return .ignored }
            if let track = currentSong?.tracks.first(where: { $0.id == trackID }) {
                projectViewModel.setTrackRecordArmed(trackID: trackID, armed: !track.isRecordArmed)
                return .handled
            }
            return .ignored
        }
        // M: toggle metronome
        .onKeyPress("m") {
            transportViewModel?.toggleMetronome()
            return .handled
        }
        // Left arrow: nudge playhead -1 bar
        .onKeyPress(.leftArrow) {
            guard let tv = transportViewModel else { return .ignored }
            tv.setPlayheadPosition(max(tv.playheadBar - 1.0, 1.0))
            return .handled
        }
        // Right arrow: nudge playhead +1 bar
        .onKeyPress(.rightArrow) {
            guard let tv = transportViewModel else { return .ignored }
            tv.setPlayheadPosition(tv.playheadBar + 1.0)
            return .handled
        }
        // Home (Fn+Left): jump to bar 1
        .onKeyPress(.home) {
            transportViewModel?.setPlayheadPosition(1.0)
            return .handled
        }
        // End (Fn+Right): jump to last bar with content
        .onKeyPress(.end) {
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
        // Escape: deselect all
        .onKeyPress(.escape) {
            projectViewModel.deselectAll()
            timelineViewModel.selectedTrackIDs = []
            timelineViewModel.clearSelectedRange()
            return .handled
        }
        // Tab: cycle inspector mode
        .onKeyPress(.tab) {
            cycleInspectorMode()
            return .handled
        }
        // Cmd+Shift+M: toggle mixer view
        .onKeyPress("m", phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.shift) else { return .ignored }
            contentMode = contentMode == .timeline ? .mixer : .timeline
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
                    SetlistSidebarView(viewModel: setlistVM)
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
    }

    // MARK: - Timeline Content

    @ViewBuilder
    private func timelineContent(song: Song) -> some View {
        // Ruler row (fixed, not scrollable vertically)
        HStack(spacing: 0) {
            Color.clear.frame(width: 160, height: 20)
            Divider()
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
                .frame(width: 160, height: 24)
                .background(Color(nsColor: .controlBackgroundColor))
            Divider()
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
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // Track headers — fixed width, scroll vertically with tracks
                    VStack(spacing: 0) {
                        ForEach(song.tracks) { track in
                            trackHeaderWithActions(track: track)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 160)
                    .frame(minHeight: geo.size.height)
                    .background(Color(nsColor: .controlBackgroundColor))

                    Divider()

                    // Timeline — scrolls horizontally inside, vertically with parent
                    ScrollView(.horizontal, showsIndicators: true) {
                        TimelineView(
                            viewModel: timelineViewModel,
                            projectViewModel: projectViewModel,
                            song: song,
                            minHeight: geo.size.height,
                            onContainerDoubleClick: {
                                showContainerDetailEditor = true
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

        Divider()

        // Add Track button
        HStack {
            addTrackMenu
                .padding(4)
                .frame(width: 160)
            Spacer()
        }
    }

    // MARK: - Mixer Content

    @ViewBuilder
    private func mixerContent(song: Song) -> some View {
        MixerView(
            tracks: song.tracks,
            mixerViewModel: mixerViewModel ?? MixerViewModel(),
            onVolumeChange: { trackID, volume in
                projectViewModel.setTrackVolume(trackID: trackID, volume: volume)
            },
            onPanChange: { trackID, pan in
                projectViewModel.setTrackPan(trackID: trackID, pan: pan)
            },
            onMuteToggle: { trackID in
                projectViewModel.toggleMute(trackID: trackID)
            },
            onSoloToggle: { trackID in
                projectViewModel.toggleSolo(trackID: trackID)
            },
            onRecordArmToggle: { trackID, armed in
                projectViewModel.setTrackRecordArmed(trackID: trackID, armed: armed)
            },
            onMonitorToggle: { trackID, monitoring in
                projectViewModel.setTrackMonitoring(trackID: trackID, monitoring: monitoring)
                if let track = song.tracks.first(where: { $0.id == trackID }) {
                    transportViewModel?.setInputMonitoring(track: track, enabled: monitoring)
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        Divider()

        // Add Track button
        HStack {
            addTrackMenu
                .padding(4)
                .frame(width: 160)
            Spacer()
        }
    }

    // MARK: - Inspector Content

    @ViewBuilder
    private var containerInspectorContent: some View {
        if let container = projectViewModel.selectedContainer {
            ContainerInspector(
                container: container,
                trackKind: projectViewModel.selectedContainerTrackKind ?? .audio,
                allContainers: projectViewModel.allContainersInCurrentSong,
                allTracks: projectViewModel.allTracksInCurrentSong,
                showDetailEditor: $showContainerDetailEditor,
                onUpdateLoopSettings: { settings in
                    projectViewModel.updateContainerLoopSettings(containerID: container.id, settings: settings)
                },
                onUpdateName: { name in
                    projectViewModel.updateContainerName(containerID: container.id, name: name)
                },
                onAddEffect: { effect in
                    projectViewModel.addContainerEffect(containerID: container.id, effect: effect)
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
                }
            )
        } else if let track = projectViewModel.selectedTrack {
            trackInspectorContent(track: track)
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
            inputPortName: inputPortName(for: track.inputPortID),
            outputPortName: outputPortName(for: track.outputPortID),
            midiDeviceName: midiDeviceName(for: track.midiInputDeviceID),
            midiChannelLabel: midiChannelLabel(for: track.midiInputChannel)
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
        let perTrackHeight = timelineViewModel.trackHeight(for: track, baseHeight: 80)
        let isSelected = timelineViewModel.selectedTrackIDs.contains(track.id)
        return TrackHeaderView(
            track: track,
            height: perTrackHeight,
            inputPortName: inputPortName(for: track.inputPortID),
            outputPortName: outputPortName(for: track.outputPortID),
            midiDeviceName: midiDeviceName(for: track.midiInputDeviceID),
            midiChannelLabel: midiChannelLabel(for: track.midiInputChannel),
            isAutomationExpanded: isExpanded,
            automationLaneLabels: laneLabels,
            onMuteToggle: { projectViewModel.toggleMute(trackID: track.id) },
            onSoloToggle: { projectViewModel.toggleSolo(trackID: track.id) },
            onRecordArmToggle: { projectViewModel.setTrackRecordArmed(trackID: track.id, armed: !track.isRecordArmed) },
            onMonitorToggle: {
                let newState = !track.isMonitoring
                projectViewModel.setTrackMonitoring(trackID: track.id, monitoring: newState)
                transportViewModel?.setInputMonitoring(track: track, enabled: newState)
            },
            onAutomationToggle: {
                timelineViewModel.toggleAutomationExpanded(trackID: track.id)
            },
            isTrackSelected: isSelected
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
        let trackName = currentSong?.tracks.first(where: { $0.id == path.trackID })?.name ?? "?"
        if let containerID = path.containerID {
            let cName = currentSong?.tracks.flatMap(\.containers).first(where: { $0.id == containerID })?.name ?? "?"
            return "\(trackName)/\(cName) FX\(path.effectIndex)"
        }
        return "\(trackName) FX\(path.effectIndex)"
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
