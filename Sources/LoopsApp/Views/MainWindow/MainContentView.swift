import SwiftUI
import LoopsCore

/// Main content area using HSplitView: sidebar + timeline + inspector.
public struct MainContentView: View {
    @Bindable var projectViewModel: ProjectViewModel
    @Bindable var timelineViewModel: TimelineViewModel
    @State private var trackToDelete: Track?
    @State private var editingTrackID: ID<Track>?
    @State private var editingTrackName: String = ""
    @State private var isSidebarVisible: Bool = true

    public init(projectViewModel: ProjectViewModel, timelineViewModel: TimelineViewModel) {
        self.projectViewModel = projectViewModel
        self.timelineViewModel = timelineViewModel
    }

    private var currentSong: Song? {
        projectViewModel.currentSong
    }

    public var body: some View {
        HSplitView {
            // Sidebar
            if isSidebarVisible {
                SongListView(viewModel: projectViewModel)
                    .frame(minWidth: 150, idealWidth: 200, maxWidth: 250)
            }

            // Timeline center area
            if let song = currentSong {
                VStack(spacing: 0) {
                    // Track headers + timeline
                    HStack(spacing: 0) {
                        // Track headers column
                        VStack(spacing: 0) {
                            // Ruler spacer
                            Color.clear.frame(width: 160, height: 28)
                            Divider()

                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(spacing: 0) {
                                    ForEach(song.tracks) { track in
                                        trackHeaderWithActions(track: track)
                                    }
                                }
                            }

                            Divider()

                            // Add Track button
                            addTrackMenu
                                .padding(4)
                        }
                        .frame(width: 160)

                        Divider()

                        // Timeline
                        TimelineView(
                            viewModel: timelineViewModel,
                            projectViewModel: projectViewModel,
                            song: song
                        )
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
        }
    }

    private func trackHeaderWithActions(track: Track) -> some View {
        TrackHeaderView(
            track: track,
            onMuteToggle: { projectViewModel.toggleMute(trackID: track.id) },
            onSoloToggle: { projectViewModel.toggleSolo(trackID: track.id) }
        )
        .contextMenu {
            Button("Rename...") {
                editingTrackID = track.id
                editingTrackName = track.name
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
}
