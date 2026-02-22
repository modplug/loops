import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore

@Suite("Track Inspector Tests")
struct TrackInspectorTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    private func makeEffect(name: String = "TestFX", orderIndex: Int = 0) -> InsertEffect {
        InsertEffect(
            component: AudioComponentInfo(componentType: 1, componentSubType: 2, componentManufacturer: 3),
            displayName: name,
            orderIndex: orderIndex
        )
    }

    // MARK: - Selection Model: Mutual Exclusion

    @Test("Setting selectedTrackID clears selectedContainerID")
    @MainActor
    func selectTrackClearsContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id
        vm.selectedContainerID = containerID
        #expect(vm.selectedContainerID == containerID)

        vm.selectedTrackID = trackID
        #expect(vm.selectedTrackID == trackID)
        #expect(vm.selectedContainerID == nil)
    }

    @Test("Setting selectedContainerID clears selectedTrackID")
    @MainActor
    func selectContainerClearsTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        vm.selectedTrackID = trackID
        #expect(vm.selectedTrackID == trackID)

        vm.selectedContainerID = containerID
        #expect(vm.selectedContainerID == containerID)
        #expect(vm.selectedTrackID == nil)
    }

    @Test("selectedTrack returns the correct track")
    @MainActor
    func selectedTrackProperty() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let track = vm.project.songs[0].tracks[0]
        vm.selectedTrackID = track.id
        #expect(vm.selectedTrack?.id == track.id)
        #expect(vm.selectedTrack?.name == track.name)
    }

    @Test("selectedTrack returns nil when nothing selected")
    @MainActor
    func selectedTrackNilWhenNoSelection() {
        let vm = ProjectViewModel()
        vm.newProject()
        #expect(vm.selectedTrack == nil)
    }

    // MARK: - Track insertEffects Codable Round-Trip

    @Test("Track with insertEffects Codable round-trip")
    func trackInsertEffectsRoundTrip() throws {
        let effect1 = makeEffect(name: "Delay", orderIndex: 0)
        let effect2 = makeEffect(name: "Reverb", orderIndex: 1)
        let track = Track(
            name: "Audio 1",
            kind: .audio,
            insertEffects: [effect1, effect2],
            isEffectChainBypassed: true
        )
        let decoded = try roundTrip(track)
        #expect(decoded.insertEffects.count == 2)
        #expect(decoded.insertEffects[0].displayName == "Delay")
        #expect(decoded.insertEffects[1].displayName == "Reverb")
        #expect(decoded.isEffectChainBypassed == true)
    }

    // MARK: - Add Track Effect

    @Test("addTrackEffect appends effect with correct orderIndex")
    @MainActor
    func addTrackEffect() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let effect = makeEffect(name: "Delay")
        vm.addTrackEffect(trackID: trackID, effect: effect)

        #expect(vm.project.songs[0].tracks[0].insertEffects.count == 1)
        #expect(vm.project.songs[0].tracks[0].insertEffects[0].displayName == "Delay")
        #expect(vm.project.songs[0].tracks[0].insertEffects[0].orderIndex == 0)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("addTrackEffect multiple effects auto-increments orderIndex")
    @MainActor
    func addMultipleTrackEffects() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "Delay"))
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "Reverb"))

        #expect(vm.project.songs[0].tracks[0].insertEffects.count == 2)
        #expect(vm.project.songs[0].tracks[0].insertEffects[0].orderIndex == 0)
        #expect(vm.project.songs[0].tracks[0].insertEffects[1].orderIndex == 1)
    }

    @Test("addTrackEffect invalid trackID is no-op")
    @MainActor
    func addTrackEffectInvalidID() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrackEffect(trackID: ID<Track>(), effect: makeEffect())
        // Master track should not get the effect
        let master = vm.project.songs[0].tracks.first(where: { $0.kind == .master })
        #expect(master?.insertEffects.isEmpty == true)
    }

    // MARK: - Remove Track Effect

    @Test("removeTrackEffect removes effect and reindexes")
    @MainActor
    func removeTrackEffect() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "Delay"))
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "Reverb"))
        let effectID = vm.project.songs[0].tracks[0].insertEffects[0].id
        vm.removeTrackEffect(trackID: trackID, effectID: effectID)

        #expect(vm.project.songs[0].tracks[0].insertEffects.count == 1)
        #expect(vm.project.songs[0].tracks[0].insertEffects[0].displayName == "Reverb")
        #expect(vm.project.songs[0].tracks[0].insertEffects[0].orderIndex == 0)
    }

    // MARK: - Reorder Track Effects

    @Test("reorderTrackEffects moves effect down and reindexes")
    @MainActor
    func reorderTrackEffectsDown() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "A"))
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "B"))
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "C"))

        // Move first effect to after second (index 0 → position 2)
        vm.reorderTrackEffects(trackID: trackID, from: IndexSet(integer: 0), to: 2)

        let effects = vm.project.songs[0].tracks[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(effects[0].displayName == "B")
        #expect(effects[1].displayName == "A")
        #expect(effects[2].displayName == "C")
        #expect(effects[0].orderIndex == 0)
        #expect(effects[1].orderIndex == 1)
        #expect(effects[2].orderIndex == 2)
    }

    // MARK: - Toggle Track Effect Bypass

    @Test("toggleTrackEffectBypass toggles single effect bypass")
    @MainActor
    func toggleTrackEffectBypass() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "Delay"))
        let effectID = vm.project.songs[0].tracks[0].insertEffects[0].id
        #expect(vm.project.songs[0].tracks[0].insertEffects[0].isBypassed == false)

        vm.toggleTrackEffectBypass(trackID: trackID, effectID: effectID)
        #expect(vm.project.songs[0].tracks[0].insertEffects[0].isBypassed == true)

        vm.toggleTrackEffectBypass(trackID: trackID, effectID: effectID)
        #expect(vm.project.songs[0].tracks[0].insertEffects[0].isBypassed == false)
    }

    // MARK: - Toggle Track Effect Chain Bypass

    @Test("toggleTrackEffectChainBypass toggles chain bypass flag")
    @MainActor
    func toggleTrackEffectChainBypass() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(vm.project.songs[0].tracks[0].isEffectChainBypassed == false)

        vm.toggleTrackEffectChainBypass(trackID: trackID)
        #expect(vm.project.songs[0].tracks[0].isEffectChainBypassed == true)

        vm.toggleTrackEffectChainBypass(trackID: trackID)
        #expect(vm.project.songs[0].tracks[0].isEffectChainBypassed == false)
    }

    // MARK: - Undo/Redo

    @Test("addTrackEffect undo/redo")
    @MainActor
    func addTrackEffectUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "Delay"))
        #expect(vm.project.songs[0].tracks[0].insertEffects.count == 1)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].insertEffects.count == 0)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].insertEffects.count == 1)
        #expect(vm.project.songs[0].tracks[0].insertEffects[0].displayName == "Delay")
    }

    @Test("removeTrackEffect undo/redo")
    @MainActor
    func removeTrackEffectUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "Delay"))
        let effectID = vm.project.songs[0].tracks[0].insertEffects[0].id

        vm.removeTrackEffect(trackID: trackID, effectID: effectID)
        #expect(vm.project.songs[0].tracks[0].insertEffects.count == 0)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].insertEffects.count == 1)
        #expect(vm.project.songs[0].tracks[0].insertEffects[0].displayName == "Delay")
    }

    @Test("reorderTrackEffects undo restores original order")
    @MainActor
    func reorderTrackEffectsUndo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "A"))
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "B"))

        vm.reorderTrackEffects(trackID: trackID, from: IndexSet(integer: 0), to: 2)
        let reordered = vm.project.songs[0].tracks[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(reordered[0].displayName == "B")
        #expect(reordered[1].displayName == "A")

        vm.undoManager?.undo()
        let restored = vm.project.songs[0].tracks[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(restored[0].displayName == "A")
        #expect(restored[1].displayName == "B")
    }

    @Test("reorderTrackEffects undo then redo restores reordered state")
    @MainActor
    func reorderTrackEffectsUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "A"))
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "B"))
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "C"))

        vm.reorderTrackEffects(trackID: trackID, from: IndexSet(integer: 0), to: 3)

        let reordered = vm.project.songs[0].tracks[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(reordered[0].displayName == "B")
        #expect(reordered[1].displayName == "C")
        #expect(reordered[2].displayName == "A")

        vm.undoManager?.undo()
        let undone = vm.project.songs[0].tracks[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(undone[0].displayName == "A")
        #expect(undone[1].displayName == "B")
        #expect(undone[2].displayName == "C")

        vm.undoManager?.redo()
        let redone = vm.project.songs[0].tracks[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(redone[0].displayName == "B")
        #expect(redone[1].displayName == "C")
        #expect(redone[2].displayName == "A")
    }

    @Test("reorderTrackEffects moves middle effect to end")
    @MainActor
    func reorderTrackEffectsMiddleToEnd() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "A"))
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "B"))
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "C"))

        // SwiftUI .onMove: drag item at index 1 to end (position 3)
        vm.reorderTrackEffects(trackID: trackID, from: IndexSet(integer: 1), to: 3)

        let effects = vm.project.songs[0].tracks[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(effects[0].displayName == "A")
        #expect(effects[1].displayName == "C")
        #expect(effects[2].displayName == "B")
    }

    @Test("reorderContainerEffects undo then redo restores reordered state")
    @MainActor
    func reorderContainerEffectsUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "A", orderIndex: 0))
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "B", orderIndex: 1))
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "C", orderIndex: 2))

        vm.reorderContainerEffects(containerID: containerID, from: IndexSet(integer: 2), to: 0)
        let reordered = vm.project.songs[0].tracks[0].containers[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(reordered[0].displayName == "C")
        #expect(reordered[1].displayName == "A")
        #expect(reordered[2].displayName == "B")

        vm.undoManager?.undo()
        let undone = vm.project.songs[0].tracks[0].containers[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(undone[0].displayName == "A")
        #expect(undone[1].displayName == "B")
        #expect(undone[2].displayName == "C")

        vm.undoManager?.redo()
        let redone = vm.project.songs[0].tracks[0].containers[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(redone[0].displayName == "C")
        #expect(redone[1].displayName == "A")
        #expect(redone[2].displayName == "B")
    }

    @Test("toggleTrackEffectChainBypass undo/redo")
    @MainActor
    func toggleChainBypassUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.toggleTrackEffectChainBypass(trackID: trackID)
        #expect(vm.project.songs[0].tracks[0].isEffectChainBypassed == true)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].isEffectChainBypassed == false)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].isEffectChainBypassed == true)
    }

    // MARK: - Selection Does Not Interfere with Existing Behavior

    @Test("deselectAll clears both selectedTrackID and selectedContainerID")
    @MainActor
    func deselectAllClearsBoth() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)

        vm.selectedTrackID = trackID
        vm.deselectAll()
        #expect(vm.selectedTrackID == nil)
        #expect(vm.selectedContainerID == nil)
    }

    @Test("selectTrackByIndex sets selectedTrackID correctly")
    @MainActor
    func selectTrackByIndexSetsID() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        vm.selectTrackByIndex(1)
        #expect(vm.selectedTrackID == vm.project.songs[0].tracks[1].id)
    }

    // MARK: - Track Selection Single-Select Model

    @Test("Selecting a different track deselects the previous one")
    @MainActor
    func selectDifferentTrackDeselectsPrevious() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        let track0 = vm.project.songs[0].tracks[0].id
        let track1 = vm.project.songs[0].tracks[1].id

        vm.selectedTrackID = track0
        #expect(vm.selectedTrackID == track0)

        vm.selectedTrackID = track1
        #expect(vm.selectedTrackID == track1)
        // Only one track selected at a time (single-select model)
    }

    @Test("Selecting a track sets selection and inspector shows track properties")
    @MainActor
    func selectTrackSetsSelectionAndInspector() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let track = vm.project.songs[0].tracks[0]

        vm.selectedTrackID = track.id
        #expect(vm.selectedTrackID == track.id)
        #expect(vm.selectedTrack?.id == track.id)
        #expect(vm.selectedTrack?.name == track.name)
        #expect(vm.selectedContainerID == nil)
    }
}
