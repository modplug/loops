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
                                        minHeight: geo.size.height
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
                        onUpdateLoopSettings: { settings in
                            projectViewModel.updateContainerLoopSettings(containerID: container.id, settings: settings)
                        },
                        onUpdateName: { name in
                            projectViewModel.updateContainerName(containerID: container.id, name: name)
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
    }

    private func trackHeaderWithActions(track: Track) -> some View {
        TrackHeaderView(
            track: track,
            inputPortName: inputPortName(for: track.inputPortID),
            outputPortName: outputPortName(for: track.outputPortID),
            onMuteToggle: { projectViewModel.toggleMute(trackID: track.id) },
            onSoloToggle: { projectViewModel.toggleSolo(trackID: track.id) }
        )
        .contextMenu {
            Button("Rename...") {
                editingTrackID = track.id
                editingTrackName = track.name
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

            Divider()
            Button("Delete Track", role: .destructive) {
                trackToDelete = track
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
