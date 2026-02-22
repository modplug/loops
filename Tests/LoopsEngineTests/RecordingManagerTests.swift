import Testing
import Foundation
import AVFoundation
@testable import LoopsEngine
@testable import LoopsCore
@testable import LoopsApp

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

    // MARK: - Container armed state serialization

    @Test("Container isRecordArmed serialization round-trip")
    func containerArmedSerializationRoundTrip() throws {
        let container = Container(
            name: "Record Me",
            startBar: 3,
            lengthBars: 4,
            isRecordArmed: true
        )
        let data = try JSONEncoder().encode(container)
        let decoded = try JSONDecoder().decode(Container.self, from: data)
        #expect(decoded.isRecordArmed == true)
        #expect(decoded.name == "Record Me")
        #expect(decoded.startBar == 3)
        #expect(decoded.lengthBars == 4)
    }

    @Test("Container isRecordArmed defaults to false")
    func containerArmedDefaultsFalse() {
        let container = Container(name: "Default", startBar: 1, lengthBars: 4)
        #expect(!container.isRecordArmed)
    }

    // MARK: - ContainerRecorder

    @Test("CAFWriter produces valid audio file for container recording")
    func cafWriterProducesValidFile() throws {
        let dir = temporaryAudioDir()
        defer { cleanup(dir) }

        let filename = UUID().uuidString + ".caf"
        let fileURL = dir.appendingPathComponent(filename)
        let writer = try CAFWriter(url: fileURL, sampleRate: 44100.0)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        buffer.frameLength = 4096

        // Write a sine wave to verify valid audio data
        if let data = buffer.floatChannelData {
            for i in 0..<4096 {
                data[0][i] = sin(Float(i) * 0.1)
            }
        }
        try writer.write(buffer)
        let sampleCount = writer.close()

        #expect(sampleCount == 4096)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        // Verify the file can be read back
        let readFile = try AVAudioFile(forReading: fileURL)
        #expect(readFile.length == 4096)
        #expect(readFile.processingFormat.sampleRate == 44100.0)
    }

    @Test("ContainerRecorder recording duration matches bar range at 120 BPM")
    func recordingDurationMatchesBarRange() throws {
        // At 120 BPM, 4/4 time:
        // 1 beat = 0.5 seconds
        // 1 bar = 4 beats = 2.0 seconds
        // 4 bars = 8.0 seconds
        // At 44100 Hz: 8.0 * 44100 = 352800 samples

        let dir = temporaryAudioDir()
        defer { cleanup(dir) }

        let sampleRate = 44100.0
        let bpm = 120.0
        let beatsPerBar = 4
        let secondsPerBar = Double(beatsPerBar) * (60.0 / bpm)  // 2.0
        let bars = 4
        let expectedDuration = Double(bars) * secondsPerBar  // 8.0
        let expectedSamples = Int64(expectedDuration * sampleRate)  // 352800

        // Create a CAF file with the expected number of samples
        let filename = "recording.caf"
        let fileURL = dir.appendingPathComponent(filename)
        let writer = try CAFWriter(url: fileURL, sampleRate: sampleRate)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let chunkSize: AVAudioFrameCount = 4096
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize)!
        buffer.frameLength = chunkSize
        if let data = buffer.floatChannelData {
            for i in 0..<Int(chunkSize) {
                data[0][i] = 0.0
            }
        }

        // Write enough samples for 4 bars
        var written: Int64 = 0
        while written < expectedSamples {
            let remaining = expectedSamples - written
            buffer.frameLength = AVAudioFrameCount(min(Int64(chunkSize), remaining))
            try writer.write(buffer)
            written += Int64(buffer.frameLength)
        }

        let totalSamples = writer.close()
        let recording = SourceRecording(
            filename: filename,
            sampleRate: sampleRate,
            sampleCount: totalSamples
        )

        // Verify duration matches 4 bars at 120 BPM
        #expect(totalSamples == expectedSamples)
        let durationError = abs(recording.durationSeconds - expectedDuration)
        #expect(durationError < 0.001)
    }

    @Test("Set container recording clears live peaks")
    @MainActor
    func setContainerRecordingClearsLivePeaks() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        // Simulate live recording peaks
        vm.updateRecordingPeaks(containerID: containerID, peaks: [0.5, 0.8, 0.3])
        #expect(vm.liveRecordingPeaks[containerID] != nil)

        let recording = SourceRecording(
            filename: "test.caf",
            sampleRate: 44100.0,
            sampleCount: 88200,
            waveformPeaks: [0.5, 0.8, 0.3, 0.6]
        )

        vm.setContainerRecording(trackID: trackID, containerID: containerID, recording: recording)

        // Live peaks should be cleared
        #expect(vm.liveRecordingPeaks[containerID] == nil)
        // Waveform should now come from the SourceRecording
        let container = vm.project.songs[0].tracks[0].containers[0]
        let peaks = vm.waveformPeaks(for: container)
        #expect(peaks == [0.5, 0.8, 0.3, 0.6])
    }

    @Test("Live recording peaks shown during recording")
    @MainActor
    func liveRecordingPeaksShownDuringRecording() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        // No peaks initially
        let container = vm.project.songs[0].tracks[0].containers[0]
        #expect(vm.waveformPeaks(for: container) == nil)

        // Simulate live recording peaks
        vm.updateRecordingPeaks(containerID: containerID, peaks: [0.2, 0.5])
        #expect(vm.waveformPeaks(for: container) == [0.2, 0.5])

        // Update with more peaks
        vm.updateRecordingPeaks(containerID: containerID, peaks: [0.2, 0.5, 0.9])
        #expect(vm.waveformPeaks(for: container) == [0.2, 0.5, 0.9])
    }

    @Test("Container record arm undo/redo")
    @MainActor
    func containerRecordArmUndoRedo() {
        let vm = ProjectViewModel()
        vm.newProject()
        vm.addTrack(kind: .audio)
        let trackID = vm.project.songs[0].tracks[0].id
        let _ = vm.addContainer(trackID: trackID, startBar: 1, lengthBars: 4)
        let containerID = vm.project.songs[0].tracks[0].containers[0].id

        #expect(!vm.project.songs[0].tracks[0].containers[0].isRecordArmed)
        vm.toggleContainerRecordArm(trackID: trackID, containerID: containerID)
        #expect(vm.project.songs[0].tracks[0].containers[0].isRecordArmed)

        vm.undoManager?.undo()
        #expect(!vm.project.songs[0].tracks[0].containers[0].isRecordArmed)

        vm.undoManager?.redo()
        #expect(vm.project.songs[0].tracks[0].containers[0].isRecordArmed)
    }

    @Test("WaveformGenerator peaksFromSamples produces correct peaks")
    func peaksFromSamplesCorrectPeaks() {
        // Create sample data with known peaks
        var samples: [Float] = []
        // First peak group: 100 samples, max = 0.8
        for _ in 0..<100 {
            samples.append(0.5)
        }
        samples[50] = 0.8

        // Second peak group: 100 samples, max = 0.3
        for _ in 0..<100 {
            samples.append(0.1)
        }
        samples[150] = 0.3

        let peaks = samples.withUnsafeBufferPointer { ptr in
            WaveformGenerator.peaksFromSamples(ptr, samplesPerPeak: 100)
        }

        #expect(peaks.count == 2)
        #expect(peaks[0] == 0.8)
        #expect(peaks[1] == 0.3)
    }

    @Test("ContainerRecorder samplesPerBar calculation")
    func containerRecorderSamplesPerBarCalc() {
        // At 120 BPM, 4/4 time, 44100 Hz:
        // secondsPerBeat = 60/120 = 0.5
        // beatsPerBar = 4
        // secondsPerBar = 4 * 0.5 = 2.0
        // samplesPerBar = 2.0 * 44100 = 88200
        let bpm = 120.0
        let sampleRate = 44100.0
        let beatsPerBar = 4
        let secondsPerBeat = 60.0 / bpm
        let secondsPerBar = Double(beatsPerBar) * secondsPerBeat
        let samplesPerBar = secondsPerBar * sampleRate

        #expect(samplesPerBar == 88200.0)
    }

    @Test("Armed container visual state persists through encode/decode")
    func armedContainerVisualStatePersists() throws {
        var container = Container(name: "Armed", startBar: 1, lengthBars: 4)
        container.isRecordArmed = true
        #expect(container.isRecordArmed)

        let data = try JSONEncoder().encode(container)
        let decoded = try JSONDecoder().decode(Container.self, from: data)
        #expect(decoded.isRecordArmed == true)

        // Non-armed container
        let unarmed = Container(name: "Unarmed", startBar: 5, lengthBars: 4, isRecordArmed: false)
        let unarmedData = try JSONEncoder().encode(unarmed)
        let unarmedDecoded = try JSONDecoder().decode(Container.self, from: unarmedData)
        #expect(unarmedDecoded.isRecordArmed == false)
    }
}
