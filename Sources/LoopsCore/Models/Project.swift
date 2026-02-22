import Foundation

public struct Project: Codable, Equatable, Sendable {
    public var id: ID<Project>
    public var name: String
    public var songs: [Song]
    public var setlists: [Setlist]
    public var sourceRecordings: [ID<SourceRecording>: SourceRecording]
    public var midiMappings: [MIDIMapping]
    public var midiParameterMappings: [MIDIParameterMapping]
    public var audioDeviceSettings: AudioDeviceSettings
    public var schemaVersion: Int

    public init(
        id: ID<Project> = ID(),
        name: String = "Untitled Project",
        songs: [Song] = [],
        setlists: [Setlist] = [],
        sourceRecordings: [ID<SourceRecording>: SourceRecording] = [:],
        midiMappings: [MIDIMapping] = [],
        midiParameterMappings: [MIDIParameterMapping] = [],
        audioDeviceSettings: AudioDeviceSettings = AudioDeviceSettings(),
        schemaVersion: Int = 1
    ) {
        self.id = id
        self.name = name
        self.songs = songs
        self.setlists = setlists
        self.sourceRecordings = sourceRecordings
        self.midiMappings = midiMappings
        self.midiParameterMappings = midiParameterMappings
        self.audioDeviceSettings = audioDeviceSettings
        self.schemaVersion = schemaVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ID<Project>.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        songs = try container.decode([Song].self, forKey: .songs)
        setlists = try container.decode([Setlist].self, forKey: .setlists)
        sourceRecordings = try container.decode([ID<SourceRecording>: SourceRecording].self, forKey: .sourceRecordings)
        midiMappings = try container.decode([MIDIMapping].self, forKey: .midiMappings)
        midiParameterMappings = try container.decodeIfPresent([MIDIParameterMapping].self, forKey: .midiParameterMappings) ?? []
        audioDeviceSettings = try container.decode(AudioDeviceSettings.self, forKey: .audioDeviceSettings)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    }
}
