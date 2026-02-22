import Testing
import Foundation
@testable import LoopsApp
@testable import LoopsCore

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
}
