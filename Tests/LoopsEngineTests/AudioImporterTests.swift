import Testing
import Foundation
import AVFoundation
@testable import LoopsEngine
@testable import LoopsCore

@Suite("AudioImporter Tests")
struct AudioImporterTests {

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

    private func temporaryAudioDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("test-audio-\(UUID().uuidString)")
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Supported file extensions are recognized")
    func supportedExtensions() {
        #expect(AudioImporter.isSupportedAudioFile(URL(fileURLWithPath: "/test.wav")))
        #expect(AudioImporter.isSupportedAudioFile(URL(fileURLWithPath: "/test.aiff")))
        #expect(AudioImporter.isSupportedAudioFile(URL(fileURLWithPath: "/test.caf")))
        #expect(AudioImporter.isSupportedAudioFile(URL(fileURLWithPath: "/test.mp3")))
        #expect(AudioImporter.isSupportedAudioFile(URL(fileURLWithPath: "/test.m4a")))
        #expect(!AudioImporter.isSupportedAudioFile(URL(fileURLWithPath: "/test.txt")))
        #expect(!AudioImporter.isSupportedAudioFile(URL(fileURLWithPath: "/test.pdf")))
    }

    @Test("Import creates CAF file in audio directory")
    func importCreatesFile() throws {
        let sourceURL = try createTestAudioFile()
        let audioDir = temporaryAudioDir()
        defer {
            cleanup(sourceURL)
            cleanup(audioDir)
        }

        let importer = AudioImporter()
        let recording = try importer.importAudio(from: sourceURL, to: audioDir)

        let destURL = audioDir.appendingPathComponent(recording.filename)
        #expect(FileManager.default.fileExists(atPath: destURL.path))
        #expect(recording.filename.hasSuffix(".caf"))
        #expect(recording.sampleRate == 44100)
        #expect(recording.sampleCount > 0)
    }

    @Test("Import generates waveform peaks")
    func importGeneratesPeaks() throws {
        let sourceURL = try createTestAudioFile()
        let audioDir = temporaryAudioDir()
        defer {
            cleanup(sourceURL)
            cleanup(audioDir)
        }

        let importer = AudioImporter()
        let recording = try importer.importAudio(from: sourceURL, to: audioDir)

        #expect(recording.waveformPeaks != nil)
        #expect(!recording.waveformPeaks!.isEmpty)
    }

    @Test("Bars for duration calculation")
    func barsForDuration() {
        // 120 BPM, 4/4: bar = 2 seconds
        let tempo = Tempo(bpm: 120)
        let ts = TimeSignature(beatsPerBar: 4, beatUnit: 4)

        #expect(AudioImporter.barsForDuration(2.0, tempo: tempo, timeSignature: ts) == 1)
        #expect(AudioImporter.barsForDuration(4.0, tempo: tempo, timeSignature: ts) == 2)
        #expect(AudioImporter.barsForDuration(3.0, tempo: tempo, timeSignature: ts) == 2) // rounds up
        #expect(AudioImporter.barsForDuration(0.1, tempo: tempo, timeSignature: ts) == 1) // minimum 1

        // 60 BPM, 3/4: bar = 3 seconds
        let slowTempo = Tempo(bpm: 60)
        let ts34 = TimeSignature(beatsPerBar: 3, beatUnit: 4)
        #expect(AudioImporter.barsForDuration(3.0, tempo: slowTempo, timeSignature: ts34) == 1)
        #expect(AudioImporter.barsForDuration(7.0, tempo: slowTempo, timeSignature: ts34) == 3) // ceil(7/3) = 3
    }

    @Test("Read metadata returns correct duration and sample rate")
    func readMetadata() throws {
        let sourceURL = try createTestAudioFile(sampleRate: 44100, durationSeconds: 3.0)
        defer { cleanup(sourceURL) }

        let metadata = try AudioImporter.readMetadata(from: sourceURL)
        #expect(metadata.sampleRate == 44100)
        #expect(metadata.channelCount == 1)
        // 3 seconds at 44100 Hz = 132300 samples
        #expect(metadata.sampleCount == 132300)
        #expect(abs(metadata.durationSeconds - 3.0) < 0.01)
    }

    @Test("Read metadata with different sample rates")
    func readMetadataDifferentRates() throws {
        let sourceURL = try createTestAudioFile(sampleRate: 48000, durationSeconds: 1.0)
        defer { cleanup(sourceURL) }

        let metadata = try AudioImporter.readMetadata(from: sourceURL)
        #expect(metadata.sampleRate == 48000)
        #expect(metadata.sampleCount == 48000)
        #expect(abs(metadata.durationSeconds - 1.0) < 0.01)
    }

    @Test("importAudioFile creates file without peaks")
    func importAudioFileNoPeaks() throws {
        let sourceURL = try createTestAudioFile()
        let audioDir = temporaryAudioDir()
        defer {
            cleanup(sourceURL)
            cleanup(audioDir)
        }

        let importer = AudioImporter()
        let recording = try importer.importAudioFile(from: sourceURL, to: audioDir)

        let destURL = audioDir.appendingPathComponent(recording.filename)
        #expect(FileManager.default.fileExists(atPath: destURL.path))
        #expect(recording.filename.hasSuffix(".caf"))
        #expect(recording.sampleRate == 44100)
        #expect(recording.sampleCount > 0)
        // importAudioFile does NOT generate peaks
        #expect(recording.waveformPeaks == nil)
    }

    @Test("Progressive peak generation matches complete generation")
    func progressivePeaksMatchComplete() throws {
        let sourceURL = try createTestAudioFile(sampleRate: 44100, durationSeconds: 2.0)
        let audioDir = temporaryAudioDir()
        defer {
            cleanup(sourceURL)
            cleanup(audioDir)
        }

        let importer = AudioImporter()
        let recording = try importer.importAudioFile(from: sourceURL, to: audioDir)
        let destURL = audioDir.appendingPathComponent(recording.filename)

        let generator = WaveformGenerator()

        // Generate peaks normally
        let completePeaks = try generator.generatePeaks(from: destURL)

        // Generate peaks progressively
        nonisolated(unsafe) var progressCallCount = 0
        let progressivePeaks = try generator.generatePeaksProgressively(
            from: destURL,
            batchSize: 50
        ) { _ in
            progressCallCount += 1
        }

        // Progressive result matches complete result
        #expect(progressivePeaks.count == completePeaks.count)
        for i in 0..<completePeaks.count {
            #expect(abs(progressivePeaks[i] - completePeaks[i]) < 0.001)
        }
        // Progress callback was called at least once (the final one)
        #expect(progressCallCount >= 1)
    }

    @Test("Progressive peak generation calls progress multiple times for long files")
    func progressiveCallbackFrequency() throws {
        // 5 seconds at 44100 = 500 peaks at 100/sec
        let sourceURL = try createTestAudioFile(sampleRate: 44100, durationSeconds: 5.0)
        let audioDir = temporaryAudioDir()
        defer {
            cleanup(sourceURL)
            cleanup(audioDir)
        }

        let importer = AudioImporter()
        let recording = try importer.importAudioFile(from: sourceURL, to: audioDir)
        let destURL = audioDir.appendingPathComponent(recording.filename)

        let generator = WaveformGenerator()
        nonisolated(unsafe) var progressCounts: [Int] = []
        let _ = try generator.generatePeaksProgressively(
            from: destURL,
            batchSize: 100
        ) { peaks in
            progressCounts.append(peaks.count)
        }

        // 500 peaks / 100 batch = 5 batches + 1 final = at least 5 progress calls
        #expect(progressCounts.count >= 5)
        // Each successive callback has more peaks than the last (or equal for final)
        for i in 1..<progressCounts.count {
            #expect(progressCounts[i] >= progressCounts[i - 1])
        }
    }
}
