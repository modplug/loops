import Foundation
import AVFoundation
import LoopsCore

/// Imports audio files into the project bundle, converting to CAF format.
public final class AudioImporter: Sendable {
    /// Supported audio file extensions.
    public static let supportedExtensions: Set<String> = ["wav", "aiff", "aif", "caf", "mp3", "m4a"]

    public init() {}

    /// Checks if a file URL has a supported audio extension.
    public static func isSupportedAudioFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Imports an audio file into the project's audio directory.
    /// Converts the audio to CAF format and generates waveform peaks.
    /// Returns a SourceRecording with the imported audio's metadata.
    public func importAudio(from sourceURL: URL, to audioDirectory: URL) throws -> SourceRecording {
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

        // Generate waveform peaks
        let generator = WaveformGenerator()
        let peaks = try? generator.generatePeaks(from: destinationURL)

        return SourceRecording(
            filename: filename,
            sampleRate: processingFormat.sampleRate,
            sampleCount: sampleCount,
            waveformPeaks: peaks
        )
    }

    /// Calculates the number of bars an audio file spans at a given tempo and time signature.
    public static func barsForDuration(_ durationSeconds: Double, tempo: Tempo, timeSignature: TimeSignature) -> Int {
        let barDuration = (60.0 / tempo.bpm) * Double(timeSignature.beatsPerBar)
        let bars = durationSeconds / barDuration
        return max(1, Int(ceil(bars)))
    }
}
