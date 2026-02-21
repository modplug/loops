import Foundation

public struct Project: Codable, Equatable, Sendable {
    public var id: ID<Project>
    public var name: String
    public var songs: [Song]
    public var setlists: [Setlist]
    public var sourceRecordings: [ID<SourceRecording>: SourceRecording]
    public var midiMappings: [MIDIMapping]
    public var audioDeviceSettings: AudioDeviceSettings
    public var schemaVersion: Int

    public init(
        id: ID<Project> = ID(),
        name: String = "Untitled Project",
        songs: [Song] = [],
        setlists: [Setlist] = [],
        sourceRecordings: [ID<SourceRecording>: SourceRecording] = [:],
        midiMappings: [MIDIMapping] = [],
        audioDeviceSettings: AudioDeviceSettings = AudioDeviceSettings(),
        schemaVersion: Int = 1
    ) {
        self.id = id
        self.name = name
        self.songs = songs
        self.setlists = setlists
        self.sourceRecordings = sourceRecordings
        self.midiMappings = midiMappings
        self.audioDeviceSettings = audioDeviceSettings
        self.schemaVersion = schemaVersion
    }
}
