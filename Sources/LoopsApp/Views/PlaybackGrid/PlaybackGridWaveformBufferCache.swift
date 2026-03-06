import Foundation
import Metal
import LoopsCore

final class PlaybackGridWaveformBufferCache {
    enum Mode: Hashable {
        case envelope
        case rms
    }

    private struct Key: Hashable {
        let recordingID: ID<SourceRecording>
        let stride: Int
        let hash: Int
        let mode: Mode
    }

    private var cache: [Key: MTLBuffer] = [:]
    private let lock = NSLock()

    func buffer(
        for recordingID: ID<SourceRecording>,
        level: PlaybackGridWaveformCache.Level,
        mode: Mode,
        device: MTLDevice
    ) -> MTLBuffer? {
        let key = Key(
            recordingID: recordingID,
            stride: level.stride,
            hash: Self.hash(level.extrema, rms: level.rms),
            mode: mode
        )

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let packedExtrema: [SIMD2<Float>]
        switch mode {
        case .envelope:
            packedExtrema = level.extrema.map { SIMD2<Float>($0.minimum, $0.maximum) }
        case .rms:
            packedExtrema = level.rms.map { rms in
                let clamped = min(max(rms, 0), 1)
                return SIMD2<Float>(-clamped, clamped)
            }
        }
        guard let buffer = packedExtrema.withUnsafeBytes({ ptr -> MTLBuffer? in
            guard let baseAddress = ptr.baseAddress else { return nil }
            return device.makeBuffer(bytes: baseAddress, length: ptr.count, options: .storageModeShared)
        }) else {
            return nil
        }

        lock.lock()
        cache[key] = buffer
        lock.unlock()
        return buffer
    }

    func invalidate(recordingID: ID<SourceRecording>) {
        lock.lock()
        cache = cache.filter { $0.key.recordingID != recordingID }
        lock.unlock()
    }

    func clear() {
        lock.lock()
        cache.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    private static func hash(_ extrema: [WaveformExtrema], rms: [Float]) -> Int {
        guard !extrema.isEmpty else { return 0 }
        var hasher = Hasher()
        hasher.combine(extrema.count)

        let sampleCount = min(16, extrema.count)
        let step = max(1, extrema.count / sampleCount)
        var index = 0
        while index < extrema.count {
            hasher.combine(extrema[index].minimum.bitPattern)
            hasher.combine(extrema[index].maximum.bitPattern)
            index += step
        }

        let rmsSampleCount = min(16, rms.count)
        if rmsSampleCount > 0 {
            let rmsStep = max(1, rms.count / rmsSampleCount)
            var rmsIndex = 0
            while rmsIndex < rms.count {
                hasher.combine(rms[rmsIndex].bitPattern)
                rmsIndex += rmsStep
            }
        }

        return hasher.finalize()
    }
}
