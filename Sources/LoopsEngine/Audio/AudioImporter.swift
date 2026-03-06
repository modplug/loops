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

    private static let defaultTargetSampleRate = 44100.0

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
    public func importAudio(
        from sourceURL: URL,
        to audioDirectory: URL,
        targetSampleRate: Double? = nil
    ) throws -> SourceRecording {
        let recording = try importAudioFile(
            from: sourceURL,
            to: audioDirectory,
            targetSampleRate: targetSampleRate
        )
        // Generate waveform peaks synchronously
        let destURL = audioDirectory.appendingPathComponent(recording.filename)
        let generator = WaveformGenerator()
        let renderData = try? generator.generateRenderData(from: destURL)
        return SourceRecording(
            id: recording.id,
            filename: recording.filename,
            sampleRate: recording.sampleRate,
            sampleCount: recording.sampleCount,
            waveformPeaks: renderData?.peaks,
            waveformExtrema: renderData?.extrema,
            waveformRMS: renderData?.rms
        )
    }

    /// Imports an audio file into the project's audio directory (file copy only, no peak generation).
    /// Returns a SourceRecording with metadata but nil waveformPeaks.
    public func importAudioFile(
        from sourceURL: URL,
        to audioDirectory: URL,
        targetSampleRate: Double? = nil
    ) throws -> SourceRecording {
        let filename = UUID().uuidString + ".caf"
        let destinationURL = audioDirectory.appendingPathComponent(filename)

        // Create audio directory if needed
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let targetRate = sanitizedTargetSampleRate(targetSampleRate)
        let sampleCount = try conformAudioFile(
            from: sourceURL,
            to: destinationURL,
            targetSampleRate: targetRate
        )

        return SourceRecording(
            filename: filename,
            sampleRate: targetRate,
            sampleCount: sampleCount,
            waveformPeaks: nil
        )
    }

    public func ensurePlaybackConformedFile(
        from sourceURL: URL,
        cacheDirectory: URL,
        key: String,
        targetSampleRate: Double
    ) throws -> URL {
        let targetRate = sanitizedTargetSampleRate(targetSampleRate)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let destinationURL = cacheDirectory.appendingPathComponent("\(key)-\(Int(targetRate.rounded())).caf")
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        _ = try conformAudioFile(from: sourceURL, to: destinationURL, targetSampleRate: targetRate)
        return destinationURL
    }

    private func sanitizedTargetSampleRate(_ targetSampleRate: Double?) -> Double {
        let rate = targetSampleRate ?? Self.defaultTargetSampleRate
        return rate > 0 ? rate : Self.defaultTargetSampleRate
    }

    @discardableResult
    private func conformAudioFile(
        from sourceURL: URL,
        to destinationURL: URL,
        targetSampleRate: Double
    ) throws -> Int64 {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        let sourceFormat = sourceFile.processingFormat
        let totalFrames = AVAudioFrameCount(sourceFile.length)

        guard totalFrames > 0 else {
            throw LoopsError.importFailed(reason: "Audio file is empty")
        }

        guard let destinationFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: sourceFormat.channelCount,
            interleaved: true
        ) else {
            throw LoopsError.importFailed(reason: "Could not create destination audio format")
        }

        let destFile = try AVAudioFile(
            forWriting: destinationURL,
            settings: destinationFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: true
        )

        guard let converter = AVAudioConverter(from: sourceFormat, to: destinationFormat) else {
            throw LoopsError.importFailed(reason: "Could not create audio converter")
        }

        let inputChunkSize: AVAudioFrameCount = 32768
        let outputChunkSize = AVAudioFrameCount(
            max(
                4096,
                Int(ceil(Double(inputChunkSize) * targetSampleRate / sourceFormat.sampleRate)) + 1024
            )
        )

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: inputChunkSize) else {
            throw LoopsError.importFailed(reason: "Could not create source audio buffer")
        }

        var sourceExhausted = false
        var sampleCount: Int64 = 0

        while true {
            guard let destBuffer = AVAudioPCMBuffer(
                pcmFormat: destinationFormat,
                frameCapacity: outputChunkSize
            ) else {
                throw LoopsError.importFailed(reason: "Could not create destination audio buffer")
            }

            var conversionError: NSError?
            let status = converter.convert(to: destBuffer, error: &conversionError) { _, outStatus in
                if sourceExhausted {
                    outStatus.pointee = .endOfStream
                    return nil
                }

                sourceBuffer.frameLength = 0
                do {
                    let framesToRead = min(
                        inputChunkSize,
                        AVAudioFrameCount(max(sourceFile.length - sourceFile.framePosition, 0))
                    )
                    if framesToRead == 0 {
                        sourceExhausted = true
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    try sourceFile.read(into: sourceBuffer, frameCount: framesToRead)
                } catch {
                    sourceExhausted = true
                    outStatus.pointee = .endOfStream
                    return nil
                }

                if sourceBuffer.frameLength == 0 {
                    sourceExhausted = true
                    outStatus.pointee = .endOfStream
                    return nil
                }

                outStatus.pointee = .haveData
                return sourceBuffer
            }

            if let conversionError {
                throw conversionError
            }

            if destBuffer.frameLength > 0 {
                try destFile.write(from: destBuffer)
                sampleCount += Int64(destBuffer.frameLength)
            }

            switch status {
            case .haveData, .inputRanDry:
                continue
            case .endOfStream:
                return sampleCount
            case .error:
                throw LoopsError.importFailed(reason: "Audio conversion failed")
            @unknown default:
                throw LoopsError.importFailed(reason: "Unexpected audio conversion status")
            }
        }
    }

    /// Calculates the number of bars an audio file spans at a given tempo and time signature.
    public static func barsForDuration(_ durationSeconds: Double, tempo: Tempo, timeSignature: TimeSignature) -> Double {
        let barDuration = (60.0 / tempo.bpm) * Double(timeSignature.beatsPerBar)
        let bars = durationSeconds / barDuration
        return max(1.0, ceil(bars))
    }
}
