import Foundation
import AVFoundation

public struct PlaybackStartReceipt: Sendable, Equatable {
    public let hostStartTime: UInt64?
    public let startupCompensationSeconds: Double
    public let maxPathLatencySeconds: Double
    public let effectiveHeadroomSeconds: Double
    public let monitorLatencySeconds: Double?

    public init(
        hostStartTime: UInt64?,
        startupCompensationSeconds: Double,
        maxPathLatencySeconds: Double,
        effectiveHeadroomSeconds: Double,
        monitorLatencySeconds: Double? = nil
    ) {
        self.hostStartTime = hostStartTime
        self.startupCompensationSeconds = startupCompensationSeconds
        self.maxPathLatencySeconds = maxPathLatencySeconds
        self.effectiveHeadroomSeconds = effectiveHeadroomSeconds
        self.monitorLatencySeconds = monitorLatencySeconds
    }
}

struct PlaybackStartPlannerItem: Sendable {
    let id: ObjectIdentifier
    let latencySeconds: Double
}

struct PlaybackStartPlan: Sendable {
    let hostTimes: [ObjectIdentifier: UInt64]
    let maxPathLatencySeconds: Double
    let startHeadroomSeconds: Double
    let prepareFrames: AVAudioFrameCount
}

struct PlaybackStartPlanner {
    func makeInitialPlan(
        items: [PlaybackStartPlannerItem],
        sampleRate: Double,
        outputMaxFrames: Double,
        recentStartDispatchSeconds: Double
    ) -> PlaybackStartPlan {
        guard !items.isEmpty else {
            return PlaybackStartPlan(
                hostTimes: [:],
                maxPathLatencySeconds: 0,
                startHeadroomSeconds: 0,
                prepareFrames: 2048
            )
        }

        let maxPathLatency = items.map(\.latencySeconds).max() ?? 0
        let maxFrames = outputMaxFrames > 0 ? outputMaxFrames : 512
        let sr = sampleRate > 0 ? sampleRate : 44100.0
        let renderQuantumSeconds = maxFrames / sr
        let baseHeadroom = max(0.060, renderQuantumSeconds * 3.0 + 0.010)
        let fanOutHeadroom = Double(max(0, items.count - 1)) * 0.006
        let historicalDispatch = max(0.0, recentStartDispatchSeconds * 1.2)
        let startHeadroom = min(1.250, baseHeadroom + fanOutHeadroom + historicalDispatch)

        let earliestStartHostTime = Self.hostTime(afterSeconds: startHeadroom)
        var hostTimes: [ObjectIdentifier: UInt64] = [:]
        hostTimes.reserveCapacity(items.count)
        for item in items {
            let delaySeconds = max(0, maxPathLatency - item.latencySeconds)
            hostTimes[item.id] = Self.offsetHostTime(base: earliestStartHostTime, bySeconds: delaySeconds)
        }

        let configuredMaxFrames = max(512, Int(outputMaxFrames))
        let prepareFrames = AVAudioFrameCount(max(2048, configuredMaxFrames * 8))
        return PlaybackStartPlan(
            hostTimes: hostTimes,
            maxPathLatencySeconds: maxPathLatency,
            startHeadroomSeconds: startHeadroom,
            prepareFrames: prepareFrames
        )
    }

    static func hostTime(afterSeconds seconds: Double) -> UInt64 {
        offsetHostTime(base: mach_absolute_time(), bySeconds: seconds)
    }

    static func offsetHostTime(base: UInt64, bySeconds seconds: Double) -> UInt64 {
        guard seconds > 0 else { return base }
        let nanos = UInt64(seconds * 1_000_000_000.0)
        return base &+ hostTicks(fromNanoseconds: nanos)
    }

    static func hostTicksToSeconds(_ ticks: UInt64) -> Double {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanos = Double(ticks) * Double(timebase.numer) / Double(timebase.denom)
        return nanos / 1_000_000_000.0
    }

    private static func hostTicks(fromNanoseconds nanos: UInt64) -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        guard timebase.numer > 0 else { return nanos }
        return nanos &* UInt64(timebase.denom) / UInt64(timebase.numer)
    }
}
