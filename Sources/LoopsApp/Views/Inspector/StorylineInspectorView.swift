import SwiftUI
import LoopsCore

/// Storyline inspector: shows song progression as a vertical list derived from section regions.
public struct StorylineInspectorView: View {
    let entries: [StorylineEntry]
    let onUpdateNotes: (ID<SectionRegion>, String?) -> Void

    @State private var expandedSections: Set<ID<SectionRegion>> = []

    public init(
        entries: [StorylineEntry],
        onUpdateNotes: @escaping (ID<SectionRegion>, String?) -> Void
    ) {
        self.entries = entries
        self.onUpdateNotes = onUpdateNotes
    }

    public var body: some View {
        if entries.isEmpty {
            VStack {
                Image(systemName: "text.book.closed")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No sections defined")
                    .foregroundStyle(.secondary)
                Text("Drag on the section lane to create sections")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(entries, id: \.section.id) { entry in
                        storylineEntryView(entry)
                    }
                }
                .padding(8)
            }
        }
    }

    private func storylineEntryView(_ entry: StorylineEntry) -> some View {
        let isExpanded = expandedSections.contains(entry.section.id)
        return VStack(alignment: .leading, spacing: 4) {
            // Header row: colored badge + name + bar range
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedSections.remove(entry.section.id)
                    } else {
                        expandedSections.insert(entry.section.id)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 10)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(colorFromHex(entry.section.color))
                        .frame(width: 12, height: 12)

                    Text(entry.section.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Spacer()

                    Text("Bar \(entry.section.startBar)–\(entry.section.endBar - 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Summary line
            if !isExpanded {
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 28)
            }

            // Expanded detail
            if isExpanded {
                expandedDetail(entry)
                    .padding(.leading, 16)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func expandedDetail(_ entry: StorylineEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.trackSummaries.isEmpty {
                Text("No active containers")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                ForEach(entry.trackSummaries, id: \.trackID) { trackSummary in
                    trackDetailView(trackSummary)
                }
            }

            Divider()

            // Notes field
            notesField(entry)
        }
    }

    private func trackDetailView(_ trackSummary: TrackActivitySummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: trackKindIcon(trackSummary.trackKind))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(trackSummary.trackName)
                    .font(.caption)
                    .fontWeight(.semibold)
                if trackSummary.isRecordArmed {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.red)
                }
            }

            ForEach(Array(trackSummary.containers.enumerated()), id: \.offset) { _, container in
                containerDetailView(container)
            }
        }
        .padding(.vertical, 2)
    }

    private func containerDetailView(_ container: ContainerActivitySummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(container.containerName)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                if container.isRecordArmed {
                    Text("REC")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.red)
                }
            }
            .padding(.leading, 12)

            if !container.enterActionDescriptions.isEmpty {
                ForEach(container.enterActionDescriptions, id: \.self) { desc in
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 8))
                            .foregroundStyle(.green)
                        Text(desc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 16)
                }
            }

            if !container.exitActionDescriptions.isEmpty {
                ForEach(container.exitActionDescriptions, id: \.self) { desc in
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.left.circle")
                            .font(.system(size: 8))
                            .foregroundStyle(.red)
                        Text(desc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 16)
                }
            }

            if !container.effectNames.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "waveform")
                        .font(.system(size: 8))
                        .foregroundStyle(.cyan)
                    Text(container.effectNames.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 16)
            }

            if container.automationLaneCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 8))
                        .foregroundStyle(.purple)
                    Text("\(container.automationLaneCount) automation lane\(container.automationLaneCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 16)
            }
        }
    }

    private func notesField(_ entry: StorylineEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Performance Notes")
                .font(.caption)
                .foregroundStyle(.secondary)
            NotesTextField(
                sectionID: entry.section.id,
                initialText: entry.section.notes ?? "",
                onCommit: { text in
                    onUpdateNotes(entry.section.id, text.isEmpty ? nil : text)
                }
            )
        }
    }

    private func trackKindIcon(_ kind: TrackKind) -> String {
        switch kind {
        case .audio: return "speaker.wave.2"
        case .midi: return "pianokeys"
        case .bus: return "arrow.triangle.branch"
        case .backing: return "music.note"
        }
    }

    private func colorFromHex(_ hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let value = UInt64(cleaned, radix: 16) else { return .blue }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

/// A text field for section notes that commits on focus loss.
private struct NotesTextField: View {
    let sectionID: ID<SectionRegion>
    let initialText: String
    let onCommit: (String) -> Void

    @State private var text: String = ""

    var body: some View {
        TextField("Add performance notes...", text: $text, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .lineLimit(1...4)
            .onAppear { text = initialText }
            .onChange(of: sectionID) { _, _ in text = initialText }
            .onSubmit { onCommit(text) }
            .onChange(of: text) { _, newValue in
                onCommit(newValue)
            }
    }
}
