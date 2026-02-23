import Foundation
import AVFoundation
import LoopsCore

/// Lightweight audio file metadata read from the header without decoding samples.
public struct AudioFileMetadata: Sendable {
    public let sampleRate: Double
    public let sampleCount: Int64
    public let channelCount: Int

    public var durationSeconds: Double { Double(sampleCount) / sampleRate }
}

/// Imports audio files into the project bundle, converting to CAF format.
public final class AudioImporter: Sendable {
    /// Supported audio file extensions.
    public static let supportedExtensions: Set<String> = ["wav", "aiff", "aif", "caf", "mp3", "m4a"]

    public init() {}

    /// Checks if a file URL has a supported audio extension.
    public static func isSupportedAudioFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Reads audio file metadata (duration, sample rate) without decoding samples.
    /// This is fast enough to call on the main thread at drop time.
    public static func readMetadata(from url: URL) throws -> AudioFileMetadata {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = file.length
        guard totalFrames > 0 else {
            throw LoopsError.importFailed(reason: "Audio file is empty")
        }
        return AudioFileMetadata(
            sampleRate: format.sampleRate,
            sampleCount: totalFrames,
            channelCount: Int(format.channelCount)
        )
    }

    /// Imports an audio file into the project's audio directory.
    /// Converts the audio to CAF format and generates waveform peaks.
    /// Returns a SourceRecording with the imported audio's metadata.
    public func importAudio(from sourceURL: URL, to audioDirectory: URL) throws -> SourceRecording {
        let recording = try importAudioFile(from: sourceURL, to: audioDirectory)
        // Generate waveform peaks synchronously
        let destURL = audioDirectory.appendingPathComponent(recording.filename)
        let generator = WaveformGenerator()
        let peaks = try? generator.generatePeaks(from: destURL)
        return SourceRecording(
            id: recording.id,
            filename: recording.filename,
            sampleRate: recording.sampleRate,
            sampleCount: recording.sampleCount,
            waveformPeaks: peaks
        )
    }

    /// Imports an audio file into the project's audio directory (file copy only, no peak generation).
    /// Returns a SourceRecording with metadata but nil waveformPeaks.
    public func importAudioFile(from sourceURL: URL, to audioDirectory: URL) throws -> SourceRecording {
        let filename = UUID().uuidString + ".caf"
        let destinationURL = audioDirectory.appendingPathComponent(filename)

        // Create audio directory if needed
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        // Read source file
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        let processingFormat = sourceFile.processingFormat
        let totalFrames = AVAudioFrameCount(sourceFile.length)

        guard totalFrames > 0 else {
            throw LoopsError.importFailed(reason: "Audio file is empty")
        }

        // Write as CAF
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: processingFormat.sampleRate,
            AVNumberOfChannelsKey: processingFormat.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: processingFormat.isInterleaved ? false : true
        ]

        let destFile = try AVAudioFile(forWriting: destinationURL, settings: settings)

        // Copy in chunks
        let chunkSize: AVAudioFrameCount = 65536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: chunkSize) else {
            throw LoopsError.importFailed(reason: "Could not create audio buffer")
        }

        var sampleCount: Int64 = 0
        while sourceFile.framePosition < sourceFile.length {
            let framesToRead = min(chunkSize, AVAudioFrameCount(sourceFile.length - sourceFile.framePosition))
            try sourceFile.read(into: buffer, frameCount: framesToRead)
            try destFile.write(from: buffer)
            sampleCount += Int64(buffer.frameLength)
        }

        return SourceRecording(
            filename: filename,
            sampleRate: processingFormat.sampleRate,
            sampleCount: sampleCount,
            waveformPeaks: nil
        )
    }

    /// Calculates the number of bars an audio file spans at a given tempo and time signature.
    public static func barsForDuration(_ durationSeconds: Double, tempo: Tempo, timeSignature: TimeSignature) -> Double {
        let barDuration = (60.0 / tempo.bpm) * Double(timeSignature.beatsPerBar)
        let bars = durationSeconds / barDuration
        return max(1.0, ceil(bars))
    }
}
