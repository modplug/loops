import Foundation
import AVFoundation
import Accelerate
import LoopsCore

/// Generates downsampled peak amplitude data from audio files.
/// Uses Accelerate/vDSP for SIMD-vectorized peak computation.
public final class WaveformGenerator: Sendable {
    /// Number of peaks to generate per second of audio.
    public static let peaksPerSecond: Int = 100
    /// Number of min/max extrema buckets to generate per second of audio for
    /// high-zoom waveform rendering.
    public static let extremaPerSecond: Int = 400

    public struct RenderData: Sendable, Equatable {
        public var peaks: [Float]
        public var extrema: [WaveformExtrema]
        public var rms: [Float]

        public init(peaks: [Float], extrema: [WaveformExtrema], rms: [Float]) {
            self.peaks = peaks
            self.extrema = extrema
            self.rms = rms
        }
    }

    public init() {}

    public func generateRenderData(
        from url: URL,
        targetPeakCount: Int? = nil,
        targetExtremaCount: Int? = nil
    ) throws -> RenderData {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = AVAudioFrameCount(file.length)

        guard totalFrames > 0 else { return RenderData(peaks: [], extrema: [], rms: []) }

        let durationSeconds = Double(totalFrames) / format.sampleRate
        let extremaCount = targetExtremaCount ?? max(1, Int(durationSeconds * Double(Self.extremaPerSecond)))
        let peaksCount = targetPeakCount ?? max(1, Int(durationSeconds * Double(Self.peaksPerSecond)))

        let extremaFramesPerBucket = max(1, Int(totalFrames) / extremaCount)
        let peaksPerExtremaBucket = max(1, extremaCount / max(peaksCount, 1))
        let batchSize = min(extremaCount, 1024)
        let framesPerBatch = AVAudioFrameCount(extremaFramesPerBucket * batchSize)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerBatch) else {
            return RenderData(peaks: [], extrema: [], rms: [])
        }

        var extrema: [WaveformExtrema] = []
        extrema.reserveCapacity(extremaCount)
        var rms: [Float] = []
        rms.reserveCapacity(extremaCount)

        var remainingExtrema = extremaCount
        while remainingExtrema > 0 {
            let extremaThisBatch = min(remainingExtrema, batchSize)
            let framesToRead = AVAudioFrameCount(extremaFramesPerBucket * extremaThisBatch)

            buffer.frameLength = 0
            do {
                try file.read(into: buffer, frameCount: framesToRead)
            } catch {
                break
            }

            guard buffer.frameLength > 0 else { break }
            let actualFrames = Int(buffer.frameLength)

            if let channelData = buffer.floatChannelData {
                var offset = 0
                for _ in 0..<extremaThisBatch {
                    let chunkFrames = min(extremaFramesPerBucket, actualFrames - offset)
                    guard chunkFrames > 0 else { break }

                    extrema.append(Self.extremaForChunk(
                        channelData: channelData,
                        channelCount: Int(format.channelCount),
                        offset: offset,
                        frameCount: chunkFrames
                    ))
                    rms.append(Self.rmsForChunk(
                        channelData: channelData,
                        channelCount: Int(format.channelCount),
                        offset: offset,
                        frameCount: chunkFrames
                    ))
                    offset += extremaFramesPerBucket
                }
            }

            remainingExtrema -= extremaThisBatch
        }

        let peaks = Self.peaks(from: extrema, bucketsPerPeak: peaksPerExtremaBucket)
        return RenderData(peaks: peaks, extrema: extrema, rms: rms)
    }

    /// Extracts downsampled peak data from an audio file.
    /// Returns an array of peak amplitudes (0.0...1.0).
    /// Uses large I/O buffers and vDSP for fast computation.
    public func generatePeaks(from url: URL, targetPeakCount: Int? = nil) throws -> [Float] {
        try generateRenderData(from: url, targetPeakCount: targetPeakCount).peaks
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

    public static func extremaFromSamples(
        _ samples: UnsafeBufferPointer<Float>,
        samplesPerBucket: Int
    ) -> [WaveformExtrema] {
        guard samplesPerBucket > 0, !samples.isEmpty else { return [] }

        let bucketCount = samples.count / samplesPerBucket + (samples.count % samplesPerBucket > 0 ? 1 : 0)
        var extrema: [WaveformExtrema] = []
        extrema.reserveCapacity(bucketCount)

        var index = 0
        while index < samples.count {
            let chunkLength = min(samplesPerBucket, samples.count - index)
            let chunk = UnsafeBufferPointer(start: samples.baseAddress!.advanced(by: index), count: chunkLength)
            let (minValue, maxValue) = extremaForSignedSamples(chunk)
            extrema.append(WaveformExtrema(minimum: minValue, maximum: maxValue))
            index += samplesPerBucket
        }

        return extrema
    }

    public static func rmsFromSamples(
        _ samples: UnsafeBufferPointer<Float>,
        samplesPerBucket: Int
    ) -> [Float] {
        guard samplesPerBucket > 0, !samples.isEmpty else { return [] }

        let bucketCount = samples.count / samplesPerBucket + (samples.count % samplesPerBucket > 0 ? 1 : 0)
        var rms: [Float] = []
        rms.reserveCapacity(bucketCount)

        var index = 0
        while index < samples.count {
            let chunkLength = min(samplesPerBucket, samples.count - index)
            let chunk = UnsafeBufferPointer(start: samples.baseAddress!.advanced(by: index), count: chunkLength)
            rms.append(rmsForSignedSamples(chunk))
            index += samplesPerBucket
        }

        return rms
    }

    /// Generates peaks from raw sample data (for streaming during recording).
    /// Uses vDSP for SIMD-accelerated max-magnitude computation.
    public static func peaksFromSamples(_ samples: UnsafeBufferPointer<Float>, samplesPerPeak: Int) -> [Float] {
        let extrema = extremaFromSamples(samples, samplesPerBucket: samplesPerPeak)
        return peaks(from: extrema, bucketsPerPeak: 1)
    }

    private static func extremaForChunk(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        offset: Int,
        frameCount: Int
    ) -> WaveformExtrema {
        var minSample: Float = 1.0
        var maxSample: Float = -1.0

        for ch in 0..<channelCount {
            let samples = channelData[ch].advanced(by: offset)
            var channelMin: Float = 0
            var channelMax: Float = 0
            vDSP_minv(samples, 1, &channelMin, vDSP_Length(frameCount))
            vDSP_maxv(samples, 1, &channelMax, vDSP_Length(frameCount))
            minSample = min(minSample, channelMin)
            maxSample = max(maxSample, channelMax)
        }

        return WaveformExtrema(
            minimum: max(minSample, -1.0),
            maximum: min(maxSample, 1.0)
        )
    }

    private static func rmsForChunk(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        offset: Int,
        frameCount: Int
    ) -> Float {
        var maxRMS: Float = 0

        for ch in 0..<channelCount {
            let samples = UnsafeBufferPointer(
                start: channelData[ch].advanced(by: offset),
                count: frameCount
            )
            maxRMS = max(maxRMS, rmsForSignedSamples(samples))
        }

        return min(maxRMS, 1.0)
    }

    private static func extremaForSignedSamples(_ samples: UnsafeBufferPointer<Float>) -> (Float, Float) {
        var minValue: Float = 0
        var maxValue: Float = 0
        vDSP_minv(samples.baseAddress!, 1, &minValue, vDSP_Length(samples.count))
        vDSP_maxv(samples.baseAddress!, 1, &maxValue, vDSP_Length(samples.count))
        return (max(minValue, -1.0), min(maxValue, 1.0))
    }

    private static func rmsForSignedSamples(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard let baseAddress = samples.baseAddress else { return 0 }
        var meanSquare: Float = 0
        vDSP_measqv(baseAddress, 1, &meanSquare, vDSP_Length(samples.count))
        return min(sqrt(meanSquare), 1.0)
    }

    private static func peaks(from extrema: [WaveformExtrema], bucketsPerPeak: Int) -> [Float] {
        guard !extrema.isEmpty else { return [] }
        let stride = max(1, bucketsPerPeak)
        let peakCount = extrema.count / stride + (extrema.count % stride > 0 ? 1 : 0)
        var peaks: [Float] = []
        peaks.reserveCapacity(peakCount)

        var index = 0
        while index < extrema.count {
            let end = min(index + stride, extrema.count)
            var maxAmplitude: Float = 0
            for bucket in extrema[index..<end] {
                maxAmplitude = max(maxAmplitude, max(abs(bucket.minimum), abs(bucket.maximum)))
            }
            peaks.append(min(maxAmplitude, 1.0))
            index = end
        }

        return peaks
    }
}
