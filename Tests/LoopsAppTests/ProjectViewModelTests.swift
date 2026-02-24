import Testing
import Foundation
import AVFoundation
@testable import LoopsApp
@testable import LoopsCore
@testable import LoopsEngine

@Suite("ProjectViewModel Tests")
struct ProjectViewModelTests {

    @Test("New project creates a default song")
    @MainActor
    func newProject() {
        let vm = ProjectViewModel()
        vm.newProject()
        #expect(vm.project.songs.count == 1)
        #expect(vm.project.songs[0].name == "Song 1")
    }

    @Test("Add audio track to current song")
    @MainActor
    func addAudioTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        // 2 tracks: Audio 1 + auto-created Master
        #expect(vm.project.songs[0].tracks.count == 2)
        #expect(vm.project.songs[0].tracks[0].name == "Audio 1")
        #expect(vm.project.songs[0].tracks[0].kind == .audio)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Add multiple tracks auto-increments names")
    @MainActor
    func addMultipleTracks() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        // 4 tracks: 3 added + Master (always last)
        #expect(vm.project.songs[0].tracks.count == 4)
        #expect(vm.project.songs[0].tracks[0].name == "Audio 1")
        #expect(vm.project.songs[0].tracks[1].name == "Audio 2")
        #expect(vm.project.songs[0].tracks[2].name == "MIDI 1")
        #expect(vm.project.songs[0].tracks[3].kind == .master)
    }

    @Test("Remove track by ID")
    @MainActor
    func removeTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        let audioTrackID = vm.project.songs[0].tracks[0].id
        vm.removeTrack(id: audioTrackID)
        // 2 tracks: MIDI + Master
        #expect(vm.project.songs[0].tracks.count == 2)
        #expect(vm.project.songs[0].tracks[0].kind == .midi)
    }

    @Test("Rename track")
    @MainActor
    func renameTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.renameTrack(id: trackID, newName: "Lead Guitar")
        #expect(vm.project.songs[0].tracks[0].name == "Lead Guitar")
    }

    @Test("Move track reorders and reindexes")
    @MainActor
    func moveTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        vm.addTrack(kind: .bus)

        // Move track at index 0 to index 2
        vm.moveTrack(from: IndexSet(integer: 0), to: 2)
        #expect(vm.project.songs[0].tracks[0].kind == .midi)
        #expect(vm.project.songs[0].tracks[1].kind == .audio)
        #expect(vm.project.songs[0].tracks[2].kind == .bus)

        // Verify orderIndex was updated
        for (i, track) in vm.project.songs[0].tracks.enumerated() {
            #expect(track.orderIndex == i)
        }
    }

    @Test("Toggle mute")
    @MainActor
    func toggleMute() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(!vm.project.songs[0].tracks[0].isMuted)
        vm.toggleMute(trackID: trackID)
        #expect(vm.project.songs[0].tracks[0].isMuted)
        vm.toggleMute(trackID: trackID)
        #expect(!vm.project.songs[0].tracks[0].isMuted)
    }

    @Test("Toggle solo")
    @MainActor
    func toggleSolo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(!vm.project.songs[0].tracks[0].isSoloed)
        vm.toggleSolo(trackID: trackID)
        #expect(vm.project.songs[0].tracks[0].isSoloed)
    }

    @Test("Set track record armed")
    @MainActor
    func setTrackRecordArmed() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(!vm.project.songs[0].tracks[0].isRecordArmed)
        vm.setTrackRecordArmed(trackID: trackID, armed: true)
        #expect(vm.project.songs[0].tracks[0].isRecordArmed)
        vm.setTrackRecordArmed(trackID: trackID, armed: false)
        #expect(!vm.project.songs[0].tracks[0].isRecordArmed)
    }

    @Test("Set track monitoring")
    @MainActor
    func setTrackMonitoring() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(!vm.project.songs[0].tracks[0].isMonitoring)
        vm.setTrackMonitoring(trackID: trackID, monitoring: true)
        #expect(vm.project.songs[0].tracks[0].isMonitoring)
        vm.setTrackMonitoring(trackID: trackID, monitoring: false)
        #expect(!vm.project.songs[0].tracks[0].isMonitoring)
    }

    @Test("Set track MIDI input device and channel")
    @MainActor
    func setTrackMIDIInput() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(vm.project.songs[0].tracks[0].midiInputDeviceID == nil)
        #expect(vm.project.songs[0].tracks[0].midiInputChannel == nil)
        vm.setTrackMIDIInput(trackID: trackID, deviceID: "device-42", channel: 5)
        #expect(vm.project.songs[0].tracks[0].midiInputDeviceID == "device-42")
        #expect(vm.project.songs[0].tracks[0].midiInputChannel == 5)
    }

    @Test("Undo/redo set track MIDI input")
    @MainActor
    func undoRedoSetTrackMIDIInput() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.setTrackMIDIInput(trackID: trackID, deviceID: "dev-1", channel: 3)
        #expect(vm.project.songs[0].tracks[0].midiInputDeviceID == "dev-1")
        #expect(vm.project.songs[0].tracks[0].midiInputChannel == 3)
        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].midiInputDeviceID == nil)
        #expect(vm.project.songs[0].tracks[0].midiInputChannel == nil)
        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].midiInputDeviceID == "dev-1")
        #expect(vm.project.songs[0].tracks[0].midiInputChannel == 3)
    }

    @Test("Current song returns first song")
    @MainActor
    func currentSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        #expect(vm.currentSong?.name == "Song 1")
    }

    @Test("Track operations on empty project are safe")
    @MainActor
    func emptyProjectSafety() {
        let vm = ProjectViewModel()
        // These should all be no-ops, not crashes
        vm.addTrack(kind: .audio)
        vm.removeTrack(id: ID<Track>())
        vm.renameTrack(id: ID<Track>(), newName: "Test")
        vm.toggleMute(trackID: ID<Track>())
        vm.toggleSolo(trackID: ID<Track>())
    }

    // MARK: - Container Management

    @Test("Add container to track")
    @MainActor
    func addContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let result = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        #expect(result)
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)
        #expect(vm.project.songs[0].tracks[0].containers[0].startBar == 1)
        #expect(vm.project.songs[0].tracks[0].containers[0].lengthBars == 4)
        #expect(vm.selectedContainerID != nil)
    }

    @Test("Container overlap prevention")
    @MainActor
    func containerOverlap() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        // Add first container: bars 1-4
        let first = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        #expect(first)

        // Try overlapping container: bars 3-6 — should fail
        let overlap = vm.addContainer(trackID: trackID, startBar: 3, lengthBars: 4)
        #expect(!overlap)
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)

        // Non-overlapping container: bars 5-8 — should succeed
        let noOverlap = vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4)
        #expect(noOverlap)
        #expect(vm.project.songs[0].tracks[0].containers.count == 2)
    }

    @Test("Remove container")
    @MainActor
    func removeContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        vm.selectedContainerID = containerID
        vm.removeContainer(trackID: trackID, containerID: containerID)
        #expect(vm.project.songs[0].tracks[0].containers.isEmpty)
        #expect(vm.selectedContainerID == nil)
    }

    @Test("Move container")
    @MainActor
    func moveContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let result = vm.moveContainer(trackID: trackID, containerID: containerID, newStartBar: 5)
        #expect(result)
        #expect(vm.project.songs[0].tracks[0].containers[0].startBar == 5)
    }

    @Test("Move container prevents overlap")
    @MainActor
    func moveContainerOverlap() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let _ = vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4)
        let firstID = vm.project.songs[0].tracks[0].containers[0].id

        // Try to move first container to bar 4 — would overlap with second
        let result = vm.moveContainer(trackID: trackID, containerID: firstID, newStartBar: 4)
        #expect(!result)
        #expect(vm.project.songs[0].tracks[0].containers[0].startBar == 1)
    }

    @Test("Resize container")
    @MainActor
    func resizeContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let result = vm.resizeContainer(trackID: trackID, containerID: containerID, newLengthBars: 8)
        #expect(result)
        #expect(vm.project.songs[0].tracks[0].containers[0].lengthBars == 8)
    }

    @Test("Resize container prevents overlap")
    @MainActor
    func resizeContainerOverlap() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let _ = vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4)
        let firstID = vm.project.songs[0].tracks[0].containers[0].id

        // Try to extend first container to 6 bars — would overlap
        let result = vm.resizeContainer(trackID: trackID, containerID: firstID, newLengthBars: 6)
        #expect(!result)
        #expect(vm.project.songs[0].tracks[0].containers[0].lengthBars == 4)
    }

    @Test("Container startBar clamps to minimum 1")
    @MainActor
    func containerStartBarClamp() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let result = vm.addContainer(trackID: trackID, startBar: -5, lengthBars: 4)
        #expect(result)
        #expect(vm.project.songs[0].tracks[0].containers[0].startBar == 1)
    }

    // MARK: - Song Management

    @Test("New project sets currentSongID")
    @MainActor
    func newProjectSetsSongID() {
        let vm = ProjectViewModel()
        vm.newProject()
        #expect(vm.currentSongID != nil)
        #expect(vm.currentSongID == vm.project.songs[0].id)
    }

    @Test("Add song creates new song with default settings")
    @MainActor
    func addSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSong()
        #expect(vm.project.songs.count == 2)
        #expect(vm.project.songs[1].name == "Song 2")
        #expect(vm.currentSongID == vm.project.songs[1].id)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Select song by ID")
    @MainActor
    func selectSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSong()
        let firstSongID = vm.project.songs[0].id
        vm.selectSong(id: firstSongID)
        #expect(vm.currentSongID == firstSongID)
        #expect(vm.currentSongIndex == 0)
    }

    @Test("Remove song selects nearest")
    @MainActor
    func removeSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSong()
        vm.addSong()
        #expect(vm.project.songs.count == 3)

        let secondSongID = vm.project.songs[1].id
        vm.selectSong(id: secondSongID)
        vm.removeSong(id: secondSongID)

        #expect(vm.project.songs.count == 2)
        #expect(vm.currentSongID != nil)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Cannot remove last song")
    @MainActor
    func cannotRemoveLastSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        #expect(vm.project.songs.count == 1)
        let songID = vm.project.songs[0].id
        vm.removeSong(id: songID)
        #expect(vm.project.songs.count == 1)
    }

    @Test("Rename song")
    @MainActor
    func renameSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id
        vm.renameSong(id: songID, newName: "My Cool Song")
        #expect(vm.project.songs[0].name == "My Cool Song")
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Duplicate song creates copy")
    @MainActor
    func duplicateSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        let songID = vm.project.songs[0].id
        vm.duplicateSong(id: songID)

        #expect(vm.project.songs.count == 2)
        #expect(vm.project.songs[1].name == "Song 1 Copy")
        #expect(vm.project.songs[1].tracks.count == 3) // audio + midi + master
        #expect(vm.project.songs[1].tempo == vm.project.songs[0].tempo)
        // IDs should be different
        #expect(vm.project.songs[1].id != vm.project.songs[0].id)
        #expect(vm.project.songs[1].tracks[0].id != vm.project.songs[0].tracks[0].id)
        // Should select the copy
        #expect(vm.currentSongID == vm.project.songs[1].id)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Select nonexistent song is no-op")
    @MainActor
    func selectNonexistentSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        let originalID = vm.currentSongID
        vm.selectSong(id: ID<Song>())
        #expect(vm.currentSongID == originalID)
    }

    @Test("Selecting a song clears container selection")
    @MainActor
    func selectSongClearsContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        #expect(vm.selectedContainerID != nil)

        vm.addSong()
        let secondSongID = vm.project.songs[1].id
        vm.selectSong(id: vm.project.songs[0].id)
        vm.selectSong(id: secondSongID)
        #expect(vm.selectedContainerID == nil)
    }

    // MARK: - Volume / Pan

    @Test("Set track volume is clamped")
    @MainActor
    func setTrackVolume() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.setTrackVolume(trackID: trackID, volume: 1.5)
        #expect(vm.project.songs[0].tracks[0].volume == 1.5)

        vm.setTrackVolume(trackID: trackID, volume: 3.0)
        #expect(vm.project.songs[0].tracks[0].volume == 2.0) // clamped

        vm.setTrackVolume(trackID: trackID, volume: -1.0)
        #expect(vm.project.songs[0].tracks[0].volume == 0.0) // clamped
    }

    @Test("Set track pan is clamped")
    @MainActor
    func setTrackPan() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.setTrackPan(trackID: trackID, pan: 0.5)
        #expect(vm.project.songs[0].tracks[0].pan == 0.5)

        vm.setTrackPan(trackID: trackID, pan: 2.0)
        #expect(vm.project.songs[0].tracks[0].pan == 1.0) // clamped

        vm.setTrackPan(trackID: trackID, pan: -5.0)
        #expect(vm.project.songs[0].tracks[0].pan == -1.0) // clamped
    }

    // MARK: - Undo / Redo

    @Test("Undo add track restores previous state")
    @MainActor
    func undoAddTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        // Only master track after newProject
        #expect(vm.project.songs[0].tracks.count == 1)
        #expect(vm.project.songs[0].tracks[0].kind == .master)

        vm.addTrack(kind: .audio)
        #expect(vm.project.songs[0].tracks.count == 2)
        #expect(vm.undoManager?.canUndo == true)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks.count == 1)
    }

    @Test("Redo restores undone action")
    @MainActor
    func redoAddTrack() {
        let vm = ProjectViewModel()
        vm.newProject()

        vm.addTrack(kind: .audio)
        #expect(vm.project.songs[0].tracks.count == 2)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks.count == 1)
        #expect(vm.undoManager?.canRedo == true)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks.count == 2)
    }

    @Test("Undo remove track restores track")
    @MainActor
    func undoRemoveTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.removeTrack(id: trackID)
        #expect(vm.project.songs[0].tracks.count == 1) // just master

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks.count == 2)
    }

    @Test("Undo rename track restores old name")
    @MainActor
    func undoRenameTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.renameTrack(id: trackID, newName: "Lead")
        #expect(vm.project.songs[0].tracks[0].name == "Lead")

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].name == "Audio 1")
    }

    @Test("Undo toggle mute restores state")
    @MainActor
    func undoToggleMute() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.toggleMute(trackID: trackID)
        #expect(vm.project.songs[0].tracks[0].isMuted)

        vm.undoManager?.undo()
        #expect(!vm.project.songs[0].tracks[0].isMuted)
    }

    @Test("Undo toggle solo restores state")
    @MainActor
    func undoToggleSolo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.toggleSolo(trackID: trackID)
        #expect(vm.project.songs[0].tracks[0].isSoloed)

        vm.undoManager?.undo()
        #expect(!vm.project.songs[0].tracks[0].isSoloed)
    }

    @Test("Undo set track record armed restores state")
    @MainActor
    func undoSetTrackRecordArmed() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.setTrackRecordArmed(trackID: trackID, armed: true)
        #expect(vm.project.songs[0].tracks[0].isRecordArmed)

        vm.undoManager?.undo()
        #expect(!vm.project.songs[0].tracks[0].isRecordArmed)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].isRecordArmed)
    }

    @Test("Undo/redo set track monitoring")
    @MainActor
    func undoSetTrackMonitoring() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.setTrackMonitoring(trackID: trackID, monitoring: true)
        #expect(vm.project.songs[0].tracks[0].isMonitoring)

        vm.undoManager?.undo()
        #expect(!vm.project.songs[0].tracks[0].isMonitoring)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].isMonitoring)
    }

    @Test("Undo add container restores empty track")
    @MainActor
    func undoAddContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].containers.isEmpty)
    }

    @Test("Undo remove container restores it")
    @MainActor
    func undoRemoveContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        vm.removeContainer(trackID: trackID, containerID: containerID)
        #expect(vm.project.songs[0].tracks[0].containers.isEmpty)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)
    }

    @Test("Undo move container restores position")
    @MainActor
    func undoMoveContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let _ = vm.moveContainer(trackID: trackID, containerID: containerID, newStartBar: 5)
        #expect(vm.project.songs[0].tracks[0].containers[0].startBar == 5)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].containers[0].startBar == 1)
    }

    @Test("Undo resize container restores dimensions")
    @MainActor
    func undoResizeContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let _ = vm.resizeContainer(trackID: trackID, containerID: containerID, newLengthBars: 8)
        #expect(vm.project.songs[0].tracks[0].containers[0].lengthBars == 8)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].containers[0].lengthBars == 4)
    }

    @Test("Undo add song restores song count")
    @MainActor
    func undoAddSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        #expect(vm.project.songs.count == 1)

        vm.addSong()
        #expect(vm.project.songs.count == 2)

        vm.undoManager?.undo()
        #expect(vm.project.songs.count == 1)
    }

    @Test("Undo remove song restores it")
    @MainActor
    func undoRemoveSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSong()
        #expect(vm.project.songs.count == 2)
        let secondID = vm.project.songs[1].id

        vm.removeSong(id: secondID)
        #expect(vm.project.songs.count == 1)

        vm.undoManager?.undo()
        #expect(vm.project.songs.count == 2)
    }

    @Test("Undo rename song restores name")
    @MainActor
    func undoRenameSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id

        vm.renameSong(id: songID, newName: "Renamed")
        #expect(vm.project.songs[0].name == "Renamed")

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].name == "Song 1")
    }

    @Test("Undo duplicate song removes copy")
    @MainActor
    func undoDuplicateSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id

        vm.duplicateSong(id: songID)
        #expect(vm.project.songs.count == 2)

        vm.undoManager?.undo()
        #expect(vm.project.songs.count == 1)
    }

    @Test("Undo volume change restores value")
    @MainActor
    func undoVolumeChange() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.setTrackVolume(trackID: trackID, volume: 0.5)
        #expect(vm.project.songs[0].tracks[0].volume == 0.5)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].volume == 1.0) // default
    }

    @Test("Undo pan change restores value")
    @MainActor
    func undoPanChange() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.setTrackPan(trackID: trackID, pan: -0.5)
        #expect(vm.project.songs[0].tracks[0].pan == -0.5)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].pan == 0.0) // default
    }

    @Test("New project clears undo stack")
    @MainActor
    func newProjectClearsUndo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        #expect(vm.undoManager?.canUndo == true)

        vm.newProject()
        #expect(vm.undoManager?.canUndo == false)
    }

    @Test("Undo action name is set correctly")
    @MainActor
    func undoActionName() {
        let vm = ProjectViewModel()
        vm.newProject()

        vm.addTrack(kind: .audio)
        #expect(vm.undoManager?.undoActionName == "Add Track")

        let trackID = vm.project.songs[0].tracks[0].id
        vm.toggleMute(trackID: trackID)
        #expect(vm.undoManager?.undoActionName == "Toggle Mute")
    }

    @Test("Multiple undo/redo operations")
    @MainActor
    func multipleUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()

        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        vm.addTrack(kind: .bus)
        #expect(vm.project.songs[0].tracks.count == 4) // 3 + master

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks.count == 3)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks.count == 2)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks.count == 3)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks.count == 4)
    }

    // MARK: - Container Detail Editor Tests (Reorder Effects)

    @Test("Reorder container effects moves effect down")
    @MainActor
    func reorderContainerEffectsDown() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        let effectA = InsertEffect(component: comp, displayName: "Reverb", orderIndex: 0)
        let effectB = InsertEffect(component: comp, displayName: "Delay", orderIndex: 1)
        let effectC = InsertEffect(component: comp, displayName: "Chorus", orderIndex: 2)

        vm.addContainerEffect(containerID: containerID, effect: effectA)
        vm.addContainerEffect(containerID: containerID, effect: effectB)
        vm.addContainerEffect(containerID: containerID, effect: effectC)

        let effects = vm.project.songs[0].tracks[0].containers[0].insertEffects
        #expect(effects.count == 3)

        // Move first effect to position 2 (after second)
        vm.reorderContainerEffects(containerID: containerID, from: IndexSet(integer: 0), to: 2)

        let reordered = vm.project.songs[0].tracks[0].containers[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(reordered[0].displayName == "Delay")
        #expect(reordered[1].displayName == "Reverb")
        #expect(reordered[2].displayName == "Chorus")
        #expect(reordered[0].orderIndex == 0)
        #expect(reordered[1].orderIndex == 1)
        #expect(reordered[2].orderIndex == 2)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Reorder container effects moves effect up")
    @MainActor
    func reorderContainerEffectsUp() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "Reverb", orderIndex: 0))
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "Delay", orderIndex: 1))
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "Chorus", orderIndex: 2))

        // Move last effect to position 0 (beginning)
        vm.reorderContainerEffects(containerID: containerID, from: IndexSet(integer: 2), to: 0)

        let reordered = vm.project.songs[0].tracks[0].containers[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(reordered[0].displayName == "Chorus")
        #expect(reordered[1].displayName == "Reverb")
        #expect(reordered[2].displayName == "Delay")
    }

    @Test("Reorder container effects with undo restores original order")
    @MainActor
    func reorderContainerEffectsUndo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "Reverb", orderIndex: 0))
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "Delay", orderIndex: 1))

        vm.reorderContainerEffects(containerID: containerID, from: IndexSet(integer: 0), to: 2)

        let afterReorder = vm.project.songs[0].tracks[0].containers[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(afterReorder[0].displayName == "Delay")
        #expect(afterReorder[1].displayName == "Reverb")

        vm.undoManager?.undo()

        let afterUndo = vm.project.songs[0].tracks[0].containers[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(afterUndo[0].displayName == "Reverb")
        #expect(afterUndo[1].displayName == "Delay")
    }

    @Test("Reorder with invalid container ID is no-op")
    @MainActor
    func reorderContainerEffectsInvalidID() {
        let vm = ProjectViewModel()
        vm.newProject()

        let bogusID = ID<Container>()
        vm.reorderContainerEffects(containerID: bogusID, from: IndexSet(integer: 0), to: 1)
        // Should not crash or modify state — no unsaved changes from reorder
        #expect(!vm.hasUnsavedChanges)
    }

    @Test("Selected container returns correct container")
    @MainActor
    func selectedContainerProperty() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        vm.selectedContainerID = containerID
        #expect(vm.selectedContainer != nil)
        #expect(vm.selectedContainer?.id == containerID)
        #expect(vm.selectedContainerTrackKind == .audio)
    }

    @Test("All containers in current song returns all containers across tracks")
    @MainActor
    func allContainersInCurrentSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        let track1ID = vm.project.songs[0].tracks[0].id
        let track2ID = vm.project.songs[0].tracks[1].id
        let _ = vm.addContainer(trackID: track1ID, startBar: 1, lengthBars: 2)
        let _ = vm.addContainer(trackID: track1ID, startBar: 3, lengthBars: 2)
        let _ = vm.addContainer(trackID: track2ID, startBar: 1, lengthBars: 4)

        let allContainers = vm.allContainersInCurrentSong
        #expect(allContainers.count == 3)
    }

    @Test("All tracks in current song returns all tracks")
    @MainActor
    func allTracksInCurrentSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        vm.addTrack(kind: .bus)

        let allTracks = vm.allTracksInCurrentSong
        #expect(allTracks.count == 4) // 3 added + master
    }

    // MARK: - Count-In

    @Test("setCountInBars updates song")
    @MainActor
    func setCountInBars() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id
        #expect(vm.project.songs[0].countInBars == 0)
        vm.setCountInBars(songID: songID, bars: 4)
        #expect(vm.project.songs[0].countInBars == 4)
        vm.setCountInBars(songID: songID, bars: 2)
        #expect(vm.project.songs[0].countInBars == 2)
    }

    @Test("setCountInBars undo/redo")
    @MainActor
    func setCountInBarsUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id
        vm.setCountInBars(songID: songID, bars: 4)
        #expect(vm.project.songs[0].countInBars == 4)
        vm.undoManager?.undo()
        #expect(vm.project.songs[0].countInBars == 0)
        vm.undoManager?.redo()
        #expect(vm.project.songs[0].countInBars == 4)
    }

    @Test("duplicateSong copies countInBars")
    @MainActor
    func duplicateSongCopiesCountInBars() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id
        vm.setCountInBars(songID: songID, bars: 2)
        vm.duplicateSong(id: songID)
        #expect(vm.project.songs.count == 2)
        #expect(vm.project.songs[1].countInBars == 2)
    }

    // MARK: - Section Management

    @Test("Add section to current song")
    @MainActor
    func addSection() {
        let vm = ProjectViewModel()
        vm.newProject()
        let result = vm.addSection(name: "Intro", startBar: 1, lengthBars: 4)
        #expect(result)
        #expect(vm.project.songs[0].sections.count == 1)
        #expect(vm.project.songs[0].sections[0].name == "Intro")
        #expect(vm.project.songs[0].sections[0].startBar == 1)
        #expect(vm.project.songs[0].sections[0].lengthBars == 4)
        #expect(vm.selectedSectionID != nil)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Add section with default name auto-increments")
    @MainActor
    func addSectionDefaultName() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSection(startBar: 1, lengthBars: 4)
        vm.addSection(startBar: 5, lengthBars: 4)
        #expect(vm.project.songs[0].sections[0].name == "Section 1")
        #expect(vm.project.songs[0].sections[1].name == "Section 2")
    }

    @Test("Section overlap prevention")
    @MainActor
    func sectionOverlap() {
        let vm = ProjectViewModel()
        vm.newProject()

        // Add first section: bars 1-4
        let first = vm.addSection(startBar: 1, lengthBars: 4)
        #expect(first)

        // Try overlapping section: bars 3-6 — should fail
        let overlap = vm.addSection(startBar: 3, lengthBars: 4)
        #expect(!overlap)
        #expect(vm.project.songs[0].sections.count == 1)

        // Non-overlapping section: bars 5-8 — should succeed
        let noOverlap = vm.addSection(startBar: 5, lengthBars: 4)
        #expect(noOverlap)
        #expect(vm.project.songs[0].sections.count == 2)
    }

    @Test("Remove section")
    @MainActor
    func removeSection() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSection(startBar: 1, lengthBars: 4)
        let sectionID = vm.project.songs[0].sections[0].id
        vm.selectedSectionID = sectionID
        vm.removeSection(sectionID: sectionID)
        #expect(vm.project.songs[0].sections.isEmpty)
        #expect(vm.selectedSectionID == nil)
    }

    @Test("Move section")
    @MainActor
    func moveSection() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSection(startBar: 1, lengthBars: 4)
        let sectionID = vm.project.songs[0].sections[0].id
        let result = vm.moveSection(sectionID: sectionID, newStartBar: 5)
        #expect(result)
        #expect(vm.project.songs[0].sections[0].startBar == 5)
    }

    @Test("Move section prevents overlap")
    @MainActor
    func moveSectionOverlap() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSection(startBar: 1, lengthBars: 4)
        vm.addSection(startBar: 5, lengthBars: 4)
        let firstID = vm.project.songs[0].sections[0].id

        // Try to move first section to bar 4 — would overlap with second
        let result = vm.moveSection(sectionID: firstID, newStartBar: 4)
        #expect(!result)
        #expect(vm.project.songs[0].sections[0].startBar == 1)
    }

    @Test("Resize section")
    @MainActor
    func resizeSection() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSection(startBar: 1, lengthBars: 4)
        let sectionID = vm.project.songs[0].sections[0].id
        let result = vm.resizeSection(sectionID: sectionID, newLengthBars: 8)
        #expect(result)
        #expect(vm.project.songs[0].sections[0].lengthBars == 8)
    }

    @Test("Resize section prevents overlap")
    @MainActor
    func resizeSectionOverlap() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSection(startBar: 1, lengthBars: 4)
        vm.addSection(startBar: 5, lengthBars: 4)
        let firstID = vm.project.songs[0].sections[0].id

        let result = vm.resizeSection(sectionID: firstID, newLengthBars: 6)
        #expect(!result)
        #expect(vm.project.songs[0].sections[0].lengthBars == 4)
    }

    @Test("Rename section")
    @MainActor
    func renameSection() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSection(name: "Intro", startBar: 1, lengthBars: 4)
        let sectionID = vm.project.songs[0].sections[0].id
        vm.renameSection(sectionID: sectionID, name: "Outro")
        #expect(vm.project.songs[0].sections[0].name == "Outro")
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Recolor section")
    @MainActor
    func recolorSection() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSection(startBar: 1, lengthBars: 4, color: "#5B9BD5")
        let sectionID = vm.project.songs[0].sections[0].id
        vm.recolorSection(sectionID: sectionID, color: "#FF0000")
        #expect(vm.project.songs[0].sections[0].color == "#FF0000")
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Undo/redo add section")
    @MainActor
    func undoRedoAddSection() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSection(startBar: 1, lengthBars: 4)
        #expect(vm.project.songs[0].sections.count == 1)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].sections.isEmpty)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].sections.count == 1)
    }

    @Test("Undo/redo remove section")
    @MainActor
    func undoRedoRemoveSection() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSection(startBar: 1, lengthBars: 4)
        let sectionID = vm.project.songs[0].sections[0].id
        vm.removeSection(sectionID: sectionID)
        #expect(vm.project.songs[0].sections.isEmpty)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].sections.count == 1)
    }

    @Test("duplicateSong copies sections")
    @MainActor
    func duplicateSongCopiesSections() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSection(name: "Intro", startBar: 1, lengthBars: 4, color: "#FF5733")
        vm.addSection(name: "Verse", startBar: 5, lengthBars: 8, color: "#5B9BD5")
        let songID = vm.project.songs[0].id
        vm.duplicateSong(id: songID)
        #expect(vm.project.songs.count == 2)
        #expect(vm.project.songs[1].sections.count == 2)
        #expect(vm.project.songs[1].sections[0].name == "Intro")
        #expect(vm.project.songs[1].sections[1].name == "Verse")
        // IDs should be different
        #expect(vm.project.songs[1].sections[0].id != vm.project.songs[0].sections[0].id)
    }

    // MARK: - Container Clone Management

    @Test("Clone container creates linked clone at position")
    @MainActor
    func cloneContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let originalID = vm.project.songs[0].tracks[0].containers[0].id

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: originalID, newStartBar: 5)
        #expect(cloneID != nil)
        #expect(vm.project.songs[0].tracks[0].containers.count == 2)

        let clone = vm.project.songs[0].tracks[0].containers[1]
        #expect(clone.parentContainerID == originalID)
        #expect(clone.overriddenFields.isEmpty)
        #expect(clone.startBar == 5)
        #expect(clone.lengthBars == 4)
        #expect(clone.isClone)
        #expect(vm.selectedContainerID == cloneID)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Clone container prevents overlap")
    @MainActor
    func cloneContainerOverlap() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let originalID = vm.project.songs[0].tracks[0].containers[0].id

        // Try to clone at overlapping position
        let cloneID = vm.cloneContainer(trackID: trackID, containerID: originalID, newStartBar: 3)
        #expect(cloneID == nil)
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)
    }

    @Test("Clone of clone links to original parent (no nesting)")
    @MainActor
    func cloneOfCloneNoNesting() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let originalID = vm.project.songs[0].tracks[0].containers[0].id

        // Create first clone
        let clone1ID = vm.cloneContainer(trackID: trackID, containerID: originalID, newStartBar: 5)
        #expect(clone1ID != nil)
        let clone1 = vm.project.songs[0].tracks[0].containers[1]
        #expect(clone1.parentContainerID == originalID)

        // Clone the clone — should link to original, not to clone1
        let clone2ID = vm.cloneContainer(trackID: trackID, containerID: clone1ID!, newStartBar: 9)
        #expect(clone2ID != nil)
        let clone2 = vm.project.songs[0].tracks[0].containers[2]
        #expect(clone2.parentContainerID == originalID)
    }

    @Test("Consolidate container disconnects from parent")
    @MainActor
    func consolidateContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let originalID = vm.project.songs[0].tracks[0].containers[0].id

        // Update the original's name so we can verify consolidation resolves it
        vm.updateContainerName(containerID: originalID, name: "OriginalName")

        // Create clone
        let cloneID = vm.cloneContainer(trackID: trackID, containerID: originalID, newStartBar: 5)!

        // Verify clone inherits parent name (not overridden)
        let cloneBefore = vm.project.songs[0].tracks[0].containers[1]
        #expect(cloneBefore.parentContainerID == originalID)
        #expect(!cloneBefore.overriddenFields.contains(.name))

        // Consolidate
        vm.consolidateContainer(trackID: trackID, containerID: cloneID)

        let consolidated = vm.project.songs[0].tracks[0].containers[1]
        #expect(consolidated.parentContainerID == nil)
        #expect(consolidated.overriddenFields == Set(ContainerField.allCases))
        // Name should be resolved from parent
        #expect(consolidated.name == "OriginalName")
        #expect(!consolidated.isClone)
    }

    @Test("Clone undo/redo")
    @MainActor
    func cloneUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let originalID = vm.project.songs[0].tracks[0].containers[0].id

        let _ = vm.cloneContainer(trackID: trackID, containerID: originalID, newStartBar: 5)
        #expect(vm.project.songs[0].tracks[0].containers.count == 2)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].containers.count == 2)
        #expect(vm.project.songs[0].tracks[0].containers[1].parentContainerID == originalID)
    }

    @Test("Consolidate undo/redo")
    @MainActor
    func consolidateUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let originalID = vm.project.songs[0].tracks[0].containers[0].id

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: originalID, newStartBar: 5)!

        vm.consolidateContainer(trackID: trackID, containerID: cloneID)
        #expect(vm.project.songs[0].tracks[0].containers[1].parentContainerID == nil)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].containers[1].parentContainerID == originalID)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].containers[1].parentContainerID == nil)
    }

    @Test("Editing clone field auto-marks override")
    @MainActor
    func editingCloneFieldMarksOverride() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let originalID = vm.project.songs[0].tracks[0].containers[0].id

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: originalID, newStartBar: 5)!

        // Clone should start with no overrides
        #expect(vm.project.songs[0].tracks[0].containers[1].overriddenFields.isEmpty)

        // Rename the clone — should mark .name as overridden
        vm.updateContainerName(containerID: cloneID, name: "Custom Name")
        #expect(vm.project.songs[0].tracks[0].containers[1].overriddenFields.contains(.name))

        // Change loop settings — should mark .loopSettings
        vm.updateContainerLoopSettings(containerID: cloneID, settings: LoopSettings(loopCount: .fill))
        #expect(vm.project.songs[0].tracks[0].containers[1].overriddenFields.contains(.loopSettings))
    }

    @Test("duplicateSong copies clone fields")
    @MainActor
    func duplicateSongCopiesCloneFields() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let originalID = vm.project.songs[0].tracks[0].containers[0].id
        let _ = vm.cloneContainer(trackID: trackID, containerID: originalID, newStartBar: 5)

        let songID = vm.project.songs[0].id
        vm.duplicateSong(id: songID)

        #expect(vm.project.songs.count == 2)
        let copiedClone = vm.project.songs[1].tracks[0].containers[1]
        // parentContainerID is copied (points to original in the original song)
        #expect(copiedClone.parentContainerID == originalID)
        #expect(copiedClone.overriddenFields.isEmpty)
    }

    // MARK: - Context Menu: Duplicate Container

    @Test("Duplicate container creates independent copy at next position")
    @MainActor
    func duplicateContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let dupID = vm.duplicateContainer(trackID: trackID, containerID: containerID)
        #expect(dupID != nil)
        #expect(vm.project.songs[0].tracks[0].containers.count == 2)

        let dup = vm.project.songs[0].tracks[0].containers[1]
        #expect(dup.startBar == 5) // placed right after original (endBar)
        #expect(dup.lengthBars == 4)
        #expect(dup.id != containerID) // independent copy
        #expect(dup.parentContainerID == nil) // not a clone
        #expect(vm.selectedContainerID == dupID)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Duplicate container blocked by overlap returns nil")
    @MainActor
    func duplicateContainerOverlap() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let _ = vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4) // block position 5
        let firstID = vm.project.songs[0].tracks[0].containers[0].id

        let dupID = vm.duplicateContainer(trackID: trackID, containerID: firstID)
        #expect(dupID == nil)
        #expect(vm.project.songs[0].tracks[0].containers.count == 2)
    }

    // MARK: - Context Menu: Duplicate Track

    @Test("Duplicate track produces correct deep copy")
    @MainActor
    func duplicateTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let _ = vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4)
        vm.renameTrack(id: trackID, newName: "Lead Guitar")

        let copyID = vm.duplicateTrack(trackID: trackID)
        #expect(copyID != nil)
        #expect(vm.project.songs[0].tracks.count == 3) // original + copy + master

        let copy = vm.project.songs[0].tracks[1]
        #expect(copy.name == "Lead Guitar Copy")
        #expect(copy.kind == .audio)
        #expect(copy.containers.count == 2)
        #expect(copy.containers[0].startBar == 1)
        #expect(copy.containers[0].lengthBars == 4)
        #expect(copy.containers[1].startBar == 5)
        #expect(copy.containers[1].lengthBars == 4)
        // IDs must be different
        #expect(copy.id != trackID)
        #expect(copy.containers[0].id != vm.project.songs[0].tracks[0].containers[0].id)
        #expect(copy.containers[1].id != vm.project.songs[0].tracks[0].containers[1].id)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Duplicate track copies track properties")
    @MainActor
    func duplicateTrackCopiesProperties() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.setTrackVolume(trackID: trackID, volume: 0.7)
        vm.setTrackPan(trackID: trackID, pan: -0.5)
        vm.toggleMute(trackID: trackID)
        vm.setTrackMIDIInput(trackID: trackID, deviceID: "dev-1", channel: 3)

        let copyID = vm.duplicateTrack(trackID: trackID)!
        let copy = vm.project.songs[0].tracks.first(where: { $0.id == copyID })!
        #expect(copy.volume == 0.7)
        #expect(copy.pan == -0.5)
        #expect(copy.isMuted)
        #expect(copy.midiInputDeviceID == "dev-1")
        #expect(copy.midiInputChannel == 3)
    }

    @Test("Duplicate track undo removes copy")
    @MainActor
    func duplicateTrackUndo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.duplicateTrack(trackID: trackID)
        #expect(vm.project.songs[0].tracks.count == 3) // original + copy + master

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks.count == 2)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks.count == 3)
    }

    // MARK: - Context Menu: Copy/Paste

    @Test("Copy container stores entry in clipboard")
    @MainActor
    func copyContainer() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 3, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        vm.copyContainer(trackID: trackID, containerID: containerID)
        #expect(vm.clipboard.count == 1)
        #expect(vm.clipboard[0].container.id == containerID)
        #expect(vm.clipboard[0].trackID == trackID)
        #expect(vm.clipboardBaseBar == 3)
    }

    @Test("Paste at position creates containers at correct bar offset")
    @MainActor
    func pasteAtPosition() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 3, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        // Copy container at bar 3
        vm.copyContainer(trackID: trackID, containerID: containerID)

        // Paste at bar 10 → offset is +7, so container should start at bar 10
        let pasted = vm.pasteContainers(trackID: trackID, atBar: 10)
        #expect(pasted == 1)
        #expect(vm.project.songs[0].tracks[0].containers.count == 2)
        let pastedContainer = vm.project.songs[0].tracks[0].containers[1]
        #expect(pastedContainer.startBar == 10)
        #expect(pastedContainer.lengthBars == 4)
        #expect(pastedContainer.id != containerID) // new ID
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Paste skips overlapping containers")
    @MainActor
    func pasteSkipsOverlap() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        vm.copyContainer(trackID: trackID, containerID: containerID)

        // Paste at bar 3 → would overlap existing (1-4), should be skipped
        let pasted = vm.pasteContainers(trackID: trackID, atBar: 3)
        #expect(pasted == 0)
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)
    }

    @Test("Copy section copies containers in range")
    @MainActor
    func copySectionContainers() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let _ = vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4)
        let _ = vm.addContainer(trackID: trackID, startBar: 10, lengthBars: 2) // outside range

        // Copy range bars 1-8 (should get first two containers)
        vm.copyContainersInRange(startBar: 1, endBar: 9)
        #expect(vm.clipboard.count == 2)
        #expect(vm.clipboardBaseBar == 1)
    }

    // MARK: - Context Menu: Split Section

    @Test("Split section at playhead creates two sections")
    @MainActor
    func splitSection() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSection(name: "Intro", startBar: 1, lengthBars: 8, color: "#FF5733")
        let sectionID = vm.project.songs[0].sections[0].id

        let result = vm.splitSection(sectionID: sectionID, atBar: 5)
        #expect(result)
        #expect(vm.project.songs[0].sections.count == 2)

        let first = vm.project.songs[0].sections[0]
        let second = vm.project.songs[0].sections[1]
        #expect(first.startBar == 1)
        #expect(first.lengthBars == 4)
        #expect(first.name == "Intro")
        #expect(second.startBar == 5)
        #expect(second.lengthBars == 4)
        #expect(second.name == "Intro (2)")
        #expect(second.color == "#FF5733")
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Split section at boundary fails")
    @MainActor
    func splitSectionAtBoundary() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSection(startBar: 1, lengthBars: 4)
        let sectionID = vm.project.songs[0].sections[0].id

        // At start bar — not strictly inside
        #expect(!vm.splitSection(sectionID: sectionID, atBar: 1))
        // At end bar — not strictly inside
        #expect(!vm.splitSection(sectionID: sectionID, atBar: 5))
        // Outside
        #expect(!vm.splitSection(sectionID: sectionID, atBar: 10))
        #expect(vm.project.songs[0].sections.count == 1)
    }

    @Test("Split section undo restores original")
    @MainActor
    func splitSectionUndo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSection(name: "Intro", startBar: 1, lengthBars: 8)
        let sectionID = vm.project.songs[0].sections[0].id

        vm.splitSection(sectionID: sectionID, atBar: 5)
        #expect(vm.project.songs[0].sections.count == 2)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].sections.count == 1)
        #expect(vm.project.songs[0].sections[0].lengthBars == 8)
    }

    // MARK: - Context Menu: Unlink only shown on clones

    @Test("Container isClone reflects parentContainerID state")
    @MainActor
    func containerIsCloneState() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let originalID = vm.project.songs[0].tracks[0].containers[0].id

        // Original is not a clone
        #expect(!vm.project.songs[0].tracks[0].containers[0].isClone)

        // Create clone
        let cloneID = vm.cloneContainer(trackID: trackID, containerID: originalID, newStartBar: 5)!
        let clone = vm.project.songs[0].tracks[0].containers.first(where: { $0.id == cloneID })!
        #expect(clone.isClone)

        // Consolidate removes clone status
        vm.consolidateContainer(trackID: trackID, containerID: cloneID)
        let consolidated = vm.project.songs[0].tracks[0].containers.first(where: { $0.id == cloneID })!
        #expect(!consolidated.isClone)
    }

    // MARK: - Time Range Selection & Copy/Paste (#69)

    @Test("Range copy produces correct containers within range only")
    @MainActor
    func rangeCopyWithinRange() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let _ = vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4)
        let _ = vm.addContainer(trackID: trackID, startBar: 10, lengthBars: 2) // outside range

        // Copy range bars 1-8 (endBar exclusive = 9)
        vm.copyContainersInRange(startBar: 1, endBar: 9)
        #expect(vm.clipboard.count == 2)
        #expect(vm.clipboardBaseBar == 1)
        #expect(vm.clipboardSectionRegion == nil)
    }

    @Test("Paste at bar offset adjusts container positions correctly")
    @MainActor
    func pasteMultiTrackAtOffset() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        let track1ID = vm.project.songs[0].tracks[0].id
        let track2ID = vm.project.songs[0].tracks[1].id
        let _ = vm.addContainer(trackID: track1ID, startBar: 1, lengthBars: 4)
        let _ = vm.addContainer(trackID: track2ID, startBar: 2, lengthBars: 3)

        // Copy range bars 1-5
        vm.copyContainersInRange(startBar: 1, endBar: 6)
        #expect(vm.clipboard.count == 2)

        // Paste at bar 10 → offset is +9
        let pasted = vm.pasteContainersToOriginalTracks(atBar: 10)
        #expect(pasted == 2)
        // Track 1 should have original (1-4) + pasted (10-13)
        #expect(vm.project.songs[0].tracks[0].containers.count == 2)
        let pastedContainer1 = vm.project.songs[0].tracks[0].containers[1]
        #expect(pastedContainer1.startBar == 10)
        #expect(pastedContainer1.lengthBars == 4)
        // Track 2 should have original (2-4) + pasted (11-13)
        #expect(vm.project.songs[0].tracks[1].containers.count == 2)
        let pastedContainer2 = vm.project.songs[0].tracks[1].containers[1]
        #expect(pastedContainer2.startBar == 11)
        #expect(pastedContainer2.lengthBars == 3)
    }

    @Test("Section copy includes section metadata")
    @MainActor
    func sectionCopyIncludesMetadata() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        vm.addSection(name: "Intro", startBar: 1, lengthBars: 4, color: "#FF5733")
        let sectionID = vm.project.songs[0].sections[0].id

        vm.copySectionWithMetadata(sectionID: sectionID)
        #expect(vm.clipboard.count == 1)
        #expect(vm.clipboardSectionRegion != nil)
        #expect(vm.clipboardSectionRegion?.name == "Intro")
        #expect(vm.clipboardSectionRegion?.color == "#FF5733")

        // Paste at bar 10 — should create containers AND section region
        let pasted = vm.pasteContainersToOriginalTracks(atBar: 10)
        #expect(pasted == 1)
        #expect(vm.project.songs[0].sections.count == 2)
        let pastedSection = vm.project.songs[0].sections[1]
        #expect(pastedSection.name == "Intro")
        #expect(pastedSection.startBar == 10)
        #expect(pastedSection.lengthBars == 4)
        #expect(pastedSection.color == "#FF5733")
    }

    @Test("Track filter excludes non-selected tracks from copy")
    @MainActor
    func trackFilterExcludesNonSelected() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        let track1ID = vm.project.songs[0].tracks[0].id
        let track2ID = vm.project.songs[0].tracks[1].id
        let _ = vm.addContainer(trackID: track1ID, startBar: 1, lengthBars: 4)
        let _ = vm.addContainer(trackID: track2ID, startBar: 1, lengthBars: 4)

        // Copy with filter — only track 1
        vm.copyContainersInRange(startBar: 1, endBar: 5, trackFilter: [track1ID])
        #expect(vm.clipboard.count == 1)
        #expect(vm.clipboard[0].trackID == track1ID)
    }

    @Test("Empty range copy produces empty clipboard")
    @MainActor
    func emptyRangeCopy() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4)

        // Copy range that has no containers
        vm.copyContainersInRange(startBar: 20, endBar: 25)
        #expect(vm.clipboard.isEmpty)
    }

    @Test("Paste with empty clipboard is no-op")
    @MainActor
    func pasteEmptyClipboard() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        // Reset unsaved changes flag
        vm.hasUnsavedChanges = false

        #expect(vm.clipboard.isEmpty)
        let pasted = vm.pasteContainersToOriginalTracks(atBar: 1)
        #expect(pasted == 0)
        // Containers count unchanged
        #expect(vm.project.songs[0].tracks[0].containers.isEmpty)
        _ = trackID
    }

    @Test("Regular copy clears section metadata from clipboard")
    @MainActor
    func regularCopyClearsSectionMetadata() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        // First do a section copy
        vm.addSection(name: "Intro", startBar: 1, lengthBars: 4)
        let sectionID = vm.project.songs[0].sections[0].id
        vm.copySectionWithMetadata(sectionID: sectionID)
        #expect(vm.clipboardSectionRegion != nil)

        // Regular copy should clear section metadata
        vm.copyContainer(trackID: trackID, containerID: containerID)
        #expect(vm.clipboardSectionRegion == nil)
    }

    @Test("Range copy clears section metadata from clipboard")
    @MainActor
    func rangeCopyClearsSectionMetadata() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)

        // First do a section copy
        vm.addSection(name: "Intro", startBar: 1, lengthBars: 4)
        let sectionID = vm.project.songs[0].sections[0].id
        vm.copySectionWithMetadata(sectionID: sectionID)
        #expect(vm.clipboardSectionRegion != nil)

        // Range copy should clear section metadata
        vm.copyContainersInRange(startBar: 1, endBar: 5)
        #expect(vm.clipboardSectionRegion == nil)
    }

    @Test("Multi-track paste skips overlapping containers")
    @MainActor
    func multiTrackPasteSkipsOverlap() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)

        // Copy the container
        vm.copyContainersInRange(startBar: 1, endBar: 5)
        #expect(vm.clipboard.count == 1)

        // Paste at bar 3 — overlaps with existing (1-4)
        let pasted = vm.pasteContainersToOriginalTracks(atBar: 3)
        #expect(pasted == 0)
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)
    }

    @Test("Paste with empty track filter includes all tracks")
    @MainActor
    func emptyTrackFilterIncludesAll() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        vm.addTrack(kind: .bus)
        let track1ID = vm.project.songs[0].tracks[0].id
        let track2ID = vm.project.songs[0].tracks[1].id
        let track3ID = vm.project.songs[0].tracks[2].id
        let _ = vm.addContainer(trackID: track1ID, startBar: 1, lengthBars: 2)
        let _ = vm.addContainer(trackID: track2ID, startBar: 1, lengthBars: 2)
        let _ = vm.addContainer(trackID: track3ID, startBar: 1, lengthBars: 2)

        // Empty filter means all tracks
        vm.copyContainersInRange(startBar: 1, endBar: 3, trackFilter: [])
        #expect(vm.clipboard.count == 3)
    }

    @Test("Paste creates independent containers not clones")
    @MainActor
    func pasteCreatesIndependentContainers() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let originalID = vm.project.songs[0].tracks[0].containers[0].id

        vm.copyContainersInRange(startBar: 1, endBar: 5)
        let pasted = vm.pasteContainersToOriginalTracks(atBar: 10)
        #expect(pasted == 1)

        let pastedContainer = vm.project.songs[0].tracks[0].containers[1]
        #expect(pastedContainer.id != originalID)
        #expect(pastedContainer.parentContainerID == nil) // not a clone
        #expect(!pastedContainer.isClone)
    }

    @Test("Paste multi-track undo restores state")
    @MainActor
    func pasteMultiTrackUndo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        let track1ID = vm.project.songs[0].tracks[0].id
        let track2ID = vm.project.songs[0].tracks[1].id
        let _ = vm.addContainer(trackID: track1ID, startBar: 1, lengthBars: 4)
        let _ = vm.addContainer(trackID: track2ID, startBar: 1, lengthBars: 4)

        vm.copyContainersInRange(startBar: 1, endBar: 5)
        vm.pasteContainersToOriginalTracks(atBar: 10)
        #expect(vm.project.songs[0].tracks[0].containers.count == 2)
        #expect(vm.project.songs[0].tracks[1].containers.count == 2)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)
        #expect(vm.project.songs[0].tracks[1].containers.count == 1)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].containers.count == 2)
        #expect(vm.project.songs[0].tracks[1].containers.count == 2)
    }

    // MARK: - Keyboard Shortcuts (#72)

    @Test("Select all containers returns correct IDs")
    @MainActor
    func selectAllContainers() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        let track1ID = vm.project.songs[0].tracks[0].id
        let track2ID = vm.project.songs[0].tracks[1].id
        let _ = vm.addContainer(trackID: track1ID, startBar: 1, lengthBars: 2)
        let _ = vm.addContainer(trackID: track1ID, startBar: 3, lengthBars: 2)
        let _ = vm.addContainer(trackID: track2ID, startBar: 1, lengthBars: 4)

        vm.selectAllContainers()
        #expect(vm.selectedContainerIDs.count == 3)
        // All three container IDs should be in the set
        let allIDs = Set(vm.project.songs[0].tracks.flatMap(\.containers).map(\.id))
        #expect(vm.selectedContainerIDs == allIDs)
        // Single selection should be nil when multi-selecting
        #expect(vm.selectedContainerID == nil)
    }

    @Test("Select all containers on empty song returns empty set")
    @MainActor
    func selectAllContainersEmpty() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.selectAllContainers()
        #expect(vm.selectedContainerIDs.isEmpty)
    }

    @Test("Deselect all clears all selection state")
    @MainActor
    func deselectAll() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id
        vm.addSection(startBar: 1, lengthBars: 4)
        let sectionID = vm.project.songs[0].sections[0].id

        vm.selectedContainerID = containerID
        vm.selectedTrackID = trackID
        vm.selectedSectionID = sectionID
        vm.selectedContainerIDs = [containerID]

        vm.deselectAll()
        #expect(vm.selectedContainerID == nil)
        #expect(vm.selectedTrackID == nil)
        #expect(vm.selectedSectionID == nil)
        #expect(vm.selectedContainerIDs.isEmpty)
    }

    @Test("Select track by index sets selectedTrackID")
    @MainActor
    func selectTrackByIndex() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        vm.addTrack(kind: .bus)

        vm.selectTrackByIndex(0)
        #expect(vm.selectedTrackID == vm.project.songs[0].tracks[0].id)

        vm.selectTrackByIndex(2)
        #expect(vm.selectedTrackID == vm.project.songs[0].tracks[2].id)
    }

    @Test("Select track by out-of-range index is no-op")
    @MainActor
    func selectTrackByIndexOutOfRange() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)

        vm.selectTrackByIndex(5)
        #expect(vm.selectedTrackID == nil)
    }

    @Test("Last bar with content returns correct value")
    @MainActor
    func lastBarWithContent() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        // Empty song → 1
        #expect(vm.lastBarWithContent == 1)

        // Add container at bars 5-8 → endBar = 9
        let _ = vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4)
        #expect(vm.lastBarWithContent == 9)

        // Add section at bars 1-20 → endBar = 21
        vm.addSection(startBar: 1, lengthBars: 20)
        #expect(vm.lastBarWithContent == 21)
    }

    @Test("Last bar with content uses max of containers and sections")
    @MainActor
    func lastBarWithContentMaxOfBoth() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 100)
        vm.addSection(startBar: 1, lengthBars: 4)

        // Container endBar = 101 > section endBar = 5
        #expect(vm.lastBarWithContent == 101)
    }

    @Test("Duplicate container undo/redo via shortcut")
    @MainActor
    func duplicateContainerUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let dupID = vm.duplicateContainer(trackID: trackID, containerID: containerID)
        #expect(dupID != nil)
        #expect(vm.project.songs[0].tracks[0].containers.count == 2)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].containers.count == 2)
    }

    // MARK: - Time Signature

    @Test("setTimeSignature updates song time signature")
    @MainActor
    func setTimeSignature() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id
        vm.setTimeSignature(songID: songID, beatsPerBar: 3, beatUnit: 4)
        #expect(vm.project.songs[0].timeSignature.beatsPerBar == 3)
        #expect(vm.project.songs[0].timeSignature.beatUnit == 4)
        #expect(vm.hasUnsavedChanges)
    }

    @Test("setTimeSignature undo/redo")
    @MainActor
    func setTimeSignatureUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id
        #expect(vm.project.songs[0].timeSignature.beatsPerBar == 4)
        #expect(vm.project.songs[0].timeSignature.beatUnit == 4)

        vm.setTimeSignature(songID: songID, beatsPerBar: 6, beatUnit: 8)
        #expect(vm.project.songs[0].timeSignature.beatsPerBar == 6)
        #expect(vm.project.songs[0].timeSignature.beatUnit == 8)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].timeSignature.beatsPerBar == 4)
        #expect(vm.project.songs[0].timeSignature.beatUnit == 4)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].timeSignature.beatsPerBar == 6)
        #expect(vm.project.songs[0].timeSignature.beatUnit == 8)
    }

    @Test("setTimeSignature rejects invalid beatsPerBar")
    @MainActor
    func setTimeSignatureInvalidBeatsPerBar() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id

        vm.setTimeSignature(songID: songID, beatsPerBar: 0, beatUnit: 4)
        #expect(vm.project.songs[0].timeSignature.beatsPerBar == 4)

        vm.setTimeSignature(songID: songID, beatsPerBar: 13, beatUnit: 4)
        #expect(vm.project.songs[0].timeSignature.beatsPerBar == 4)

        vm.setTimeSignature(songID: songID, beatsPerBar: -1, beatUnit: 4)
        #expect(vm.project.songs[0].timeSignature.beatsPerBar == 4)
    }

    @Test("setTimeSignature rejects invalid beatUnit")
    @MainActor
    func setTimeSignatureInvalidBeatUnit() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id

        vm.setTimeSignature(songID: songID, beatsPerBar: 4, beatUnit: 3)
        #expect(vm.project.songs[0].timeSignature.beatUnit == 4)

        vm.setTimeSignature(songID: songID, beatsPerBar: 4, beatUnit: 5)
        #expect(vm.project.songs[0].timeSignature.beatUnit == 4)

        vm.setTimeSignature(songID: songID, beatsPerBar: 4, beatUnit: 0)
        #expect(vm.project.songs[0].timeSignature.beatUnit == 4)
    }

    @Test("setTimeSignature accepts all valid beatUnit values")
    @MainActor
    func setTimeSignatureValidBeatUnits() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id

        for unit in [2, 4, 8, 16] {
            vm.setTimeSignature(songID: songID, beatsPerBar: 4, beatUnit: unit)
            #expect(vm.project.songs[0].timeSignature.beatUnit == unit)
        }
    }

    @Test("setTimeSignature accepts beatsPerBar boundary values")
    @MainActor
    func setTimeSignatureBeatsPerBarBounds() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id

        vm.setTimeSignature(songID: songID, beatsPerBar: 1, beatUnit: 4)
        #expect(vm.project.songs[0].timeSignature.beatsPerBar == 1)

        vm.setTimeSignature(songID: songID, beatsPerBar: 12, beatUnit: 4)
        #expect(vm.project.songs[0].timeSignature.beatsPerBar == 12)
    }

    @Test("setTimeSignature no-op when same value")
    @MainActor
    func setTimeSignatureNoOpSameValue() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id
        vm.hasUnsavedChanges = false

        vm.setTimeSignature(songID: songID, beatsPerBar: 4, beatUnit: 4)
        #expect(!vm.hasUnsavedChanges)
    }

    @Test("setTimeSignature does not reposition containers")
    @MainActor
    func setTimeSignatureDoesNotMoveContainers() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4)

        vm.setTimeSignature(songID: songID, beatsPerBar: 3, beatUnit: 4)

        #expect(vm.project.songs[0].tracks[0].containers[0].startBar == 5)
        #expect(vm.project.songs[0].tracks[0].containers[0].lengthBars == 4)
    }

    // MARK: - Master Track

    @Test("New project auto-creates master track")
    @MainActor
    func newProjectCreatesMasterTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        let song = vm.project.songs[0]
        #expect(song.masterTrack != nil)
        #expect(song.tracks.last?.kind == .master)
        #expect(song.tracks.last?.name == "Master")
    }

    @Test("Master track is always last after adding tracks")
    @MainActor
    func masterTrackAlwaysLast() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        vm.addTrack(kind: .bus)
        let tracks = vm.project.songs[0].tracks
        #expect(tracks.last?.kind == .master)
        for track in tracks.dropLast() {
            #expect(track.kind != .master)
        }
    }

    @Test("Cannot delete master track")
    @MainActor
    func cannotDeleteMasterTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        let masterID = vm.project.songs[0].tracks.first(where: { $0.kind == .master })!.id
        vm.removeTrack(id: masterID)
        // Master track should still be present
        #expect(vm.project.songs[0].tracks.contains(where: { $0.kind == .master }))
    }

    @Test("Cannot duplicate master track")
    @MainActor
    func cannotDuplicateMasterTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        let masterID = vm.project.songs[0].tracks.first(where: { $0.kind == .master })!.id
        let copyID = vm.duplicateTrack(trackID: masterID)
        #expect(copyID == nil)
        // Only one master track
        #expect(vm.project.songs[0].tracks.filter({ $0.kind == .master }).count == 1)
    }

    @Test("Cannot add master track via addTrack")
    @MainActor
    func cannotAddMasterTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .master)
        // Should still have exactly 1 master track
        #expect(vm.project.songs[0].tracks.filter({ $0.kind == .master }).count == 1)
    }

    @Test("Master track stays last after move")
    @MainActor
    func masterTrackStaysLastAfterMove() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        // tracks: [Audio, MIDI, Master]
        vm.moveTrack(from: IndexSet(integer: 0), to: 2)
        // After move: [MIDI, Audio, Master]
        #expect(vm.project.songs[0].tracks.last?.kind == .master)
    }

    @Test("Added song gets master track")
    @MainActor
    func addedSongGetsMasterTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSong()
        #expect(vm.project.songs[1].masterTrack != nil)
        #expect(vm.project.songs[1].tracks.last?.kind == .master)
    }

    @Test("ensureMasterTrack is idempotent")
    func ensureMasterTrackIdempotent() {
        var song = Song(name: "Test")
        song.ensureMasterTrack()
        #expect(song.tracks.filter({ $0.kind == .master }).count == 1)
        song.ensureMasterTrack()
        #expect(song.tracks.filter({ $0.kind == .master }).count == 1)
    }

    // MARK: - Metronome Config (#76)

    @MainActor
    @Test("setMetronomeConfig updates song metronome config")
    func setMetronomeConfigUpdates() {
        let vm = ProjectViewModel()
        vm.newProject()
        guard let songID = vm.currentSongID else {
            Issue.record("No current song")
            return
        }
        let config = MetronomeConfig(volume: 0.5, subdivision: .triplet, outputPortID: "test:0:0")
        vm.setMetronomeConfig(songID: songID, config: config)
        #expect(vm.currentSong?.metronomeConfig.volume == 0.5)
        #expect(vm.currentSong?.metronomeConfig.subdivision == .triplet)
        #expect(vm.currentSong?.metronomeConfig.outputPortID == "test:0:0")
    }

    @MainActor
    @Test("setMetronomeConfig undo/redo")
    func setMetronomeConfigUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        guard let songID = vm.currentSongID else {
            Issue.record("No current song")
            return
        }
        let original = vm.currentSong!.metronomeConfig
        let config = MetronomeConfig(volume: 0.3, subdivision: .sixteenth)
        vm.setMetronomeConfig(songID: songID, config: config)
        #expect(vm.currentSong?.metronomeConfig.subdivision == .sixteenth)

        vm.undoManager?.undo()
        #expect(vm.currentSong?.metronomeConfig == original)

        vm.undoManager?.redo()
        #expect(vm.currentSong?.metronomeConfig.subdivision == .sixteenth)
    }

    @MainActor
    @Test("setMetronomeConfig no-op when same config")
    func setMetronomeConfigNoOp() {
        let vm = ProjectViewModel()
        vm.newProject()
        guard let songID = vm.currentSongID else {
            Issue.record("No current song")
            return
        }
        let config = vm.currentSong!.metronomeConfig
        vm.setMetronomeConfig(songID: songID, config: config)
        // Should not have registered an undo since nothing changed
        #expect(!(vm.undoManager?.canUndo ?? false))
    }

    @MainActor
    @Test("duplicateSong copies metronomeConfig")
    func duplicateSongCopiesMetronomeConfig() {
        let vm = ProjectViewModel()
        vm.newProject()
        guard let songID = vm.currentSongID else {
            Issue.record("No current song")
            return
        }
        let config = MetronomeConfig(volume: 0.4, subdivision: .eighth, outputPortID: "test:1:0")
        vm.setMetronomeConfig(songID: songID, config: config)
        vm.duplicateSong(id: songID)
        #expect(vm.project.songs.count == 2)
        #expect(vm.project.songs[1].metronomeConfig == config)
    }

    // MARK: - Track Inspector Routing Tests (#87)

    @Test("Set input port via inspector updates track model")
    @MainActor
    func setInputPortUpdatesTrackModel() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(vm.project.songs[0].tracks[0].inputPortID == nil)
        vm.setTrackInputPort(trackID: trackID, portID: "device:0:0")
        #expect(vm.project.songs[0].tracks[0].inputPortID == "device:0:0")
    }

    @Test("Set output port via inspector updates track model")
    @MainActor
    func setOutputPortUpdatesTrackModel() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(vm.project.songs[0].tracks[0].outputPortID == nil)
        vm.setTrackOutputPort(trackID: trackID, portID: "device:1:0")
        #expect(vm.project.songs[0].tracks[0].outputPortID == "device:1:0")
    }

    @Test("Add effect via inspector is reflected in track insert chain")
    @MainActor
    func addEffectReflectedInTrackChain() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(vm.project.songs[0].tracks[0].insertEffects.isEmpty)
        let effect = InsertEffect(
            component: AudioComponentInfo(componentType: 0x61756678, componentSubType: 0x74737431, componentManufacturer: 0x41706C65),
            displayName: "Test Effect",
            orderIndex: 0
        )
        vm.addTrackEffect(trackID: trackID, effect: effect)
        #expect(vm.project.songs[0].tracks[0].insertEffects.count == 1)
        #expect(vm.project.songs[0].tracks[0].insertEffects[0].displayName == "Test Effect")
    }

    @Test("Set input port undo/redo")
    @MainActor
    func setInputPortUndoRedo() {
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

    @Test("Set output port undo/redo")
    @MainActor
    func setOutputPortUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.setTrackOutputPort(trackID: trackID, portID: "device:1:0")
        #expect(vm.project.songs[0].tracks[0].outputPortID == "device:1:0")
        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].outputPortID == nil)
        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].outputPortID == "device:1:0")
    }

    @Test("Set master output port updates master track")
    @MainActor
    func setMasterOutputPort() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        guard let masterTrack = vm.project.songs[0].tracks.first(where: { $0.kind == .master }) else {
            Issue.record("Master track not found")
            return
        }
        #expect(masterTrack.outputPortID == nil)
        vm.setMasterOutputPort(portID: "device:2:0")
        let updated = vm.project.songs[0].tracks.first(where: { $0.kind == .master })!
        #expect(updated.outputPortID == "device:2:0")
    }

    @Test("Set MIDI input via inspector updates device and channel")
    @MainActor
    func setMIDIInputUpdatesDeviceAndChannel() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id
        #expect(vm.project.songs[0].tracks[0].midiInputDeviceID == nil)
        #expect(vm.project.songs[0].tracks[0].midiInputChannel == nil)
        vm.setTrackMIDIInput(trackID: trackID, deviceID: "midi-dev-1", channel: 10)
        #expect(vm.project.songs[0].tracks[0].midiInputDeviceID == "midi-dev-1")
        #expect(vm.project.songs[0].tracks[0].midiInputChannel == 10)
    }

    @Test("Clear input port sets to nil (default)")
    @MainActor
    func clearInputPortSetsNil() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.setTrackInputPort(trackID: trackID, portID: "device:0:0")
        #expect(vm.project.songs[0].tracks[0].inputPortID == "device:0:0")
        vm.setTrackInputPort(trackID: trackID, portID: nil)
        #expect(vm.project.songs[0].tracks[0].inputPortID == nil)
    }

    @Test("Invalid track ID is no-op for set input port")
    @MainActor
    func setInputPortInvalidTrackID() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let bogusID = ID<Track>()
        vm.setTrackInputPort(trackID: bogusID, portID: "device:0:0")
        #expect(vm.project.songs[0].tracks[0].inputPortID == nil)
    }

    // MARK: - Container Inspector Inline Editing Tests

    @Test("Toggle effect bypass in inspector updates container model")
    @MainActor
    func toggleEffectBypassInInspector() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        let effect = InsertEffect(component: comp, displayName: "TestEffect", orderIndex: 0)
        vm.addContainerEffect(containerID: containerID, effect: effect)

        let effectID = vm.project.songs[0].tracks[0].containers[0].insertEffects[0].id
        #expect(!vm.project.songs[0].tracks[0].containers[0].insertEffects[0].isBypassed)

        vm.toggleContainerEffectBypass(containerID: containerID, effectID: effectID)
        #expect(vm.project.songs[0].tracks[0].containers[0].insertEffects[0].isBypassed)

        vm.toggleContainerEffectBypass(containerID: containerID, effectID: effectID)
        #expect(!vm.project.songs[0].tracks[0].containers[0].insertEffects[0].isBypassed)
    }

    @Test("Set enter fade in inspector updates container model")
    @MainActor
    func setEnterFadeInInspector() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        #expect(vm.project.songs[0].tracks[0].containers[0].enterFade == nil)

        let fade = FadeSettings(duration: 2.0, curve: .exponential)
        vm.setContainerEnterFade(containerID: containerID, fade: fade)

        let result = vm.project.songs[0].tracks[0].containers[0].enterFade
        #expect(result != nil)
        #expect(result?.duration == 2.0)
        #expect(result?.curve == .exponential)
    }

    @Test("Set exit fade in inspector updates container model")
    @MainActor
    func setExitFadeInInspector() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let fade = FadeSettings(duration: 4.0, curve: .sCurve)
        vm.setContainerExitFade(containerID: containerID, fade: fade)

        let result = vm.project.songs[0].tracks[0].containers[0].exitFade
        #expect(result != nil)
        #expect(result?.duration == 4.0)
        #expect(result?.curve == .sCurve)
    }

    @Test("Clear fade in inspector removes fade from container model")
    @MainActor
    func clearFadeInInspector() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        vm.setContainerEnterFade(containerID: containerID, fade: FadeSettings(duration: 2.0, curve: .linear))
        #expect(vm.project.songs[0].tracks[0].containers[0].enterFade != nil)

        vm.setContainerEnterFade(containerID: containerID, fade: nil)
        #expect(vm.project.songs[0].tracks[0].containers[0].enterFade == nil)
    }

    @Test("Fade setting undo/redo in inspector")
    @MainActor
    func fadeSettingUndoRedoInInspector() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let fade = FadeSettings(duration: 3.0, curve: .exponential)
        vm.setContainerEnterFade(containerID: containerID, fade: fade)
        #expect(vm.project.songs[0].tracks[0].containers[0].enterFade?.duration == 3.0)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].containers[0].enterFade == nil)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].containers[0].enterFade?.duration == 3.0)
    }

    @Test("Add and remove enter action in inspector updates container model")
    @MainActor
    func addRemoveEnterActionInInspector() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        #expect(vm.project.songs[0].tracks[0].containers[0].onEnterActions.isEmpty)

        let action = ContainerAction.makeSendMIDI(
            message: .programChange(channel: 0, program: 42),
            destination: .externalPort(name: "MIDI Out")
        )
        vm.addContainerEnterAction(containerID: containerID, action: action)
        #expect(vm.project.songs[0].tracks[0].containers[0].onEnterActions.count == 1)

        let actionID = vm.project.songs[0].tracks[0].containers[0].onEnterActions[0].id
        vm.removeContainerEnterAction(containerID: containerID, actionID: actionID)
        #expect(vm.project.songs[0].tracks[0].containers[0].onEnterActions.isEmpty)
    }

    @Test("Add and remove automation lane in inspector updates container model")
    @MainActor
    func addRemoveAutomationLaneInInspector() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        #expect(vm.project.songs[0].tracks[0].containers[0].automationLanes.isEmpty)

        let path = EffectPath(trackID: trackID, containerID: containerID, effectIndex: 0, parameterAddress: 100)
        let lane = AutomationLane(targetPath: path)
        vm.addAutomationLane(containerID: containerID, lane: lane)
        #expect(vm.project.songs[0].tracks[0].containers[0].automationLanes.count == 1)

        let laneID = vm.project.songs[0].tracks[0].containers[0].automationLanes[0].id
        vm.removeAutomationLane(containerID: containerID, laneID: laneID)
        #expect(vm.project.songs[0].tracks[0].containers[0].automationLanes.isEmpty)
    }

    @Test("Toggle effect chain bypass in inspector updates container model")
    @MainActor
    func toggleEffectChainBypassInInspector() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        #expect(!vm.project.songs[0].tracks[0].containers[0].isEffectChainBypassed)

        vm.toggleContainerEffectChainBypass(containerID: containerID)
        #expect(vm.project.songs[0].tracks[0].containers[0].isEffectChainBypassed)

        vm.toggleContainerEffectChainBypass(containerID: containerID)
        #expect(!vm.project.songs[0].tracks[0].containers[0].isEffectChainBypassed)
    }

    // MARK: - Track Reorder, Delete, Creation (#91)

    @Test("Reorder tracks updates model order correctly")
    @MainActor
    func reorderTracksUpdatesModel() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        vm.addTrack(kind: .bus)
        // Order: Audio 1, MIDI 1, Bus 1, Master
        #expect(vm.project.songs[0].tracks[0].kind == .audio)
        #expect(vm.project.songs[0].tracks[1].kind == .midi)
        #expect(vm.project.songs[0].tracks[2].kind == .bus)
        #expect(vm.project.songs[0].tracks[3].kind == .master)

        // Move Bus (index 2) to top (index 0)
        vm.moveTrack(from: IndexSet(integer: 2), to: 0)
        #expect(vm.project.songs[0].tracks[0].kind == .bus)
        #expect(vm.project.songs[0].tracks[1].kind == .audio)
        #expect(vm.project.songs[0].tracks[2].kind == .midi)
        // Master still at bottom
        #expect(vm.project.songs[0].tracks[3].kind == .master)
        // orderIndex updated
        for (i, track) in vm.project.songs[0].tracks.enumerated() {
            #expect(track.orderIndex == i)
        }
    }

    @Test("Reorder tracks: master cannot be moved")
    @MainActor
    func reorderMasterCannotBeMoved() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        // Order: Audio 1, MIDI 1, Master
        let masterIndex = vm.project.songs[0].tracks.firstIndex(where: { $0.kind == .master })!
        vm.moveTrack(from: IndexSet(integer: masterIndex), to: 0)
        // Master still at bottom (move was rejected)
        #expect(vm.project.songs[0].tracks.last?.kind == .master)
    }

    @Test("Reorder tracks undo/redo")
    @MainActor
    func reorderTracksUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        let originalOrder = vm.project.songs[0].tracks.map { $0.kind }

        vm.moveTrack(from: IndexSet(integer: 1), to: 0)
        let reorderedOrder = vm.project.songs[0].tracks.map { $0.kind }
        #expect(reorderedOrder != originalOrder)

        vm.undoManager?.undo()
        let afterUndo = vm.project.songs[0].tracks.map { $0.kind }
        #expect(afterUndo == originalOrder)

        vm.undoManager?.redo()
        let afterRedo = vm.project.songs[0].tracks.map { $0.kind }
        #expect(afterRedo == reorderedOrder)
    }

    @Test("Delete track removes it from song")
    @MainActor
    func deleteTrackRemovesFromSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        // 3 tracks: Audio, MIDI, Master
        #expect(vm.project.songs[0].tracks.count == 3)

        let midiID = vm.project.songs[0].tracks[1].id
        vm.removeTrack(id: midiID)
        #expect(vm.project.songs[0].tracks.count == 2)
        #expect(vm.project.songs[0].tracks[0].kind == .audio)
        #expect(vm.project.songs[0].tracks[1].kind == .master)
    }

    @Test("Delete master track is prevented")
    @MainActor
    func deleteMasterTrackPrevented() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let masterID = vm.project.songs[0].tracks.first(where: { $0.kind == .master })!.id
        let countBefore = vm.project.songs[0].tracks.count
        vm.removeTrack(id: masterID)
        #expect(vm.project.songs[0].tracks.count == countBefore)
    }

    @Test("Insert track at specific index")
    @MainActor
    func insertTrackAtIndex() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .midi)
        // Order: Audio 1, MIDI 1, Master
        #expect(vm.project.songs[0].tracks.count == 3)

        // Insert a bus track at index 1 (between Audio and MIDI)
        vm.insertTrack(kind: .bus, atIndex: 1)
        #expect(vm.project.songs[0].tracks.count == 4)
        #expect(vm.project.songs[0].tracks[0].kind == .audio)
        #expect(vm.project.songs[0].tracks[1].kind == .bus)
        #expect(vm.project.songs[0].tracks[2].kind == .midi)
        #expect(vm.project.songs[0].tracks[3].kind == .master)
        // orderIndex updated
        for (i, track) in vm.project.songs[0].tracks.enumerated() {
            #expect(track.orderIndex == i)
        }
    }

    @Test("Insert track at end goes above master")
    @MainActor
    func insertTrackAtEndAboveMaster() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        // Order: Audio 1, Master

        // Insert at index beyond track count — should go before master
        vm.insertTrack(kind: .midi, atIndex: 100)
        #expect(vm.project.songs[0].tracks.count == 3)
        #expect(vm.project.songs[0].tracks[1].kind == .midi)
        #expect(vm.project.songs[0].tracks[2].kind == .master)
    }

    @Test("Insert track undo/redo")
    @MainActor
    func insertTrackUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        #expect(vm.project.songs[0].tracks.count == 2)

        vm.insertTrack(kind: .midi, atIndex: 0)
        #expect(vm.project.songs[0].tracks.count == 3)
        #expect(vm.project.songs[0].tracks[0].kind == .midi)

        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks.count == 2)
        #expect(vm.project.songs[0].tracks[0].kind == .audio)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks.count == 3)
        #expect(vm.project.songs[0].tracks[0].kind == .midi)
    }

    @Test("Insert master track is prevented")
    @MainActor
    func insertMasterTrackPrevented() {
        let vm = ProjectViewModel()
        vm.newProject()
        let countBefore = vm.project.songs[0].tracks.count
        vm.insertTrack(kind: .master, atIndex: 0)
        #expect(vm.project.songs[0].tracks.count == countBefore)
    }

    // MARK: - Fade Handle Tests (#93)

    @Test("Fade handle drag sets enter fade duration correctly")
    @MainActor
    func fadeHandleDragSetsEnterFadeDuration() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 8)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        // Simulate drag handle setting a 2-bar fade-in
        vm.setContainerEnterFade(containerID: containerID, fade: FadeSettings(duration: 2.0, curve: .linear))
        let result = vm.project.songs[0].tracks[0].containers[0].enterFade
        #expect(result?.duration == 2.0)
        #expect(result?.curve == .linear)
    }

    @Test("Fade handle drag sets exit fade duration correctly")
    @MainActor
    func fadeHandleDragSetsExitFadeDuration() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 8)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        // Simulate drag handle setting a 3-bar fade-out with exponential curve
        vm.setContainerExitFade(containerID: containerID, fade: FadeSettings(duration: 3.0, curve: .exponential))
        let result = vm.project.songs[0].tracks[0].containers[0].exitFade
        #expect(result?.duration == 3.0)
        #expect(result?.curve == .exponential)
    }

    @Test("Fade handle drag to zero removes fade")
    @MainActor
    func fadeHandleDragToZeroRemovesFade() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 8)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        // Set a fade first
        vm.setContainerEnterFade(containerID: containerID, fade: FadeSettings(duration: 2.0, curve: .linear))
        #expect(vm.project.songs[0].tracks[0].containers[0].enterFade != nil)

        // Drag to zero removes fade
        vm.setContainerEnterFade(containerID: containerID, fade: nil)
        #expect(vm.project.songs[0].tracks[0].containers[0].enterFade == nil)
    }

    @Test("Fade handle preserves curve type when adjusting duration")
    @MainActor
    func fadeHandlePreservesCurveType() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 8)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        // Set initial fade with s-curve
        vm.setContainerEnterFade(containerID: containerID, fade: FadeSettings(duration: 2.0, curve: .sCurve))
        #expect(vm.project.songs[0].tracks[0].containers[0].enterFade?.curve == .sCurve)

        // Adjust duration but keep same curve (simulates drag handle behavior)
        vm.setContainerEnterFade(containerID: containerID, fade: FadeSettings(duration: 4.0, curve: .sCurve))
        #expect(vm.project.songs[0].tracks[0].containers[0].enterFade?.duration == 4.0)
        #expect(vm.project.songs[0].tracks[0].containers[0].enterFade?.curve == .sCurve)
    }

    @Test("FadeOverlayShape produces non-empty path for enter fade")
    func fadeOverlayEnterFadePath() {
        let shape = FadeOverlayShape(
            containerWidth: 480,
            height: 76,
            enterFade: FadeSettings(duration: 2.0, curve: .linear),
            exitFade: nil,
            enterFadeDragWidth: nil,
            exitFadeDragWidth: nil,
            pixelsPerBar: 120
        )
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 480, height: 76))
        #expect(!path.isEmpty)
    }

    @Test("FadeOverlayShape produces non-empty path for exit fade")
    func fadeOverlayExitFadePath() {
        let shape = FadeOverlayShape(
            containerWidth: 480,
            height: 76,
            enterFade: nil,
            exitFade: FadeSettings(duration: 1.5, curve: .exponential),
            enterFadeDragWidth: nil,
            exitFadeDragWidth: nil,
            pixelsPerBar: 120
        )
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 480, height: 76))
        #expect(!path.isEmpty)
    }

    @Test("FadeOverlayShape produces non-empty path for each curve type")
    func fadeOverlayAllCurveTypes() {
        for curve in CurveType.allCases {
            let shape = FadeOverlayShape(
                containerWidth: 480,
                height: 76,
                enterFade: FadeSettings(duration: 2.0, curve: curve),
                exitFade: FadeSettings(duration: 2.0, curve: curve),
                enterFadeDragWidth: nil,
                exitFadeDragWidth: nil,
                pixelsPerBar: 120
            )
            let path = shape.path(in: CGRect(x: 0, y: 0, width: 480, height: 76))
            #expect(!path.isEmpty, "Path should not be empty for curve type \(curve)")
        }
    }

    @Test("FadeOverlayShape empty when no fades")
    func fadeOverlayEmptyWhenNoFades() {
        let shape = FadeOverlayShape(
            containerWidth: 480,
            height: 76,
            enterFade: nil,
            exitFade: nil,
            enterFadeDragWidth: nil,
            exitFadeDragWidth: nil,
            pixelsPerBar: 120
        )
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 480, height: 76))
        #expect(path.isEmpty)
    }

    @Test("FadeOverlayShape uses drag width over model during drag")
    func fadeOverlayDragWidthOverride() {
        // Model has 2-bar fade but drag is showing 4-bar width
        let shape = FadeOverlayShape(
            containerWidth: 480,
            height: 76,
            enterFade: FadeSettings(duration: 2.0, curve: .linear),
            exitFade: nil,
            enterFadeDragWidth: 480, // 4 bars at 120ppb
            exitFadeDragWidth: nil,
            pixelsPerBar: 120
        )
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 480, height: 76))
        #expect(!path.isEmpty)
        // The path should use the drag width (480px = full container) not the model (240px = 2 bars)
        let bounds = path.boundingRect
        #expect(bounds.width > 300, "Drag width should produce wider overlay than model duration")
    }

    @Test("FadeSettings serialization round-trip with various durations")
    func fadeSettingsVariousDurationsRoundTrip() throws {
        let durations: [Double] = [0.25, 0.5, 1.0, 2.5, 4.0, 8.0, 16.0]
        for duration in durations {
            let settings = FadeSettings(duration: duration, curve: .linear)
            let data = try JSONEncoder().encode(settings)
            let decoded = try JSONDecoder().decode(FadeSettings.self, from: data)
            #expect(settings == decoded, "Round-trip failed for duration \(duration)")
        }
    }

    // MARK: - Async Audio Import (#96)

    private func createTestAudioFile(sampleRate: Double = 44100, durationSeconds: Double = 2.0) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-import-\(UUID().uuidString).caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(sampleRate * durationSeconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        if let data = buffer.floatChannelData {
            for i in 0..<Int(frames) {
                data[0][i] = sin(Float(i) * 2.0 * .pi * 440.0 / Float(sampleRate)) * 0.5
            }
        }
        try file.write(from: buffer)
        return url
    }

    @Test("importAudioAsync creates container immediately with correct length")
    @MainActor
    func importAudioAsyncCreatesContainer() throws {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        let sourceURL = try createTestAudioFile(sampleRate: 44100, durationSeconds: 4.0)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let audioDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-async-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: audioDir) }

        let containerID = vm.importAudioAsync(
            url: sourceURL,
            trackID: trackID,
            startBar: 5,
            audioDirectory: audioDir
        )

        // Container should be created immediately (synchronously)
        #expect(containerID != nil)
        let container = vm.project.songs[0].tracks[0].containers.first { $0.id == containerID }
        #expect(container != nil)
        #expect(container?.startBar == 5)
        // At 120 BPM 4/4, 1 bar = 2s, so 4s = 2 bars
        #expect(container?.lengthBars == 2)
        #expect(container?.sourceRecordingID != nil)
    }

    @Test("importAudioAsync recording has peaks immediately (synchronous generation)")
    @MainActor
    func importAudioAsyncHasPeaksImmediately() throws {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        let sourceURL = try createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let audioDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-async-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: audioDir) }

        let containerID = vm.importAudioAsync(
            url: sourceURL,
            trackID: trackID,
            startBar: 1,
            audioDirectory: audioDir
        )

        #expect(containerID != nil)
        let container = vm.project.songs[0].tracks[0].containers.first { $0.id == containerID }
        #expect(container != nil)
        // Peaks are generated synchronously from the source URL before file copy
        let peaks = vm.waveformPeaks(for: container!)
        #expect(peaks != nil)
        #expect(peaks!.count > 0)
    }

    @Test("importAudioAsync rejects overlapping container")
    @MainActor
    func importAudioAsyncRejectsOverlap() throws {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        let sourceURL = try createTestAudioFile(sampleRate: 44100, durationSeconds: 4.0)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let audioDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-async-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: audioDir) }

        // First import succeeds
        let first = vm.importAudioAsync(url: sourceURL, trackID: trackID, startBar: 1, audioDirectory: audioDir)
        #expect(first != nil)

        // Second import at overlapping position fails
        let second = vm.importAudioAsync(url: sourceURL, trackID: trackID, startBar: 2, audioDirectory: audioDir)
        #expect(second == nil)
    }

    @Test("importAudioAsync selects new container")
    @MainActor
    func importAudioAsyncSelectsContainer() throws {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        let sourceURL = try createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let audioDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-async-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: audioDir) }

        let containerID = vm.importAudioAsync(url: sourceURL, trackID: trackID, startBar: 1, audioDirectory: audioDir)
        #expect(vm.selectedContainerID == containerID)
    }

    // MARK: - Song Switch (#102)

    @Test("Switching songs fires onSongChanged callback")
    @MainActor
    func switchSongFiresCallback() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addSong()
        let song1ID = vm.project.songs[0].id
        let song2ID = vm.project.songs[1].id

        vm.selectSong(id: song1ID)

        var callbackFired = false
        vm.onSongChanged = { callbackFired = true }

        vm.selectSong(id: song2ID)
        #expect(callbackFired)
        #expect(vm.currentSongID == song2ID)
    }

    @Test("Selecting same song does not fire onSongChanged")
    @MainActor
    func selectSameSongNoCallback() {
        let vm = ProjectViewModel()
        vm.newProject()
        let songID = vm.project.songs[0].id
        vm.selectSong(id: songID)

        var callbackFired = false
        vm.onSongChanged = { callbackFired = true }

        vm.selectSong(id: songID)
        #expect(!callbackFired)
    }

    @Test("handleSongChanged resets playhead to bar 1")
    @MainActor
    func handleSongChangedResetsPlayhead() {
        let transport = TransportManager()
        let transportVM = TransportViewModel(transport: transport)
        transport.setPlayheadPosition(5.0)
        #expect(transport.playheadBar == 5.0)

        transportVM.handleSongChanged()
        #expect(transportVM.playheadBar == 1.0)
    }

    @Test("handleSongChanged during playback restarts playback")
    @MainActor
    func handleSongChangedRestartsPlayback() {
        let transport = TransportManager()
        let transportVM = TransportViewModel(transport: transport)

        // Simulate playing state (no engine — transport.play() starts immediately)
        transport.play()
        #expect(transport.state == .playing)
        transportVM.handleSongChanged()

        // After handleSongChanged, transport should be playing again from bar 1
        #expect(transport.state == .playing)
        #expect(transportVM.playheadBar == 1.0)
        transport.stop()
    }

    @Test("handleSongChanged while stopped does not start playback")
    @MainActor
    func handleSongChangedWhileStoppedNoPlayback() {
        let transport = TransportManager()
        let transportVM = TransportViewModel(transport: transport)
        transport.setPlayheadPosition(8.0)

        transportVM.handleSongChanged()
        #expect(transport.state == .stopped)
        #expect(transportVM.playheadBar == 1.0)
    }

    // MARK: - Return to Start Position (#103)

    @Test("TransportViewModel stop returns to start position when enabled")
    @MainActor
    func transportVMStopReturnsToStartPosition() {
        let transport = TransportManager()
        let transportVM = TransportViewModel(transport: transport)
        transportVM.returnToStartEnabled = true
        transport.setPlayheadPosition(5.0)
        transport.play()
        transport.setPlayheadPosition(12.0)
        transportVM.stop()
        #expect(transportVM.playheadBar == 5.0)
    }

    @Test("TransportViewModel stop leaves playhead at current position when disabled")
    @MainActor
    func transportVMStopLeavesPlayheadWhenDisabled() {
        let transport = TransportManager()
        let transportVM = TransportViewModel(transport: transport)
        transportVM.returnToStartEnabled = false
        transport.setPlayheadPosition(5.0)
        transport.play()
        transport.setPlayheadPosition(12.0)
        transportVM.stop()
        // When return-to-start is disabled, playhead stays at current position
        #expect(transportVM.playheadBar == 12.0)
    }

    @Test("TransportViewModel stop bypasses return-to-start in perform mode")
    @MainActor
    func transportVMStopBypassesInPerformMode() {
        let transport = TransportManager()
        let transportVM = TransportViewModel(transport: transport)
        transportVM.returnToStartEnabled = true
        transportVM.isPerformMode = true
        transport.setPlayheadPosition(5.0)
        transport.play()
        transport.setPlayheadPosition(12.0)
        transportVM.stop()
        // In perform mode, return-to-start is bypassed — goes to bar 1
        #expect(transportVM.playheadBar == 1.0)
    }

    @Test("TransportViewModel return-to-start works when perform mode off")
    @MainActor
    func transportVMReturnToStartWithPerformModeOff() {
        let transport = TransportManager()
        let transportVM = TransportViewModel(transport: transport)
        transportVM.returnToStartEnabled = true
        transportVM.isPerformMode = false
        transport.setPlayheadPosition(8.0)
        transport.play()
        transport.setPlayheadPosition(15.0)
        transportVM.stop()
        #expect(transportVM.playheadBar == 8.0)
    }

    // MARK: - Linked Container Recording Propagation

    @Test("Recording propagates to clone containers via parentContainerID")
    @MainActor
    func recordingPropagatesViaParentContainerID() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        // Create a clone at bars 5-9
        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)
        #expect(cloneID != nil)

        // Record into parent
        let recording = SourceRecording(
            filename: "test.caf",
            sampleRate: 44100,
            sampleCount: 176400
        )
        vm.setContainerRecording(trackID: trackID, containerID: parentID, recording: recording)

        // Parent should have the recording
        let parent = vm.project.songs[0].tracks[0].containers.first(where: { $0.id == parentID })
        #expect(parent?.sourceRecordingID == recording.id)

        // Clone should also have the recording (propagated)
        let clone = vm.project.songs[0].tracks[0].containers.first(where: { $0.id == cloneID })
        #expect(clone?.sourceRecordingID == recording.id)
    }

    @Test("Recording propagates to containers in same link group")
    @MainActor
    func recordingPropagatesViaLinkGroup() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4)

        let containerAID = vm.project.songs[0].tracks[0].containers[0].id
        let containerBID = vm.project.songs[0].tracks[0].containers[1].id

        // Link the two containers
        vm.linkContainers(containerIDs: [containerAID, containerBID])

        // Verify they have the same linkGroupID
        let containerA = vm.project.songs[0].tracks[0].containers.first(where: { $0.id == containerAID })
        let containerB = vm.project.songs[0].tracks[0].containers.first(where: { $0.id == containerBID })
        #expect(containerA?.linkGroupID != nil)
        #expect(containerA?.linkGroupID == containerB?.linkGroupID)

        // Record into container A
        let recording = SourceRecording(
            filename: "test.caf",
            sampleRate: 44100,
            sampleCount: 176400
        )
        vm.setContainerRecording(trackID: trackID, containerID: containerAID, recording: recording)

        // Both should have the recording
        let updatedA = vm.project.songs[0].tracks[0].containers.first(where: { $0.id == containerAID })
        let updatedB = vm.project.songs[0].tracks[0].containers.first(where: { $0.id == containerBID })
        #expect(updatedA?.sourceRecordingID == recording.id)
        #expect(updatedB?.sourceRecordingID == recording.id)
    }

    @Test("Recording override isolation: overridden clone keeps its own recording")
    @MainActor
    func recordingOverrideIsolation() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        // Create a clone
        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        // Record into clone first (this should mark .sourceRecording as overridden)
        let cloneRecording = SourceRecording(
            filename: "clone.caf",
            sampleRate: 44100,
            sampleCount: 88200
        )
        vm.setContainerRecording(trackID: trackID, containerID: cloneID, recording: cloneRecording)

        // Now record into parent — clone should NOT be affected
        let parentRecording = SourceRecording(
            filename: "parent.caf",
            sampleRate: 44100,
            sampleCount: 176400
        )
        vm.setContainerRecording(trackID: trackID, containerID: parentID, recording: parentRecording)

        let parent = vm.project.songs[0].tracks[0].containers.first(where: { $0.id == parentID })
        let clone = vm.project.songs[0].tracks[0].containers.first(where: { $0.id == cloneID })
        #expect(parent?.sourceRecordingID == parentRecording.id)
        #expect(clone?.sourceRecordingID == cloneRecording.id)
        #expect(clone?.overriddenFields.contains(.sourceRecording) == true)
    }

    @Test("Recording into clone marks .sourceRecording as overridden")
    @MainActor
    func recordingIntoCloneMarksOverridden() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        let recording = SourceRecording(
            filename: "test.caf",
            sampleRate: 44100,
            sampleCount: 176400
        )
        vm.setContainerRecording(trackID: trackID, containerID: cloneID, recording: recording)

        let clone = vm.project.songs[0].tracks[0].containers.first(where: { $0.id == cloneID })
        #expect(clone?.overriddenFields.contains(.sourceRecording) == true)
    }

    @Test("onRecordingPropagated fires with linked container list")
    @MainActor
    func onRecordingPropagatedCallback() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        var propagatedRecordingID: ID<SourceRecording>?
        var propagatedContainers: [Container] = []
        vm.onRecordingPropagated = { recID, _, containers in
            propagatedRecordingID = recID
            propagatedContainers = containers
        }

        let recording = SourceRecording(
            filename: "test.caf",
            sampleRate: 44100,
            sampleCount: 176400
        )
        vm.setContainerRecording(trackID: trackID, containerID: parentID, recording: recording)

        #expect(propagatedRecordingID == recording.id)
        #expect(propagatedContainers.count == 1)
        #expect(propagatedContainers[0].id == cloneID)
    }

    @Test("Live recording peaks propagate to linked containers")
    @MainActor
    func liveRecordingPeaksPropagate() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        let peaks: [Float] = [0.1, 0.5, 0.8, 0.3]
        vm.updateRecordingPeaks(containerID: parentID, peaks: peaks)

        // Parent gets peaks
        #expect(vm.liveRecordingPeaks[parentID] == peaks)
        // Clone also gets peaks
        #expect(vm.liveRecordingPeaks[cloneID] == peaks)
    }

    @Test("Live recording peaks do not propagate to overridden clone")
    @MainActor
    func liveRecordingPeaksDoNotPropagateToOverridden() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        // Record into clone first to mark .sourceRecording as overridden
        let cloneRecording = SourceRecording(
            filename: "clone.caf",
            sampleRate: 44100,
            sampleCount: 88200
        )
        vm.setContainerRecording(trackID: trackID, containerID: cloneID, recording: cloneRecording)

        // Now update peaks for parent recording
        let peaks: [Float] = [0.1, 0.5, 0.8, 0.3]
        vm.updateRecordingPeaks(containerID: parentID, peaks: peaks)

        // Parent gets peaks
        #expect(vm.liveRecordingPeaks[parentID] == peaks)
        // Clone should NOT get peaks (it has its own recording)
        #expect(vm.liveRecordingPeaks[cloneID] == nil)
    }

    @Test("setContainerRecording clears live peaks for all linked containers")
    @MainActor
    func setContainerRecordingClearsLivePeaks() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id

        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        // Simulate live peaks
        vm.liveRecordingPeaks[parentID] = [0.1, 0.5]
        vm.liveRecordingPeaks[cloneID] = [0.1, 0.5]

        let recording = SourceRecording(
            filename: "test.caf",
            sampleRate: 44100,
            sampleCount: 176400,
            waveformPeaks: [0.2, 0.6, 0.9]
        )
        vm.setContainerRecording(trackID: trackID, containerID: parentID, recording: recording)

        // Live peaks should be cleared after recording completes
        #expect(vm.liveRecordingPeaks[parentID] == nil)
        #expect(vm.liveRecordingPeaks[cloneID] == nil)
    }

    @Test("No recording propagation without clone or link group relationship")
    @MainActor
    func noRecordingPropagationToUnrelated() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4)

        let containerAID = vm.project.songs[0].tracks[0].containers[0].id
        let containerBID = vm.project.songs[0].tracks[0].containers[1].id

        let recording = SourceRecording(
            filename: "test.caf",
            sampleRate: 44100,
            sampleCount: 176400
        )
        vm.setContainerRecording(trackID: trackID, containerID: containerAID, recording: recording)

        let containerA = vm.project.songs[0].tracks[0].containers.first(where: { $0.id == containerAID })
        let containerB = vm.project.songs[0].tracks[0].containers.first(where: { $0.id == containerBID })
        #expect(containerA?.sourceRecordingID == recording.id)
        #expect(containerB?.sourceRecordingID == nil)
    }

    // MARK: - Cross-Song Copy/Paste

    @Test("Copy container to different song places it in matching track by name")
    @MainActor
    func copyContainerToSongMatchByName() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks.first(where: { $0.kind == .audio })!.id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks.first(where: { $0.id == trackID })!.containers[0].id
        let song1ID = vm.project.songs[0].id

        // Add second song with a matching-name track
        vm.addSong()
        let song2ID = vm.project.songs[1].id
        vm.addTrack(kind: .audio)
        // Rename to match source track
        let song2TrackID = vm.project.songs[1].tracks.first(where: { $0.kind == .audio })!.id
        vm.renameTrack(id: song2TrackID, newName: "Audio 1")

        // Switch back to song 1 to copy from
        vm.selectSong(id: song1ID)
        let newContainerID = vm.copyContainerToSong(trackID: trackID, containerID: containerID, targetSongID: song2ID)
        #expect(newContainerID != nil)

        // Verify container was added to the matching track in song 2
        let song2Track = vm.project.songs[1].tracks.first(where: { $0.name == "Audio 1" && $0.kind != .master })
        #expect(song2Track != nil)
        #expect(song2Track!.containers.contains(where: { $0.id == newContainerID }))
    }

    @Test("Copy container to different song creates new track when no match")
    @MainActor
    func copyContainerToSongCreatesTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks.first(where: { $0.kind == .midi })!.id
        vm.renameTrack(id: trackID, newName: "Synth Lead")
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks.first(where: { $0.id == trackID })!.containers[0].id
        let song1ID = vm.project.songs[0].id

        // Add second song with no matching track
        vm.addSong()
        let song2ID = vm.project.songs[1].id
        // Song 2 initially has only master track

        vm.selectSong(id: song1ID)
        let newContainerID = vm.copyContainerToSong(trackID: trackID, containerID: containerID, targetSongID: song2ID)
        #expect(newContainerID != nil)

        // A new track should have been created
        let song2TracksNonMaster = vm.project.songs[1].tracks.filter { $0.kind != .master }
        #expect(song2TracksNonMaster.count == 1)
        #expect(song2TracksNonMaster[0].name == "Synth Lead")
        #expect(song2TracksNonMaster[0].kind == .midi)
        #expect(song2TracksNonMaster[0].containers.contains(where: { $0.id == newContainerID }))
    }

    @Test("Copy track to different song duplicates track with all containers")
    @MainActor
    func copyTrackToSong() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks.first(where: { $0.kind == .audio })!.id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let _ = vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 4)
        let song1ID = vm.project.songs[0].id

        vm.addSong()
        let song2ID = vm.project.songs[1].id

        vm.selectSong(id: song1ID)
        let newTrackID = vm.copyTrackToSong(trackID: trackID, targetSongID: song2ID)
        #expect(newTrackID != nil)

        let newTrack = vm.project.songs[1].tracks.first(where: { $0.id == newTrackID })
        #expect(newTrack != nil)
        #expect(newTrack!.name == "Audio 1")
        #expect(newTrack!.kind == .audio)
        #expect(newTrack!.containers.count == 2)
        // New containers should have different IDs
        let sourceContainerIDs = Set(vm.project.songs[0].tracks.first(where: { $0.id == trackID })!.containers.map(\.id))
        let copiedContainerIDs = Set(newTrack!.containers.map(\.id))
        #expect(sourceContainerIDs.isDisjoint(with: copiedContainerIDs))
    }

    @Test("Track matching finds by name first, then by kind")
    @MainActor
    func trackMatchingLogic() {
        let vm = ProjectViewModel()
        vm.newProject()

        // Create two audio tracks in song 1
        vm.addTrack(kind: .audio) // "Audio 1"
        vm.addTrack(kind: .audio) // "Audio 2"

        // Add second song
        vm.addSong()
        let song2Index = 1
        vm.addTrack(kind: .audio) // "Audio 1" in song 2

        // Match by name: "Audio 1" should match the first audio track
        let match1 = vm.findMatchingTrack(in: song2Index, name: "Audio 1", kind: .audio)
        #expect(match1 != nil)
        #expect(vm.project.songs[song2Index].tracks[match1!].name == "Audio 1")

        // Match by kind: "Audio 2" has no name match, falls back to kind match
        let match2 = vm.findMatchingTrack(in: song2Index, name: "Audio 2", kind: .audio)
        #expect(match2 != nil)
        #expect(vm.project.songs[song2Index].tracks[match2!].kind == .audio)

        // No match: MIDI track not present
        let match3 = vm.findMatchingTrack(in: song2Index, name: "MIDI 1", kind: .midi)
        #expect(match3 == nil)
    }

    @Test("Undo cross-song container paste reverts changes in target song")
    @MainActor
    func undoCrossSongPaste() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks.first(where: { $0.kind == .audio })!.id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks.first(where: { $0.id == trackID })!.containers[0].id
        let song1ID = vm.project.songs[0].id

        vm.addSong()
        let song2ID = vm.project.songs[1].id

        vm.selectSong(id: song1ID)
        let _ = vm.copyContainerToSong(trackID: trackID, containerID: containerID, targetSongID: song2ID)

        // Song 2 should have a non-master track with a container
        let song2NonMaster = vm.project.songs[1].tracks.filter { $0.kind != .master }
        #expect(song2NonMaster.count == 1)
        #expect(song2NonMaster[0].containers.count == 1)

        // Undo should revert the change — use vm's own undoManager
        vm.undoManager?.undo()
        let song2NonMasterAfterUndo = vm.project.songs[1].tracks.filter { $0.kind != .master }
        #expect(song2NonMasterAfterUndo.isEmpty)
    }

    @Test("Copy track to song includes effects and routing configuration")
    @MainActor
    func copyTrackToSongPreservesConfig() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks.first(where: { $0.kind == .audio })!.id

        // Add an effect to the track
        let component = AudioComponentInfo(componentType: 0x61756678, componentSubType: 0x74657374, componentManufacturer: 0x54657374)
        let effect = InsertEffect(component: component, displayName: "TestEffect", orderIndex: 0)
        vm.addTrackEffect(trackID: trackID, effect: effect)
        let song1ID = vm.project.songs[0].id

        vm.addSong()
        let song2ID = vm.project.songs[1].id

        vm.selectSong(id: song1ID)
        let newTrackID = vm.copyTrackToSong(trackID: trackID, targetSongID: song2ID)
        #expect(newTrackID != nil)

        let newTrack = vm.project.songs[1].tracks.first(where: { $0.id == newTrackID })
        #expect(newTrack != nil)
        #expect(newTrack!.insertEffects.count == 1)
        #expect(newTrack!.insertEffects[0].displayName == "TestEffect")
    }

    @Test("Cannot copy track to same song")
    @MainActor
    func copyTrackToSameSongFails() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks.first(where: { $0.kind == .audio })!.id
        let song1ID = vm.project.songs[0].id

        let result = vm.copyTrackToSong(trackID: trackID, targetSongID: song1ID)
        #expect(result == nil)
    }

    @Test("Cannot copy master track to another song")
    @MainActor
    func copyMasterTrackFails() {
        let vm = ProjectViewModel()
        vm.newProject()
        let masterID = vm.project.songs[0].tracks.first(where: { $0.kind == .master })!.id

        vm.addSong()
        let song2ID = vm.project.songs[1].id

        vm.selectSong(id: vm.project.songs[0].id)
        let result = vm.copyTrackToSong(trackID: masterID, targetSongID: song2ID)
        #expect(result == nil)
    }

    @Test("otherSongs returns songs excluding current")
    @MainActor
    func otherSongsExcludesCurrent() {
        let vm = ProjectViewModel()
        vm.newProject()
        let song1ID = vm.project.songs[0].id
        vm.addSong()
        vm.addSong()

        vm.selectSong(id: song1ID)
        let others = vm.otherSongs
        #expect(others.count == 2)
        #expect(!others.contains(where: { $0.id == song1ID }))
    }

    @Test("Copy container to song preserves MIDI sequence")
    @MainActor
    func copyContainerToSongPreservesMIDI() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks.first(where: { $0.kind == .midi })!.id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks.first(where: { $0.id == trackID })!.containers[0].id
        let note = MIDINoteEvent(pitch: 60, velocity: 100, startBeat: 0.0, duration: 1.0)
        vm.addMIDINote(containerID: containerID, note: note)
        let song1ID = vm.project.songs[0].id

        vm.addSong()
        let song2ID = vm.project.songs[1].id

        vm.selectSong(id: song1ID)
        let newContainerID = vm.copyContainerToSong(trackID: trackID, containerID: containerID, targetSongID: song2ID)
        #expect(newContainerID != nil)

        let song2Tracks = vm.project.songs[1].tracks.filter { $0.kind != .master }
        let newContainer = song2Tracks.flatMap(\.containers).first(where: { $0.id == newContainerID })
        #expect(newContainer?.midiSequence != nil)
        #expect(newContainer?.midiSequence?.notes.count == 1)
        #expect(newContainer?.midiSequence?.notes.first?.pitch == 60)
    }

    // MARK: - Effect/Instrument Removal Cleanup (#119)

    @Test("Remove track effect also removes its automation lanes and MIDI mappings")
    @MainActor
    func removeTrackEffectCleansUpAutomationAndMIDI() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        let effect = InsertEffect(component: comp, displayName: "Reverb", orderIndex: 0)
        vm.addTrackEffect(trackID: trackID, effect: effect)
        let effectID = vm.project.songs[0].tracks[0].insertEffects[0].id

        // Add automation lane targeting this effect
        let lane = AutomationLane(targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 100))
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.count == 1)

        // Add MIDI parameter mapping targeting this effect
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 1),
            targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 100)
        )
        vm.addMIDIParameterMapping(mapping)
        #expect(vm.project.midiParameterMappings.count == 1)

        // Remove the effect
        vm.removeTrackEffect(trackID: trackID, effectID: effectID)

        // Automation lane and MIDI mapping should be gone
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.isEmpty)
        #expect(vm.project.midiParameterMappings.isEmpty)
    }

    @Test("Remove track effect at index N decrements automation/MIDI for effects after N")
    @MainActor
    func removeTrackEffectDecrementsHigherIndices() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        vm.addTrackEffect(trackID: trackID, effect: InsertEffect(component: comp, displayName: "A", orderIndex: 0))
        vm.addTrackEffect(trackID: trackID, effect: InsertEffect(component: comp, displayName: "B", orderIndex: 1))
        vm.addTrackEffect(trackID: trackID, effect: InsertEffect(component: comp, displayName: "C", orderIndex: 2))
        let effectBID = vm.project.songs[0].tracks[0].insertEffects.first(where: { $0.displayName == "B" })!.id

        // Add automation for A (index 0) and C (index 2)
        let laneA = AutomationLane(targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 100))
        let laneC = AutomationLane(targetPath: EffectPath(trackID: trackID, effectIndex: 2, parameterAddress: 200))
        vm.addTrackAutomationLane(trackID: trackID, lane: laneA)
        vm.addTrackAutomationLane(trackID: trackID, lane: laneC)

        // Add MIDI mapping for C (index 2)
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 1),
            targetPath: EffectPath(trackID: trackID, effectIndex: 2, parameterAddress: 200)
        )
        vm.addMIDIParameterMapping(mapping)

        // Remove B (index 1)
        vm.removeTrackEffect(trackID: trackID, effectID: effectBID)

        // A's lane unchanged (index 0)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.count == 2)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].targetPath.effectIndex == 0)
        // C's lane decremented from 2 to 1
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[1].targetPath.effectIndex == 1)
        // MIDI mapping for C also decremented
        #expect(vm.project.midiParameterMappings[0].targetPath.effectIndex == 1)
    }

    @Test("Reorder track effects updates effectIndex in automation lanes and MIDI mappings")
    @MainActor
    func reorderTrackEffectsUpdatesAutomationAndMIDI() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        vm.addTrackEffect(trackID: trackID, effect: InsertEffect(component: comp, displayName: "A", orderIndex: 0))
        vm.addTrackEffect(trackID: trackID, effect: InsertEffect(component: comp, displayName: "B", orderIndex: 1))
        vm.addTrackEffect(trackID: trackID, effect: InsertEffect(component: comp, displayName: "C", orderIndex: 2))

        // Add automation lane for A (index 0) and MIDI mapping for C (index 2)
        let laneA = AutomationLane(targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 100))
        vm.addTrackAutomationLane(trackID: trackID, lane: laneA)
        let mappingC = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 1),
            targetPath: EffectPath(trackID: trackID, effectIndex: 2, parameterAddress: 200)
        )
        vm.addMIDIParameterMapping(mappingC)

        // Move A (index 0) to after C (position 3) → new order: B(0), C(1), A(2)
        vm.reorderTrackEffects(trackID: trackID, from: IndexSet(integer: 0), to: 3)

        // Verify effects reordered
        let effects = vm.project.songs[0].tracks[0].insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        #expect(effects[0].displayName == "B")
        #expect(effects[1].displayName == "C")
        #expect(effects[2].displayName == "A")

        // A's automation lane moved from index 0 to index 2
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].targetPath.effectIndex == 2)
        // C's MIDI mapping moved from index 2 to index 1
        #expect(vm.project.midiParameterMappings[0].targetPath.effectIndex == 1)
    }

    @Test("Remove container effect also removes its automation lanes and MIDI mappings")
    @MainActor
    func removeContainerEffectCleansUpAutomationAndMIDI() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        let effect = InsertEffect(component: comp, displayName: "Reverb", orderIndex: 0)
        vm.addContainerEffect(containerID: containerID, effect: effect)
        let effectID = vm.project.songs[0].tracks[0].containers[0].insertEffects[0].id

        // Add automation lane targeting this container effect
        let lane = AutomationLane(targetPath: EffectPath(trackID: trackID, containerID: containerID, effectIndex: 0, parameterAddress: 100))
        vm.addAutomationLane(containerID: containerID, lane: lane)
        #expect(vm.project.songs[0].tracks[0].containers[0].automationLanes.count == 1)

        // Add MIDI parameter mapping targeting this container effect
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 1),
            targetPath: EffectPath(trackID: trackID, containerID: containerID, effectIndex: 0, parameterAddress: 100)
        )
        vm.addMIDIParameterMapping(mapping)
        #expect(vm.project.midiParameterMappings.count == 1)

        // Remove the effect
        vm.removeContainerEffect(containerID: containerID, effectID: effectID)

        // Automation lane and MIDI mapping should be gone
        #expect(vm.project.songs[0].tracks[0].containers[0].automationLanes.isEmpty)
        #expect(vm.project.midiParameterMappings.isEmpty)
    }

    @Test("Remove container effect at index N decrements automation/MIDI for effects after N")
    @MainActor
    func removeContainerEffectDecrementsHigherIndices() {
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
        let effectBID = vm.project.songs[0].tracks[0].containers[0].insertEffects.first(where: { $0.displayName == "B" })!.id

        // Add automation for A (index 0) and C (index 2)
        let laneA = AutomationLane(targetPath: EffectPath(trackID: trackID, containerID: containerID, effectIndex: 0, parameterAddress: 100))
        let laneC = AutomationLane(targetPath: EffectPath(trackID: trackID, containerID: containerID, effectIndex: 2, parameterAddress: 200))
        vm.addAutomationLane(containerID: containerID, lane: laneA)
        vm.addAutomationLane(containerID: containerID, lane: laneC)

        // Remove B (index 1)
        vm.removeContainerEffect(containerID: containerID, effectID: effectBID)

        // A's lane unchanged (index 0)
        #expect(vm.project.songs[0].tracks[0].containers[0].automationLanes.count == 2)
        #expect(vm.project.songs[0].tracks[0].containers[0].automationLanes[0].targetPath.effectIndex == 0)
        // C's lane decremented from 2 to 1
        #expect(vm.project.songs[0].tracks[0].containers[0].automationLanes[1].targetPath.effectIndex == 1)
    }

    @Test("Reorder container effects updates effectIndex in automation lanes")
    @MainActor
    func reorderContainerEffectsUpdatesAutomation() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "A", orderIndex: 0))
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "B", orderIndex: 1))

        // Add automation lane for A (index 0)
        let laneA = AutomationLane(targetPath: EffectPath(trackID: trackID, containerID: containerID, effectIndex: 0, parameterAddress: 100))
        vm.addAutomationLane(containerID: containerID, lane: laneA)

        // Move A (index 0) to after B (position 2) → new order: B(0), A(1)
        vm.reorderContainerEffects(containerID: containerID, from: IndexSet(integer: 0), to: 2)

        // A's automation lane moved from index 0 to index 1
        #expect(vm.project.songs[0].tracks[0].containers[0].automationLanes[0].targetPath.effectIndex == 1)
    }

    @Test("Remove instrument override removes instrument automation lanes and MIDI mappings")
    @MainActor
    func removeInstrumentOverrideCleansUpAutomation() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        // Set instrument override
        let instComp = AudioComponentInfo(componentType: 1, componentSubType: 2, componentManufacturer: 1)
        vm.setContainerInstrumentOverride(containerID: containerID, override: instComp)

        // Add instrument automation lane (effectIndex == -2)
        let instLane = AutomationLane(targetPath: EffectPath(trackID: trackID, containerID: containerID, effectIndex: EffectPath.instrumentParameterEffectIndex, parameterAddress: 50))
        vm.addAutomationLane(containerID: containerID, lane: instLane)

        // Add a regular effect automation lane (should NOT be removed)
        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        vm.addContainerEffect(containerID: containerID, effect: InsertEffect(component: comp, displayName: "FX", orderIndex: 0))
        let effectLane = AutomationLane(targetPath: EffectPath(trackID: trackID, containerID: containerID, effectIndex: 0, parameterAddress: 100))
        vm.addAutomationLane(containerID: containerID, lane: effectLane)

        // Add MIDI mapping for instrument
        let instMapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 1),
            targetPath: EffectPath(trackID: trackID, containerID: containerID, effectIndex: EffectPath.instrumentParameterEffectIndex, parameterAddress: 50)
        )
        vm.addMIDIParameterMapping(instMapping)

        #expect(vm.project.songs[0].tracks[0].containers[0].automationLanes.count == 2)
        #expect(vm.project.midiParameterMappings.count == 1)

        // Remove instrument override
        vm.setContainerInstrumentOverride(containerID: containerID, override: nil)

        // Instrument automation lane and MIDI mapping removed, effect lane preserved
        #expect(vm.project.songs[0].tracks[0].containers[0].automationLanes.count == 1)
        #expect(vm.project.songs[0].tracks[0].containers[0].automationLanes[0].targetPath.effectIndex == 0)
        #expect(vm.project.midiParameterMappings.isEmpty)
    }

    @Test("Undo track effect removal restores automation lanes and MIDI mappings")
    @MainActor
    func undoTrackEffectRemovalRestoresAutomationAndMIDI() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        let comp = AudioComponentInfo(componentType: 1, componentSubType: 1, componentManufacturer: 1)
        vm.addTrackEffect(trackID: trackID, effect: InsertEffect(component: comp, displayName: "Reverb", orderIndex: 0))
        let effectID = vm.project.songs[0].tracks[0].insertEffects[0].id

        // Add automation and MIDI mapping
        let lane = AutomationLane(targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 100))
        vm.addTrackAutomationLane(trackID: trackID, lane: lane)
        let mapping = MIDIParameterMapping(
            trigger: .controlChange(channel: 0, controller: 1),
            targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 100)
        )
        vm.addMIDIParameterMapping(mapping)

        // Remove the effect
        vm.removeTrackEffect(trackID: trackID, effectID: effectID)
        #expect(vm.project.songs[0].tracks[0].insertEffects.isEmpty)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.isEmpty)
        #expect(vm.project.midiParameterMappings.isEmpty)

        // Undo should restore everything
        vm.undoManager?.undo()
        #expect(vm.project.songs[0].tracks[0].insertEffects.count == 1)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes.count == 1)
        #expect(vm.project.midiParameterMappings.count == 1)
        #expect(vm.project.songs[0].tracks[0].trackAutomationLanes[0].targetPath.effectIndex == 0)
        #expect(vm.project.midiParameterMappings[0].targetPath.effectIndex == 0)
    }

    // MARK: - Split Container

    @Test("splitContainer creates two containers with correct bars")
    @MainActor
    func splitContainerBasic() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 8)

        let originalID = vm.project.songs[0].tracks[0].containers[0].id
        let rightID = vm.splitContainer(trackID: trackID, containerID: originalID, atBar: 5)

        #expect(rightID != nil)
        let containers = vm.project.songs[0].tracks[0].containers.sorted { $0.startBar < $1.startBar }
        #expect(containers.count == 2)
        #expect(containers[0].startBar == 1)
        #expect(containers[0].lengthBars == 4)
        #expect(containers[1].startBar == 5)
        #expect(containers[1].lengthBars == 4)
    }

    @Test("splitContainer sets correct audioStartOffset on right half")
    @MainActor
    func splitContainerAudioOffset() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 10)

        let originalID = vm.project.songs[0].tracks[0].containers[0].id
        let _ = vm.splitContainer(trackID: trackID, containerID: originalID, atBar: 4)

        let containers = vm.project.songs[0].tracks[0].containers.sorted { $0.startBar < $1.startBar }
        #expect(containers[0].audioStartOffset == 0.0)
        #expect(containers[1].audioStartOffset == 3.0) // 4 - 1 = 3 bars into recording
    }

    @Test("splitContainerAtRange creates three containers")
    @MainActor
    func splitContainerAtRangeBasic() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 12)

        let containerID = vm.project.songs[0].tracks[0].containers[0].id
        let result = vm.splitContainerAtRange(
            trackID: trackID, containerID: containerID,
            rangeStart: 5, rangeEnd: 9
        )

        #expect(result == true)
        let containers = vm.project.songs[0].tracks[0].containers.sorted { $0.startBar < $1.startBar }
        #expect(containers.count == 3)

        // Left part: bars 1-4
        #expect(containers[0].startBar == 1)
        #expect(containers[0].lengthBars == 4)
        #expect(containers[0].audioStartOffset == 0.0)

        // Middle part: bars 5-8
        #expect(containers[1].startBar == 5)
        #expect(containers[1].lengthBars == 4)
        #expect(containers[1].audioStartOffset == 4.0)

        // Right part: bars 9-12
        #expect(containers[2].startBar == 9)
        #expect(containers[2].lengthBars == 4)
        #expect(containers[2].audioStartOffset == 8.0)
    }

    @Test("splitContainerAtRange at container start creates two containers")
    @MainActor
    func splitContainerAtRangeFromStart() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 10)

        let containerID = vm.project.songs[0].tracks[0].containers[0].id
        let result = vm.splitContainerAtRange(
            trackID: trackID, containerID: containerID,
            rangeStart: 1, rangeEnd: 4
        )

        #expect(result == true)
        let containers = vm.project.songs[0].tracks[0].containers.sorted { $0.startBar < $1.startBar }
        #expect(containers.count == 2)

        // Middle (selection): bars 1-3
        #expect(containers[0].startBar == 1)
        #expect(containers[0].lengthBars == 3)

        // Right: bars 4-10
        #expect(containers[1].startBar == 4)
        #expect(containers[1].lengthBars == 7)
        #expect(containers[1].audioStartOffset == 3.0)
    }

    @Test("splitContainerAtRange at container end creates two containers")
    @MainActor
    func splitContainerAtRangeToEnd() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 10)

        let containerID = vm.project.songs[0].tracks[0].containers[0].id
        let result = vm.splitContainerAtRange(
            trackID: trackID, containerID: containerID,
            rangeStart: 7, rangeEnd: 11
        )

        #expect(result == true)
        let containers = vm.project.songs[0].tracks[0].containers.sorted { $0.startBar < $1.startBar }
        #expect(containers.count == 2)

        // Left: bars 1-6
        #expect(containers[0].startBar == 1)
        #expect(containers[0].lengthBars == 6)

        // Middle (selection): bars 7-10
        #expect(containers[1].startBar == 7)
        #expect(containers[1].lengthBars == 4)
        #expect(containers[1].audioStartOffset == 6.0)
    }

    @Test("splitContainerAtRange preserves audioStartOffset from original")
    @MainActor
    func splitContainerAtRangePreservesOffset() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 5, lengthBars: 10)

        // Set an existing audioStartOffset
        vm.project.songs[0].tracks[0].containers[0].audioStartOffset = 2.0

        let containerID = vm.project.songs[0].tracks[0].containers[0].id
        let result = vm.splitContainerAtRange(
            trackID: trackID, containerID: containerID,
            rangeStart: 8, rangeEnd: 12
        )

        #expect(result == true)
        let containers = vm.project.songs[0].tracks[0].containers.sorted { $0.startBar < $1.startBar }
        #expect(containers.count == 3)

        // Left: bars 5-7, offset = original 2.0
        #expect(containers[0].audioStartOffset == 2.0)
        // Middle: bars 8-11, offset = 2.0 + (8-5) = 5.0
        #expect(containers[1].audioStartOffset == 5.0)
        // Right: bars 12-14, offset = 2.0 + (12-5) = 9.0
        #expect(containers[2].audioStartOffset == 9.0)
    }

    // MARK: - Glue / Consolidate Containers

    @Test("Glue MIDI containers merges notes with correct beat offsets")
    @MainActor
    func glueMIDIContainers() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)

        let c1 = Container(
            name: "MIDI 1",
            startBar: 1.0,
            lengthBars: 4.0,
            midiSequence: MIDISequence(notes: [
                MIDINoteEvent(pitch: 60, velocity: 100, startBeat: 0.0, duration: 1.0),
                MIDINoteEvent(pitch: 64, velocity: 80, startBeat: 2.0, duration: 0.5),
            ])
        )
        let c2 = Container(
            name: "MIDI 2",
            startBar: 5.0,
            lengthBars: 4.0,
            midiSequence: MIDISequence(notes: [
                MIDINoteEvent(pitch: 67, velocity: 90, startBeat: 0.0, duration: 2.0),
                MIDINoteEvent(pitch: 72, velocity: 110, startBeat: 2.0, duration: 1.0),
            ])
        )

        vm.project.songs[0].tracks[0].containers = [c1, c2]

        let result = vm.glueContainers(containerIDs: Set([c1.id, c2.id]))
        #expect(result != nil)

        let containers = vm.project.songs[0].tracks[0].containers
        #expect(containers.count == 1)

        let merged = containers[0]
        #expect(merged.startBar == 1.0)
        #expect(merged.lengthBars == 8.0)
        #expect(merged.midiSequence != nil)

        let notes = merged.midiSequence!.notes.sorted { $0.startBeat < $1.startBeat }
        #expect(notes.count == 4)

        // c1 notes: bar offset 0, beat offset 0
        #expect(notes[0].pitch == 60)
        #expect(notes[0].startBeat == 0.0)
        #expect(notes[1].pitch == 64)
        #expect(notes[1].startBeat == 2.0)

        // c2 notes: bar offset 4, beat offset 16 (4 bars * 4 beats)
        #expect(notes[2].pitch == 67)
        #expect(notes[2].startBeat == 16.0)
        #expect(notes[3].pitch == 72)
        #expect(notes[3].startBeat == 18.0)
    }

    @Test("Glue containers with gap spans full range including gap")
    @MainActor
    func glueContainersWithGap() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)

        let c1 = Container(
            name: "First",
            startBar: 1.0,
            lengthBars: 4.0,
            midiSequence: MIDISequence(notes: [
                MIDINoteEvent(pitch: 60, startBeat: 0.0, duration: 1.0),
            ])
        )
        // Gap: bars 5-7 (3 bars of silence)
        let c2 = Container(
            name: "Second",
            startBar: 8.0,
            lengthBars: 4.0,
            midiSequence: MIDISequence(notes: [
                MIDINoteEvent(pitch: 72, startBeat: 0.0, duration: 1.0),
            ])
        )

        vm.project.songs[0].tracks[0].containers = [c1, c2]

        let result = vm.glueContainers(containerIDs: Set([c1.id, c2.id]))
        #expect(result != nil)

        let merged = vm.project.songs[0].tracks[0].containers[0]
        // Should span bars 1 to 12 (start=1, length=11)
        #expect(merged.startBar == 1.0)
        #expect(merged.lengthBars == 11.0)

        // Second container's note at bar 8 → beat offset (8-1)*4 = 28
        let notes = merged.midiSequence!.notes.sorted { $0.startBeat < $1.startBeat }
        #expect(notes[0].startBeat == 0.0)
        #expect(notes[1].startBeat == 28.0)
    }

    @Test("Glue requires at least 2 containers")
    @MainActor
    func glueRequiresMultiple() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)

        let c1 = Container(startBar: 1.0, midiSequence: MIDISequence())
        vm.project.songs[0].tracks[0].containers = [c1]

        let result = vm.glueContainers(containerIDs: Set([c1.id]))
        #expect(result == nil)
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)
    }

    @Test("Glue rejects containers on different tracks")
    @MainActor
    func glueRejectsCrossTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        vm.addTrack(kind: .midi)

        let c1 = Container(startBar: 1.0, midiSequence: MIDISequence())
        let c2 = Container(startBar: 5.0, midiSequence: MIDISequence())

        vm.project.songs[0].tracks[0].containers = [c1]
        vm.project.songs[0].tracks[1].containers = [c2]

        let result = vm.glueContainers(containerIDs: Set([c1.id, c2.id]))
        #expect(result == nil)
    }

    @Test("Glue merges automation breakpoints with re-offset positions")
    @MainActor
    func glueAutomation() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)

        let trackID = vm.project.songs[0].tracks[0].id
        let c1ID = ID<Container>()
        let c2ID = ID<Container>()

        let targetPath1 = EffectPath(trackID: trackID, containerID: c1ID, effectIndex: 0, parameterAddress: 100)
        let targetPath2 = EffectPath(trackID: trackID, containerID: c2ID, effectIndex: 0, parameterAddress: 100)

        let c1 = Container(
            id: c1ID,
            startBar: 1.0,
            lengthBars: 4.0,
            automationLanes: [
                AutomationLane(targetPath: targetPath1, breakpoints: [
                    AutomationBreakpoint(position: 0.0, value: 0.0),
                    AutomationBreakpoint(position: 2.0, value: 1.0),
                ])
            ],
            midiSequence: MIDISequence()
        )
        let c2 = Container(
            id: c2ID,
            startBar: 5.0,
            lengthBars: 4.0,
            automationLanes: [
                AutomationLane(targetPath: targetPath2, breakpoints: [
                    AutomationBreakpoint(position: 0.0, value: 0.5),
                    AutomationBreakpoint(position: 1.0, value: 0.8),
                ])
            ],
            midiSequence: MIDISequence()
        )

        vm.project.songs[0].tracks[0].containers = [c1, c2]

        let result = vm.glueContainers(containerIDs: Set([c1.id, c2.id]))
        #expect(result != nil)

        let merged = vm.project.songs[0].tracks[0].containers[0]
        #expect(merged.automationLanes.count == 1)

        let lane = merged.automationLanes[0]
        // The merged lane should target the new container ID
        #expect(lane.targetPath.containerID == merged.id)
        #expect(lane.breakpoints.count == 4)

        let bps = lane.breakpoints.sorted { $0.position < $1.position }
        // c1 breakpoints: offset 0 (bar 1 - bar 1 = 0)
        #expect(bps[0].position == 0.0)
        #expect(bps[0].value == 0.0)
        #expect(bps[1].position == 2.0)
        #expect(bps[1].value == 1.0)
        // c2 breakpoints: offset 4 (bar 5 - bar 1 = 4)
        #expect(bps[2].position == 4.0)
        #expect(bps[2].value == 0.5)
        #expect(bps[3].position == 5.0)
        #expect(bps[3].value == 0.8)
    }

    @Test("Glue supports undo restoring original containers")
    @MainActor
    func glueUndo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)

        let c1 = Container(
            name: "A",
            startBar: 1.0,
            lengthBars: 4.0,
            midiSequence: MIDISequence()
        )
        let c2 = Container(
            name: "B",
            startBar: 5.0,
            lengthBars: 4.0,
            midiSequence: MIDISequence()
        )
        let originalIDs = Set([c1.id, c2.id])
        vm.project.songs[0].tracks[0].containers = [c1, c2]

        vm.glueContainers(containerIDs: originalIDs)
        #expect(vm.project.songs[0].tracks[0].containers.count == 1)

        vm.undoManager?.undo()
        let restored = vm.project.songs[0].tracks[0].containers
        #expect(restored.count == 2)
        let restoredIDs = Set(restored.map(\.id))
        #expect(restoredIDs == originalIDs)
    }
}
