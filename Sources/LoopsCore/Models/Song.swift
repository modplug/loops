import Foundation

public struct Song: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<Song>
    public var name: String
    public var tempo: Tempo
    public var timeSignature: TimeSignature
    public var tracks: [Track]

    public init(
        id: ID<Song> = ID(),
        name: String = "Untitled Song",
        tempo: Tempo = Tempo(),
        timeSignature: TimeSignature = TimeSignature(),
        tracks: [Track] = []
    ) {
        self.id = id
        self.name = name
        self.tempo = tempo
        self.timeSignature = timeSignature
        self.tracks = tracks
    }
}
