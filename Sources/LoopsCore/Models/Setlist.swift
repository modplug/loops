import Foundation

public struct Setlist: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<Setlist>
    public var name: String
    public var entries: [SetlistEntry]

    public init(
        id: ID<Setlist> = ID(),
        name: String = "Setlist",
        entries: [SetlistEntry] = []
    ) {
        self.id = id
        self.name = name
        self.entries = entries
    }
}
