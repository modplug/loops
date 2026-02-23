import SwiftUI

/// Dedicated observable for undo history display state, extracted from ProjectViewModel.
/// Isolates undo history and toast changes so only views that display undo state
/// (toolbar history panel, toast overlay) re-evaluate when undo state changes.
@Observable
@MainActor
public final class UndoState {

    /// History of undo/redo actions for the undo history panel.
    public var undoHistory: [UndoHistoryEntry] = []

    /// The index in undoHistory pointing to the current state.
    /// Entries above this index are "undone" (available for redo).
    public var undoHistoryCursor: Int = -1

    /// Current toast message, set on undo/redo and auto-cleared.
    public var undoToastMessage: UndoToastMessage?

    /// Adds an entry to the undo history, trimming any "future" entries above the cursor.
    public func appendToHistory(actionName: String) {
        // Remove entries above the current cursor (they represent undone actions that are now invalidated)
        if undoHistoryCursor < undoHistory.count - 1 {
            undoHistory.removeSubrange((undoHistoryCursor + 1)...)
        }
        // Unmark previous current
        for i in undoHistory.indices {
            undoHistory[i].isCurrent = false
        }
        let entry = UndoHistoryEntry(actionName: actionName, isCurrent: true)
        undoHistory.append(entry)
        undoHistoryCursor = undoHistory.count - 1
    }

    /// Handles undo notification: moves cursor back and shows toast.
    public func handleUndo(redoActionName: String) {
        if undoHistoryCursor >= 0 {
            undoHistoryCursor -= 1
            for i in undoHistory.indices {
                undoHistory[i].isCurrent = (i == undoHistoryCursor)
            }
        }
        undoToastMessage = UndoToastMessage(text: "Undo: \(redoActionName)")
    }

    /// Handles redo notification: moves cursor forward and shows toast.
    public func handleRedo(undoActionName: String) {
        if undoHistoryCursor < undoHistory.count - 1 {
            undoHistoryCursor += 1
            for i in undoHistory.indices {
                undoHistory[i].isCurrent = (i == undoHistoryCursor)
            }
        }
        undoToastMessage = UndoToastMessage(text: "Redo: \(undoActionName)")
    }

    /// Clears the undo history panel.
    public func clear() {
        undoHistory.removeAll()
        undoHistoryCursor = -1
    }

    nonisolated public init() {}
}
