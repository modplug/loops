import Testing
import Foundation
import AVFoundation
@testable import LoopsEngine
@testable import LoopsCore

@Suite("OfflineRenderer Tests")
struct OfflineRendererTests {

    // MARK: - ExportFormat

    @Test("Export formats have correct extensions")
    func formatExtensions() {
        #expect(ExportFormat.wav16.fileExtension == "wav")
        #expect(ExportFormat.wav24.fileExtension == "wav")
        #expect(ExportFormat.aiff.fileExtension == "aiff")
    }

    @Test("Export formats have correct bit depths")
    func formatBitDepths() {
        #expect(ExportFormat.wav16.bitDepth == 16)
        #expect(ExportFormat.wav24.bitDepth == 24)
        #expect(ExportFormat.aiff.bitDepth == 24)
    }

    @Test("Export formats are not float")
    func formatIsNotFloat() {
        for format in ExportFormat.allCases {
            #expect(!format.isFloat)
        }
    }

    @Test("All export formats have allCases")
    func allExportFormats() {
        #expect(ExportFormat.allCases.count == 3)
    }

    // MARK: - ExportSampleRate

    @Test("Sample rate values")
    func sampleRateValues() {
        #expect(ExportSampleRate.rate44100.rawValue == 44100)
        #expect(ExportSampleRate.rate48000.rawValue == 48000)
    }

    @Test("Sample rate display names")
    func sampleRateDisplayNames() {
        #expect(ExportSampleRate.rate44100.displayName == "44.1 kHz")
        #expect(ExportSampleRate.rate48000.displayName == "48 kHz")
    }

    // MARK: - Song Length Calculation

    @Test("Empty song has zero length")
    func emptySongLength() {
        let song = Song(name: "Test", tracks: [])
        #expect(OfflineRenderer.songLengthBars(song: song) == 0)
    }

    @Test("Song length from single container")
    func singleContainerLength() {
        let container = Container(name: "C1", startBar: 1, lengthBars: 4)
        let track = Track(name: "T1", kind: .audio, containers: [container])
        let song = Song(name: "Test", tracks: [track])
        // endBar = 5, so songLengthBars = 5 - 1 = 4
        #expect(OfflineRenderer.songLengthBars(song: song) == 4)
    }

    @Test("Song length from multiple containers")
    func multipleContainerLength() {
        let c1 = Container(name: "C1", startBar: 1, lengthBars: 4)
        let c2 = Container(name: "C2", startBar: 5, lengthBars: 4) // endBar = 9
        let track = Track(name: "T1", kind: .audio, containers: [c1, c2])
        let song = Song(name: "Test", tracks: [track])
        #expect(OfflineRenderer.songLengthBars(song: song) == 8)
    }

    @Test("Song length across multiple tracks")
    func multiTrackLength() {
        let c1 = Container(name: "C1", startBar: 1, lengthBars: 2) // endBar = 3
        let c2 = Container(name: "C2", startBar: 1, lengthBars: 6) // endBar = 7
        let track1 = Track(name: "T1", kind: .audio, containers: [c1])
        let track2 = Track(name: "T2", kind: .audio, containers: [c2])
        let song = Song(name: "Test", tracks: [track1, track2])
        #expect(OfflineRenderer.songLengthBars(song: song) == 6)
    }

    @Test("Track with no containers adds zero length")
    func emptyTrackLength() {
        let emptyTrack = Track(name: "Empty", kind: .audio, containers: [])
        let c1 = Container(name: "C1", startBar: 1, lengthBars: 4)
        let track = Track(name: "T1", kind: .audio, containers: [c1])
        let song = Song(name: "Test", tracks: [emptyTrack, track])
        #expect(OfflineRenderer.songLengthBars(song: song) == 4)
    }

    // MARK: - Samples Per Bar Calculation

    @Test("Samples per bar at 120 BPM, 4/4, 44100 Hz")
    func samplesPerBar120bpm() {
        let spb = OfflineRenderer.samplesPerBar(
            bpm: 120,
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            sampleRate: 44100
        )
        // 4 beats per bar * (60/120) seconds per beat * 44100 = 4 * 0.5 * 44100 = 88200
        #expect(spb == 88200.0)
    }

    @Test("Samples per bar at 60 BPM, 3/4, 48000 Hz")
    func samplesPerBar60bpm() {
        let spb = OfflineRenderer.samplesPerBar(
            bpm: 60,
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
            sampleRate: 48000
        )
        // 3 beats * (60/60) * 48000 = 3 * 1 * 48000 = 144000
        #expect(spb == 144000.0)
    }

    // MARK: - ExportConfiguration

    @Test("Export configuration holds values")
    func exportConfigValues() {
        let url = URL(fileURLWithPath: "/tmp/test.wav")
        let config = ExportConfiguration(
            format: .wav16,
            sampleRate: .rate44100,
            destinationURL: url
        )
        #expect(config.format == .wav16)
        #expect(config.sampleRate == .rate44100)
        #expect(config.destinationURL == url)
    }

    // MARK: - Render Tests

    @Test("Render empty song throws error")
    func renderEmptySong() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let renderer = OfflineRenderer(audioDirURL: tempDir)
        let song = Song(name: "Empty", tracks: [])
        let destURL = tempDir.appendingPathComponent("out.wav")
        let config = ExportConfiguration(format: .wav24, sampleRate: .rate44100, destinationURL: destURL)

        await #expect(throws: LoopsError.self) {
            try await renderer.render(song: song, sourceRecordings: [:], config: config)
        }
    }

    @Test("Render song with recording creates output file")
    func renderWithRecording() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-render-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a test audio file
        let audioURL = tempDir.appendingPathComponent("test.caf")
        let sampleRate: Double = 44100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let durationFrames = AVAudioFrameCount(sampleRate * 2.0) // 2 seconds
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: durationFrames)!
        sourceBuffer.frameLength = durationFrames
        if let data = sourceBuffer.floatChannelData {
            for i in 0..<Int(durationFrames) {
                data[0][i] = sin(Float(i) * 2.0 * .pi * 440.0 / Float(sampleRate)) * 0.5
            }
        }
        let sourceFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        try sourceFile.write(from: sourceBuffer)

        // Build model
        let recording = SourceRecording(
            filename: "test.caf",
            sampleRate: sampleRate,
            sampleCount: Int64(durationFrames)
        )
        let container = Container(
            name: "C1",
            startBar: 1,
            lengthBars: 1,
            sourceRecordingID: recording.id
        )
        let track = Track(name: "T1", kind: .audio, containers: [container])
        let song = Song(
            name: "Test",
            tempo: Tempo(bpm: 120),
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            tracks: [track]
        )

        let destURL = tempDir.appendingPathComponent("output.wav")
        let config = ExportConfiguration(format: .wav24, sampleRate: .rate44100, destinationURL: destURL)

        let renderer = OfflineRenderer(audioDirURL: tempDir)
        let resultURL = try await renderer.render(
            song: song,
            sourceRecordings: [recording.id: recording],
            config: config
        )

        #expect(FileManager.default.fileExists(atPath: resultURL.path))

        // Verify the output file is readable
        let outputFile = try AVAudioFile(forReading: resultURL)
        #expect(outputFile.length > 0)
        #expect(outputFile.fileFormat.sampleRate == 44100)
        #expect(outputFile.fileFormat.channelCount == 2) // stereo output
    }

    @Test("Render reports progress")
    func renderReportsProgress() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a test audio file
        let audioURL = tempDir.appendingPathComponent("test.caf")
        let sampleRate: Double = 44100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let durationFrames = AVAudioFrameCount(sampleRate * 1.0)
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: durationFrames)!
        sourceBuffer.frameLength = durationFrames
        if let data = sourceBuffer.floatChannelData {
            for i in 0..<Int(durationFrames) {
                data[0][i] = 0.1
            }
        }
        let sourceFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        try sourceFile.write(from: sourceBuffer)

        let recording = SourceRecording(
            filename: "test.caf",
            sampleRate: sampleRate,
            sampleCount: Int64(durationFrames)
        )
        let container = Container(name: "C1", startBar: 1, lengthBars: 2, sourceRecordingID: recording.id)
        let track = Track(name: "T1", kind: .audio, containers: [container])
        let song = Song(
            name: "Test",
            tempo: Tempo(bpm: 120),
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            tracks: [track]
        )

        let destURL = tempDir.appendingPathComponent("output.wav")
        let config = ExportConfiguration(format: .wav16, sampleRate: .rate44100, destinationURL: destURL)

        var progressValues: [Double] = []
        let renderer = OfflineRenderer(audioDirURL: tempDir)
        let _ = try await renderer.render(
            song: song,
            sourceRecordings: [recording.id: recording],
            config: config
        ) { progress in
            progressValues.append(progress)
        }

        #expect(!progressValues.isEmpty)
        // Last progress should be 1.0
        #expect(progressValues.last! >= 0.99)
        // Progress should be monotonically increasing
        for i in 1..<progressValues.count {
            #expect(progressValues[i] >= progressValues[i - 1])
        }
    }

    @Test("Muted tracks are excluded from render")
    func mutedTrackExcluded() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-muted-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a loud test audio file
        let audioURL = tempDir.appendingPathComponent("loud.caf")
        let sampleRate: Double = 44100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let durationFrames = AVAudioFrameCount(sampleRate * 1.0)
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: durationFrames)!
        sourceBuffer.frameLength = durationFrames
        if let data = sourceBuffer.floatChannelData {
            for i in 0..<Int(durationFrames) {
                data[0][i] = 0.9
            }
        }
        let sourceFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        try sourceFile.write(from: sourceBuffer)

        let recording = SourceRecording(
            filename: "loud.caf",
            sampleRate: sampleRate,
            sampleCount: Int64(durationFrames)
        )
        let container = Container(name: "C1", startBar: 1, lengthBars: 1, sourceRecordingID: recording.id)

        // Muted track
        let mutedTrack = Track(name: "Muted", kind: .audio, isMuted: true, containers: [container])
        let song = Song(
            name: "Test",
            tempo: Tempo(bpm: 120),
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            tracks: [mutedTrack]
        )

        let destURL = tempDir.appendingPathComponent("output.wav")
        let config = ExportConfiguration(format: .wav16, sampleRate: .rate44100, destinationURL: destURL)

        let renderer = OfflineRenderer(audioDirURL: tempDir)
        let resultURL = try await renderer.render(
            song: song,
            sourceRecordings: [recording.id: recording],
            config: config
        )

        // Read output - should be silent (all zeros)
        let outputFile = try AVAudioFile(forReading: resultURL)
        let readFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false)!
        let readBuffer = AVAudioPCMBuffer(pcmFormat: readFormat, frameCapacity: AVAudioFrameCount(outputFile.length))!
        try outputFile.read(into: readBuffer)

        var maxSample: Float = 0
        if let data = readBuffer.floatChannelData {
            for ch in 0..<2 {
                for i in 0..<Int(readBuffer.frameLength) {
                    maxSample = max(maxSample, abs(data[ch][i]))
                }
            }
        }
        #expect(maxSample < 0.001) // Effectively silent
    }

    @Test("AIFF export creates valid file")
    func aiffExport() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-aiff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let audioURL = tempDir.appendingPathComponent("test.caf")
        let sampleRate: Double = 48000
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let durationFrames = AVAudioFrameCount(sampleRate * 0.5)
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: durationFrames)!
        sourceBuffer.frameLength = durationFrames
        if let data = sourceBuffer.floatChannelData {
            for i in 0..<Int(durationFrames) {
                data[0][i] = 0.3
            }
        }
        let sourceFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        try sourceFile.write(from: sourceBuffer)

        let recording = SourceRecording(
            filename: "test.caf",
            sampleRate: sampleRate,
            sampleCount: Int64(durationFrames)
        )
        let container = Container(name: "C1", startBar: 1, lengthBars: 1, sourceRecordingID: recording.id)
        let track = Track(name: "T1", kind: .audio, containers: [container])
        let song = Song(
            name: "Test",
            tempo: Tempo(bpm: 120),
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            tracks: [track]
        )

        let destURL = tempDir.appendingPathComponent("output.aiff")
        let config = ExportConfiguration(format: .aiff, sampleRate: .rate48000, destinationURL: destURL)

        let renderer = OfflineRenderer(audioDirURL: tempDir)
        let resultURL = try await renderer.render(
            song: song,
            sourceRecordings: [recording.id: recording],
            config: config
        )

        let outputFile = try AVAudioFile(forReading: resultURL)
        #expect(outputFile.length > 0)
        #expect(outputFile.fileFormat.sampleRate == 48000)
    }

    // MARK: - Fade Tests

    @Test("Render with enter fade applies gain ramp")
    func renderWithEnterFade() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-fade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleRate: Double = 44100
        let audioURL = tempDir.appendingPathComponent("tone.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        // Create 2 bars of constant amplitude
        let spb = OfflineRenderer.samplesPerBar(
            bpm: 120, timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4), sampleRate: sampleRate
        )
        let durationFrames = AVAudioFrameCount(spb * 2)
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: durationFrames)!
        sourceBuffer.frameLength = durationFrames
        if let data = sourceBuffer.floatChannelData {
            for i in 0..<Int(durationFrames) { data[0][i] = 0.8 }
        }
        let sourceFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        try sourceFile.write(from: sourceBuffer)

        let recording = SourceRecording(filename: "tone.caf", sampleRate: sampleRate, sampleCount: Int64(durationFrames))
        let container = Container(
            name: "Faded",
            startBar: 1,
            lengthBars: 2,
            sourceRecordingID: recording.id,
            enterFade: FadeSettings(duration: 1.0, curve: .linear)
        )
        let track = Track(name: "T1", kind: .audio, containers: [container])
        let song = Song(
            name: "Test", tempo: Tempo(bpm: 120),
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4), tracks: [track]
        )

        let destURL = tempDir.appendingPathComponent("output.wav")
        let config = ExportConfiguration(format: .wav24, sampleRate: .rate44100, destinationURL: destURL)
        let renderer = OfflineRenderer(audioDirURL: tempDir)
        let resultURL = try await renderer.render(
            song: song, sourceRecordings: [recording.id: recording], config: config
        )

        let outputFile = try AVAudioFile(forReading: resultURL)
        let readFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!
        let readBuffer = AVAudioPCMBuffer(pcmFormat: readFormat, frameCapacity: AVAudioFrameCount(outputFile.length))!
        try outputFile.read(into: readBuffer)

        guard let outData = readBuffer.floatChannelData else {
            Issue.record("No output data")
            return
        }

        let fadeSamples = Int(spb) // 1 bar fade
        // First sample should be near zero (fade starts at 0)
        #expect(abs(outData[0][0]) < 0.01)
        // Sample at ~50% of fade should be near 50% of full amplitude
        let midFade = fadeSamples / 2
        let midValue = abs(outData[0][midFade])
        #expect(midValue > 0.2 && midValue < 0.6)
        // Sample after fade should be at full amplitude
        let afterFade = fadeSamples + 100
        #expect(abs(outData[0][afterFade]) > 0.7)
    }

    @Test("Render with exit fade applies gain ramp down")
    func renderWithExitFade() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-exitfade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleRate: Double = 44100
        let audioURL = tempDir.appendingPathComponent("tone.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let spb = OfflineRenderer.samplesPerBar(
            bpm: 120, timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4), sampleRate: sampleRate
        )
        let durationFrames = AVAudioFrameCount(spb * 2)
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: durationFrames)!
        sourceBuffer.frameLength = durationFrames
        if let data = sourceBuffer.floatChannelData {
            for i in 0..<Int(durationFrames) { data[0][i] = 0.8 }
        }
        let sourceFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        try sourceFile.write(from: sourceBuffer)

        let recording = SourceRecording(filename: "tone.caf", sampleRate: sampleRate, sampleCount: Int64(durationFrames))
        let container = Container(
            name: "Faded",
            startBar: 1,
            lengthBars: 2,
            sourceRecordingID: recording.id,
            exitFade: FadeSettings(duration: 1.0, curve: .linear)
        )
        let track = Track(name: "T1", kind: .audio, containers: [container])
        let song = Song(
            name: "Test", tempo: Tempo(bpm: 120),
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4), tracks: [track]
        )

        let destURL = tempDir.appendingPathComponent("output.wav")
        let config = ExportConfiguration(format: .wav24, sampleRate: .rate44100, destinationURL: destURL)
        let renderer = OfflineRenderer(audioDirURL: tempDir)
        let resultURL = try await renderer.render(
            song: song, sourceRecordings: [recording.id: recording], config: config
        )

        let outputFile = try AVAudioFile(forReading: resultURL)
        let readFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!
        let readBuffer = AVAudioPCMBuffer(pcmFormat: readFormat, frameCapacity: AVAudioFrameCount(outputFile.length))!
        try outputFile.read(into: readBuffer)

        guard let outData = readBuffer.floatChannelData else {
            Issue.record("No output data")
            return
        }

        let totalSamples = Int(readBuffer.frameLength)
        let fadeSamples = Int(spb) // 1 bar fade
        // First sample should be at full amplitude (before fade region)
        #expect(abs(outData[0][0]) > 0.7)
        // Last sample should be near zero
        #expect(abs(outData[0][totalSamples - 1]) < 0.05)
        // Sample at middle of fade region
        let fadeStart = totalSamples - fadeSamples
        let midFade = fadeStart + fadeSamples / 2
        let midValue = abs(outData[0][midFade])
        #expect(midValue > 0.2 && midValue < 0.6)
    }

    @Test("Bypassed effect chain renders dry")
    func bypassedEffectChainRendersDry() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-bypass-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleRate: Double = 44100
        let audioURL = tempDir.appendingPathComponent("tone.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let spb = OfflineRenderer.samplesPerBar(
            bpm: 120, timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4), sampleRate: sampleRate
        )
        let durationFrames = AVAudioFrameCount(spb)
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: durationFrames)!
        sourceBuffer.frameLength = durationFrames
        if let data = sourceBuffer.floatChannelData {
            for i in 0..<Int(durationFrames) { data[0][i] = 0.5 }
        }
        let sourceFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        try sourceFile.write(from: sourceBuffer)

        let recording = SourceRecording(filename: "tone.caf", sampleRate: sampleRate, sampleCount: Int64(durationFrames))

        // Container with a (fake) effect but chain bypassed
        let fakeEffect = InsertEffect(
            component: AudioComponentInfo(componentType: 0x61756678, componentSubType: 0x64656C79, componentManufacturer: 0x6170706C),
            displayName: "Delay",
            orderIndex: 0
        )
        let container = Container(
            name: "Bypassed",
            startBar: 1,
            lengthBars: 1,
            sourceRecordingID: recording.id,
            insertEffects: [fakeEffect],
            isEffectChainBypassed: true
        )
        let track = Track(name: "T1", kind: .audio, containers: [container])
        let song = Song(
            name: "Test", tempo: Tempo(bpm: 120),
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4), tracks: [track]
        )

        let destURL = tempDir.appendingPathComponent("output.wav")
        let config = ExportConfiguration(format: .wav24, sampleRate: .rate44100, destinationURL: destURL)
        let renderer = OfflineRenderer(audioDirURL: tempDir)
        let resultURL = try await renderer.render(
            song: song, sourceRecordings: [recording.id: recording], config: config
        )

        let outputFile = try AVAudioFile(forReading: resultURL)
        let readFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!
        let readBuffer = AVAudioPCMBuffer(pcmFormat: readFormat, frameCapacity: AVAudioFrameCount(outputFile.length))!
        try outputFile.read(into: readBuffer)

        // Should render dry - output should have signal (not silent)
        var maxSample: Float = 0
        if let data = readBuffer.floatChannelData {
            for ch in 0..<2 {
                for i in 0..<Int(readBuffer.frameLength) {
                    maxSample = max(maxSample, abs(data[ch][i]))
                }
            }
        }
        #expect(maxSample > 0.4) // Dry signal should be present
    }

    @Test("MIDI actions are skipped during offline render")
    func midiActionsSkipped() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-midi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleRate: Double = 44100
        let audioURL = tempDir.appendingPathComponent("tone.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let durationFrames = AVAudioFrameCount(sampleRate)
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: durationFrames)!
        sourceBuffer.frameLength = durationFrames
        if let data = sourceBuffer.floatChannelData {
            for i in 0..<Int(durationFrames) { data[0][i] = 0.5 }
        }
        let sourceFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        try sourceFile.write(from: sourceBuffer)

        let recording = SourceRecording(filename: "tone.caf", sampleRate: sampleRate, sampleCount: Int64(durationFrames))
        let midiAction = ContainerAction.makeSendMIDI(
            message: .programChange(channel: 0, program: 42),
            destination: .externalPort(name: "TestPort")
        )
        let container = Container(
            name: "MIDIContainer",
            startBar: 1,
            lengthBars: 1,
            sourceRecordingID: recording.id,
            onEnterActions: [midiAction]
        )
        let track = Track(name: "T1", kind: .audio, containers: [container])
        let song = Song(
            name: "Test", tempo: Tempo(bpm: 120),
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4), tracks: [track]
        )

        let destURL = tempDir.appendingPathComponent("output.wav")
        let config = ExportConfiguration(format: .wav24, sampleRate: .rate44100, destinationURL: destURL)
        let renderer = OfflineRenderer(audioDirURL: tempDir)

        // Should not throw — MIDI actions are skipped, not sent
        let resultURL = try await renderer.render(
            song: song, sourceRecordings: [recording.id: recording], config: config
        )
        #expect(FileManager.default.fileExists(atPath: resultURL.path))
    }

    @Test("Container with AU effect produces processed output")
    func renderWithAUEffect() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-effect-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleRate: Double = 44100
        let audioURL = tempDir.appendingPathComponent("tone.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let spb = OfflineRenderer.samplesPerBar(
            bpm: 120, timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4), sampleRate: sampleRate
        )
        let durationFrames = AVAudioFrameCount(spb)
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: durationFrames)!
        sourceBuffer.frameLength = durationFrames
        if let data = sourceBuffer.floatChannelData {
            // Short impulse followed by silence — delay/reverb would add a tail
            data[0][0] = 1.0
            for i in 1..<Int(durationFrames) { data[0][i] = 0.0 }
        }
        let sourceFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        try sourceFile.write(from: sourceBuffer)

        let recording = SourceRecording(filename: "tone.caf", sampleRate: sampleRate, sampleCount: Int64(durationFrames))

        // Use Apple's built-in AUDelay (kAudioUnitType_Effect, kAudioUnitSubType_Delay, kAudioUnitManufacturer_Apple)
        let delayComponent = AudioComponentInfo(
            componentType: 0x61756678, // 'aufx'
            componentSubType: 0x64656C79, // 'dely'
            componentManufacturer: 0x6170706C // 'appl'
        )
        let effect = InsertEffect(
            component: delayComponent,
            displayName: "Apple Delay",
            orderIndex: 0
        )

        // Render with effect
        let containerWithEffect = Container(
            name: "WithEffect",
            startBar: 1,
            lengthBars: 1,
            sourceRecordingID: recording.id,
            insertEffects: [effect]
        )
        let trackWithEffect = Track(name: "T1", kind: .audio, containers: [containerWithEffect])
        let songWithEffect = Song(
            name: "Eff", tempo: Tempo(bpm: 120),
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4), tracks: [trackWithEffect]
        )

        let destEffURL = tempDir.appendingPathComponent("out_eff.wav")
        let configEff = ExportConfiguration(format: .wav24, sampleRate: .rate44100, destinationURL: destEffURL)
        let renderer = OfflineRenderer(audioDirURL: tempDir)
        let effURL = try await renderer.render(
            song: songWithEffect, sourceRecordings: [recording.id: recording], config: configEff
        )

        // Render without effect (dry)
        let containerDry = Container(
            name: "Dry",
            startBar: 1,
            lengthBars: 1,
            sourceRecordingID: recording.id
        )
        let trackDry = Track(name: "T1", kind: .audio, containers: [containerDry])
        let songDry = Song(
            name: "Dry", tempo: Tempo(bpm: 120),
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4), tracks: [trackDry]
        )

        let destDryURL = tempDir.appendingPathComponent("out_dry.wav")
        let configDry = ExportConfiguration(format: .wav24, sampleRate: .rate44100, destinationURL: destDryURL)
        let dryURL = try await renderer.render(
            song: songDry, sourceRecordings: [recording.id: recording], config: configDry
        )

        // Read both outputs
        let effFile = try AVAudioFile(forReading: effURL)
        let dryFile = try AVAudioFile(forReading: dryURL)
        let readFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!

        let effBuf = AVAudioPCMBuffer(pcmFormat: readFormat, frameCapacity: AVAudioFrameCount(effFile.length))!
        try effFile.read(into: effBuf)
        let dryBuf = AVAudioPCMBuffer(pcmFormat: readFormat, frameCapacity: AVAudioFrameCount(dryFile.length))!
        try dryFile.read(into: dryBuf)

        // The effect output should differ from dry — delay adds signal after the impulse
        // Check that some samples in the second half differ
        let halfPoint = Int(effBuf.frameLength) / 2
        var sumDiffSquared: Float = 0
        if let effData = effBuf.floatChannelData, let dryData = dryBuf.floatChannelData {
            let frames = min(Int(effBuf.frameLength), Int(dryBuf.frameLength))
            for i in halfPoint..<frames {
                let diff = effData[0][i] - dryData[0][i]
                sumDiffSquared += diff * diff
            }
        }
        // Effect should have added signal energy after the impulse
        #expect(sumDiffSquared > 0.001)
    }

    @Test("Trigger action includes container from muted track")
    func triggerResolvesContainerFromMutedTrack() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-trigger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleRate: Double = 44100
        let audioURL = tempDir.appendingPathComponent("tone.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let durationFrames = AVAudioFrameCount(sampleRate)
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: durationFrames)!
        sourceBuffer.frameLength = durationFrames
        if let data = sourceBuffer.floatChannelData {
            for i in 0..<Int(durationFrames) { data[0][i] = 0.5 }
        }
        let sourceFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        try sourceFile.write(from: sourceBuffer)

        let recording = SourceRecording(filename: "tone.caf", sampleRate: sampleRate, sampleCount: Int64(durationFrames))

        // Container on muted track
        let targetContainer = Container(
            name: "Target",
            startBar: 1,
            lengthBars: 1,
            sourceRecordingID: recording.id
        )
        let mutedTrack = Track(name: "Muted", kind: .audio, isMuted: true, containers: [targetContainer])

        // Container on audible track that triggers the muted container
        let triggerAction = ContainerAction.makeTriggerContainer(
            targetID: targetContainer.id,
            action: .start
        )
        let triggerContainer = Container(
            name: "Trigger",
            startBar: 1,
            lengthBars: 1,
            sourceRecordingID: recording.id,
            onEnterActions: [triggerAction]
        )
        let audibleTrack = Track(name: "Audible", kind: .audio, containers: [triggerContainer])

        let song = Song(
            name: "Test", tempo: Tempo(bpm: 120),
            timeSignature: TimeSignature(beatsPerBar: 4, beatUnit: 4),
            tracks: [audibleTrack, mutedTrack]
        )

        let destURL = tempDir.appendingPathComponent("output.wav")
        let config = ExportConfiguration(format: .wav24, sampleRate: .rate44100, destinationURL: destURL)
        let renderer = OfflineRenderer(audioDirURL: tempDir)
        let resultURL = try await renderer.render(
            song: song, sourceRecordings: [recording.id: recording], config: config
        )

        let outputFile = try AVAudioFile(forReading: resultURL)
        let readFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!
        let readBuffer = AVAudioPCMBuffer(pcmFormat: readFormat, frameCapacity: AVAudioFrameCount(outputFile.length))!
        try outputFile.read(into: readBuffer)

        // Output should have signal from BOTH tracks (triggered container is included)
        var maxSample: Float = 0
        if let data = readBuffer.floatChannelData {
            for i in 0..<Int(readBuffer.frameLength) {
                maxSample = max(maxSample, abs(data[0][i]))
            }
        }
        // Both containers contribute 0.5, so mixed signal should exceed a single container's level
        #expect(maxSample > 0.8)
    }
}
