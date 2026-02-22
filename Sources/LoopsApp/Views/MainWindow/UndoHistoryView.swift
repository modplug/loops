import SwiftUI

/// A popover panel showing the undo history list with action names and timestamps.
public struct UndoHistoryView: View {
    let entries: [UndoHistoryEntry]
    let cursor: Int

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Undo History")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider()

            if entries.isEmpty {
                Text("No actions yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated().reversed()), id: \.element.id) { index, entry in
                            HStack {
                                Circle()
                                    .fill(entry.isCurrent ? Color.accentColor : Color.clear)
                                    .frame(width: 6, height: 6)
                                Text(entry.actionName)
                                    .font(.callout)
                                    .foregroundStyle(index <= cursor ? .primary : .secondary)
                                Spacer()
                                Text(entry.relativeTimeString)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(entry.isCurrent ? Color.accentColor.opacity(0.1) : Color.clear)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .frame(width: 260)
    }
}
