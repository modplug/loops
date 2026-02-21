import Testing
import Foundation
import AVFoundation
@testable import LoopsEngine
@testable import LoopsCore

@Suite("WaveformGenerator Tests")
struct WaveformGeneratorTests {

    @Test("Peaks from samples generates correct count")
    func peaksFromSamples() {
        // 1000 samples, 100 per peak = 10 peaks
        var samples: [Float] = []
        for i in 0..<1000 {
            samples.append(Float(i % 100) / 100.0)
        }
        let peaks = samples.withUnsafeBufferPointer { ptr in
            WaveformGenerator.peaksFromSamples(ptr, samplesPerPeak: 100)
        }
        #expect(peaks.count == 10)
    }

    @Test("Peaks from samples captures max amplitude")
    func peaksFromSamplesMaxAmplitude() {
        // Create samples where one chunk has a clear spike
        var samples: [Float] = Array(repeating: 0.1, count: 200)
        samples[50] = 0.9 // spike in first chunk
        samples[150] = 0.5 // lower spike in second chunk

        let peaks = samples.withUnsafeBufferPointer { ptr in
            WaveformGenerator.peaksFromSamples(ptr, samplesPerPeak: 100)
        }
        #expect(peaks.count == 2)
        #expect(peaks[0] >= 0.9)
        #expect(peaks[1] >= 0.5)
    }

    @Test("Peaks from empty samples returns empty")
    func peaksFromEmptySamples() {
        let samples: [Float] = []
        let peaks = samples.withUnsafeBufferPointer { ptr in
            WaveformGenerator.peaksFromSamples(ptr, samplesPerPeak: 100)
        }
        #expect(peaks.isEmpty)
    }

    @Test("Peaks from samples with zero samplesPerPeak returns empty")
    func peaksFromSamplesZeroSPP() {
        let samples: [Float] = [0.1, 0.2, 0.3]
        let peaks = samples.withUnsafeBufferPointer { ptr in
            WaveformGenerator.peaksFromSamples(ptr, samplesPerPeak: 0)
        }
        #expect(peaks.isEmpty)
    }

    @Test("Peaks clamped to 1.0")
    func peaksClampedToOne() {
        var samples: [Float] = Array(repeating: 0.0, count: 100)
        samples[0] = 1.5 // above 1.0

        let peaks = samples.withUnsafeBufferPointer { ptr in
            WaveformGenerator.peaksFromSamples(ptr, samplesPerPeak: 100)
        }
        #expect(peaks.count == 1)
        #expect(peaks[0] == 1.0)
    }

    @Test("Negative samples use absolute value")
    func negativeSamplesAbsolute() {
        var samples: [Float] = Array(repeating: 0.0, count: 100)
        samples[0] = -0.8

        let peaks = samples.withUnsafeBufferPointer { ptr in
            WaveformGenerator.peaksFromSamples(ptr, samplesPerPeak: 100)
        }
        #expect(peaks.count == 1)
        #expect(peaks[0] >= 0.8)
    }

    @Test("Generate peaks from file creates valid output")
    func generatePeaksFromFile() throws {
        // Create a temporary audio file with known content
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-waveform-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
        buffer.frameLength = 44100
        if let data = buffer.floatChannelData {
            for i in 0..<44100 {
                // Generate a simple sine wave
                data[0][i] = sin(Float(i) * 2.0 * .pi * 440.0 / 44100.0) * 0.5
            }
        }
        try file.write(from: buffer)

        let generator = WaveformGenerator()
        let peaks = try generator.generatePeaks(from: url, targetPeakCount: 50)
        #expect(!peaks.isEmpty)
        #expect(peaks.count <= 50)
        // All peaks should be non-negative
        for peak in peaks {
            #expect(peak >= 0.0)
            #expect(peak <= 1.0)
        }
    }
}
