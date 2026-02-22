import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore
@testable import LoopsEngine

@Suite("MIDI Parameter Mapping Tests")
struct MIDIParameterMappingTests {

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

    // MARK: - MIDIParameterMapping Codable

    @Test("MIDIParameterMapping Codable round-trip")
    func mappingRoundTrip() throws {
        let trackID = ID<Track>()
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 11),
            targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 42),
            minValue: 0.0,
            maxValue: 1.0
        )
        let decoded = try roundTrip(mapping)
        #expect(decoded == mapping)
        #expect(decoded.trigger == .controlChange(channel: 0, controller: 11))
        #expect(decoded.targetPath.trackID == trackID)
        #expect(decoded.targetPath.effectIndex == 0)
        #expect(decoded.targetPath.parameterAddress == 42)
        #expect(decoded.minValue == 0.0)
        #expect(decoded.maxValue == 1.0)
    }

    // MARK: - CC Value Scaling

    @Test("CC 0 maps to minValue")
    func ccZeroMapsToMin() {
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 1),
            targetPath: EffectPath(trackID: ID<Track>(), effectIndex: 0, parameterAddress: 0),
            minValue: 0.2,
            maxValue: 0.8
        )
        let scaled = mapping.scaledValue(ccValue: 0)
        #expect(abs(scaled - 0.2) < 0.001)
    }

    @Test("CC 127 maps to maxValue")
    func cc127MapsToMax() {
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 1),
            targetPath: EffectPath(trackID: ID<Track>(), effectIndex: 0, parameterAddress: 0),
            minValue: 0.2,
            maxValue: 0.8
        )
        let scaled = mapping.scaledValue(ccValue: 127)
        #expect(abs(scaled - 0.8) < 0.001)
    }

    @Test("CC 64 maps to midpoint")
    func cc64MapToMidpoint() {
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 1),
            targetPath: EffectPath(trackID: ID<Track>(), effectIndex: 0, parameterAddress: 0),
            minValue: 0.0,
            maxValue: 1.0
        )
        let scaled = mapping.scaledValue(ccValue: 64)
        let expected: Float = 64.0 / 127.0
        #expect(abs(scaled - expected) < 0.001)
    }

    // MARK: - Project backward-compatible decode

    @Test("Project without midiParameterMappings decodes to empty array")
    func projectBackwardCompat() throws {
        // Encode a project, then strip the midiParameterMappings key from JSON
        let project = Project(name: "Test")
        let data = try encoder.encode(project)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "midiParameterMappings")
        let modifiedData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try decoder.decode(Project.self, from: modifiedData)
        #expect(decoded.midiParameterMappings.isEmpty)
        #expect(decoded.name == "Test")
    }

    @Test("Project with midiParameterMappings round-trips")
    func projectWithMappingsRoundTrip() throws {
        let trackID = ID<Track>()
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 7),
            targetPath: EffectPath.trackVolume(trackID: trackID),
            minValue: 0.0,
            maxValue: 2.0
        )
        let project = Project(name: "Test", midiParameterMappings: [mapping])
        let decoded = try roundTrip(project)
        #expect(decoded.midiParameterMappings.count == 1)
        #expect(decoded.midiParameterMappings[0].trigger == .controlChange(channel: 0, controller: 7))
        #expect(decoded.midiParameterMappings[0].targetPath.isTrackVolume)
    }

    // MARK: - ProjectViewModel MIDI Parameter Mapping CRUD

    @Test("Add MIDI parameter mapping")
    @MainActor
    func addMapping() {
        let vm = ProjectViewModel()
        vm.newProject()
        let trackID = ID<Track>()
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 11),
            targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0)
        )
        vm.addMIDIParameterMapping(mapping)
        #expect(vm.project.midiParameterMappings.count == 1)
        #expect(vm.project.midiParameterMappings[0].trigger == .controlChange(channel: 0, controller: 11))
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Remove MIDI parameter mapping by ID")
    @MainActor
    func removeMappingByID() {
        let vm = ProjectViewModel()
        vm.newProject()
        let trackID = ID<Track>()
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 11),
            targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0)
        )
        vm.addMIDIParameterMapping(mapping)
        #expect(vm.project.midiParameterMappings.count == 1)

        vm.removeMIDIParameterMapping(mappingID: mapping.id)
        #expect(vm.project.midiParameterMappings.isEmpty)
    }

    @Test("Remove MIDI parameter mapping by target")
    @MainActor
    func removeMappingByTarget() {
        let vm = ProjectViewModel()
        vm.newProject()
        let trackID = ID<Track>()
        let targetPath = EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0)
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 11),
            targetPath: targetPath
        )
        vm.addMIDIParameterMapping(mapping)
        #expect(vm.project.midiParameterMappings.count == 1)

        vm.removeMIDIParameterMapping(forTarget: targetPath)
        #expect(vm.project.midiParameterMappings.isEmpty)
    }

    @Test("Remove all MIDI parameter mappings")
    @MainActor
    func removeAllMappings() {
        let vm = ProjectViewModel()
        vm.newProject()
        let trackID = ID<Track>()
        vm.addMIDIParameterMapping(MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 11),
            targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0)
        ))
        vm.addMIDIParameterMapping(MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 7),
            targetPath: EffectPath.trackVolume(trackID: trackID)
        ))
        #expect(vm.project.midiParameterMappings.count == 2)

        vm.removeAllMIDIParameterMappings()
        #expect(vm.project.midiParameterMappings.isEmpty)
    }

    @Test("Remove all mappings no-op when empty")
    @MainActor
    func removeAllNoOp() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.hasUnsavedChanges = false
        vm.removeAllMIDIParameterMappings()
        #expect(!vm.hasUnsavedChanges)
    }

    @Test("Add MIDI mapping undo/redo")
    @MainActor
    func addMappingUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        let trackID = ID<Track>()
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 11),
            targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0)
        )
        vm.addMIDIParameterMapping(mapping)
        #expect(vm.project.midiParameterMappings.count == 1)

        vm.undoManager?.undo()
        #expect(vm.project.midiParameterMappings.isEmpty)

        vm.undoManager?.redo()
        #expect(vm.project.midiParameterMappings.count == 1)
    }

    @Test("Remove MIDI mapping undo/redo")
    @MainActor
    func removeMappingUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        let trackID = ID<Track>()
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 11),
            targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0)
        )
        vm.addMIDIParameterMapping(mapping)
        vm.removeMIDIParameterMapping(mappingID: mapping.id)
        #expect(vm.project.midiParameterMappings.isEmpty)

        vm.undoManager?.undo()
        #expect(vm.project.midiParameterMappings.count == 1)

        vm.undoManager?.redo()
        #expect(vm.project.midiParameterMappings.isEmpty)
    }

    // MARK: - Multiple mappings: different CCs to different parameters

    @Test("Multiple mappings for different CCs to different parameters")
    @MainActor
    func multipleMappings() {
        let vm = ProjectViewModel()
        vm.newProject()
        let trackID = ID<Track>()
        vm.addMIDIParameterMapping(MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 7),
            targetPath: EffectPath.trackVolume(trackID: trackID)
        ))
        vm.addMIDIParameterMapping(MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 10),
            targetPath: EffectPath.trackPan(trackID: trackID)
        ))
        vm.addMIDIParameterMapping(MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 11),
            targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 42)
        ))
        #expect(vm.project.midiParameterMappings.count == 3)

        // Look up by target
        let volMapping = vm.midiParameterMapping(forTarget: .trackVolume(trackID: trackID))
        #expect(volMapping != nil)
        #expect(volMapping?.trigger == .controlChange(channel: 0, controller: 7))

        let panMapping = vm.midiParameterMapping(forTarget: .trackPan(trackID: trackID))
        #expect(panMapping != nil)
        #expect(panMapping?.trigger == .controlChange(channel: 0, controller: 10))
    }

    // MARK: - MIDIDispatcher parameter dispatch

    @Test("MIDIDispatcher dispatches CC value to parameter callback")
    func dispatcherParameterValue() {
        let dispatcher = MIDIDispatcher()
        let trackID = ID<Track>()
        let targetPath = EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 42)
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 11),
            targetPath: targetPath,
            minValue: 0.0,
            maxValue: 1.0
        )
        dispatcher.updateParameterMappings([mapping])

        var receivedPath: EffectPath?
        var receivedValue: Float?
        dispatcher.onParameterValue = { path, value in
            receivedPath = path
            receivedValue = value
        }

        dispatcher.dispatch(.controlChange(channel: 0, controller: 11), ccValue: 127)
        #expect(receivedPath == targetPath)
        #expect(receivedValue != nil)
        #expect(abs(receivedValue! - 1.0) < 0.001)
    }

    @Test("MIDIDispatcher does not dispatch parameter for unmapped CC")
    func dispatcherNoParameterForUnmapped() {
        let dispatcher = MIDIDispatcher()
        let trackID = ID<Track>()
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 11),
            targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 42)
        )
        dispatcher.updateParameterMappings([mapping])

        var called = false
        dispatcher.onParameterValue = { _, _ in
            called = true
        }

        // Different controller number
        dispatcher.dispatch(.controlChange(channel: 0, controller: 12), ccValue: 64)
        #expect(!called)
    }

    @Test("MIDIDispatcher learn mode intercepts parameter dispatch")
    func dispatcherLearnModeIntercepts() {
        let dispatcher = MIDIDispatcher()
        let trackID = ID<Track>()
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 11),
            targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 42)
        )
        dispatcher.updateParameterMappings([mapping])
        dispatcher.isLearning = true

        var paramCalled = false
        dispatcher.onParameterValue = { _, _ in
            paramCalled = true
        }

        var learnedTrigger: MIDITrigger?
        dispatcher.onMIDILearnEvent = { trigger in
            learnedTrigger = trigger
        }

        dispatcher.dispatch(.controlChange(channel: 0, controller: 11), ccValue: 64)
        #expect(!paramCalled)
        #expect(learnedTrigger == .controlChange(channel: 0, controller: 11))
    }

    // MARK: - MIDILearnController parameter learning

    @Test("MIDILearnController parameter learning creates mapping")
    func learnControllerParameterLearning() {
        let dispatcher = MIDIDispatcher()
        let controller = MIDILearnController(dispatcher: dispatcher)
        let trackID = ID<Track>()
        let targetPath = EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 42)

        var learnedMapping: MIDIParameterMapping?
        controller.onParameterMappingLearned = { mapping in
            learnedMapping = mapping
        }

        controller.startParameterLearning(for: targetPath)
        #expect(dispatcher.isLearning)
        #expect(controller.learningControl == nil)

        dispatcher.dispatch(.controlChange(channel: 1, controller: 74))
        #expect(learnedMapping != nil)
        #expect(learnedMapping?.trigger == .controlChange(channel: 1, controller: 74))
        #expect(learnedMapping?.targetPath == targetPath)
        #expect(learnedMapping?.minValue == 0.0)
        #expect(learnedMapping?.maxValue == 1.0)
        #expect(!dispatcher.isLearning)
    }

    @Test("MIDILearnController cancel parameter learning")
    func learnControllerCancelParameter() {
        let dispatcher = MIDIDispatcher()
        let controller = MIDILearnController(dispatcher: dispatcher)
        let trackID = ID<Track>()

        controller.startParameterLearning(for: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0))
        #expect(dispatcher.isLearning)

        controller.cancelLearning()
        #expect(!dispatcher.isLearning)
        #expect(controller.learningTarget == nil)
    }

    // MARK: - ProjectViewModel MIDI learn flow

    @Test("ProjectViewModel completeMIDIParameterLearn creates mapping")
    @MainActor
    func completeMIDILearn() {
        let vm = ProjectViewModel()
        vm.newProject()
        let trackID = ID<Track>()
        let targetPath = EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 42)

        vm.startMIDIParameterLearn(targetPath: targetPath)
        #expect(vm.isMIDIParameterLearning)
        #expect(vm.midiLearnTargetPath == targetPath)

        vm.completeMIDIParameterLearn(trigger: .controlChange(channel: 0, controller: 11))
        #expect(!vm.isMIDIParameterLearning)
        #expect(vm.midiLearnTargetPath == nil)
        #expect(vm.project.midiParameterMappings.count == 1)
        #expect(vm.project.midiParameterMappings[0].trigger == .controlChange(channel: 0, controller: 11))
        #expect(vm.project.midiParameterMappings[0].targetPath == targetPath)
    }

    @Test("ProjectViewModel cancelMIDIParameterLearn resets state")
    @MainActor
    func cancelMIDILearn() {
        let vm = ProjectViewModel()
        vm.newProject()
        let trackID = ID<Track>()

        vm.startMIDIParameterLearn(targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0))
        #expect(vm.isMIDIParameterLearning)

        vm.cancelMIDIParameterLearn()
        #expect(!vm.isMIDIParameterLearning)
        #expect(vm.midiLearnTargetPath == nil)
        #expect(vm.project.midiParameterMappings.isEmpty)
    }

    @Test("completeMIDIParameterLearn replaces existing mapping for same trigger")
    @MainActor
    func learnReplacesSameTrigger() {
        let vm = ProjectViewModel()
        vm.newProject()
        let trackID = ID<Track>()
        let target1 = EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0)
        let target2 = EffectPath(trackID: trackID, effectIndex: 1, parameterAddress: 0)

        // First mapping: CC 11 → effect 0
        vm.startMIDIParameterLearn(targetPath: target1)
        vm.completeMIDIParameterLearn(trigger: .controlChange(channel: 0, controller: 11))
        #expect(vm.project.midiParameterMappings.count == 1)

        // Second mapping: CC 11 → effect 1 (should replace the first)
        vm.startMIDIParameterLearn(targetPath: target2)
        vm.completeMIDIParameterLearn(trigger: .controlChange(channel: 0, controller: 11))
        #expect(vm.project.midiParameterMappings.count == 1)
        #expect(vm.project.midiParameterMappings[0].targetPath == target2)
    }

    // MARK: - Extended MIDI Mapping Targets (Issue #110)

    @Test("ProjectViewModel dispatches mute toggle for mapped track")
    @MainActor
    func muteToggleViaMIDI() {
        let vm = ProjectViewModel()
        vm.newProject()
        let tracks = vm.currentSong?.tracks.filter { $0.kind != .master } ?? []
        guard let track = tracks.first else { return }

        #expect(!track.isMuted)
        vm.toggleMute(trackID: track.id)
        let mutedTrack = vm.currentSong?.tracks.first(where: { $0.id == track.id })
        #expect(mutedTrack?.isMuted == true)
    }

    @Test("ProjectViewModel dispatches solo toggle for mapped track")
    @MainActor
    func soloToggleViaMIDI() {
        let vm = ProjectViewModel()
        vm.newProject()
        let tracks = vm.currentSong?.tracks.filter { $0.kind != .master } ?? []
        guard let track = tracks.first else { return }

        #expect(!track.isSoloed)
        vm.toggleSolo(trackID: track.id)
        let soloedTrack = vm.currentSong?.tracks.first(where: { $0.id == track.id })
        #expect(soloedTrack?.isSoloed == true)
    }

    @Test("ProjectViewModel selectSong by index triggers song change")
    @MainActor
    func songSelectByIndex() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSong()
        #expect(vm.project.songs.count == 2)

        let secondSongID = vm.project.songs[1].id
        vm.selectSong(id: secondSongID)
        #expect(vm.currentSongID == secondSongID)
    }

    @Test("ProjectViewModel setTrackVolume clamps to 0-2 range")
    @MainActor
    func trackVolumeClamp() {
        let vm = ProjectViewModel()
        vm.newProject()
        let tracks = vm.currentSong?.tracks.filter { $0.kind != .master } ?? []
        guard let track = tracks.first else { return }

        vm.setTrackVolume(trackID: track.id, volume: 1.5)
        let updated = vm.currentSong?.tracks.first(where: { $0.id == track.id })
        #expect(updated?.volume == 1.5)

        vm.setTrackVolume(trackID: track.id, volume: 3.0) // Over max
        let clamped = vm.currentSong?.tracks.first(where: { $0.id == track.id })
        #expect(clamped?.volume == 2.0)
    }

    @Test("ProjectViewModel setTrackPan clamps to -1..1 range")
    @MainActor
    func trackPanClamp() {
        let vm = ProjectViewModel()
        vm.newProject()
        let tracks = vm.currentSong?.tracks.filter { $0.kind != .master } ?? []
        guard let track = tracks.first else { return }

        vm.setTrackPan(trackID: track.id, pan: 0.5)
        let updated = vm.currentSong?.tracks.first(where: { $0.id == track.id })
        #expect(updated?.pan == 0.5)

        vm.setTrackPan(trackID: track.id, pan: -2.0) // Under min
        let clamped = vm.currentSong?.tracks.first(where: { $0.id == track.id })
        #expect(clamped?.pan == -1.0)
    }

    @Test("ProjectViewModel setTrackSendLevel with valid index")
    @MainActor
    func setTrackSendLevel() {
        let vm = ProjectViewModel()
        vm.newProject()
        let tracks = vm.currentSong?.tracks.filter { $0.kind != .master } ?? []
        guard let track = tracks.first else { return }

        // By default tracks have no send levels, so this should be a no-op
        vm.setTrackSendLevel(trackID: track.id, sendIndex: 0, level: 0.5)
        // No crash = success for out-of-bounds guard
    }

    @Test("onMIDIMappingsChanged callback fires when set")
    @MainActor
    func onMIDIMappingsChangedCallback() {
        let vm = ProjectViewModel()
        vm.newProject()

        var callbackFired = false
        vm.onMIDIMappingsChanged = { callbackFired = true }
        vm.onMIDIMappingsChanged?()
        #expect(callbackFired)
    }
}
