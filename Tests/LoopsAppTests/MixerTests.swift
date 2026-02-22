import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore

@Suite("Mixer Tests")
struct MixerTests {

    // MARK: - setTrackVolume

    @Test("setTrackVolume updates track volume")
    @MainActor
    func setTrackVolume() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(vm.project.songs[0].tracks[0].volume == 1.0)
        vm.setTrackVolume(trackID: trackID, volume: 0.5)
        #expect(vm.project.songs[0].tracks[0].volume == 0.5)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("setTrackVolume undo/redo")
    @MainActor
    func setTrackVolumeUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.setTrackVolume(trackID: trackID, volume: 0.75)
        #expect(vm.project.songs[0].tracks[0].volume == 0.75)
        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].volume == 1.0)
        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].volume == 0.75)
    }

    @Test("setTrackVolume clamps to 0.0...2.0")
    @MainActor
    func setTrackVolumeClamping() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        // Clamp below 0
        vm.setTrackVolume(trackID: trackID, volume: -0.5)
        #expect(vm.project.songs[0].tracks[0].volume == 0.0)

        // Clamp above 2.0
        vm.setTrackVolume(trackID: trackID, volume: 3.0)
        #expect(vm.project.songs[0].tracks[0].volume == 2.0)

        // Valid boundary values
        vm.setTrackVolume(trackID: trackID, volume: 0.0)
        #expect(vm.project.songs[0].tracks[0].volume == 0.0)

        vm.setTrackVolume(trackID: trackID, volume: 2.0)
        #expect(vm.project.songs[0].tracks[0].volume == 2.0)
    }

    // MARK: - setTrackPan

    @Test("setTrackPan updates track pan")
    @MainActor
    func setTrackPan() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(vm.project.songs[0].tracks[0].pan == 0.0)
        vm.setTrackPan(trackID: trackID, pan: -0.5)
        #expect(vm.project.songs[0].tracks[0].pan == -0.5)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("setTrackPan undo/redo")
    @MainActor
    func setTrackPanUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.setTrackPan(trackID: trackID, pan: 0.8)
        #expect(vm.project.songs[0].tracks[0].pan == 0.8)
        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].pan == 0.0)
        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].pan == 0.8)
    }

    @Test("setTrackPan clamps to -1.0...1.0")
    @MainActor
    func setTrackPanClamping() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        // Clamp below -1.0
        vm.setTrackPan(trackID: trackID, pan: -2.0)
        #expect(vm.project.songs[0].tracks[0].pan == -1.0)

        // Clamp above 1.0
        vm.setTrackPan(trackID: trackID, pan: 1.5)
        #expect(vm.project.songs[0].tracks[0].pan == 1.0)

        // Valid boundary values
        vm.setTrackPan(trackID: trackID, pan: -1.0)
        #expect(vm.project.songs[0].tracks[0].pan == -1.0)

        vm.setTrackPan(trackID: trackID, pan: 1.0)
        #expect(vm.project.songs[0].tracks[0].pan == 1.0)
    }

    // MARK: - MixerViewModel

    @Test("MixerViewModel gainToDBString conversions")
    @MainActor
    func gainToDBString() {
        #expect(MixerViewModel.gainToDBString(1.0) == "0.0 dB")
        #expect(MixerViewModel.gainToDBString(0.0) == "-inf")
        #expect(MixerViewModel.gainToDBString(0.00001) == "-inf")
        // 2.0 gain ~ +6.0 dB
        let twoGainDB = MixerViewModel.gainToDBString(2.0)
        #expect(twoGainDB.contains("6.0"))
    }

    @Test("MixerViewModel dbToGain conversions")
    @MainActor
    func dbToGain() {
        #expect(MixerViewModel.dbToGain(0.0) == 1.0)
        #expect(MixerViewModel.dbToGain(-80.0) == 0.0)
        #expect(MixerViewModel.dbToGain(-100.0) == 0.0)
        // +6 dB ~ 2.0 gain
        let gain = MixerViewModel.dbToGain(6.0)
        #expect(gain > 1.9 && gain < 2.1)
    }

    @Test("MixerViewModel updateLevel stores per-track levels")
    @MainActor
    func updateLevel() {
        let vm = MixerViewModel()
        let trackID = ID<Track>()
        #expect(vm.trackLevels[trackID] == nil)
        vm.updateLevel(trackID: trackID, peak: 0.75)
        #expect(vm.trackLevels[trackID] == 0.75)
    }

    @Test("MixerViewModel updateMasterLevel stores master level")
    @MainActor
    func updateMasterLevel() {
        let vm = MixerViewModel()
        #expect(vm.masterLevel == 0.0)
        vm.updateMasterLevel(0.9)
        #expect(vm.masterLevel == 0.9)
    }

    // MARK: - Volume/Pan on master track

    @Test("setTrackVolume works on master track")
    @MainActor
    func setMasterTrackVolume() {
        let vm = ProjectViewModel()
        vm.newProject()
        // Master track is auto-created
        guard let masterTrack = vm.project.songs[0].tracks.first(where: { $0.kind == .master }) else {
            Issue.record("Expected master track")
            return
        }
        vm.setTrackVolume(trackID: masterTrack.id, volume: 0.6)
        #expect(vm.project.songs[0].tracks.first(where: { $0.kind == .master })?.volume == 0.6)
    }

    @Test("setTrackPan works on master track")
    @MainActor
    func setMasterTrackPan() {
        let vm = ProjectViewModel()
        vm.newProject()
        guard let masterTrack = vm.project.songs[0].tracks.first(where: { $0.kind == .master }) else {
            Issue.record("Expected master track")
            return
        }
        vm.setTrackPan(trackID: masterTrack.id, pan: -0.3)
        #expect(vm.project.songs[0].tracks.first(where: { $0.kind == .master })?.pan == -0.3)
    }

    // MARK: - Invalid track ID

    @Test("setTrackVolume with invalid ID is no-op")
    @MainActor
    func setTrackVolumeInvalidID() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let fakeID = ID<Track>()
        vm.setTrackVolume(trackID: fakeID, volume: 0.5)
        // Should not crash, and should not modify existing tracks
        #expect(vm.project.songs[0].tracks[0].volume == 1.0)
    }

    @Test("setTrackPan with invalid ID is no-op")
    @MainActor
    func setTrackPanInvalidID() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let fakeID = ID<Track>()
        vm.setTrackPan(trackID: fakeID, pan: 0.5)
        // Should not crash, and should not modify existing tracks
        #expect(vm.project.songs[0].tracks[0].pan == 0.0)
    }

    // MARK: - Fader/pan drag propagation

    @Test("Volume fader drag values propagate to engine model immediately")
    @MainActor
    func faderDragPropagatesToEngine() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        // Simulate rapid drag updates (as from a custom drag gesture)
        vm.setTrackVolume(trackID: trackID, volume: 0.3)
        #expect(vm.project.songs[0].tracks[0].volume == 0.3)

        vm.setTrackVolume(trackID: trackID, volume: 0.6)
        #expect(vm.project.songs[0].tracks[0].volume == 0.6)

        vm.setTrackVolume(trackID: trackID, volume: 1.5)
        #expect(vm.project.songs[0].tracks[0].volume == 1.5)

        // Each intermediate value is immediately reflected
        vm.setTrackVolume(trackID: trackID, volume: 0.0)
        #expect(vm.project.songs[0].tracks[0].volume == 0.0)
    }

    @Test("Engine volume state is readable back after changes")
    @MainActor
    func engineVolumeStateReadback() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        // Set volume via model (simulates engine update)
        vm.setTrackVolume(trackID: trackID, volume: 0.42)

        // Read back from the track model — this is what MixerStripView's
        // onChange(of: track.volume) observes for UI sync
        let readbackVolume = vm.project.songs[0].tracks.first(where: { $0.id == trackID })?.volume
        #expect(readbackVolume == 0.42)
    }

    @Test("Pan knob drag values propagate to engine model immediately")
    @MainActor
    func panDragPropagatesToEngine() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        // Simulate rapid pan drag updates
        vm.setTrackPan(trackID: trackID, pan: -0.7)
        #expect(vm.project.songs[0].tracks[0].pan == -0.7)

        vm.setTrackPan(trackID: trackID, pan: 0.0)
        #expect(vm.project.songs[0].tracks[0].pan == 0.0)

        vm.setTrackPan(trackID: trackID, pan: 0.9)
        #expect(vm.project.songs[0].tracks[0].pan == 0.9)
    }

    @Test("Engine pan state is readable back after changes")
    @MainActor
    func enginePanStateReadback() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.setTrackPan(trackID: trackID, pan: -0.65)

        let readbackPan = vm.project.songs[0].tracks.first(where: { $0.id == trackID })?.pan
        #expect(readbackPan == -0.65)
    }
}
