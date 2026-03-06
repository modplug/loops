import Foundation
import LoopsCore

public final class PlaybackGridWaveformCache {
    public struct Level: Equatable {
        public let stride: Int
        public let extrema: [WaveformExtrema]
        public let rms: [Float]
    }

    private struct Entry {
        let hash: Int
        let levels: [Level]
    }

    private var cache: [ID<SourceRecording>: Entry] = [:]
    private let lock = NSLock()

    public init() {}

    public func levels(for recordingID: ID<SourceRecording>, extrema: [WaveformExtrema], rms: [Float]) -> [Level] {
        let hash = Self.hash(extrema: extrema, rms: rms)

        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[recordingID], cached.hash == hash {
            return cached.levels
        }

        let levels = Self.buildLevels(from: extrema, rms: rms)
        cache[recordingID] = Entry(hash: hash, levels: levels)
        return levels
    }

    public func invalidate(recordingID: ID<SourceRecording>) {
        lock.lock()
        cache.removeValue(forKey: recordingID)
        lock.unlock()
    }

    public func clear() {
        lock.lock()
        cache.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    private static func buildLevels(from extrema: [WaveformExtrema], rms: [Float]) -> [Level] {
        guard !extrema.isEmpty else { return [] }

        let baseRMS = normalizedRMS(rms, matching: extrema.count)
        var levels: [Level] = [Level(stride: 1, extrema: extrema, rms: baseRMS)]
        var current = extrema
        var currentRMS = baseRMS
        var stride = 1

        while current.count > 512 {
            stride *= 2
            var downsampled: [WaveformExtrema] = []
            downsampled.reserveCapacity((current.count + 1) / 2)
            var downsampledRMS: [Float] = []
            downsampledRMS.reserveCapacity((currentRMS.count + 1) / 2)

            var index = 0
            while index < current.count {
                let a = current[index]
                let b = index + 1 < current.count ? current[index + 1] : a
                downsampled.append(WaveformExtrema(
                    minimum: min(a.minimum, b.minimum),
                    maximum: max(a.maximum, b.maximum)
                ))
                let rmsA = currentRMS[index]
                let rmsB = index + 1 < currentRMS.count ? currentRMS[index + 1] : rmsA
                downsampledRMS.append(sqrt(((rmsA * rmsA) + (rmsB * rmsB)) * 0.5))
                index += 2
            }

            levels.append(Level(stride: stride, extrema: downsampled, rms: downsampledRMS))
            current = downsampled
            currentRMS = downsampledRMS
        }

        return levels
    }

    private static func normalizedRMS(_ rms: [Float], matching count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !rms.isEmpty else { return Array(repeating: 0, count: count) }
        if rms.count == count { return rms }

        var normalized = [Float]()
        normalized.reserveCapacity(count)
        for index in 0..<count {
            let sourceIndex = min(rms.count - 1, Int((Double(index) / Double(max(count - 1, 1))) * Double(max(rms.count - 1, 0))))
            normalized.append(rms[sourceIndex])
        }
        return normalized
    }

    private static func hash(extrema: [WaveformExtrema], rms: [Float]) -> Int {
        guard !extrema.isEmpty else { return 0 }
        var hasher = Hasher()
        hasher.combine(extrema.count)

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
            var rmsIndex = 0
            while rmsIndex < rms.count {
                hasher.combine(rms[rmsIndex].bitPattern)
                rmsIndex += rmsStep
            }
        }

        return hasher.finalize()
    }
}
