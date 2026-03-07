import Foundation

@MainActor
@Observable
public final class CommandPaletteViewModel {
    public struct ForwardEntry {
        public let parentNodeID: String
        public let stackEntry: StackEntry

        public init(parentNodeID: String, stackEntry: StackEntry) {
            self.parentNodeID = parentNodeID
            self.stackEntry = stackEntry
        }
    }

    public struct MultiSelectionState {
        public let commitTitle: String
        public let helperText: String
        public let allowsSelection: (CommandNode) -> Bool
        public let commit: ([CommandNode]) -> Void
        public var selectedNodeIDs: Set<String>

        public init(configuration: CommandNodeMultiSelection) {
            self.commitTitle = configuration.commitTitle
            self.helperText = configuration.helperText
            self.allowsSelection = configuration.allowsSelection
            self.commit = configuration.commit
            self.selectedNodeIDs = []
        }
    }

    public struct StackEntry {
        public var title: String
        public var breadcrumbTitle: String
        public var query: String
        public var selectedFilter: CommandPaletteFilter
        public let nodesProvider: () -> [CommandNode]
        public var multiSelection: MultiSelectionState?
        public let sourceNodeID: String?

        public init(
            title: String,
            breadcrumbTitle: String? = nil,
            query: String = "",
            selectedFilter: CommandPaletteFilter = .all,
            nodesProvider: @escaping () -> [CommandNode],
            multiSelection: MultiSelectionState? = nil,
            sourceNodeID: String? = nil
        ) {
            self.title = title
            self.breadcrumbTitle = breadcrumbTitle ?? title
            self.query = query
            self.selectedFilter = selectedFilter
            self.nodesProvider = nodesProvider
            self.multiSelection = multiSelection
            self.sourceNodeID = sourceNodeID
        }
    }

    public private(set) var isPresented = false
    public private(set) var stack: [StackEntry]
    public private(set) var selectedIndex = 0
    public private(set) var pendingConfirmationNode: CommandNode?
    public private(set) var refreshToken = 0
    public private(set) var forwardEntries: [ForwardEntry] = []

    public var onPreviewNode: ((CommandNode?) -> Void)?
    public var onClose: ((_ committed: Bool) -> Void)?
    public var onExecuteNode: ((CommandNode) -> Void)?

    private var previewTask: Task<Void, Never>?
    private var rootProvider: () -> [CommandNode]

    public init(rootProvider: @escaping () -> [CommandNode]) {
        self.rootProvider = rootProvider
        self.stack = [StackEntry(title: "Command Palette", breadcrumbTitle: "Root", nodesProvider: rootProvider)]
    }

    public func setRootProvider(_ provider: @escaping () -> [CommandNode]) {
        rootProvider = provider
        forwardEntries = []
        if !stack.isEmpty {
            stack[0] = StackEntry(
                title: "Command Palette",
                breadcrumbTitle: "Root",
                query: stack[0].query,
                selectedFilter: stack[0].selectedFilter,
                nodesProvider: provider,
                multiSelection: nil
            )
        }
        selectedIndex = 0
        clampSelection()
    }

    public func refresh() {
        refreshToken += 1
        clampSelection()
        schedulePreview()
    }

    public var query: String {
        get { stack.last?.query ?? "" }
        set {
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].query = newValue
            forwardEntries.removeAll()
            selectedIndex = 0
            clampSelection()
            schedulePreview()
        }
    }

    public var breadcrumbTitles: [String] {
        stack.map(\.breadcrumbTitle)
    }

    public var selectedFilter: CommandPaletteFilter {
        get { stack.last?.selectedFilter ?? .all }
        set {
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].selectedFilter = newValue
            forwardEntries.removeAll()
            selectedIndex = 0
            clampSelection()
            schedulePreview()
        }
    }

    public var availableFilters: [CommandPaletteFilter] {
        let nodes = stack.last?.nodesProvider() ?? []
        let matching = CommandPaletteFilter.allCases.filter { filter in
            filter == .all || nodes.contains(where: { filter.matches($0) })
        }
        return matching
    }

    public var visibleNodes: [CommandNode] {
        guard let entry = stack.last else { return [] }
        let filtered = entry.selectedFilter == .all
            ? entry.nodesProvider()
            : entry.nodesProvider().filter { entry.selectedFilter.matches($0) }
        return CommandPaletteSearch.rank(nodes: filtered, query: entry.query)
    }

    public var selectedNode: CommandNode? {
        let nodes = visibleNodes
        guard nodes.indices.contains(selectedIndex) else { return nil }
        return nodes[selectedIndex]
    }

    public var canPop: Bool {
        stack.count > 1
    }

    public var isInMultiSelectionMode: Bool {
        stack.last?.multiSelection != nil
    }

    public var multiSelectionCount: Int {
        stack.last?.multiSelection?.selectedNodeIDs.count ?? 0
    }

    public var multiSelectionCommitTitle: String? {
        stack.last?.multiSelection?.commitTitle
    }

    public var multiSelectionHelperText: String? {
        stack.last?.multiSelection?.helperText
    }

    public func isNodeSelected(_ node: CommandNode) -> Bool {
        stack.last?.multiSelection?.selectedNodeIDs.contains(node.id) == true
    }

    public func canSelectNode(_ node: CommandNode) -> Bool {
        stack.last?.multiSelection?.allowsSelection(node) == true
    }

    public func open(path: [String] = []) {
        isPresented = true
        if stack.isEmpty {
            stack = [StackEntry(title: "Command Palette", breadcrumbTitle: "Root", nodesProvider: rootProvider)]
        } else {
            stack = [
                StackEntry(
                    title: "Command Palette",
                    breadcrumbTitle: "Root",
                    query: "",
                    selectedFilter: .all,
                    nodesProvider: rootProvider
                )
            ]
        }
        pendingConfirmationNode = nil
        forwardEntries = []
        selectedIndex = 0
        for nodeID in path {
            guard let node = stack.last?.nodesProvider().first(where: { $0.id == nodeID }) else { continue }
            if let childEntry = childEntry(for: node) {
                stack.append(childEntry)
            } else if let index = visibleNodes.firstIndex(where: { $0.id == node.id }) {
                selectedIndex = index
            }
        }
        clampSelection()
        schedulePreview()
    }

    public func close(committed: Bool = false) {
        previewTask?.cancel()
        previewTask = nil
        pendingConfirmationNode = nil
        forwardEntries = []
        isPresented = false
        onPreviewNode?(nil)
        onClose?(committed)
    }

    public func clearOrClose() {
        if !query.isEmpty {
            query = ""
            return
        }
        if canPop {
            pop()
            return
        }
        close()
    }

    public func pop() {
        guard canPop else {
            close()
            return
        }
        previewTask?.cancel()
        let poppedEntry = stack.removeLast()
        if let parentNodeID = poppedEntry.sourceNodeID {
            forwardEntries.append(ForwardEntry(parentNodeID: parentNodeID, stackEntry: poppedEntry))
            setSelection(nodeID: parentNodeID)
        }
        pendingConfirmationNode = nil
        clampSelection()
        schedulePreview()
    }

    public func popToStackIndex(_ index: Int) {
        guard stack.indices.contains(index) else { return }
        guard index < stack.count - 1 else { return }
        previewTask?.cancel()
        stack = Array(stack.prefix(index + 1))
        forwardEntries = []
        pendingConfirmationNode = nil
        selectedIndex = 0
        clampSelection()
        schedulePreview()
    }

    public func stepForwardOrActivateSelected() {
        if restoreForwardEntryForSelectedNode() {
            return
        }
        activateSelected()
    }

    public func moveSelection(delta: Int) {
        let nodes = visibleNodes
        guard !nodes.isEmpty else {
            selectedIndex = 0
            onPreviewNode?(nil)
            return
        }
        selectedIndex = min(max(selectedIndex + delta, 0), nodes.count - 1)
        schedulePreview()
    }

    public func setSelection(nodeID: String) {
        guard let index = visibleNodes.firstIndex(where: { $0.id == nodeID }) else { return }
        selectedIndex = index
        schedulePreview()
    }

    public func activateSelected() {
        guard let node = selectedNode else { return }
        if pendingConfirmationNode == nil,
           let multiSelection = stack.last?.multiSelection,
           multiSelection.selectedNodeIDs.isEmpty == false {
            commitMultiSelection()
            return
        }
        activate(node: node)
    }

    public func activate(node: CommandNode) {
        if let confirmation = node.confirmation, pendingConfirmationNode?.id != node.id {
            pendingConfirmationNode = CommandNode(
                id: node.id,
                kind: node.kind,
                title: confirmation.title,
                subtitle: confirmation.message,
                breadcrumbs: node.breadcrumbs,
                badges: node.badges,
                searchableText: node.searchableText,
                shortcutDisplay: node.shortcutDisplay,
                previewTarget: node.previewTarget,
                previewStyle: node.previewStyle,
                confirmation: node.confirmation,
                childEntryBuilder: node.childEntryBuilder,
                childrenProvider: node.childrenProvider,
                execute: node.execute
            )
            return
        }

        if let entry = childEntry(for: node) {
            previewTask?.cancel()
            pendingConfirmationNode = nil
            forwardEntries.removeAll()
            stack.append(entry)
            selectedIndex = 0
            schedulePreview()
            return
        }

        pendingConfirmationNode = nil
        node.execute?()
        onExecuteNode?(node)
        close(committed: true)
    }

    public func handleRowClick(_ node: CommandNode) {
        setSelection(nodeID: node.id)
        if pendingConfirmationNode?.id == node.id {
            confirmPendingAction()
            return
        }
        if toggleSelection(nodeID: node.id) {
            return
        }
        activate(node: node)
    }

    @discardableResult
    public func toggleSelectionForSelected() -> Bool {
        guard let node = selectedNode else { return false }
        return toggleSelection(nodeID: node.id)
    }

    public func commitMultiSelection() {
        guard var multiSelection = stack.last?.multiSelection else { return }
        let nodes = visibleNodes.filter { multiSelection.selectedNodeIDs.contains($0.id) }
        guard !nodes.isEmpty else { return }
        multiSelection.commit(nodes)
        close(committed: true)
    }

    public func confirmPendingAction() {
        guard let node = pendingConfirmationNode else { return }
        pendingConfirmationNode = nil
        node.execute?()
        onExecuteNode?(node)
        close(committed: true)
    }

    public func cancelPendingAction() {
        pendingConfirmationNode = nil
        schedulePreview()
    }

    private func clampSelection() {
        let count = visibleNodes.count
        if count == 0 {
            selectedIndex = 0
        } else {
            selectedIndex = min(max(selectedIndex, 0), count - 1)
        }
    }

    private func schedulePreview() {
        previewTask?.cancel()
        let node = selectedNode
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.onPreviewNode?(node)
            }
        }
    }

    private func toggleSelection(nodeID: String) -> Bool {
        guard !stack.isEmpty, var multiSelection = stack[stack.count - 1].multiSelection else {
            return false
        }
        guard let node = visibleNodes.first(where: { $0.id == nodeID }), multiSelection.allowsSelection(node) else {
            return false
        }
        if multiSelection.selectedNodeIDs.contains(nodeID) {
            multiSelection.selectedNodeIDs.remove(nodeID)
        } else {
            multiSelection.selectedNodeIDs.insert(nodeID)
        }
        stack[stack.count - 1].multiSelection = multiSelection
        schedulePreview()
        return true
    }

    private func childEntry(for node: CommandNode) -> StackEntry? {
        if let childEntry = node.childEntryBuilder?() {
            return StackEntry(
                title: childEntry.title,
                breadcrumbTitle: childEntry.breadcrumbTitle,
                query: childEntry.query,
                selectedFilter: childEntry.selectedFilter,
                nodesProvider: childEntry.nodesProvider,
                multiSelection: childEntry.multiSelection.map(MultiSelectionState.init(configuration:)),
                sourceNodeID: node.id
            )
        }
        if let childrenProvider = node.childrenProvider {
            return StackEntry(
                title: node.title,
                breadcrumbTitle: node.title,
                selectedFilter: .all,
                nodesProvider: childrenProvider,
                sourceNodeID: node.id
            )
        }
        return nil
    }

    private func restoreForwardEntryForSelectedNode() -> Bool {
        guard let selectedNode else { return false }
        guard let forwardIndex = forwardEntries.lastIndex(where: { $0.parentNodeID == selectedNode.id }) else {
            return false
        }
        let forwardEntry = forwardEntries.remove(at: forwardIndex)
        pendingConfirmationNode = nil
        previewTask?.cancel()
        stack.append(forwardEntry.stackEntry)
        selectedIndex = 0
        clampSelection()
        schedulePreview()
        return true
    }
}

enum CommandPaletteSearch {
    static func rank(nodes: [CommandNode], query: String) -> [CommandNode] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nodes }
        let lowered = trimmed.lowercased()
        let queryTokens = lowered.split(whereSeparator: \.isWhitespace).map(String.init)

        return nodes
            .compactMap { node -> (CommandNode, Int)? in
                let haystacks = searchableTerms(for: node)
                let score = score(haystacks: haystacks, query: lowered, queryTokens: queryTokens, kind: node.kind)
                guard score > 0 else { return nil }
                return (node, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }

    private static func searchableTerms(for node: CommandNode) -> [String] {
        let explicit = node.searchableText
        let joinedBreadcrumbs = node.breadcrumbs.joined(separator: " ")
        return ([node.title, node.subtitle, joinedBreadcrumbs] + node.badges + explicit)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
    }

    private static func score(
        haystacks: [String],
        query: String,
        queryTokens: [String],
        kind: CommandNodeKind
    ) -> Int {
        var best = 0
        for haystack in haystacks {
            if haystack.hasPrefix(query) {
                best = max(best, 300)
            }
            if haystack.split(whereSeparator: \.isWhitespace).contains(where: { $0 == Substring(query) }) {
                best = max(best, 220)
            }
            if haystack.contains(query) {
                best = max(best, 160)
            }
            let allTokensMatch = !queryTokens.isEmpty && queryTokens.allSatisfy { haystack.contains($0) }
            if allTokensMatch {
                best = max(best, 130)
            }
        }

        switch kind {
        case .plugin:
            best += 25
        case .pluginInstance:
            best += 20
        case .track, .container, .automation:
            best += 10
        default:
            break
        }

        return best
    }
}
