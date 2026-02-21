import SwiftUI
import LoopsCore

/// Sidebar view displaying all songs in the project with management controls.
public struct SongListView: View {
    @Bindable var viewModel: ProjectViewModel
    @State private var songToDelete: Song?
    @State private var renamingSongID: ID<Song>?
    @State private var renamingText: String = ""

    public init(viewModel: ProjectViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with add button
            HStack {
                Text("Songs")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.addSong() }) {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("New Song")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if viewModel.project.songs.isEmpty {
                Spacer()
                Text("No songs")
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                List(viewModel.project.songs) { song in
                    songRow(song: song)
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                }
                .listStyle(.sidebar)
            }
        }
        .alert("Delete Song", isPresented: .init(
            get: { songToDelete != nil },
            set: { if !$0 { songToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { songToDelete = nil }
            Button("Delete", role: .destructive) {
                if let song = songToDelete {
                    viewModel.removeSong(id: song.id)
                    songToDelete = nil
                }
            }
        } message: {
            if let song = songToDelete {
                Text("Are you sure you want to delete \"\(song.name)\"? This cannot be undone.")
            }
        }
    }

    @ViewBuilder
    private func songRow(song: Song) -> some View {
        let isSelected = viewModel.currentSongID == song.id

        HStack {
            if renamingSongID == song.id {
                TextField("Song name", text: $renamingText)
                    .textFieldStyle(.plain)
                    .onSubmit { commitRename() }
                    .onExitCommand { renamingSongID = nil }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.name)
                        .font(.body)
                        .lineLimit(1)
                    Text("\(Int(song.tempo.bpm)) BPM · \(song.timeSignature.beatsPerBar)/\(song.timeSignature.beatUnit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .onTapGesture { viewModel.selectSong(id: song.id) }
        .contextMenu {
            Button("Rename...") {
                renamingSongID = song.id
                renamingText = song.name
            }
            Button("Duplicate") {
                viewModel.duplicateSong(id: song.id)
            }
            Divider()
            Button("Delete", role: .destructive) {
                songToDelete = song
            }
            .disabled(viewModel.project.songs.count <= 1)
        }
    }

    private func commitRename() {
        if let id = renamingSongID, !renamingText.isEmpty {
            viewModel.renameSong(id: id, newName: renamingText)
        }
        renamingSongID = nil
    }
}
