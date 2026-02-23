import Foundation

/// Persisted view/layout settings for a song's timeline.
public struct SongViewSettings: Codable, Equatable, Sendable {
    /// Per-track custom row heights. Tracks not in this dictionary use the default.
    public var trackHeights: [ID<Track>: Double]
    /// Width of the track header column in points.
    public var trackHeaderWidth: Double
    /// Horizontal zoom level (pixels per bar).
    public var pixelsPerBar: Double
    /// Set of track IDs with automation sub-lanes expanded.
    public var automationExpanded: Set<ID<Track>>

    public init(
        trackHeights: [ID<Track>: Double] = [:],
        trackHeaderWidth: Double = 160,
        pixelsPerBar: Double = 120,
        automationExpanded: Set<ID<Track>> = []
    ) {
        self.trackHeights = trackHeights
        self.trackHeaderWidth = trackHeaderWidth
        self.pixelsPerBar = pixelsPerBar
        self.automationExpanded = automationExpanded
    }

    private enum CodingKeys: String, CodingKey {
        case trackHeights, trackHeaderWidth, pixelsPerBar, automationExpanded
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trackHeights = try c.decodeIfPresent([ID<Track>: Double].self, forKey: .trackHeights) ?? [:]
        trackHeaderWidth = try c.decodeIfPresent(Double.self, forKey: .trackHeaderWidth) ?? 160
        pixelsPerBar = try c.decodeIfPresent(Double.self, forKey: .pixelsPerBar) ?? 120
        automationExpanded = try c.decodeIfPresent(Set<ID<Track>>.self, forKey: .automationExpanded) ?? []
    }
}
