import Foundation

public protocol PositionConverter: Sendable {
    func samplePosition(for barBeat: BarBeatPosition, sampleRate: Double) -> SamplePosition
    func barBeatPosition(for sample: SamplePosition, sampleRate: Double) -> BarBeatPosition
    func sampleCount(forBars bars: Int, sampleRate: Double) -> Int64
}
