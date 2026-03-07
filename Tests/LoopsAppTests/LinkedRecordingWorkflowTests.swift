import Testing
@testable import LoopsApp
@testable import LoopsCore

@Suite("Linked Recording Workflow Tests")
struct LinkedRecordingWorkflowTests {

    @Test("Recording MIDI into linked clone writes parent clip by default")
    @MainActor
    func midiRecordingWritesParentClip() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id
        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        vm.beginMIDIRecordingSession()
        vm.recordMIDINotes(containerID: cloneID, notes: [
            MIDINoteEvent(pitch: 60, velocity: 100, startBeat: 1.0, duration: 0.5),
        ])
        vm.endMIDIRecordingSession()

        let parent = vm.findContainer(id: parentID)!
        let clone = vm.findContainer(id: cloneID)!
        #expect(parent.midiSequence?.notes.count == 1)
        #expect(clone.midiSequence == nil)
        #expect(!clone.overriddenFields.contains(.midiSequence))
        #expect(vm.resolveContainer(clone).midiSequence?.notes.count == 1)
    }

    @Test("Recording MIDI into overridden clone stays local")
    @MainActor
    func midiRecordingRespectsCloneOverride() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .midi)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id
        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!

        vm.addMIDINote(containerID: cloneID, note: MIDINoteEvent(pitch: 64, startBeat: 0.0, duration: 1.0))
        vm.beginMIDIRecordingSession()
        vm.recordMIDINotes(containerID: cloneID, notes: [
            MIDINoteEvent(pitch: 67, velocity: 96, startBeat: 2.0, duration: 0.5),
        ])
        vm.endMIDIRecordingSession()

        let parent = vm.findContainer(id: parentID)!
        let clone = vm.findContainer(id: cloneID)!
        #expect(parent.midiSequence == nil)
        #expect(clone.midiSequence?.notes.count == 2)
        #expect(clone.overriddenFields.contains(.midiSequence))
    }

    @Test("Automation recording into linked clone writes parent lane by default")
    @MainActor
    func automationRecordingWritesParentClip() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id
        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!
        let clonePath = EffectPath(trackID: trackID, containerID: cloneID, effectIndex: 0, parameterAddress: 42)

        vm.beginAutomationWriteSession()
        vm.recordAutomationValue(path: clonePath, playbackBar: 5.5, value: 0.75)
        vm.endAutomationWriteSession()

        let parent = vm.findContainer(id: parentID)!
        let clone = vm.findContainer(id: cloneID)!
        #expect(parent.automationLanes.count == 1)
        #expect(parent.automationLanes[0].targetPath.containerID == parentID)
        #expect(abs(parent.automationLanes[0].breakpoints[0].position - 0.5) < 0.001)
        #expect(clone.automationLanes.isEmpty)
        #expect(!clone.overriddenFields.contains(.automation))
        #expect(vm.resolveContainer(clone).automationLanes[0].targetPath.containerID == cloneID)
        #expect(vm.lastTouchedAutomationPath?.containerID == parentID)
    }

    @Test("Automation recording into overridden clone stays local")
    @MainActor
    func automationRecordingRespectsCloneOverride() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let parentID = vm.project.songs[0].tracks[0].containers[0].id
        let cloneID = vm.cloneContainer(trackID: trackID, containerID: parentID, newStartBar: 5)!
        let clonePath = EffectPath(trackID: trackID, containerID: cloneID, effectIndex: 0, parameterAddress: 42)
        vm.addAutomationLane(containerID: cloneID, lane: AutomationLane(targetPath: clonePath))

        vm.beginAutomationWriteSession()
        vm.recordAutomationValue(path: clonePath, playbackBar: 6.0, value: 0.33)
        vm.endAutomationWriteSession()

        let parent = vm.findContainer(id: parentID)!
        let clone = vm.findContainer(id: cloneID)!
        #expect(parent.automationLanes.isEmpty)
        #expect(clone.automationLanes.count == 1)
        #expect(clone.overriddenFields.contains(.automation))
        #expect(abs(clone.automationLanes[0].breakpoints[0].position - 1.0) < 0.001)
    }

    @Test("Track automation recording writes absolute timeline positions")
    @MainActor
    func trackAutomationRecordingUsesAbsoluteBars() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id

        vm.beginAutomationWriteSession()
        vm.recordAutomationValue(path: .trackVolume(trackID: trackID), playbackBar: 9.0, value: 0.4)
        vm.endAutomationWriteSession()

        let track = vm.project.songs[0].tracks[0]
        #expect(track.trackAutomationLanes.count == 1)
        #expect(abs(track.trackAutomationLanes[0].breakpoints[0].position - 9.0) < 0.001)
        #expect(abs(track.trackAutomationLanes[0].breakpoints[0].value - 0.4) < 0.001)
    }

    @Test("Linked automation recording retargets effect path to parent track")
    @MainActor
    func automationRecordingRetargetsCrossTrackCloneToParentTrack() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        vm.addTrack(kind: .audio)

        let sourceTrackID = vm.project.songs[0].tracks[0].id
        let cloneTrackID = vm.project.songs[0].tracks[1].id
        _ = vm.addContainer(trackID: sourceTrackID, startBar: 1, lengthBars: 4)
        let parent = vm.project.songs[0].tracks[0].containers[0]

        let clone = Container(
            name: "Linked Copy",
            startBar: 5,
            lengthBars: 4,
            parentContainerID: parent.id
        )
        vm.project.songs[0].tracks[1].containers.append(clone)

        let clonePath = EffectPath(trackID: cloneTrackID, containerID: clone.id, effectIndex: 0, parameterAddress: 77)
        vm.beginAutomationWriteSession()
        vm.recordAutomationValue(path: clonePath, playbackBar: 5.25, value: 0.6)
        vm.endAutomationWriteSession()

        let updatedParent = vm.findContainer(id: parent.id)!
        #expect(updatedParent.automationLanes.count == 1)
        #expect(updatedParent.automationLanes[0].targetPath.trackID == sourceTrackID)
        #expect(updatedParent.automationLanes[0].targetPath.containerID == parent.id)
        #expect(vm.lastTouchedAutomationPath?.trackID == sourceTrackID)
        #expect(vm.lastTouchedAutomationPath?.containerID == parent.id)
    }
}
