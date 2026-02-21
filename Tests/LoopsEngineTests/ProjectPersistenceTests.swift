import Testing
import Foundation
@testable import LoopsEngine
@testable import LoopsCore

@Suite("ProjectPersistence Tests")
struct ProjectPersistenceTests {
    private let persistence = ProjectPersistence()

    private func temporaryBundleURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("test-\(UUID().uuidString).loops")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Save and load empty project")
    func saveAndLoadEmptyProject() throws {
        let url = temporaryBundleURL()
        defer { cleanup(url) }

        let project = Project(name: "Empty Test")
        try persistence.save(project, to: url)

        let loaded = try persistence.load(from: url)
        #expect(loaded.name == "Empty Test")
        #expect(loaded.songs.isEmpty)
        #expect(loaded.setlists.isEmpty)
        #expect(loaded.sourceRecordings.isEmpty)
        #expect(loaded.schemaVersion == 1)
    }

    @Test("Save and load project with songs and tracks")
    func saveAndLoadWithContent() throws {
        let url = temporaryBundleURL()
        defer { cleanup(url) }

        let track = Track(name: "Guitar", kind: .audio, orderIndex: 0)
        let song = Song(name: "Rock Song", tempo: Tempo(bpm: 140.0), tracks: [track])
        let project = Project(name: "Band Project", songs: [song])

        try persistence.save(project, to: url)
        let loaded = try persistence.load(from: url)

        #expect(loaded.name == "Band Project")
        #expect(loaded.songs.count == 1)
        #expect(loaded.songs[0].name == "Rock Song")
        #expect(loaded.songs[0].tempo.bpm == 140.0)
        #expect(loaded.songs[0].tracks.count == 1)
        #expect(loaded.songs[0].tracks[0].name == "Guitar")
        #expect(loaded.songs[0].tracks[0].kind == .audio)
    }

    @Test("Bundle directory structure is created")
    func bundleStructureCreated() throws {
        let url = temporaryBundleURL()
        defer { cleanup(url) }

        let project = Project()
        try persistence.save(project, to: url)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: url.path))
        #expect(fm.fileExists(atPath: url.appendingPathComponent("project.json").path))
        #expect(fm.fileExists(atPath: url.appendingPathComponent("audio").path))
    }

    @Test("Save overwrites existing project")
    func saveOverwrites() throws {
        let url = temporaryBundleURL()
        defer { cleanup(url) }

        var project = Project(name: "Version 1")
        try persistence.save(project, to: url)

        project.name = "Version 2"
        try persistence.save(project, to: url)

        let loaded = try persistence.load(from: url)
        #expect(loaded.name == "Version 2")
    }

    @Test("Load from nonexistent path throws projectLoadFailed")
    func loadNonexistent() throws {
        let url = temporaryBundleURL()

        #expect(throws: LoopsError.self) {
            _ = try persistence.load(from: url)
        }
    }

    @Test("Full project round-trip through persistence")
    func fullProjectRoundTrip() throws {
        let url = temporaryBundleURL()
        defer { cleanup(url) }

        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(
            id: recordingID,
            filename: "test.caf",
            sampleRate: 48000.0,
            sampleCount: 96000
        )

        let container = Container(
            name: "Intro",
            startBar: 1,
            lengthBars: 4,
            sourceRecordingID: recordingID
        )

        let track = Track(
            name: "Lead",
            kind: .audio,
            containers: [container],
            orderIndex: 0
        )

        let song = Song(
            name: "Test Song",
            tempo: Tempo(bpm: 100.0),
            timeSignature: TimeSignature(beatsPerBar: 3, beatUnit: 4),
            tracks: [track]
        )

        let setlist = Setlist(
            name: "Live Set",
            entries: [
                SetlistEntry(songID: song.id, transitionToNext: .gap(durationSeconds: 1.5))
            ]
        )

        let mapping = MIDIMapping(
            control: .stop,
            trigger: .noteOn(channel: 0, note: 36)
        )

        let project = Project(
            name: "Full Project",
            songs: [song],
            setlists: [setlist],
            sourceRecordings: [recordingID: recording],
            midiMappings: [mapping],
            audioDeviceSettings: AudioDeviceSettings(bufferSize: 128)
        )

        try persistence.save(project, to: url)
        let loaded = try persistence.load(from: url)

        #expect(project == loaded)
    }
}
