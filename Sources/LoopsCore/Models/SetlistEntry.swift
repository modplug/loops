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

    public init(
        id: ID<SetlistEntry> = ID(),
        songID: ID<Song>,
        transitionToNext: TransitionMode = .manualAdvance
    ) {
        self.id = id
        self.songID = songID
        self.transitionToNext = transitionToNext
    }
}
