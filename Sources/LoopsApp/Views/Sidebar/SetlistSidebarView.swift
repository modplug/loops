import SwiftUI
import LoopsCore

/// Sidebar view for managing setlists: list of setlists and their entries.
public struct SetlistSidebarView: View {
    @Bindable var viewModel: SetlistViewModel
    var playheadBar: Double = 1.0
    @State private var setlistToDelete: Setlist?
    @State private var renamingSetlistID: ID<Setlist>?
    @State private var renamingText: String = ""

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Setlists")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.createSetlist() }) {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("New Setlist")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if viewModel.project.project.setlists.isEmpty {
                Spacer()
                Text("No setlists")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                // Setlist list
                List(viewModel.project.project.setlists) { setlist in
                    setlistRow(setlist: setlist)
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                }
                .listStyle(.sidebar)

                Divider()

                // Entries for selected setlist
                if let setlist = viewModel.selectedSetlist {
                    SetlistEntryListView(viewModel: viewModel, setlist: setlist, playheadBar: playheadBar)
                }
            }
        }
        .alert("Delete Setlist", isPresented: .init(
            get: { setlistToDelete != nil },
            set: { if !$0 { setlistToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { setlistToDelete = nil }
            Button("Delete", role: .destructive) {
                if let setlist = setlistToDelete {
                    viewModel.removeSetlist(id: setlist.id)
                    setlistToDelete = nil
                }
            }
        } message: {
            if let setlist = setlistToDelete {
                Text("Are you sure you want to delete \"\(setlist.name)\"?")
            }
        }
    }

    @ViewBuilder
    private func setlistRow(setlist: Setlist) -> some View {
        let isSelected = viewModel.selectedSetlistID == setlist.id

        HStack {
            if renamingSetlistID == setlist.id {
                TextField("Setlist name", text: $renamingText)
                    .textFieldStyle(.plain)
                    .onSubmit { commitRename() }
                    .onExitCommand { renamingSetlistID = nil }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(setlist.name)
                        .font(.body)
                        .lineLimit(1)
                    Text("\(setlist.entries.count) song\(setlist.entries.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .onTapGesture { viewModel.selectSetlist(id: setlist.id) }
        .contextMenu {
            Button("Rename...") {
                renamingSetlistID = setlist.id
                renamingText = setlist.name
            }
            Divider()
            Button("Delete", role: .destructive) {
                setlistToDelete = setlist
            }
        }
    }

    private func commitRename() {
        if let id = renamingSetlistID, !renamingText.isEmpty {
            viewModel.renameSetlist(id: id, newName: renamingText)
        }
        renamingSetlistID = nil
    }
}

/// Lists entries within a selected setlist, with ability to add songs and reorder.
public struct SetlistEntryListView: View {
    @Bindable var viewModel: SetlistViewModel
    let setlist: Setlist
    var playheadBar: Double = 1.0

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Songs in \(setlist.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                addSongMenu
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            if setlist.entries.isEmpty {
                Text("Add songs to this setlist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List {
                    ForEach(setlist.entries) { entry in
                        entryRow(entry: entry)
                    }
                    .onMove { source, destination in
                        viewModel.moveEntries(from: source, to: destination)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            viewModel.removeEntry(id: setlist.entries[index].id)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxHeight: 300)
    }

    private func entryIndex(for entry: SetlistEntry) -> Int? {
        setlist.entries.firstIndex(where: { $0.id == entry.id })
    }

    @ViewBuilder
    private func entryRow(entry: SetlistEntry) -> some View {
        let isSelected = viewModel.selectedSetlistEntryID == entry.id
        let index = entryIndex(for: entry)
        let isCurrent = viewModel.isPerformMode && index == viewModel.currentEntryIndex
        let song = viewModel.song(for: entry)
        let activeSectionID = isCurrent ? viewModel.activeSectionID(atBar: playheadBar) : nil

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if isCurrent {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
                Text(viewModel.songName(for: entry))
                    .font(.body)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
            }

            // Progress bar for current entry
            if isCurrent {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * viewModel.currentSongProgress, height: 4)
                    }
                }
                .frame(height: 4)
            }

            // Section regions
            if let song, !song.sections.isEmpty {
                sectionList(sections: song.sections.sorted(by: { $0.startBar < $1.startBar }),
                            activeSectionID: activeSectionID)
            }

            HStack(spacing: 4) {
                Text("→")
                    .font(.caption2)
                transitionLabel(entry.transitionToNext)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .listRowBackground(
            isCurrent ? Color.accentColor.opacity(0.25) :
            isSelected ? Color.accentColor.opacity(0.1) :
            Color.clear
        )
        .onTapGesture { viewModel.selectedSetlistEntryID = entry.id }
        .contextMenu {
            Menu("Transition") {
                Button("Seamless") {
                    viewModel.updateTransition(entryID: entry.id, transition: .seamless)
                }
                Button("Gap (2s)") {
                    viewModel.updateTransition(entryID: entry.id, transition: .gap(durationSeconds: 2.0))
                }
                Button("Gap (5s)") {
                    viewModel.updateTransition(entryID: entry.id, transition: .gap(durationSeconds: 5.0))
                }
                Button("Manual Advance") {
                    viewModel.updateTransition(entryID: entry.id, transition: .manualAdvance)
                }
            }
            Divider()
            Button("Remove", role: .destructive) {
                viewModel.removeEntry(id: entry.id)
            }
        }
    }

    @ViewBuilder
    private func sectionList(sections: [SectionRegion], activeSectionID: ID<SectionRegion>?) -> some View {
        HStack(spacing: 3) {
            ForEach(sections) { section in
                let isActive = activeSectionID == section.id
                HStack(spacing: 2) {
                    Circle()
                        .fill(colorFromHex(section.color))
                        .frame(width: 6, height: 6)
                    Text(section.name)
                        .font(.system(size: 9))
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isActive
                              ? colorFromHex(section.color).opacity(0.3)
                              : Color.clear)
                )
                .foregroundStyle(isActive ? .primary : .secondary)
            }
        }
    }

    private func colorFromHex(_ hex: String) -> Color {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let rgb = Int(trimmed, radix: 16) else { return .gray }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    private func transitionLabel(_ mode: TransitionMode) -> some View {
        switch mode {
        case .seamless:
            return Text("Seamless")
        case .gap(let duration):
            return Text("Gap (\(String(format: "%.1f", duration))s)")
        case .manualAdvance:
            return Text("Manual")
        }
    }

    private var addSongMenu: some View {
        Menu {
            ForEach(viewModel.project.project.songs) { song in
                Button(song.name) {
                    viewModel.addEntry(songID: song.id)
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .help("Add Song to Setlist")
    }
}
