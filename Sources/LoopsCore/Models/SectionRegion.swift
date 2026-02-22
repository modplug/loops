import Foundation

public struct SectionRegion: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<SectionRegion>
    public var name: String
    /// 1-based bar position.
    public var startBar: Int
    public var lengthBars: Int
    /// Hex color string, e.g. "#FF5733".
    public var color: String
    /// Optional notes for storyline annotations.
    public var notes: String?

    public var endBar: Int { startBar + lengthBars }

    public init(
        id: ID<SectionRegion> = ID(),
        name: String = "Section",
        startBar: Int = 1,
        lengthBars: Int = 4,
        color: String = "#5B9BD5",
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.startBar = startBar
        self.lengthBars = lengthBars
        self.color = color
        self.notes = notes
    }
}
