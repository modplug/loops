import Foundation
import AVFoundation
import Accelerate
import LoopsCore

/// Generates downsampled peak amplitude data from audio files.
/// Uses Accelerate/vDSP for SIMD-vectorized peak computation.
public final class WaveformGenerator: Sendable {
    /// Number of peaks to generate per second of audio.
    public static let peaksPerSecond: Int = 100

    public init() {}

    /// Extracts downsampled peak data from an audio file.
    /// Returns an array of peak amplitudes (0.0...1.0).
    /// Uses large I/O buffers and vDSP for fast computation.
    public func generatePeaks(from url: URL, targetPeakCount: Int? = nil) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = AVAudioFrameCount(file.length)

        guard totalFrames > 0 else { return [] }

        let durationSeconds = Double(totalFrames) / format.sampleRate
        let peakCount = targetPeakCount ?? max(1, Int(durationSeconds * Double(Self.peaksPerSecond)))
        let framesPerPeak = Int(totalFrames) / peakCount

        guard framesPerPeak > 0 else { return [] }

        // Read in large chunks (multiple peaks at once) to reduce I/O overhead.
        // Each chunk covers `batchSize` peaks worth of frames.
        let batchSize = min(peakCount, 512)
        let framesPerBatch = AVAudioFrameCount(framesPerPeak * batchSize)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerBatch) else {
            return []
        }

        var peaks: [Float] = []
        peaks.reserveCapacity(peakCount)

        var remainingPeaks = peakCount
        while remainingPeaks > 0 {
            let peaksThisBatch = min(remainingPeaks, batchSize)
            let framesToRead = AVAudioFrameCount(framesPerPeak * peaksThisBatch)

            buffer.frameLength = 0
            do {
                try file.read(into: buffer, frameCount: framesToRead)
            } catch {
                break
            }

            guard buffer.frameLength > 0 else { break }

            let channelCount = Int(format.channelCount)
            let actualFrames = Int(buffer.frameLength)

            if let channelData = buffer.floatChannelData {
                // Process each peak within this batch
                var offset = 0
                for _ in 0..<peaksThisBatch {
                    let chunkFrames = min(framesPerPeak, actualFrames - offset)
                    guard chunkFrames > 0 else { break }

                    var maxAmplitude: Float = 0
                    for ch in 0..<channelCount {
                        let samples = channelData[ch].advanced(by: offset)
                        var channelMax: Float = 0
                        // vDSP: compute max of absolute values in one SIMD call
                        vDSP_maxmgv(samples, 1, &channelMax, vDSP_Length(chunkFrames))
                        if channelMax > maxAmplitude {
                            maxAmplitude = channelMax
                        }
                    }
                    peaks.append(min(maxAmplitude, 1.0))
                    offset += framesPerPeak
                }
            }

            remainingPeaks -= peaksThisBatch
        }

        return peaks
    }

    /// Generates peaks progressively, calling the callback with accumulated peaks at regular intervals.
    /// The callback receives the full peak array so far. Runs file I/O on the calling thread.
    public func generatePeaksProgressively(
        from url: URL,
        targetPeakCount: Int? = nil,
        batchSize: Int = 200,
        onProgress: @Sendable ([Float]) -> Void
    ) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = AVAudioFrameCount(file.length)

        guard totalFrames > 0 else { return [] }

        let durationSeconds = Double(totalFrames) / format.sampleRate
        let peakCount = targetPeakCount ?? max(1, Int(durationSeconds * Double(Self.peaksPerSecond)))
        let framesPerPeak = Int(totalFrames) / peakCount

        guard framesPerPeak > 0 else { return [] }

        // Large I/O buffer covering batchSize peaks
        let framesPerBatch = AVAudioFrameCount(framesPerPeak * batchSize)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerBatch) else {
            return []
        }

        var peaks: [Float] = []
        peaks.reserveCapacity(peakCount)

        var remainingPeaks = peakCount
        while remainingPeaks > 0 {
            let peaksThisBatch = min(remainingPeaks, batchSize)
            let framesToRead = AVAudioFrameCount(framesPerPeak * peaksThisBatch)

            buffer.frameLength = 0
            do {
                try file.read(into: buffer, frameCount: framesToRead)
            } catch {
                break
            }

            guard buffer.frameLength > 0 else { break }

            let channelCount = Int(format.channelCount)
            let actualFrames = Int(buffer.frameLength)

            if let channelData = buffer.floatChannelData {
                var offset = 0
                for _ in 0..<peaksThisBatch {
                    let chunkFrames = min(framesPerPeak, actualFrames - offset)
                    guard chunkFrames > 0 else { break }

                    var maxAmplitude: Float = 0
                    for ch in 0..<channelCount {
                        let samples = channelData[ch].advanced(by: offset)
                        var channelMax: Float = 0
                        vDSP_maxmgv(samples, 1, &channelMax, vDSP_Length(chunkFrames))
                        if channelMax > maxAmplitude {
                            maxAmplitude = channelMax
                        }
                    }
                    peaks.append(min(maxAmplitude, 1.0))
                    offset += framesPerPeak
                }
            }

            remainingPeaks -= peaksThisBatch
            onProgress(peaks)
        }

        return peaks
    }

    /// Generates peaks from raw sample data (for streaming during recording).
    /// Uses vDSP for SIMD-accelerated max-magnitude computation.
    public static func peaksFromSamples(_ samples: UnsafeBufferPointer<Float>, samplesPerPeak: Int) -> [Float] {
        guard samplesPerPeak > 0, !samples.isEmpty else { return [] }

        let peakCount = samples.count / samplesPerPeak + (samples.count % samplesPerPeak > 0 ? 1 : 0)
        var peaks: [Float] = []
        peaks.reserveCapacity(peakCount)

        var index = 0
        while index < samples.count {
            let chunkLength = min(samplesPerPeak, samples.count - index)
            var maxVal: Float = 0
            vDSP_maxmgv(samples.baseAddress!.advanced(by: index), 1, &maxVal, vDSP_Length(chunkLength))
            peaks.append(min(maxVal, 1.0))
            index += samplesPerPeak
        }
        return peaks
    }
}
