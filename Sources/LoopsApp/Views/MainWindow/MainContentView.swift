import SwiftUI
import LoopsCore

/// Main content area using HSplitView: sidebar + timeline + inspector.
public struct MainContentView: View {
    @Bindable var projectViewModel: ProjectViewModel
    @Bindable var timelineViewModel: TimelineViewModel

    public init(projectViewModel: ProjectViewModel, timelineViewModel: TimelineViewModel) {
        self.projectViewModel = projectViewModel
        self.timelineViewModel = timelineViewModel
    }

    private var currentSong: Song? {
        projectViewModel.project.songs.first
    }

    public var body: some View {
        HSplitView {
            // Sidebar (placeholder)
            VStack {
                Text("Songs")
                    .font(.headline)
                    .padding(.top, 8)
                Divider()
                if projectViewModel.project.songs.isEmpty {
                    Text("No songs")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    List(projectViewModel.project.songs) { song in
                        Text(song.name)
                    }
                }
                Spacer()
            }
            .frame(minWidth: 150, idealWidth: 200, maxWidth: 250)

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
                                        TrackHeaderView(track: track)
                                    }
                                }
                            }
                        }
                        .frame(width: 160)

                        Divider()

                        // Timeline
                        TimelineView(
                            viewModel: timelineViewModel,
                            song: song
                        )
                    }
                }
            } else {
                Text("No song selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Inspector (placeholder)
            VStack {
                Text("Inspector")
                    .font(.headline)
                    .padding(.top, 8)
                Divider()
                Text("Select a track or container")
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            }
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
        }
    }
}
