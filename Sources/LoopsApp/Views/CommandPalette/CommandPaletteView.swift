import SwiftUI

public struct CommandPaletteView: View {
    @Bindable var viewModel: CommandPaletteViewModel

    public init(viewModel: CommandPaletteViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if viewModel.isPresented {
            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.close()
                    }

                VStack(spacing: 0) {
                    header
                    if viewModel.availableFilters.count > 1 {
                        Divider()
                        filterBar
                    }
                    Divider()
                    rows
                    if let confirmation = viewModel.pendingConfirmationNode?.confirmation {
                        Divider()
                        confirmationBar(confirmation)
                    } else if viewModel.isInMultiSelectionMode {
                        Divider()
                        multiSelectionBar
                    }
                }
                .frame(width: 760, height: 560)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.16), radius: 24, y: 12)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    viewModel.pop()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .opacity(viewModel.canPop ? 1 : 0.3)
                .disabled(!viewModel.canPop)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.stack.last?.title ?? "Command Palette")
                        .font(.headline)
                    breadcrumbBar
                }

                Spacer()
            }

            CommandPaletteSearchField(
                text: Binding(
                    get: { viewModel.query },
                    set: { viewModel.query = $0 }
                ),
                isMultiSelectionMode: viewModel.isInMultiSelectionMode,
                onMoveSelection: { delta in
                    viewModel.moveSelection(delta: delta)
                },
                onActivate: {
                    if viewModel.pendingConfirmationNode != nil {
                        viewModel.confirmPendingAction()
                    } else {
                        viewModel.activateSelected()
                    }
                },
                onBack: {
                    if viewModel.canPop {
                        viewModel.pop()
                    }
                },
                onDeleteBackwardWhenEmpty: {
                    if viewModel.canPop {
                        viewModel.pop()
                    }
                },
                onForward: {
                    viewModel.stepForwardOrActivateSelected()
                },
                onToggleSelection: {
                    _ = viewModel.toggleSelectionForSelected()
                },
                onEscape: {
                    if viewModel.pendingConfirmationNode != nil {
                        viewModel.cancelPendingAction()
                    } else {
                        viewModel.clearOrClose()
                    }
                }
            )
            .frame(height: 34)
        }
        .padding(16)
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(viewModel.breadcrumbTitles.enumerated()), id: \.offset) { index, title in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        viewModel.popToStackIndex(index)
                    } label: {
                        Text(title)
                            .font(.caption.weight(index == viewModel.stack.count - 1 ? .semibold : .regular))
                            .foregroundStyle(index == viewModel.stack.count - 1 ? .primary : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(index == viewModel.stack.count - 1
                                        ? Color.accentColor.opacity(0.12)
                                        : Color.secondary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(index == viewModel.stack.count - 1)
                }
            }
        }
    }

    private var rows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if viewModel.visibleNodes.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(viewModel.visibleNodes.enumerated()), id: \.element.id) { index, node in
                            row(node: node, isSelected: index == viewModel.selectedIndex)
                                .id(node.id)
                        }
                    }
                }
                .padding(10)
            }
            .onChange(of: viewModel.selectedIndex) { _, _ in
                if let node = viewModel.selectedNode {
                    proxy.scrollTo(node.id, anchor: .center)
                }
            }
            .onAppear {
                if let node = viewModel.selectedNode {
                    proxy.scrollTo(node.id, anchor: .center)
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.availableFilters, id: \.self) { filter in
                    Button {
                        viewModel.selectedFilter = filter
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.systemImage)
                                .font(.caption.weight(.semibold))
                            Text(filter.title)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(viewModel.selectedFilter == filter ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                        )
                        .overlay(
                            Capsule()
                                .stroke(viewModel.selectedFilter == filter ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No matching commands")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func row(node: CommandNode, isSelected: Bool) -> some View {
        Button {
            viewModel.handleRowClick(node)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                multiSelectionIndicator(for: node)
                rowIcon(for: node)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(node.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !node.badges.isEmpty {
                            badgeRow(node.badges)
                        }
                    }
                    if !node.subtitle.isEmpty {
                        Text(node.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if !node.breadcrumbs.isEmpty {
                        Text(node.breadcrumbs.joined(separator: " / "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let shortcut = node.shortcutDisplay {
                    Text(shortcut)
                        .font(.callout.monospaced().weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(isSelected ? 0.18 : 0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(isSelected ? 0.14 : 0.08), lineWidth: 1)
                        )
                        .padding(.top, 1)
                }
                if node.hasChildren {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.25) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                viewModel.setSelection(nodeID: node.id)
            }
        }
    }

    private func badgeRow(_ badges: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(badges, id: \.self) { badge in
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.14)))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rowIcon(for node: CommandNode) -> some View {
        if node.badges.contains("Loading") {
            return AnyView(
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                    ProgressView()
                        .controlSize(.small)
                        .tint(.accentColor)
                }
                .frame(width: 32, height: 32)
            )
        }

        let symbol = iconName(for: node)
        let tint = iconTint(for: node)
        return AnyView(
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)
        )
    }

    private func iconName(for node: CommandNode) -> String {
        let badges = Set(node.badges.map { $0.lowercased() })
        if badges.contains("instrument") { return "pianokeys" }
        if badges.contains("settings") { return "gearshape" }
        if badges.contains("song") { return "music.quarternote.3" }

        switch node.kind {
        case .globalAction:
            return "sparkles"
        case .track:
            return "music.note.list"
        case .container:
            return "square.stack.3d.up"
        case .plugin:
            return "shippingbox"
        case .pluginAction, .pluginInstance:
            return "slider.horizontal.3"
        case .automation:
            return "waveform.path"
        case .destination:
            return "arrowshape.turn.up.right"
        case .utility:
            return badges.contains("midi") ? "pianokeys" : "bolt"
        }
    }

    private func iconTint(for node: CommandNode) -> Color {
        let badges = Set(node.badges.map { $0.lowercased() })
        if badges.contains("instrument") { return .blue }
        if badges.contains("automation") { return .purple }
        if badges.contains("song") { return .orange }
        if badges.contains("settings") { return .gray }
        if badges.contains("midi") { return .green }

        switch node.kind {
        case .track:
            return .orange
        case .container:
            return .pink
        case .plugin, .pluginAction, .pluginInstance:
            return .blue
        case .automation:
            return .purple
        case .globalAction, .destination, .utility:
            return .accentColor
        }
    }

    private func confirmationBar(_ confirmation: CommandConfirmation) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(confirmation.title)
                    .font(.subheadline.weight(.semibold))
                Text(confirmation.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") {
                viewModel.cancelPendingAction()
            }
            Button("Confirm", role: .destructive) {
                viewModel.confirmPendingAction()
            }
        }
        .padding(14)
    }

    private var multiSelectionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.multiSelectionCommitTitle ?? "Apply Selection")
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.multiSelectionHelperText ?? "Press Space to toggle the highlighted item.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(viewModel.multiSelectionCount) selected")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Button(viewModel.multiSelectionCommitTitle ?? "Apply") {
                viewModel.commitMultiSelection()
            }
            .disabled(viewModel.multiSelectionCount == 0)
        }
        .padding(14)
    }

    @ViewBuilder
    private func multiSelectionIndicator(for node: CommandNode) -> some View {
        if viewModel.isInMultiSelectionMode {
            let isSelectable = viewModel.canSelectNode(node)
            let isSelected = viewModel.isNodeSelected(node)

            ZStack {
                Circle()
                    .stroke(isSelectable ? Color.secondary.opacity(0.45) : Color.secondary.opacity(0.16), lineWidth: 1)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                    )
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                } else if !isSelectable {
                    Circle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: 18, height: 18)
            .padding(.top, 7)
        }
    }
}

private struct CommandPaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    var isMultiSelectionMode: Bool
    var onMoveSelection: (Int) -> Void
    var onActivate: () -> Void
    var onBack: () -> Void
    var onDeleteBackwardWhenEmpty: () -> Void
    var onForward: () -> Void
    var onToggleSelection: () -> Void
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isMultiSelectionMode: isMultiSelectionMode,
            onMoveSelection: onMoveSelection,
            onActivate: onActivate,
            onBack: onBack,
            onDeleteBackwardWhenEmpty: onDeleteBackwardWhenEmpty,
            onForward: onForward,
            onToggleSelection: onToggleSelection,
            onEscape: onEscape
        )
    }

    func makeNSView(context: Context) -> PaletteSearchField {
        let field = PaletteSearchField()
        field.placeholderString = "Search actions, tracks, plugins, automation..."
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 14)
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.textValue = text
        field.shouldToggleSelectionOnSpace = context.coordinator.shouldToggleSelectionOnSpace
        field.onSpace = context.coordinator.handleSpace
        context.coordinator.attach(to: field)
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: PaletteSearchField, context: Context) {
        if nsView.textValue != text {
            nsView.textValue = text
        }
        context.coordinator.isMultiSelectionMode = isMultiSelectionMode
        nsView.shouldToggleSelectionOnSpace = context.coordinator.shouldToggleSelectionOnSpace
        nsView.onSpace = context.coordinator.handleSpace
        DispatchQueue.main.async {
            if nsView.window?.firstResponder !== nsView.currentEditor() {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate, NSControlTextEditingDelegate {
        @Binding var text: String
        var isMultiSelectionMode: Bool
        let onMoveSelection: (Int) -> Void
        let onActivate: () -> Void
        let onBack: () -> Void
        let onDeleteBackwardWhenEmpty: () -> Void
        let onForward: () -> Void
        let onToggleSelection: () -> Void
        let onEscape: () -> Void
        weak var field: PaletteSearchField?
        var localMonitor: Any?

        init(
            text: Binding<String>,
            isMultiSelectionMode: Bool,
            onMoveSelection: @escaping (Int) -> Void,
            onActivate: @escaping () -> Void,
            onBack: @escaping () -> Void,
            onDeleteBackwardWhenEmpty: @escaping () -> Void,
            onForward: @escaping () -> Void,
            onToggleSelection: @escaping () -> Void,
            onEscape: @escaping () -> Void
        ) {
            self._text = text
            self.isMultiSelectionMode = isMultiSelectionMode
            self.onMoveSelection = onMoveSelection
            self.onActivate = onActivate
            self.onBack = onBack
            self.onDeleteBackwardWhenEmpty = onDeleteBackwardWhenEmpty
            self.onForward = onForward
            self.onToggleSelection = onToggleSelection
            self.onEscape = onEscape
        }

        deinit {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
            }
        }

        func attach(to field: PaletteSearchField) {
            self.field = field
            if localMonitor == nil {
                localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    guard self.isMultiSelectionMode else { return event }
                    guard event.keyCode == 49 else { return event }
                    guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
                    guard let field = self.field,
                          let window = field.window,
                          window.firstResponder === field.currentEditor() || window.firstResponder === field else {
                        return event
                    }
                    self.onToggleSelection()
                    return nil
                }
            }
        }

        func handleSpace() {
            onToggleSelection()
        }

        func shouldToggleSelectionOnSpace() -> Bool {
            isMultiSelectionMode
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                onMoveSelection(1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                onMoveSelection(-1)
                return true
            case #selector(NSResponder.moveLeft(_:)):
                onBack()
                return true
            case #selector(NSResponder.moveRight(_:)):
                onForward()
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                onActivate()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onEscape()
                return true
            case #selector(NSResponder.deleteBackward(_:)):
                if textView.string.isEmpty {
                    onDeleteBackwardWhenEmpty()
                    return true
                }
                return false
            default:
                return false
            }
        }
    }
}

private final class PaletteSearchField: NSSearchField {
    var onSpace: (() -> Void)?
    var shouldToggleSelectionOnSpace: (() -> Bool)?

    var textValue: String {
        get { stringValue }
        set { stringValue = newValue }
    }

    override func keyDown(with event: NSEvent) {
        let isPlainSpace = event.keyCode == 49 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
        if isPlainSpace && shouldToggleSelectionOnSpace?() == true {
            onSpace?()
            return
        }
        super.keyDown(with: event)
    }
}
