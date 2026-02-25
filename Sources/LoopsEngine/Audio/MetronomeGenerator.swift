import Foundation
import AVFoundation
import LoopsCore

/// Generates metronome click audio via AVAudioSourceNode.
/// Produces a short sine wave click on each beat (with subdivision support),
/// with an accented click on beat 1 of each bar.
public final class MetronomeGenerator: @unchecked Sendable {
    public let sourceNode: AVAudioSourceNode

    private let renderState: RenderState

    private let clickFrequencyHz: Double = 1000.0
    private let accentFrequencyHz: Double = 1500.0
    private let subdivisionFrequencyHz: Double = 800.0
    private let clickDurationMs: Double = 15.0

    /// User-facing volume level (0.0–1.0), independent of master track volume.
    public private(set) var volume: Float = 0.8

    /// Whether the metronome is currently enabled (producing sound).
    private var isEnabled: Bool = false

    /// Shared mutable state read by the audio render thread.
    /// Protected by an NSLock: render thread uses try() (never blocks),
    /// main thread uses lock/unlock for writes.
    private final class RenderState {
        let lock = NSLock()
        var sampleRate: Double
        var bpm: Double = 120.0
        var beatsPerBar: Int = 4
        var sampleCounter: Int64 = 0
        var clickDurationSamples: Int
        var volume: Float = 0.8
        var clicksPerBeat: Double = 1.0
        let clickFrequencyHz: Double
        let accentFrequencyHz: Double
        let subdivisionFrequencyHz: Double

        init(sampleRate: Double, clickFreq: Double, accentFreq: Double, subdivisionFreq: Double, clickDurationMs: Double) {
            self.sampleRate = sampleRate
            self.clickDurationSamples = Int(sampleRate * clickDurationMs / 1000.0)
            self.clickFrequencyHz = clickFreq
            self.accentFrequencyHz = accentFreq
            self.subdivisionFrequencyHz = subdivisionFreq
        }
    }

    public init(sampleRate: Double = 44100.0) {
        let state = RenderState(
            sampleRate: sampleRate,
            clickFreq: clickFrequencyHz,
            accentFreq: accentFrequencyHz,
            subdivisionFreq: subdivisionFrequencyHz,
            clickDurationMs: clickDurationMs
        )
        self.renderState = state

        self.sourceNode = AVAudioSourceNode { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)

            // Try to acquire the lock without blocking (audio-safe).
            // If contended, output silence for this callback (~1ms, inaudible).
            guard state.lock.try() else {
                for buffer in buffers {
                    let data = buffer.mData!.assumingMemoryBound(to: Float.self)
                    memset(data, 0, Int(frameCount) * MemoryLayout<Float>.size)
                }
                return noErr
            }
            defer { state.lock.unlock() }

            // Snapshot all state into locals while holding the lock
            let sr = state.sampleRate
            let currentBpm = state.bpm
            let vol = state.volume
            let clicksPerBeat = state.clicksPerBeat
            let beatsPerBar = state.beatsPerBar
            let clickDurationSamples = state.clickDurationSamples
            let accentFreq = state.accentFrequencyHz
            let clickFreq = state.clickFrequencyHz
            let subdivisionFreq = state.subdivisionFrequencyHz
            var sampleCounter = state.sampleCounter

            let samplesPerBeat = max(sr * 60.0 / currentBpm, 1.0)

            // Samples per subdivision click
            let samplesPerClick: Double
            if clicksPerBeat > 0 {
                samplesPerClick = samplesPerBeat / clicksPerBeat
            } else {
                samplesPerClick = samplesPerBeat
            }

            let totalClicksPerBar = clicksPerBeat * Double(beatsPerBar)

            for frame in 0..<Int(frameCount) {
                var sample: Float = 0.0

                let counter = Double(sampleCounter)
                let totalSamplesPerBar = samplesPerBeat * Double(beatsPerBar)
                let posInBar = counter.truncatingRemainder(dividingBy: max(totalSamplesPerBar, 1.0))

                // Which click within the bar are we at?
                let clickIndex = Int(posInBar / max(samplesPerClick, 1.0))
                let posInClick = Int(posInBar.truncatingRemainder(dividingBy: max(samplesPerClick, 1.0)))

                if posInClick < clickDurationSamples, clickIndex < Int(totalClicksPerBar.rounded(.up)) {
                    // Beat 1 accent: clickIndex == 0
                    // Regular beat: clickIndex is on a beat boundary
                    let isOnBeat = clicksPerBeat > 0 && (Double(clickIndex).truncatingRemainder(dividingBy: clicksPerBeat) < 0.001)
                    let isBeat1 = clickIndex == 0

                    let freq: Double
                    let amplitude: Double
                    if isBeat1 {
                        freq = accentFreq
                        amplitude = 0.5
                    } else if isOnBeat {
                        freq = clickFreq
                        amplitude = 0.5
                    } else {
                        freq = subdivisionFreq
                        amplitude = 0.3
                    }

                    let phase = Double(posInClick) / sr
                    let envelope = 1.0 - (Double(posInClick) / Double(clickDurationSamples))
                    sample = Float(sin(2.0 * .pi * freq * phase) * envelope * amplitude) * vol
                }

                for buffer in buffers {
                    let channelData = buffer.mData!.assumingMemoryBound(to: Float.self)
                    channelData[frame] = sample
                }

                sampleCounter += 1
            }

            // Write back the updated counter
            state.sampleCounter = sampleCounter
            return noErr
        }

        // Start silent — volume is used as the enable/disable switch
        sourceNode.volume = 0
    }

    /// Updates the metronome parameters.
    public func update(bpm: Double, beatsPerBar: Int, sampleRate: Double) {
        renderState.lock.lock()
        renderState.bpm = bpm
        renderState.beatsPerBar = beatsPerBar
        renderState.sampleRate = sampleRate
        renderState.clickDurationSamples = Int(sampleRate * clickDurationMs / 1000.0)
        renderState.lock.unlock()
    }

    /// Sets the metronome volume (clamped to 0.0–1.0).
    public func setVolume(_ newVolume: Float) {
        volume = min(max(newVolume, 0.0), 1.0)
        renderState.lock.lock()
        renderState.volume = volume
        renderState.lock.unlock()
    }

    /// Sets the subdivision mode, controlling clicks per beat.
    public func setSubdivision(_ subdivision: MetronomeSubdivision) {
        renderState.lock.lock()
        renderState.clicksPerBeat = subdivision.clicksPerBeat
        renderState.lock.unlock()
    }

    /// Enables or disables the metronome output.
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        sourceNode.volume = enabled ? 1.0 : 0.0
    }

    /// Resets the sample counter (e.g., when transport resets to bar 1).
    public func reset() {
        renderState.lock.lock()
        renderState.sampleCounter = 0
        renderState.lock.unlock()
    }

    /// Returns the number of clicks per bar for the given subdivision in the given time signature.
    public static func clicksPerBar(subdivision: MetronomeSubdivision, beatsPerBar: Int) -> Double {
        return subdivision.clicksPerBeat * Double(beatsPerBar)
    }
}
