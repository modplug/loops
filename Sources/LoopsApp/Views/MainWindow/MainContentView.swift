import SwiftUI
import LoopsCore
import LoopsEngine

/// Sidebar tab selection.
public enum SidebarTab: String, CaseIterable {
    case songs = "Songs"
    case setlists = "Setlists"
}

/// Main content area using HSplitView: sidebar + timeline + inspector.
public struct MainContentView: View {
    @Bindable var projectViewModel: ProjectViewModel
    @Bindable var timelineViewModel: TimelineViewModel
    var transportViewModel: TransportViewModel?
    var setlistViewModel: SetlistViewModel?
    var engineManager: AudioEngineManager?
    var settingsViewModel: SettingsViewModel?
    @State private var trackToDelete: Track?
    @State private var editingTrackID: ID<Track>?
    @State private var editingTrackName: String = ""
    @State private var isSidebarVisible: Bool = true
    @State private var sidebarTab: SidebarTab = .songs
    @State private var showContainerDetailEditor: Bool = false
    @State private var editingSectionID: ID<SectionRegion>?
    @State private var editingSectionName: String = ""

    public init(projectViewModel: ProjectViewModel, timelineViewModel: TimelineViewModel, transportViewModel: TransportViewModel? = nil, setlistViewModel: SetlistViewModel? = nil, engineManager: AudioEngineManager? = nil, settingsViewModel: SettingsViewModel? = nil) {
        self.projectViewModel = projectViewModel
        self.timelineViewModel = timelineViewModel
        self.transportViewModel = transportViewModel
        self.setlistViewModel = setlistViewModel
        self.engineManager = engineManager
        self.settingsViewModel = settingsViewModel
    }

    private var currentSong: Song? {
        projectViewModel.currentSong
    }

    public var body: some View {
        HSplitView {
            // Sidebar
            if isSidebarVisible {
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

            // Timeline center area
            if let song = currentSong {
                VStack(spacing: 0) {
                    // Ruler row (fixed, not scrollable vertically)
                    HStack(spacing: 0) {
                        Color.clear.frame(width: 160, height: 20)
                        Divider()
                        ScrollView(.horizontal, showsIndicators: false) {
                            RulerView(
                                totalBars: timelineViewModel.totalBars,
                                pixelsPerBar: timelineViewModel.pixelsPerBar,
                                timeSignature: song.timeSignature
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
                                    if let section = song.sections.first(where: { $0.id == sectionID }) {
                                        projectViewModel.copyContainersInRange(startBar: section.startBar, endBar: section.endBar)
                                    }
                                },
                                onSectionSplit: { sectionID, atBar in
                                    projectViewModel.splitSection(sectionID: sectionID, atBar: atBar)
                                },
                                playheadBar: Int(timelineViewModel.playheadBar)
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
            } else {
                Text("No song selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Inspector
            VStack {
                Text("Inspector")
                    .font(.headline)
                    .padding(.top, 8)
                Divider()
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
                } else {
                    Text("Select a container")
                        .foregroundStyle(.secondary)
                        .padding()
                    Spacer()
                }
            }
            .frame(minWidth: 180, idealWidth: 250, maxWidth: 300)
        }
        .sheet(isPresented: $showContainerDetailEditor) {
            if let container = projectViewModel.selectedContainer {
                ContainerDetailEditor(
                    container: container,
                    trackKind: projectViewModel.selectedContainerTrackKind ?? .audio,
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
                    onDismiss: {
                        showContainerDetailEditor = false
                    }
                )
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
    }

    private func trackHeaderWithActions(track: Track) -> some View {
        let isExpanded = timelineViewModel.automationExpanded.contains(track.id)
        let laneLabels = automationLaneLabels(for: track)
        let perTrackHeight = timelineViewModel.trackHeight(for: track, baseHeight: 80)
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
            }
        )
        .contextMenu {
            Button("Rename...") {
                editingTrackID = track.id
                editingTrackName = track.name
            }
            Button("Duplicate Track") {
                projectViewModel.duplicateTrack(trackID: track.id)
            }
            Divider()
            Button(track.isRecordArmed ? "Disarm Recording" : "Arm for Recording") {
                projectViewModel.setTrackRecordArmed(trackID: track.id, armed: !track.isRecordArmed)
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
            Button("Delete Track", role: .destructive) {
                if track.containers.isEmpty {
                    projectViewModel.removeTrack(id: track.id)
                } else {
                    trackToDelete = track
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

    private func commitSectionRename() {
        if let id = editingSectionID, !editingSectionName.isEmpty {
            projectViewModel.renameSection(sectionID: id, name: editingSectionName)
        }
        editingSectionID = nil
    }

    private var addTrackMenu: some View {
        Menu {
            ForEach(TrackKind.allCases, id: \.self) { kind in
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
