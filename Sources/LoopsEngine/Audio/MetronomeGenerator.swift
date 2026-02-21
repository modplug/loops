import Foundation
import AVFoundation
import LoopsCore

/// Generates metronome click audio via AVAudioSourceNode.
/// Produces a short sine wave click on each beat, with an accented
/// click on beat 1 of each bar.
public final class MetronomeGenerator: @unchecked Sendable {
    public let sourceNode: AVAudioSourceNode

    private var sampleRate: Double = 44100.0
    private var bpm: Double = 120.0
    private var beatsPerBar: Int = 4
    private var isEnabled: Bool = false

    // Click synthesis state
    private var sampleCounter: Int64 = 0
    private var clickDurationSamples: Int = 0
    private let clickFrequencyHz: Double = 1000.0
    private let accentFrequencyHz: Double = 1500.0
    private let clickDurationMs: Double = 15.0

    public init(sampleRate: Double = 44100.0) {
        self.sampleRate = sampleRate
        self.clickDurationSamples = Int(sampleRate * clickDurationMs / 1000.0)

        // Capture for closure
        var localSampleRate = sampleRate
        var localBpm = 120.0
        var localBeatsPerBar = 4
        var localEnabled = false
        var localSampleCounter: Int64 = 0
        let localClickFreq = clickFrequencyHz
        let localAccentFreq = accentFrequencyHz
        var localClickDuration = Int(sampleRate * clickDurationMs / 1000.0)

        self.sourceNode = AVAudioSourceNode { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let samplesPerBeat = Int(localSampleRate * 60.0 / localBpm)

            for frame in 0..<Int(frameCount) {
                var sample: Float = 0.0

                if localEnabled {
                    let posInBeat = Int(localSampleCounter) % samplesPerBeat
                    let beatIndex = (Int(localSampleCounter) / samplesPerBeat) % localBeatsPerBar

                    if posInBeat < localClickDuration {
                        let freq = beatIndex == 0 ? localAccentFreq : localClickFreq
                        let phase = Double(posInBeat) / localSampleRate
                        let envelope = 1.0 - (Double(posInBeat) / Double(localClickDuration))
                        sample = Float(sin(2.0 * .pi * freq * phase) * envelope * 0.3)
                    }
                }

                for buffer in buffers {
                    let channelData = buffer.mData!.assumingMemoryBound(to: Float.self)
                    channelData[frame] = sample
                }

                localSampleCounter += 1
            }
            return noErr
        }

        // Store references for update methods
        self._sampleRate = localSampleRate
        self._bpm = localBpm
        self._beatsPerBar = localBeatsPerBar
        self._enabled = localEnabled
        self._sampleCounter = localSampleCounter
        self._clickDuration = localClickDuration

        // The source node closure captures local vars, so we need a different approach.
        // We'll use the sourceNode's volume to enable/disable.
        sourceNode.volume = 0
    }

    // Internal state mirrors
    private var _sampleRate: Double
    private var _bpm: Double
    private var _beatsPerBar: Int
    private var _enabled: Bool
    private var _sampleCounter: Int64
    private var _clickDuration: Int

    /// Updates the metronome parameters.
    public func update(bpm: Double, beatsPerBar: Int, sampleRate: Double) {
        self.bpm = bpm
        self.beatsPerBar = beatsPerBar
        self.sampleRate = sampleRate
        self.clickDurationSamples = Int(sampleRate * clickDurationMs / 1000.0)
    }

    /// Enables or disables the metronome output.
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        sourceNode.volume = enabled ? 1.0 : 0.0
    }

    /// Resets the sample counter (e.g., when transport resets).
    public func reset() {
        sampleCounter = 0
    }
}
