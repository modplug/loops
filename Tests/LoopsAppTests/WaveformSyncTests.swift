import Foundation
import Testing
@testable import LoopsApp
@testable import LoopsCore
@testable import LoopsEngine

@Suite("Waveform Sync Tests")
struct WaveformSyncTests {

    // MARK: - Peak Slicing with audioStartOffset

    @Test("Peak slicing with audioStartOffset returns correct range")
    @MainActor
    func peakSlicingWithOffset() throws {
        let project = makeProjectWithRecording(
            totalPeaks: 1000,
            durationSeconds: 10.0,
            bpm: 120,
            beatsPerBar: 4,
            containerStartBar: 1.0,
            containerLengthBars: 3.0,
            audioStartOffset: 2.0
        )
        let vm = ProjectViewModel(project: project)
        vm.currentSongID = project.songs[0].id

        let container = project.songs[0].tracks[0].containers[0]
        let peaks = vm.waveformPeaks(for: container)

        #expect(peaks != nil, "Should return peaks for container with recording")

        guard let peaks else { return }

        // File duration: 10s at 120 BPM, 4 beats/bar = 2s/bar → 5 bars total
        // audioStartOffset = 2.0 bars → startIdx = (2.0/5.0) * 1000 = 400
        // lengthBars = 3.0 bars → endIdx = ((2.0+3.0)/5.0) * 1000 = 1000
        // So we expect 600 peaks (indices 400..<1000)
        #expect(peaks.count == 600,
                "Expected 600 peaks for 3-bar window starting at offset 2, got \(peaks.count)")
    }

    @Test("Peak slicing with zero offset returns all peaks")
    @MainActor
    func peakSlicingNoOffset() throws {
        let project = makeProjectWithRecording(
            totalPeaks: 500,
            durationSeconds: 10.0,
            bpm: 120,
            beatsPerBar: 4,
            containerStartBar: 1.0,
            containerLengthBars: 5.0,
            audioStartOffset: 0.0
        )
        let vm = ProjectViewModel(project: project)
        vm.currentSongID = project.songs[0].id

        let container = project.songs[0].tracks[0].containers[0]
        let peaks = vm.waveformPeaks(for: container)

        #expect(peaks != nil)
        // Container covers full file (5 bars = 10s at 120bpm) → all 500 peaks
        #expect(peaks?.count == 500,
                "Full-file container should return all 500 peaks, got \(peaks?.count ?? 0)")
    }

    @Test("Peak slicing with offset near end returns remainder")
    @MainActor
    func peakSlicingOffsetNearEnd() throws {
        let project = makeProjectWithRecording(
            totalPeaks: 1000,
            durationSeconds: 10.0,
            bpm: 120,
            beatsPerBar: 4,
            containerStartBar: 1.0,
            containerLengthBars: 1.0,
            audioStartOffset: 4.0  // starts at bar 4 of 5-bar file
        )
        let vm = ProjectViewModel(project: project)
        vm.currentSongID = project.songs[0].id

        let container = project.songs[0].tracks[0].containers[0]
        let peaks = vm.waveformPeaks(for: container)

        #expect(peaks != nil)
        // offset=4.0, length=1.0, total=5.0 bars
        // startIdx = (4.0/5.0)*1000 = 800, endIdx = (5.0/5.0)*1000 = 1000
        // → 200 peaks
        #expect(peaks?.count == 200,
                "Expected 200 peaks for last bar, got \(peaks?.count ?? 0)")
    }

    @Test("recordingDurationBars returns correct value")
    @MainActor
    func recordingDurationBarsCorrect() throws {
        let project = makeProjectWithRecording(
            totalPeaks: 100,
            durationSeconds: 10.0,
            bpm: 120,
            beatsPerBar: 4,
            containerStartBar: 1.0,
            containerLengthBars: 5.0,
            audioStartOffset: 0.0
        )
        let vm = ProjectViewModel(project: project)
        vm.currentSongID = project.songs[0].id

        let container = project.songs[0].tracks[0].containers[0]
        let duration = vm.recordingDurationBars(for: container)

        #expect(duration != nil)
        // 10s at 120bpm, 4 beats/bar → 2s/bar → 5.0 bars
        #expect(abs((duration ?? 0) - 5.0) < 0.01,
                "Expected 5.0 bars, got \(duration ?? 0)")
    }

    // MARK: - Helpers

    private func makeProjectWithRecording(
        totalPeaks: Int,
        durationSeconds: Double,
        bpm: Double,
        beatsPerBar: Int,
        containerStartBar: Double,
        containerLengthBars: Double,
        audioStartOffset: Double
    ) -> Project {
        let recordingID = ID<SourceRecording>()
        let peaks = (0..<totalPeaks).map { Float(sin(Double($0) * 0.05) * 0.8) }

        let sampleRate: Double = 44100
        let recording = SourceRecording(
            id: recordingID,
            filename: "test.wav",
            sampleRate: sampleRate,
            sampleCount: Int64(durationSeconds * sampleRate),
            waveformPeaks: peaks
        )

        var container = Container(
            name: "Test Container",
            startBar: containerStartBar,
            lengthBars: containerLengthBars
        )
        container.sourceRecordingID = recordingID
        container.audioStartOffset = audioStartOffset

        let track = Track(
            name: "Audio 1",
            kind: .audio,
            containers: [container]
        )

        var song = Song(name: "Test Song")
        song.tempo.bpm = bpm
        song.timeSignature = TimeSignature(beatsPerBar: beatsPerBar)
        song.tracks = [track]

        var project = Project()
        project.songs = [song]
        project.sourceRecordings = [recordingID: recording]

        return project
    }
}
