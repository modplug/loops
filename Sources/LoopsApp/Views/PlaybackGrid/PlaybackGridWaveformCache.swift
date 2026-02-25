import Foundation
import LoopsCore

public final class PlaybackGridWaveformCache {
    public struct Level: Equatable {
        public let stride: Int
        public let peaks: [Float]
    }

    private struct Entry {
        let hash: Int
        let levels: [Level]
    }

    private var cache: [ID<SourceRecording>: Entry] = [:]
    private let lock = NSLock()

    public init() {}

    public func levels(for recordingID: ID<SourceRecording>, peaks: [Float]) -> [Level] {
        let hash = Self.hash(peaks)

        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[recordingID], cached.hash == hash {
            return cached.levels
        }

        let levels = Self.buildLevels(from: peaks)
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

    private static func buildLevels(from peaks: [Float]) -> [Level] {
        guard !peaks.isEmpty else { return [] }

        var levels: [Level] = [Level(stride: 1, peaks: peaks)]
        var current = peaks
        var stride = 1

        while current.count > 512 {
            stride *= 2
            var downsampled: [Float] = []
            downsampled.reserveCapacity((current.count + 1) / 2)

            var index = 0
            while index < current.count {
                let a = abs(current[index])
                let b = index + 1 < current.count ? abs(current[index + 1]) : a
                downsampled.append(max(a, b))
                index += 2
            }

            levels.append(Level(stride: stride, peaks: downsampled))
            current = downsampled
        }

        return levels
    }

    private static func hash(_ peaks: [Float]) -> Int {
        guard !peaks.isEmpty else { return 0 }
        var hasher = Hasher()
        hasher.combine(peaks.count)

        let sampleCount = min(16, peaks.count)
        let step = max(1, peaks.count / sampleCount)
        var i = 0
        while i < peaks.count {
            hasher.combine(peaks[i].bitPattern)
            i += step
        }

        return hasher.finalize()
    }
}
