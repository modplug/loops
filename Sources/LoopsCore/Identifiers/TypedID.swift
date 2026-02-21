import Foundation

/// Phantom-typed identifier to prevent mixing up IDs from different model types.
public struct ID<Phantom>: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init() { self.rawValue = UUID() }
    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(UUID.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
