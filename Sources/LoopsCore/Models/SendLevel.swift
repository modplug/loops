import Foundation

public struct SendLevel: Codable, Equatable, Sendable {
    public var busTrackID: ID<Track>
    /// 0.0 (silent) to 1.0 (unity)
    public var level: Float
    public var isPreFader: Bool

    public init(busTrackID: ID<Track>, level: Float = 0.0, isPreFader: Bool = false) {
        self.busTrackID = busTrackID
        self.level = level
        self.isPreFader = isPreFader
    }
}
