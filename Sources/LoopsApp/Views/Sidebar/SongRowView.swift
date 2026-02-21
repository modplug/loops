import SwiftUI
import LoopsCore

/// A single row in the song list sidebar showing name and BPM.
public struct SongRowView: View {
    let song: Song
    let isSelected: Bool
    var onSelect: () -> Void
    var onRename: (String) -> Void

    @State private var isEditing = false
    @State private var editName = ""

    public init(
        song: Song,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onRename: @escaping (String) -> Void
    ) {
        self.song = song
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onRename = onRename
    }

    public var body: some View {
        HStack {
            if isEditing {
                TextField("Song name", text: $editName)
                    .textFieldStyle(.plain)
                    .onSubmit { commitRename() }
                    .onExitCommand { isEditing = false }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.name)
                        .font(.body)
                        .lineLimit(1)
                    Text("\(Int(song.tempo.bpm)) BPM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    /// Start inline editing.
    public func startEditing() {
        editName = song.name
        isEditing = true
    }

    private func commitRename() {
        if !editName.isEmpty {
            onRename(editName)
        }
        isEditing = false
    }
}
