import Foundation
import LoopsCore

public struct TrackRecordSession: Sendable, Equatable {
    public let trackID: ID<Track>
    public let containerID: ID<Container>
    public let filename: String
    public let startBar: Double
    public let startSampleOffset: Int64
    public let sampleCount: Int64
    public let droppedBufferCount: Int
    public let droppedSampleCount: Int64

    public init(
        trackID: ID<Track>,
        containerID: ID<Container>,
        filename: String,
        startBar: Double,
        startSampleOffset: Int64,
        sampleCount: Int64,
        droppedBufferCount: Int,
        droppedSampleCount: Int64
    ) {
        self.trackID = trackID
        self.containerID = containerID
        self.filename = filename
        self.startBar = startBar
        self.startSampleOffset = startSampleOffset
        self.sampleCount = sampleCount
        self.droppedBufferCount = droppedBufferCount
        self.droppedSampleCount = droppedSampleCount
    }
}

public struct RecordControllerDiagnostics: Sendable, Equatable {
    public let activeSessionCount: Int
    public let totalRecordedSampleCount: Int64
    public let totalDroppedBufferCount: Int
    public let totalDroppedSampleCount: Int64
    public let overloadedSessionCount: Int

    public init(
        activeSessionCount: Int,
        totalRecordedSampleCount: Int64,
        totalDroppedBufferCount: Int,
        totalDroppedSampleCount: Int64,
        overloadedSessionCount: Int
    ) {
        self.activeSessionCount = activeSessionCount
        self.totalRecordedSampleCount = totalRecordedSampleCount
        self.totalDroppedBufferCount = totalDroppedBufferCount
        self.totalDroppedSampleCount = totalDroppedSampleCount
        self.overloadedSessionCount = overloadedSessionCount
    }
}
