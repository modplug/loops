import Foundation

public struct Tempo: Codable, Equatable, Sendable {
    /// Clamped to 20.0...300.0
    public var bpm: Double

    public var beatDurationSeconds: Double { 60.0 / bpm }

    public init(bpm: Double = 120.0) {
        self.bpm = min(max(bpm, 20.0), 300.0)
    }
}
