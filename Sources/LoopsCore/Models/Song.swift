import Foundation

public struct Song: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<Song>
    public var name: String
    public var tempo: Tempo
    public var timeSignature: TimeSignature
    public var tracks: [Track]
    public var countInBars: Int
    public var sections: [SectionRegion]

    public init(
        id: ID<Song> = ID(),
        name: String = "Untitled Song",
        tempo: Tempo = Tempo(),
        timeSignature: TimeSignature = TimeSignature(),
        tracks: [Track] = [],
        countInBars: Int = 0,
        sections: [SectionRegion] = []
    ) {
        self.id = id
        self.name = name
        self.tempo = tempo
        self.timeSignature = timeSignature
        self.tracks = tracks
        self.countInBars = countInBars
        self.sections = sections
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, tempo, timeSignature, tracks, countInBars, sections
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        tempo = try c.decode(Tempo.self, forKey: .tempo)
        timeSignature = try c.decode(TimeSignature.self, forKey: .timeSignature)
        tracks = try c.decode([Track].self, forKey: .tracks)
        countInBars = try c.decodeIfPresent(Int.self, forKey: .countInBars) ?? 0
        sections = try c.decodeIfPresent([SectionRegion].self, forKey: .sections) ?? []
    }
}
