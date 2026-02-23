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

    // MARK: - Inline I/O Controls Tests

    @Test("Inline input port selection updates audio track routing")
    @MainActor
    func inlineInputPortSelection() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(vm.project.songs[0].tracks[0].inputPortID == nil)

        vm.setTrackInputPort(trackID: trackID, portID: "device:0:0")
        #expect(vm.project.songs[0].tracks[0].inputPortID == "device:0:0")
    }

    @Test("Inline output port selection updates audio track routing")
    @MainActor
    func inlineOutputPortSelection() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(vm.project.songs[0].tracks[0].outputPortID == nil)

        vm.setTrackOutputPort(trackID: trackID, portID: "device:1:0")
        #expect(vm.project.songs[0].tracks[0].outputPortID == "device:1:0")
    }

    @Test("Inline MIDI device selection updates MIDI track routing")
    @MainActor
    func inlineMIDIDeviceSelection() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(vm.project.songs[0].tracks[0].midiInputDeviceID == nil)

        vm.setTrackMIDIInput(trackID: trackID, deviceID: "midi-device-1", channel: nil)
        #expect(vm.project.songs[0].tracks[0].midiInputDeviceID == "midi-device-1")
        #expect(vm.project.songs[0].tracks[0].midiInputChannel == nil)
    }

    @Test("Inline MIDI channel selection updates MIDI track routing")
    @MainActor
    func inlineMIDIChannelSelection() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.setTrackMIDIInput(trackID: trackID, deviceID: nil, channel: 5)
        #expect(vm.project.songs[0].tracks[0].midiInputChannel == 5)
        #expect(vm.project.songs[0].tracks[0].midiInputDeviceID == nil)
    }

    @Test("Inline output port selection on master track updates master routing")
    @MainActor
    func inlineMasterOutputPortSelection() {
        let vm = ProjectViewModel()
        vm.newProject()
        guard let masterTrack = vm.currentSong?.masterTrack else {
            Issue.record("No master track found")
            return
        }
        #expect(masterTrack.outputPortID == nil)

        vm.setMasterOutputPort(portID: "device:2:0")
        #expect(vm.currentSong?.masterTrack?.outputPortID == "device:2:0")
    }

    @Test("Selecting Default clears port to nil")
    @MainActor
    func inlineSelectDefaultClearsPort() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.setTrackInputPort(trackID: trackID, portID: "device:0:0")
        #expect(vm.project.songs[0].tracks[0].inputPortID == "device:0:0")

        vm.setTrackInputPort(trackID: trackID, portID: nil)
        #expect(vm.project.songs[0].tracks[0].inputPortID == nil)
    }

    @Test("Inline routing change supports undo")
    @MainActor
    func inlineRoutingChangeUndo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.setTrackInputPort(trackID: trackID, portID: "device:0:0")
        #expect(vm.project.songs[0].tracks[0].inputPortID == "device:0:0")

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].inputPortID == nil)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].inputPortID == "device:0:0")
    }

    @Test("TrackHeaderView accepts available ports and devices")
    func trackHeaderAcceptsPortsAndDevices() {
        let ports = [
            InputPort(deviceUID: "dev1", streamIndex: 0, channelOffset: 0, layout: .stereo, defaultName: "In 1/2"),
            InputPort(deviceUID: "dev1", streamIndex: 0, channelOffset: 2, layout: .stereo, defaultName: "In 3/4")
        ]
        let outputs = [
            OutputPort(deviceUID: "dev1", streamIndex: 0, channelOffset: 0, layout: .stereo, defaultName: "Out 1/2")
        ]
        let devices = [
            MIDIInputDevice(id: "123", displayName: "Arturia KeyStep")
        ]
        let track = Track(name: "Audio 1", kind: .audio)
        let header = TrackHeaderView(
            track: track,
            availableInputPorts: ports,
            availableOutputPorts: outputs,
            availableMIDIDevices: devices
        )
        #expect(header.availableInputPorts.count == 2)
        #expect(header.availableOutputPorts.count == 1)
        #expect(header.availableMIDIDevices.count == 1)
    }

    // MARK: - onPlaybackGraphChanged Callback

    @Test("onPlaybackGraphChanged fires on addTrackEffect")
    @MainActor
    func onPlaybackGraphChangedFiresOnAddEffect() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        var callbackCount = 0
        vm.onPlaybackGraphChanged = { callbackCount += 1 }

        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "Delay"))
        #expect(callbackCount == 1)
    }

    @Test("onPlaybackGraphChanged fires on removeTrackEffect")
    @MainActor
    func onPlaybackGraphChangedFiresOnRemoveEffect() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "Delay"))
        let effectID = vm.project.songs[0].tracks[0].insertEffects[0].id

        var callbackCount = 0
        vm.onPlaybackGraphChanged = { callbackCount += 1 }

        vm.removeTrackEffect(trackID: trackID, effectID: effectID)
        #expect(callbackCount == 1)
    }

    @Test("onPlaybackGraphChanged fires on reorderTrackEffects")
    @MainActor
    func onPlaybackGraphChangedFiresOnReorder() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "A"))
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "B"))

        var callbackCount = 0
        vm.onPlaybackGraphChanged = { callbackCount += 1 }

        vm.reorderTrackEffects(trackID: trackID, from: IndexSet(integer: 0), to: 2)
        #expect(callbackCount == 1)
    }

    @Test("onPlaybackGraphChanged fires on toggleTrackEffectBypass")
    @MainActor
    func onPlaybackGraphChangedFiresOnToggleBypass() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "Delay"))
        let effectID = vm.project.songs[0].tracks[0].insertEffects[0].id

        var callbackCount = 0
        vm.onPlaybackGraphChanged = { callbackCount += 1 }

        vm.toggleTrackEffectBypass(trackID: trackID, effectID: effectID)
        #expect(callbackCount == 1)
    }

    @Test("onPlaybackGraphChanged fires on toggleTrackEffectChainBypass")
    @MainActor
    func onPlaybackGraphChangedFiresOnToggleChainBypass() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        var callbackCount = 0
        vm.onPlaybackGraphChanged = { callbackCount += 1 }

        vm.toggleTrackEffectChainBypass(trackID: trackID)
        #expect(callbackCount == 1)
    }

    @Test("onPlaybackGraphChanged does NOT fire on updateTrackEffectPreset")
    @MainActor
    func onPlaybackGraphChangedDoesNotFireOnPresetUpdate() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addTrackEffect(trackID: trackID, effect: makeEffect(name: "Delay"))
        let effectID = vm.project.songs[0].tracks[0].insertEffects[0].id

        var callbackCount = 0
        vm.onPlaybackGraphChanged = { callbackCount += 1 }

        vm.updateTrackEffectPreset(trackID: trackID, effectID: effectID, presetData: Data([1, 2, 3]))
        #expect(callbackCount == 0, "Preset updates should not trigger graph rebuild")
    }

    @Test("onPlaybackGraphChanged fires on addContainerEffect")
    @MainActor
    func onPlaybackGraphChangedFiresOnAddContainerEffect() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        var callbackCount = 0
        vm.onPlaybackGraphChanged = { callbackCount += 1 }

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "FX", orderIndex: 0))
        #expect(callbackCount == 1)
    }

    @Test("onPlaybackGraphChanged fires on removeContainerEffect")
    @MainActor
    func onPlaybackGraphChangedFiresOnRemoveContainerEffect() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id
        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "FX", orderIndex: 0))
        let effectID = vm.project.songs[0].tracks[0].containers[0].insertEffects[0].id

        var callbackCount = 0
        vm.onPlaybackGraphChanged = { callbackCount += 1 }

        vm.removeContainerEffect(containerID: containerID, effectID: effectID)
        #expect(callbackCount == 1)
    }

    // MARK: - Active Index Mapping (Visual → Scheduler)

    @Test("Active index computation skips bypassed effects")
    func activeIndexSkipsBypassedEffects() {
        // Simulates the exact computation used in ContainerInspector,
        // ContainerDetailEditor, and TrackInspectorView:
        //   let activeIndex = sortedEffects[0..<index].filter { !$0.isBypassed }.count
        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        let effects = [
            InsertEffect(component: comp, displayName: "A", orderIndex: 0),
            InsertEffect(component: comp, displayName: "B", isBypassed: true, orderIndex: 1),
            InsertEffect(component: comp, displayName: "C", orderIndex: 2),
        ]

        func activeIndex(at visualIndex: Int) -> Int {
            effects[0..<visualIndex].filter { !$0.isBypassed }.count
        }

        // A (active) at visual index 0 → scheduler index 0
        #expect(activeIndex(at: 0) == 0)
        // B (bypassed) at visual index 1 → scheduler index 1 (A is before it)
        #expect(activeIndex(at: 1) == 1)
        // C (active) at visual index 2 → scheduler index 1 (only A is active before it)
        #expect(activeIndex(at: 2) == 1)
    }

    @Test("Active index when all effects are bypassed")
    func activeIndexAllBypassed() {
        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        let effects = [
            InsertEffect(component: comp, displayName: "A", isBypassed: true, orderIndex: 0),
            InsertEffect(component: comp, displayName: "B", isBypassed: true, orderIndex: 1),
        ]

        func activeIndex(at visualIndex: Int) -> Int {
            effects[0..<visualIndex].filter { !$0.isBypassed }.count
        }

        #expect(activeIndex(at: 0) == 0)
        #expect(activeIndex(at: 1) == 0)
    }

    @Test("Active index when no effects are bypassed")
    func activeIndexNoneBypassed() {
        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        let effects = [
            InsertEffect(component: comp, displayName: "A", orderIndex: 0),
            InsertEffect(component: comp, displayName: "B", orderIndex: 1),
            InsertEffect(component: comp, displayName: "C", orderIndex: 2),
        ]

        func activeIndex(at visualIndex: Int) -> Int {
            effects[0..<visualIndex].filter { !$0.isBypassed }.count
        }

        // Visual index == scheduler index when nothing is bypassed
        #expect(activeIndex(at: 0) == 0)
        #expect(activeIndex(at: 1) == 1)
        #expect(activeIndex(at: 2) == 2)
    }

    @Test("Active index with first effect bypassed")
    func activeIndexFirstBypassed() {
        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        let effects = [
            InsertEffect(component: comp, displayName: "A", isBypassed: true, orderIndex: 0),
            InsertEffect(component: comp, displayName: "B", orderIndex: 1),
            InsertEffect(component: comp, displayName: "C", orderIndex: 2),
        ]

        func activeIndex(at visualIndex: Int) -> Int {
            effects[0..<visualIndex].filter { !$0.isBypassed }.count
        }

        // A (bypassed) at visual 0 → scheduler 0 (no active before it)
        #expect(activeIndex(at: 0) == 0)
        // B (active) at visual 1 → scheduler 0 (no active before it)
        #expect(activeIndex(at: 1) == 0)
        // C (active) at visual 2 → scheduler 1 (B is the only active before it)
        #expect(activeIndex(at: 2) == 1)
    }

    @Test("MIDI device and channel change preserves other field")
    @MainActor
    func midiDeviceChangePreservesChannel() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id

        // Set device and channel
        vm.setTrackMIDIInput(trackID: trackID, deviceID: "dev-1", channel: 3)
        #expect(vm.project.songs[0].tracks[0].midiInputDeviceID == "dev-1")
        #expect(vm.project.songs[0].tracks[0].midiInputChannel == 3)

        // Change only device, keeping channel
        vm.setTrackMIDIInput(trackID: trackID, deviceID: "dev-2", channel: 3)
        #expect(vm.project.songs[0].tracks[0].midiInputDeviceID == "dev-2")
        #expect(vm.project.songs[0].tracks[0].midiInputChannel == 3)

        // Change only channel, keeping device
        vm.setTrackMIDIInput(trackID: trackID, deviceID: "dev-2", channel: 10)
        #expect(vm.project.songs[0].tracks[0].midiInputDeviceID == "dev-2")
        #expect(vm.project.songs[0].tracks[0].midiInputChannel == 10)
    }
}
