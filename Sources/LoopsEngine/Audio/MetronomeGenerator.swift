import Foundation
import AVFoundation
import LoopsCore

/// Generates metronome click audio via AVAudioSourceNode.
/// Produces a short sine wave click on each beat, with an accented
/// click on beat 1 of each bar.
public final class MetronomeGenerator: @unchecked Sendable {
    public let sourceNode: AVAudioSourceNode

    private let renderState: RenderState

    private let clickFrequencyHz: Double = 1000.0
    private let accentFrequencyHz: Double = 1500.0
    private let clickDurationMs: Double = 15.0

    /// Shared mutable state read by the audio render thread.
    /// Property access on individual primitives is safe for prototype
    /// purposes — worst case is a one-buffer stale read.
    private final class RenderState {
        var sampleRate: Double
        var bpm: Double = 120.0
        var beatsPerBar: Int = 4
        var sampleCounter: Int64 = 0
        var clickDurationSamples: Int
        let clickFrequencyHz: Double
        let accentFrequencyHz: Double

        init(sampleRate: Double, clickFreq: Double, accentFreq: Double, clickDurationMs: Double) {
            self.sampleRate = sampleRate
            self.clickDurationSamples = Int(sampleRate * clickDurationMs / 1000.0)
            self.clickFrequencyHz = clickFreq
            self.accentFrequencyHz = accentFreq
        }
    }

    public init(sampleRate: Double = 44100.0) {
        let state = RenderState(
            sampleRate: sampleRate,
            clickFreq: clickFrequencyHz,
            accentFreq: accentFrequencyHz,
            clickDurationMs: clickDurationMs
        )
        self.renderState = state

        self.sourceNode = AVAudioSourceNode { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let sr = state.sampleRate
            let currentBpm = state.bpm
            let samplesPerBeat = max(Int(sr * 60.0 / currentBpm), 1)

            for frame in 0..<Int(frameCount) {
                var sample: Float = 0.0

                let posInBeat = Int(state.sampleCounter) % samplesPerBeat
                let beatIndex = (Int(state.sampleCounter) / samplesPerBeat) % state.beatsPerBar

                if posInBeat < state.clickDurationSamples {
                    let freq = beatIndex == 0 ? state.accentFrequencyHz : state.clickFrequencyHz
                    let phase = Double(posInBeat) / sr
                    let envelope = 1.0 - (Double(posInBeat) / Double(state.clickDurationSamples))
                    sample = Float(sin(2.0 * .pi * freq * phase) * envelope * 0.5)
                }

                for buffer in buffers {
                    let channelData = buffer.mData!.assumingMemoryBound(to: Float.self)
                    channelData[frame] = sample
                }

                state.sampleCounter += 1
            }
            return noErr
        }

        // Start silent — volume is used as the enable/disable switch
        sourceNode.volume = 0
    }

    /// Updates the metronome parameters.
    public func update(bpm: Double, beatsPerBar: Int, sampleRate: Double) {
        renderState.bpm = bpm
        renderState.beatsPerBar = beatsPerBar
        renderState.sampleRate = sampleRate
        renderState.clickDurationSamples = Int(sampleRate * clickDurationMs / 1000.0)
    }

    /// Enables or disables the metronome output.
    public func setEnabled(_ enabled: Bool) {
        sourceNode.volume = enabled ? 1.0 : 0.0
    }

    /// Resets the sample counter (e.g., when transport resets to bar 1).
    public func reset() {
        renderState.sampleCounter = 0
    }
}
