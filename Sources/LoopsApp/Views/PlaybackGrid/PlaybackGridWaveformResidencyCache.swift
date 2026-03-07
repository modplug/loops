import Foundation
import Metal
import LoopsCore

final class PlaybackGridWaveformResidencyCache {
    enum Mode: Hashable {
        case envelope
        case rms
    }

    struct Level: Equatable {
        let stride: Int
        let offset: Int
        let count: Int
        let mode: Mode
    }

    struct Residency {
        let buffer: MTLBuffer
        let levels: [Level]
    }

    private struct Entry {
        let hash: Int
        let residency: Residency
    }

    private var cache: [ID<SourceRecording>: Entry] = [:]
    private let lock = NSLock()

    func residency(
        for recordingID: ID<SourceRecording>,
        extrema: [WaveformExtrema],
        rms: [Float],
        device: MTLDevice
    ) -> Residency? {
        let hash = Self.hash(extrema: extrema, rms: rms)

        lock.lock()
        if let cached = cache[recordingID], cached.hash == hash {
            let residency = cached.residency
            lock.unlock()
            return residency
        }
        lock.unlock()

        let residency = Self.buildResidency(extrema: extrema, rms: rms, device: device)
        guard let residency else { return nil }

        lock.lock()
        cache[recordingID] = Entry(hash: hash, residency: residency)
        lock.unlock()
        return residency
    }

    func invalidate(recordingID: ID<SourceRecording>) {
        lock.lock()
        cache.removeValue(forKey: recordingID)
        lock.unlock()
    }

    func clear() {
        lock.lock()
        cache.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    private static func buildResidency(
        extrema: [WaveformExtrema],
        rms: [Float],
        device: MTLDevice
    ) -> Residency? {
        guard !extrema.isEmpty else { return nil }

        let normalizedRMS = normalizeRMS(rms, to: extrema.count)

        var envelopeLevels: [[SIMD2<Float>]] = [extrema.map { SIMD2<Float>($0.minimum, $0.maximum) }]
        var rmsLevels: [[SIMD2<Float>]] = [normalizedRMS.map { value in
            let clamped = min(max(value, 0), 1)
            return SIMD2<Float>(-clamped, clamped)
        }]
        var levels: [Level] = []
        var stride = 1

        while let currentEnvelope = envelopeLevels.last,
              let currentRMS = rmsLevels.last,
              currentEnvelope.count > 512 {
            stride *= 2
            envelopeLevels.append(downsampleEnvelope(currentEnvelope))
            rmsLevels.append(downsampleEnvelope(currentRMS))
        }

        var packed: [SIMD2<Float>] = []
        packed.reserveCapacity(envelopeLevels.reduce(0) { $0 + $1.count } + rmsLevels.reduce(0) { $0 + $1.count })

        stride = 1
        for level in envelopeLevels {
            levels.append(Level(
                stride: stride,
                offset: packed.count,
                count: level.count,
                mode: .envelope
            ))
            packed.append(contentsOf: level)
            stride *= 2
        }

        stride = 1
        for level in rmsLevels {
            levels.append(Level(
                stride: stride,
                offset: packed.count,
                count: level.count,
                mode: .rms
            ))
            packed.append(contentsOf: level)
            stride *= 2
        }

        return packed.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress,
                  let buffer = device.makeBuffer(bytes: base, length: ptr.count, options: .storageModeShared) else {
                return nil
            }
            return Residency(buffer: buffer, levels: levels)
        }
    }

    private static func normalizeRMS(_ rms: [Float], to count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !rms.isEmpty else { return Array(repeating: 0, count: count) }
        if rms.count == count { return rms }

        var output: [Float] = []
        output.reserveCapacity(count)
        for index in 0..<count {
            let sourceIndex = min(
                rms.count - 1,
                Int((Double(index) / Double(max(count - 1, 1))) * Double(max(rms.count - 1, 0)))
            )
            output.append(rms[sourceIndex])
        }
        return output
    }

    private static func downsampleEnvelope(_ values: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard values.count > 1 else { return values }
        var output: [SIMD2<Float>] = []
        output.reserveCapacity((values.count + 1) / 2)
        var index = 0
        while index < values.count {
            let a = values[index]
            let b = index + 1 < values.count ? values[index + 1] : a
            output.append(SIMD2<Float>(min(a.x, b.x), max(a.y, b.y)))
            index += 2
        }
        return output
    }

    private static func hash(extrema: [WaveformExtrema], rms: [Float]) -> Int {
        guard !extrema.isEmpty else { return 0 }
        var hasher = Hasher()
        hasher.combine(extrema.count)
        hasher.combine(rms.count)

        let sampleCount = min(16, extrema.count)
        let step = max(1, extrema.count / sampleCount)
        var i = 0
        while i < extrema.count {
            hasher.combine(extrema[i].minimum.bitPattern)
            hasher.combine(extrema[i].maximum.bitPattern)
            i += step
        }

        let rmsSampleCount = min(16, rms.count)
        if rmsSampleCount > 0 {
            let rmsStep = max(1, rms.count / rmsSampleCount)
            var j = 0
            while j < rms.count {
                hasher.combine(rms[j].bitPattern)
                j += rmsStep
            }
        }

        return hasher.finalize()
    }
}
