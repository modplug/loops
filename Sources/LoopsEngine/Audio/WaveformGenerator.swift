import Foundation
import AVFoundation
import LoopsCore

/// Generates downsampled peak amplitude data from audio files.
public final class WaveformGenerator: Sendable {
    /// Number of peaks to generate per second of audio.
    public static let peaksPerSecond: Int = 100

    public init() {}

    /// Extracts downsampled peak data from an audio file.
    /// Returns an array of peak amplitudes (0.0...1.0).
    public func generatePeaks(from url: URL, targetPeakCount: Int? = nil) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = AVAudioFrameCount(file.length)

        guard totalFrames > 0 else { return [] }

        let durationSeconds = Double(totalFrames) / format.sampleRate
        let peakCount = targetPeakCount ?? max(1, Int(durationSeconds * Double(Self.peaksPerSecond)))
        let framesPerPeak = Int(totalFrames) / peakCount

        guard framesPerPeak > 0 else { return [] }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(framesPerPeak)) else {
            return []
        }

        var peaks: [Float] = []
        peaks.reserveCapacity(peakCount)

        for _ in 0..<peakCount {
            buffer.frameLength = 0
            do {
                try file.read(into: buffer, frameCount: AVAudioFrameCount(framesPerPeak))
            } catch {
                break
            }

            guard buffer.frameLength > 0 else { break }

            var maxAmplitude: Float = 0
            if let channelData = buffer.floatChannelData {
                let channelCount = Int(format.channelCount)
                let frameCount = Int(buffer.frameLength)
                for ch in 0..<channelCount {
                    let samples = channelData[ch]
                    for i in 0..<frameCount {
                        let absVal = abs(samples[i])
                        if absVal > maxAmplitude {
                            maxAmplitude = absVal
                        }
                    }
                }
            }
            peaks.append(min(maxAmplitude, 1.0))
        }

        return peaks
    }

    /// Generates peaks from raw sample data (for streaming during recording).
    public static func peaksFromSamples(_ samples: UnsafeBufferPointer<Float>, samplesPerPeak: Int) -> [Float] {
        guard samplesPerPeak > 0, !samples.isEmpty else { return [] }

        var peaks: [Float] = []
        var index = 0
        while index < samples.count {
            var maxVal: Float = 0
            let end = min(index + samplesPerPeak, samples.count)
            for i in index..<end {
                let absVal = abs(samples[i])
                if absVal > maxVal {
                    maxVal = absVal
                }
            }
            peaks.append(min(maxVal, 1.0))
            index = end
        }
        return peaks
    }
}
