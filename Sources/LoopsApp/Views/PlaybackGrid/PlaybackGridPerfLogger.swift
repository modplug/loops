import Foundation
import QuartzCore

enum PlaybackGridPerfLogger {
    static let isEnabled: Bool = {
        ProcessInfo.processInfo.environment["LOOPS_GRID_PERF"] == "1"
        || UserDefaults.standard.bool(forKey: "PlaybackGridPerfLogs")
    }()

    private struct DurationStats {
        var totalMs: Double = 0
        var maxMs: Double = 0
        var count: Int = 0

        mutating func add(_ durationMs: Double) {
            totalMs += durationMs
            maxMs = max(maxMs, durationMs)
            count += 1
        }
    }

    private static let lock = NSLock()
    private static var counters: [String: Int] = [:]
    private static var durations: [String: DurationStats] = [:]
    private static var windowStart: CFTimeInterval = CACurrentMediaTime()
    private static let flushInterval: CFTimeInterval = 1.0

    @discardableResult
    static func tick(_ key: String) -> Bool {
        bump(key)
        return true
    }

    static func bump(_ key: String, by amount: Int = 1) {
        guard isEnabled else { return }
        lock.lock()
        counters[key, default: 0] += amount
        flushIfNeededLocked(now: CACurrentMediaTime())
        lock.unlock()
    }

    static func begin() -> CFTimeInterval {
        guard isEnabled else { return 0 }
        return CACurrentMediaTime()
    }

    static func end(_ key: String, _ startTime: CFTimeInterval) {
        guard isEnabled, startTime > 0 else { return }
        let elapsedMs = (CACurrentMediaTime() - startTime) * 1000.0
        recordDurationMs(key, elapsedMs)
    }

    static func recordDurationMs(_ key: String, _ durationMs: Double) {
        guard isEnabled else { return }
        lock.lock()
        var stats = durations[key] ?? DurationStats()
        stats.add(durationMs)
        durations[key] = stats
        flushIfNeededLocked(now: CACurrentMediaTime())
        lock.unlock()
    }

    static func log(_ message: String) {
        guard isEnabled else { return }
        print("[GRIDPERF] \(message)")
    }

    private static func flushIfNeededLocked(now: CFTimeInterval) {
        let elapsed = now - windowStart
        guard elapsed >= flushInterval else { return }

        if counters.isEmpty && durations.isEmpty {
            windowStart = now
            return
        }

        let counterSummary = counters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        let durationSummary = durations
            .sorted { $0.key < $1.key }
            .map { key, stats in
                let avgMs = stats.count > 0 ? (stats.totalMs / Double(stats.count)) : 0
                return "\(key)=\(format(avgMs))/\(format(stats.maxMs))ms[\(stats.count)]"
            }
            .joined(separator: " ")

        var segments: [String] = []
        segments.append("window=\(format(elapsed))s")
        if !counterSummary.isEmpty {
            segments.append(counterSummary)
        }
        if !durationSummary.isEmpty {
            segments.append(durationSummary)
        }
        print("[GRIDPERF] \(segments.joined(separator: " | "))")

        counters.removeAll(keepingCapacity: true)
        durations.removeAll(keepingCapacity: true)
        windowStart = now
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
