import SwiftUI
import LoopsCore

/// Shows parent container info and parameter diff for linked clones.
/// Displayed as a section within the container inspector when the selected container is a clone.
public struct LinkedClipInspectorView: View {
    let container: Container
    let parentContainer: Container?
    var onNavigateToParent: (() -> Void)?

    public init(
        container: Container,
        parentContainer: Container?,
        onNavigateToParent: (() -> Void)? = nil
    ) {
        self.container = container
        self.parentContainer = parentContainer
        self.onNavigateToParent = onNavigateToParent
    }

    public var body: some View {
        Section("Linked Clone") {
            if let parent = parentContainer {
                parentReferenceRow(parent: parent)
                Divider()
                fieldDiffList(parent: parent)
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                    Text("Parent container not found")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Parent Reference

    @ViewBuilder
    private func parentReferenceRow(parent: Container) -> some View {
        Button {
            onNavigateToParent?()
        } label: {
            HStack {
                Image(systemName: "link")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(parent.name)
                        .fontWeight(.medium)
                    Text("Bar \(parent.startBar) — \(parent.endBar)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Field Diff

    @ViewBuilder
    private func fieldDiffList(parent: Container) -> some View {
        ForEach(ContainerField.allCases, id: \.self) { field in
            let isOverridden = container.overriddenFields.contains(field)
            HStack {
                Image(systemName: isOverridden ? "pencil.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(isOverridden ? .orange : .secondary)
                    .font(.caption)
                Text(field.displayName)
                Spacer()
                Text(isOverridden ? "Overridden" : "Inherited")
                    .font(.caption)
                    .foregroundStyle(isOverridden ? .orange : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isOverridden ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.1))
                    )
            }
        }
    }
}
