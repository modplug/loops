import Foundation

public struct BarBeatPosition: Codable, Equatable, Comparable, Sendable {
    /// 1-based
    public var bar: Int
    /// 1-based within the bar
    public var beat: Int
    /// 0.0..<1.0
    public var subBeatFraction: Double

    public init(bar: Int = 1, beat: Int = 1, subBeatFraction: Double = 0.0) {
        self.bar = bar
        self.beat = beat
        self.subBeatFraction = subBeatFraction
    }

    public static func < (lhs: BarBeatPosition, rhs: BarBeatPosition) -> Bool {
        if lhs.bar != rhs.bar { return lhs.bar < rhs.bar }
        if lhs.beat != rhs.beat { return lhs.beat < rhs.beat }
        return lhs.subBeatFraction < rhs.subBeatFraction
    }
}
