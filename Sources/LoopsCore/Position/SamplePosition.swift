import Foundation

public struct SamplePosition: Codable, Equatable, Comparable, Sendable {
    public var sampleOffset: Int64

    public init(sampleOffset: Int64 = 0) {
        self.sampleOffset = sampleOffset
    }

    public static func < (lhs: SamplePosition, rhs: SamplePosition) -> Bool {
        lhs.sampleOffset < rhs.sampleOffset
    }
}
