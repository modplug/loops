import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore
@testable import LoopsEngine

@Suite("Undo History Panel & Toast Tests")
struct UndoHistoryTests {

    // MARK: - History Array Maintenance

    @Test("History array tracks actions through undo/redo cycles")
    @MainActor
    func historyTracksActionsThroughCycles() {
        let vm = ProjectViewModel()
        vm.newProject()

        // Perform two actions
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)

        #expect(vm.undoHistory.count == 2)
        #expect(vm.undoHistoryCursor == 1)
        #expect(vm.undoHistory[1].isCurrent == true)
        #expect(vm.undoHistory[0].isCurrent == false)

        // Undo one action — cursor moves back
        vm.undoManager?.undo()
        #expect(vm.undoHistory.count == 2)
        #expect(vm.undoHistoryCursor == 0)
        #expect(vm.undoHistory[0].isCurrent == true)
        #expect(vm.undoHistory[1].isCurrent == false)

        // Redo — cursor moves forward
        vm.undoManager?.redo()
        #expect(vm.undoHistory.count == 2)
        #expect(vm.undoHistoryCursor == 1)
        #expect(vm.undoHistory[1].isCurrent == true)
    }

    @Test("New action after undo trims future entries")
    @MainActor
    func newActionAfterUndoTrimsFuture() {
        let vm = ProjectViewModel()
        vm.newProject()

        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        #expect(vm.undoHistory.count == 2)

        // Undo one action
        vm.undoManager?.undo()
        #expect(vm.undoHistoryCursor == 0)

        // Perform a new action — the undone entry should be removed
        vm.addTrack(kind: .audio)
        #expect(vm.undoHistory.count == 2)
        #expect(vm.undoHistoryCursor == 1)
        #expect(vm.undoHistory[1].isCurrent == true)
    }

    @Test("History entries have action names")
    @MainActor
    func historyEntriesHaveActionNames() {
        let vm = ProjectViewModel()
        vm.newProject()

        vm.addTrack(kind: .audio)
        #expect(!vm.undoHistory[0].actionName.isEmpty)
    }

    @Test("History entries have timestamps")
    @MainActor
    func historyEntriesHaveTimestamps() {
        let vm = ProjectViewModel()
        vm.newProject()
        let before = Date()

        vm.addTrack(kind: .audio)
        #expect(vm.undoHistory[0].timestamp >= before)
        #expect(vm.undoHistory[0].timestamp <= Date())
    }

    @Test("newProject clears undo history")
    @MainActor
    func newProjectClearsHistory() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        #expect(vm.undoHistory.count == 2)

        vm.newProject()
        #expect(vm.undoHistory.isEmpty)
        #expect(vm.undoHistoryCursor == -1)
    }

    // MARK: - Toast Model

    @Test("Toast triggers on undo notification")
    @MainActor
    func toastTriggersOnUndo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)

        // Clear any toast from action
        vm.undoToastMessage = nil

        vm.undoManager?.undo()
        #expect(vm.undoToastMessage != nil)
        #expect(vm.undoToastMessage?.text.hasPrefix("Undo:") == true)
    }

    @Test("Toast triggers on redo notification")
    @MainActor
    func toastTriggersOnRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.undoManager?.undo()

        // Clear any toast from undo
        vm.undoToastMessage = nil

        vm.undoManager?.redo()
        #expect(vm.undoToastMessage != nil)
        #expect(vm.undoToastMessage?.text.hasPrefix("Redo:") == true)
    }

    // MARK: - UndoHistoryEntry Model

    @Test("relativeTimeString returns just now for recent entries")
    func relativeTimeStringJustNow() {
        let entry = UndoHistoryEntry(actionName: "Test", timestamp: Date())
        #expect(entry.relativeTimeString == "just now")
    }

    @Test("relativeTimeString returns minutes for older entries")
    func relativeTimeStringMinutes() {
        let entry = UndoHistoryEntry(actionName: "Test", timestamp: Date().addingTimeInterval(-120))
        #expect(entry.relativeTimeString == "2m ago")
    }

    @Test("relativeTimeString returns hours for old entries")
    func relativeTimeStringHours() {
        let entry = UndoHistoryEntry(actionName: "Test", timestamp: Date().addingTimeInterval(-7200))
        #expect(entry.relativeTimeString == "2h ago")
    }

    @Test("UndoHistoryEntry is Identifiable and Equatable")
    func undoHistoryEntryConformance() {
        let entry1 = UndoHistoryEntry(actionName: "Add Track")
        let entry2 = UndoHistoryEntry(actionName: "Add Track")
        // Different IDs mean they're not equal
        #expect(entry1 != entry2)
        // Same entry is equal to itself
        #expect(entry1 == entry1)
        // id is accessible
        let _ = entry1.id
    }

    // MARK: - UndoToastMessage Model

    @Test("UndoToastMessage is Equatable and Identifiable")
    func toastMessageConformance() {
        let msg1 = UndoToastMessage(text: "Undo: Add Track")
        let msg2 = UndoToastMessage(text: "Undo: Add Track")
        // Different IDs
        #expect(msg1 != msg2)
        #expect(msg1 == msg1)
        let _ = msg1.id
    }

    // MARK: - ToolbarView History Integration

    @Test("ToolbarView accepts undo history parameters")
    @MainActor
    func toolbarViewAcceptsHistoryParams() {
        let transport = TransportManager()
        let transportVM = TransportViewModel(transport: transport)
        let entries = [UndoHistoryEntry(actionName: "Add Track")]
        let _ = ToolbarView(
            viewModel: transportVM,
            onUndo: {},
            onRedo: {},
            canUndo: true,
            canRedo: false,
            undoActionName: "Add Track",
            redoActionName: "",
            undoHistory: entries,
            undoHistoryCursor: 0
        )
    }

    // MARK: - Full Undo Cycle

    @Test("Full undo cycle: multiple actions, undo all, redo all")
    @MainActor
    func fullUndoCycle() {
        let vm = ProjectViewModel()
        vm.newProject()

        // 3 actions
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        vm.addTrack(kind: .audio)
        #expect(vm.undoHistory.count == 3)
        #expect(vm.undoHistoryCursor == 2)

        // Undo all 3
        vm.undoManager?.undo()
        vm.undoManager?.undo()
        vm.undoManager?.undo()
        #expect(vm.undoHistoryCursor == -1)

        // Redo all 3
        vm.undoManager?.redo()
        vm.undoManager?.redo()
        vm.undoManager?.redo()
        #expect(vm.undoHistoryCursor == 2)
    }
}
