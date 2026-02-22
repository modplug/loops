import Foundation

public enum TransitionMode: Codable, Equatable, Sendable {
    case seamless
    case gap(durationSeconds: Double)
    case manualAdvance
}

public struct SetlistEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<SetlistEntry>
    public var songID: ID<Song>
    public var transitionToNext: TransitionMode
    /// Optional fade-in applied when this entry's song starts playing.
    public var fadeIn: FadeSettings?

    public init(
        id: ID<SetlistEntry> = ID(),
        songID: ID<Song>,
        transitionToNext: TransitionMode = .manualAdvance,
        fadeIn: FadeSettings? = nil
    ) {
        self.id = id
        self.songID = songID
        self.transitionToNext = transitionToNext
        self.fadeIn = fadeIn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ID.self, forKey: .id)
        songID = try c.decode(LoopsCore.ID<Song>.self, forKey: .songID)
        transitionToNext = try c.decode(TransitionMode.self, forKey: .transitionToNext)
        fadeIn = try c.decodeIfPresent(FadeSettings.self, forKey: .fadeIn)
    }
}
