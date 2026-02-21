import Testing
import Foundation
import AVFoundation
@testable import LoopsEngine
@testable import LoopsCore

@Suite("RecordingManager Tests")
struct RecordingManagerTests {

    private func temporaryAudioDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("test-audio-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("RecordingManager starts not recording")
    func initialState() async {
        let dir = temporaryAudioDir()
        defer { cleanup(dir) }
        let manager = RecordingManager(audioDirURL: dir)
        let isRecording = await manager.isRecording
        #expect(!isRecording)
    }

    @Test("CAFWriter creates file at specified URL")
    func cafWriterCreatesFile() throws {
        let dir = temporaryAudioDir()
        defer { cleanup(dir) }
        let url = dir.appendingPathComponent("test.caf")
        let writer = try CAFWriter(url: url, sampleRate: 44100.0)
        let _ = writer.close()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("CAFWriter tracks sample count")
    func cafWriterSampleCount() throws {
        let dir = temporaryAudioDir()
        defer { cleanup(dir) }
        let url = dir.appendingPathComponent("test.caf")
        let writer = try CAFWriter(url: url, sampleRate: 44100.0)
        // Create a buffer with 1024 frames
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        try writer.write(buffer)
        let finalCount = writer.close()
        #expect(finalCount == 1024)
    }

    @Test("Container record arm toggle")
    @MainActor
    func containerRecordArmToggle() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        #expect(!vm.project.songs[0].tracks[0].containers[0].isRecordArmed)
        vm.toggleContainerRecordArm(trackID: trackID, containerID: containerID)
        #expect(vm.project.songs[0].tracks[0].containers[0].isRecordArmed)
        vm.toggleContainerRecordArm(trackID: trackID, containerID: containerID)
        #expect(!vm.project.songs[0].tracks[0].containers[0].isRecordArmed)
    }

    @Test("Set container recording updates model")
    @MainActor
    func setContainerRecording() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        let recording = SourceRecording(
            filename: "test.caf",
            sampleRate: 44100.0,
            sampleCount: 88200
        )

        vm.setContainerRecording(trackID: trackID, containerID: containerID, recording: recording)

        #expect(vm.project.songs[0].tracks[0].containers[0].sourceRecordingID == recording.id)
        #expect(vm.project.sourceRecordings[recording.id] != nil)
        #expect(!vm.project.songs[0].tracks[0].containers[0].isRecordArmed)
    }
}
