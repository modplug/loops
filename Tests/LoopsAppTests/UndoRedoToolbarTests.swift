import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore
@testable import LoopsEngine

@Suite("Undo/Redo Toolbar Button Tests")
struct UndoRedoToolbarTests {

    @Test("ToolbarView accepts undo/redo parameters")
    @MainActor
    func toolbarViewAcceptsUndoRedoParams() {
        let transport = TransportManager()
        let transportVM = TransportViewModel(transport: transport)
        let _ = ToolbarView(
            viewModel: transportVM,
            onUndo: {},
            onRedo: {},
            canUndo: true,
            canRedo: false,
            undoActionName: "Rename Track",
            redoActionName: ""
        )
    }

    @Test("Undo button disabled when canUndo is false")
    @MainActor
    func undoDisabledWhenNoUndoAvailable() {
        let vm = ProjectViewModel()
        vm.newProject()
        // Fresh project — no undo history
        #expect(vm.undoManager?.canUndo == false)
    }

    @Test("Undo button enabled after performing an action")
    @MainActor
    func undoEnabledAfterAction() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        #expect(vm.undoManager?.canUndo == true)
    }

    @Test("Redo button enabled after performing undo")
    @MainActor
    func redoEnabledAfterUndo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.undoManager?.undo()
        #expect(vm.undoManager?.canRedo == true)
    }

    @Test("Redo button disabled when no redo available")
    @MainActor
    func redoDisabledWhenNoRedoAvailable() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        // Has undo but no redo
        #expect(vm.undoManager?.canRedo == false)
    }

    @Test("Undo action name reflects last action")
    @MainActor
    func undoActionNameReflectsLastAction() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let actionName = vm.undoManager?.undoActionName ?? ""
        #expect(!actionName.isEmpty)
    }

    @Test("Redo action name reflects undone action")
    @MainActor
    func redoActionNameReflectsUndoneAction() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.undoManager?.undo()
        let actionName = vm.undoManager?.redoActionName ?? ""
        #expect(!actionName.isEmpty)
    }

    @Test("Clicking undo reverses last action")
    @MainActor
    func clickingUndoReversesAction() {
        let vm = ProjectViewModel()
        vm.newProject()
        let trackCountBefore = vm.project.songs[0].tracks.count
        vm.addTrack(kind: .audio)
        #expect(vm.project.songs[0].tracks.count > trackCountBefore)

        // Simulate button click: calls undoManager.undo()
        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks.count == trackCountBefore)
    }

    @Test("Clicking redo reapplies undone action")
    @MainActor
    func clickingRedoReappliesAction() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackCountAfterAdd = vm.project.songs[0].tracks.count

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks.count < trackCountAfterAdd)

        // Simulate button click: calls undoManager.redo()
        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks.count == trackCountAfterAdd)
    }

    @Test("Undo/redo state updates immediately after action")
    @MainActor
    func stateUpdatesImmediately() {
        let vm = ProjectViewModel()
        vm.newProject()

        // Initially no undo/redo
        #expect(vm.undoManager?.canUndo == false)
        #expect(vm.undoManager?.canRedo == false)

        // After two actions: undo available, redo not
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        #expect(vm.undoManager?.canUndo == true)
        #expect(vm.undoManager?.canRedo == false)

        // After one undo: both available (addTrack(audio) still undoable)
        vm.undoManager?.undo()
        #expect(vm.undoManager?.canUndo == true)
        #expect(vm.undoManager?.canRedo == true)

        // After redo: undo available again, redo gone
        vm.undoManager?.redo()
        #expect(vm.undoManager?.canUndo == true)
        #expect(vm.undoManager?.canRedo == false)
    }
}
