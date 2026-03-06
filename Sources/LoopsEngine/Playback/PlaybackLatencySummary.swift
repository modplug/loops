import Foundation

public struct PlaybackLatencySummary: Sendable, Equatable {
    public let maxPathLatencySeconds: Double
    public let highLatencyTrackCount: Int
    public let compensatedTrackCount: Int
    public let highLatencyContainerCount: Int
    public let compensatedContainerCount: Int

    public init(
        maxPathLatencySeconds: Double = 0,
        highLatencyTrackCount: Int = 0,
        compensatedTrackCount: Int = 0,
        highLatencyContainerCount: Int = 0,
        compensatedContainerCount: Int = 0
    ) {
        self.maxPathLatencySeconds = maxPathLatencySeconds
        self.highLatencyTrackCount = highLatencyTrackCount
        self.compensatedTrackCount = compensatedTrackCount
        self.highLatencyContainerCount = highLatencyContainerCount
        self.compensatedContainerCount = compensatedContainerCount
    }

    public var hasLatencyCompensation: Bool {
        maxPathLatencySeconds > 0
    }
}
