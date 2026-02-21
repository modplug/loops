import Foundation

public enum BoundaryMode: String, Codable, Sendable, CaseIterable {
    case hardCut, crossfade, overdub
}

public enum LoopCount: Codable, Equatable, Sendable {
    case count(Int)
    case fill
}

public struct LoopSettings: Codable, Equatable, Sendable {
    public var loopCount: LoopCount
    public var boundaryMode: BoundaryMode
    /// Only used when boundaryMode == .crossfade
    public var crossfadeDurationMs: Double

    public init(
        loopCount: LoopCount = .fill,
        boundaryMode: BoundaryMode = .hardCut,
        crossfadeDurationMs: Double = 10.0
    ) {
        self.loopCount = loopCount
        self.boundaryMode = boundaryMode
        self.crossfadeDurationMs = crossfadeDurationMs
    }
}
