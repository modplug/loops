import Foundation

public struct TimeSignature: Codable, Equatable, Sendable {
    /// Numerator (e.g. 4)
    public var beatsPerBar: Int
    /// Denominator (e.g. 4 = quarter note)
    public var beatUnit: Int

    public init(beatsPerBar: Int = 4, beatUnit: Int = 4) {
        self.beatsPerBar = beatsPerBar
        self.beatUnit = beatUnit
    }
}
