import Foundation

public struct Song: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<Song>
    public var name: String
    public var tempo: Tempo
    public var timeSignature: TimeSignature
    public var tracks: [Track]
    public var countInBars: Int
    public var sections: [SectionRegion]
    public var metronomeConfig: MetronomeConfig
    public var viewSettings: SongViewSettings

    public init(
        id: ID<Song> = ID(),
        name: String = "Untitled Song",
        tempo: Tempo = Tempo(),
        timeSignature: TimeSignature = TimeSignature(),
        tracks: [Track] = [],
        countInBars: Int = 0,
        sections: [SectionRegion] = [],
        metronomeConfig: MetronomeConfig = MetronomeConfig(),
        viewSettings: SongViewSettings = SongViewSettings()
    ) {
        self.id = id
        self.name = name
        self.tempo = tempo
        self.timeSignature = timeSignature
        self.tracks = tracks
        self.countInBars = countInBars
        self.sections = sections
        self.metronomeConfig = metronomeConfig
        self.viewSettings = viewSettings
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, tempo, timeSignature, tracks, countInBars, sections, metronomeConfig, viewSettings
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
        metronomeConfig = try c.decodeIfPresent(MetronomeConfig.self, forKey: .metronomeConfig) ?? MetronomeConfig()
        viewSettings = try c.decodeIfPresent(SongViewSettings.self, forKey: .viewSettings) ?? SongViewSettings()
    }

    // MARK: - Master Track

    /// Returns the master track, if one exists.
    public var masterTrack: Track? {
        tracks.first(where: { $0.kind == .master })
    }

    /// Ensures the song has a master track. If absent, creates one at the end.
    public mutating func ensureMasterTrack() {
        guard !tracks.contains(where: { $0.kind == .master }) else {
            ensureMasterTrackLast()
            return
        }
        let master = Track(
            name: "Master",
            kind: .master,
            orderIndex: tracks.count
        )
        tracks.append(master)
    }

    /// Ensures the master track is always at the end of the track list.
    public mutating func ensureMasterTrackLast() {
        guard let masterIndex = tracks.firstIndex(where: { $0.kind == .master }) else { return }
        let lastIndex = tracks.count - 1
        if masterIndex != lastIndex {
            let master = tracks.remove(at: masterIndex)
            tracks.append(master)
        }
    }
}
