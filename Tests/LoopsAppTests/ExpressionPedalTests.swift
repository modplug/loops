import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore

@Suite("Expression Pedal Tests")
struct ExpressionPedalTests {

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

    // MARK: - Codable

    @Test("Track with expressionPedalCC and expressionPedalTarget Codable round-trip")
    func trackExpressionPedalRoundTrip() throws {
        let trackID = ID<Track>()
        let target = EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 42)
        let track = Track(
            id: trackID,
            name: "Audio 1",
            kind: .audio,
            expressionPedalCC: 11,
            expressionPedalTarget: target
        )
        let decoded = try roundTrip(track)
        #expect(decoded.expressionPedalCC == 11)
        #expect(decoded.expressionPedalTarget == target)
    }

    @Test("Track without expression pedal fields decodes to nil (backward compat)")
    func trackBackwardCompat() throws {
        let track = Track(name: "Audio 1", kind: .audio)
        let data = try encoder.encode(track)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "expressionPedalCC")
        json.removeValue(forKey: "expressionPedalTarget")
        let modifiedData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try decoder.decode(Track.self, from: modifiedData)
        #expect(decoded.expressionPedalCC == nil)
        #expect(decoded.expressionPedalTarget == nil)
    }

    @Test("Track with expressionPedalCC nil target (volume) round-trips")
    func trackExpressionPedalVolumeRoundTrip() throws {
        let track = Track(
            name: "Audio 1",
            kind: .audio,
            expressionPedalCC: 7,
            expressionPedalTarget: nil
        )
        let decoded = try roundTrip(track)
        #expect(decoded.expressionPedalCC == 7)
        #expect(decoded.expressionPedalTarget == nil)
    }

    // MARK: - Assign Expression Pedal

    @Test("assignExpressionPedal creates correct MIDIParameterMapping for volume")
    @MainActor
    func assignPedalToVolume() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.assignExpressionPedal(trackID: trackID, cc: 11, target: nil)

        // Track fields
        #expect(vm.project.songs[0].tracks[0].expressionPedalCC == 11)
        #expect(vm.project.songs[0].tracks[0].expressionPedalTarget == nil)

        // MIDIParameterMapping
        #expect(vm.project.midiParameterMappings.count == 1)
        let mapping = vm.project.midiParameterMappings[0]
        #expect(mapping.trigger == .controlChange(channel: 0, controller: 11))
        #expect(mapping.targetPath == .trackVolume(trackID: trackID))
        #expect(mapping.minValue == 0.0)
        #expect(mapping.maxValue == 2.0)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("assignExpressionPedal with custom CC number")
    @MainActor
    func assignPedalCustomCC() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.assignExpressionPedal(trackID: trackID, cc: 7, target: nil)

        #expect(vm.project.songs[0].tracks[0].expressionPedalCC == 7)
        #expect(vm.project.midiParameterMappings.count == 1)
        #expect(vm.project.midiParameterMappings[0].trigger == .controlChange(channel: 0, controller: 7))
    }

    @Test("assignExpressionPedal to effect parameter")
    @MainActor
    func assignPedalToEffect() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let effectPath = EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0)

        vm.assignExpressionPedal(trackID: trackID, cc: 11, target: effectPath)

        #expect(vm.project.songs[0].tracks[0].expressionPedalCC == 11)
        #expect(vm.project.songs[0].tracks[0].expressionPedalTarget == effectPath)
        #expect(vm.project.midiParameterMappings.count == 1)
        let mapping = vm.project.midiParameterMappings[0]
        #expect(mapping.targetPath == effectPath)
        #expect(mapping.minValue == 0.0)
        #expect(mapping.maxValue == 1.0)
    }

    @Test("CC #11 → track volume scales correctly (0→0.0, 127→2.0)")
    func ccVolumeScaling() {
        let trackID = ID<Track>()
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 11),
            targetPath: .trackVolume(trackID: trackID),
            minValue: 0.0,
            maxValue: 2.0
        )
        #expect(abs(mapping.scaledValue(ccValue: 0) - 0.0) < 0.001)
        #expect(abs(mapping.scaledValue(ccValue: 127) - 2.0) < 0.001)
        let mid = mapping.scaledValue(ccValue: 64)
        let expected = 2.0 * (64.0 / 127.0)
        #expect(abs(mid - Float(expected)) < 0.01)
    }

    // MARK: - Remove Expression Pedal

    @Test("removeExpressionPedal clears assignment and mapping")
    @MainActor
    func removePedal() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.assignExpressionPedal(trackID: trackID, cc: 11, target: nil)
        #expect(vm.project.midiParameterMappings.count == 1)

        vm.removeExpressionPedal(trackID: trackID)
        #expect(vm.project.songs[0].tracks[0].expressionPedalCC == nil)
        #expect(vm.project.songs[0].tracks[0].expressionPedalTarget == nil)
        #expect(vm.project.midiParameterMappings.isEmpty)
    }

    @Test("removeExpressionPedal no-op when not assigned")
    @MainActor
    func removePedalNoOp() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.hasUnsavedChanges = false

        vm.removeExpressionPedal(trackID: trackID)
        #expect(!vm.hasUnsavedChanges)
    }

    // MARK: - Undo/Redo

    @Test("assignExpressionPedal undo/redo")
    @MainActor
    func assignPedalUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.assignExpressionPedal(trackID: trackID, cc: 11, target: nil)
        #expect(vm.project.songs[0].tracks[0].expressionPedalCC == 11)
        #expect(vm.project.midiParameterMappings.count == 1)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].expressionPedalCC == nil)
        #expect(vm.project.midiParameterMappings.isEmpty)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].expressionPedalCC == 11)
        #expect(vm.project.midiParameterMappings.count == 1)
    }

    @Test("removeExpressionPedal undo/redo")
    @MainActor
    func removePedalUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.assignExpressionPedal(trackID: trackID, cc: 11, target: nil)
        vm.removeExpressionPedal(trackID: trackID)
        #expect(vm.project.songs[0].tracks[0].expressionPedalCC == nil)
        #expect(vm.project.midiParameterMappings.isEmpty)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].expressionPedalCC == 11)
        #expect(vm.project.midiParameterMappings.count == 1)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].expressionPedalCC == nil)
        #expect(vm.project.midiParameterMappings.isEmpty)
    }

    // MARK: - Reassign replaces existing

    @Test("Reassigning expression pedal replaces previous mapping")
    @MainActor
    func reassignReplacesPrevious() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        // Assign CC 11 → volume
        vm.assignExpressionPedal(trackID: trackID, cc: 11, target: nil)
        #expect(vm.project.midiParameterMappings.count == 1)

        // Reassign CC 7 → effect
        let effectPath = EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0)
        vm.assignExpressionPedal(trackID: trackID, cc: 7, target: effectPath)
        #expect(vm.project.songs[0].tracks[0].expressionPedalCC == 7)
        #expect(vm.project.songs[0].tracks[0].expressionPedalTarget == effectPath)

        // Old mapping removed, new one created
        #expect(vm.project.midiParameterMappings.count == 1)
        #expect(vm.project.midiParameterMappings[0].trigger == .controlChange(channel: 0, controller: 7))
        #expect(vm.project.midiParameterMappings[0].targetPath == effectPath)
    }

    // MARK: - duplicateTrack copies expression pedal

    @Test("duplicateTrack copies expressionPedalCC and expressionPedalTarget")
    @MainActor
    func duplicateTrackCopiesPedal() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.assignExpressionPedal(trackID: trackID, cc: 11, target: nil)

        let copyID = vm.duplicateTrack(trackID: trackID)
        #expect(copyID != nil)
        let copy = vm.project.songs[0].tracks.first(where: { $0.id == copyID })
        #expect(copy?.expressionPedalCC == 11)
        #expect(copy?.expressionPedalTarget == nil)
    }

    // MARK: - duplicateSong copies expression pedal

    @Test("duplicateSong copies expressionPedalCC and expressionPedalTarget")
    @MainActor
    func duplicateSongCopiesPedal() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let effectPath = EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 5)
        vm.assignExpressionPedal(trackID: trackID, cc: 4, target: effectPath)

        let songID = vm.project.songs[0].id
        vm.duplicateSong(id: songID)
        #expect(vm.project.songs.count == 2)
        let copiedTrack = vm.project.songs[1].tracks.first(where: { $0.kind == .audio })
        #expect(copiedTrack?.expressionPedalCC == 4)
        #expect(copiedTrack?.expressionPedalTarget?.effectIndex == 0)
        #expect(copiedTrack?.expressionPedalTarget?.parameterAddress == 5)
    }
}
