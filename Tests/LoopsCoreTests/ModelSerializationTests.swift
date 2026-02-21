import Testing
import Foundation
@testable import LoopsCore

@Suite("Model Serialization Round-Trip Tests")
struct ModelSerializationTests {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - TypedID

    @Test("ID round-trips through JSON")
    func idRoundTrip() throws {
        let id = ID<Project>()
        let decoded = try roundTrip(id)
        #expect(id == decoded)
    }

    // MARK: - TimeSignature

    @Test("TimeSignature round-trips")
    func timeSignatureRoundTrip() throws {
        let ts = TimeSignature(beatsPerBar: 3, beatUnit: 8)
        let decoded = try roundTrip(ts)
        #expect(ts == decoded)
    }

    // MARK: - Tempo

    @Test("Tempo round-trips and clamps BPM")
    func tempoRoundTrip() throws {
        let tempo = Tempo(bpm: 140.0)
        let decoded = try roundTrip(tempo)
        #expect(tempo == decoded)

        // Test clamping
        let tooFast = Tempo(bpm: 999.0)
        #expect(tooFast.bpm == 300.0)
        let tooSlow = Tempo(bpm: 5.0)
        #expect(tooSlow.bpm == 20.0)
    }

    // MARK: - LoopSettings

    @Test("LoopSettings with fill round-trips")
    func loopSettingsFillRoundTrip() throws {
        let settings = LoopSettings(loopCount: .fill, boundaryMode: .crossfade, crossfadeDurationMs: 25.0)
        let decoded = try roundTrip(settings)
        #expect(settings == decoded)
    }

    @Test("LoopSettings with count round-trips")
    func loopSettingsCountRoundTrip() throws {
        let settings = LoopSettings(loopCount: .count(4), boundaryMode: .overdub, crossfadeDurationMs: 0.0)
        let decoded = try roundTrip(settings)
        #expect(settings == decoded)
    }

    // MARK: - SourceRecording

    @Test("SourceRecording round-trips")
    func sourceRecordingRoundTrip() throws {
        let recording = SourceRecording(
            filename: "abc123.caf",
            sampleRate: 48000.0,
            sampleCount: 240000,
            waveformPeaks: [0.1, 0.5, 0.8, 0.3]
        )
        let decoded = try roundTrip(recording)
        #expect(recording == decoded)
        #expect(decoded.durationSeconds == 5.0)
    }

    // MARK: - Container

    @Test("Container round-trips")
    func containerRoundTrip() throws {
        let container = Container(
            name: "Verse",
            startBar: 5,
            lengthBars: 8,
            loopSettings: LoopSettings(loopCount: .count(2), boundaryMode: .hardCut),
            isRecordArmed: true
        )
        let decoded = try roundTrip(container)
        #expect(container == decoded)
        #expect(decoded.endBar == 13)
    }

    // MARK: - Track

    @Test("Track round-trips")
    func trackRoundTrip() throws {
        let container = Container(name: "Intro", startBar: 1, lengthBars: 4)
        let track = Track(
            name: "Guitar",
            kind: .audio,
            volume: 0.8,
            pan: -0.5,
            isMuted: false,
            isSoloed: true,
            containers: [container],
            orderIndex: 0
        )
        let decoded = try roundTrip(track)
        #expect(track == decoded)
    }

    @Test("TrackKind all cases round-trip")
    func trackKindRoundTrip() throws {
        for kind in TrackKind.allCases {
            let decoded = try roundTrip(kind)
            #expect(kind == decoded)
        }
    }

    // MARK: - Song

    @Test("Song round-trips")
    func songRoundTrip() throws {
        let song = Song(
            name: "My Song",
            tempo: Tempo(bpm: 95.0),
            timeSignature: TimeSignature(beatsPerBar: 6, beatUnit: 8),
            tracks: [Track(name: "Bass", kind: .audio)]
        )
        let decoded = try roundTrip(song)
        #expect(song == decoded)
    }

    // MARK: - MIDIMapping

    @Test("MIDIMapping with CC round-trips")
    func midiMappingCCRoundTrip() throws {
        let mapping = MIDIMapping(
            control: .playPause,
            trigger: .controlChange(channel: 0, controller: 64),
            sourceDeviceName: "My Pedal"
        )
        let decoded = try roundTrip(mapping)
        #expect(mapping == decoded)
    }

    @Test("MIDIMapping with NoteOn round-trips")
    func midiMappingNoteOnRoundTrip() throws {
        let mapping = MIDIMapping(
            control: .recordArm,
            trigger: .noteOn(channel: 1, note: 60)
        )
        let decoded = try roundTrip(mapping)
        #expect(mapping == decoded)
    }

    @Test("MappableControl all cases round-trip")
    func mappableControlRoundTrip() throws {
        for control in MappableControl.allCases {
            let decoded = try roundTrip(control)
            #expect(control == decoded)
        }
    }

    // MARK: - Setlist

    @Test("Setlist with entries round-trips")
    func setlistRoundTrip() throws {
        let songID = ID<Song>()
        let entries = [
            SetlistEntry(songID: songID, transitionToNext: .seamless),
            SetlistEntry(songID: songID, transitionToNext: .gap(durationSeconds: 2.5)),
            SetlistEntry(songID: songID, transitionToNext: .manualAdvance),
        ]
        let setlist = Setlist(name: "Friday Gig", entries: entries)
        let decoded = try roundTrip(setlist)
        #expect(setlist == decoded)
    }

    // MARK: - InsertEffect

    @Test("InsertEffect round-trips")
    func insertEffectRoundTrip() throws {
        let effect = InsertEffect(
            component: AudioComponentInfo(
                componentType: 0x61756678, // 'aufx'
                componentSubType: 0x64656C79, // 'dely'
                componentManufacturer: 0x6170706C // 'appl'
            ),
            displayName: "AUDelay",
            isBypassed: false,
            presetData: Data([0x01, 0x02, 0x03]),
            orderIndex: 0
        )
        let decoded = try roundTrip(effect)
        #expect(effect == decoded)
    }

    // MARK: - AudioDeviceSettings

    @Test("AudioDeviceSettings round-trips")
    func audioDeviceSettingsRoundTrip() throws {
        let settings = AudioDeviceSettings(
            inputDeviceUID: "BuiltInMicrophoneDevice",
            outputDeviceUID: "BuiltInSpeakerDevice",
            bufferSize: 512
        )
        let decoded = try roundTrip(settings)
        #expect(settings == decoded)
    }

    // MARK: - BarBeatPosition

    @Test("BarBeatPosition round-trips and compares correctly")
    func barBeatPositionRoundTrip() throws {
        let pos = BarBeatPosition(bar: 3, beat: 2, subBeatFraction: 0.5)
        let decoded = try roundTrip(pos)
        #expect(pos == decoded)

        let earlier = BarBeatPosition(bar: 1, beat: 1, subBeatFraction: 0.0)
        let later = BarBeatPosition(bar: 2, beat: 1, subBeatFraction: 0.0)
        #expect(earlier < later)
    }

    // MARK: - SamplePosition

    @Test("SamplePosition round-trips and compares correctly")
    func samplePositionRoundTrip() throws {
        let pos = SamplePosition(sampleOffset: 48000)
        let decoded = try roundTrip(pos)
        #expect(pos == decoded)

        let earlier = SamplePosition(sampleOffset: 0)
        #expect(earlier < pos)
    }

    // MARK: - Full Project

    @Test("Full Project round-trips through JSON")
    func projectRoundTrip() throws {
        let recordingID = ID<SourceRecording>()
        let recording = SourceRecording(
            id: recordingID,
            filename: "recording-1.caf",
            sampleRate: 44100.0,
            sampleCount: 441000
        )

        let container = Container(
            name: "Chorus",
            startBar: 1,
            lengthBars: 8,
            sourceRecordingID: recordingID,
            loopSettings: LoopSettings(loopCount: .fill, boundaryMode: .crossfade, crossfadeDurationMs: 15.0),
            isRecordArmed: false
        )

        let track = Track(
            name: "Vocals",
            kind: .audio,
            volume: 1.0,
            pan: 0.0,
            containers: [container],
            orderIndex: 0
        )

        let song = Song(
            name: "Test Song",
            tempo: Tempo(bpm: 120.0),
            timeSignature: TimeSignature(),
            tracks: [track]
        )

        let setlist = Setlist(
            name: "Set 1",
            entries: [SetlistEntry(songID: song.id, transitionToNext: .seamless)]
        )

        let mapping = MIDIMapping(
            control: .playPause,
            trigger: .controlChange(channel: 0, controller: 64)
        )

        let project = Project(
            name: "My Project",
            songs: [song],
            setlists: [setlist],
            sourceRecordings: [recordingID: recording],
            midiMappings: [mapping],
            audioDeviceSettings: AudioDeviceSettings(bufferSize: 256),
            schemaVersion: 1
        )

        let decoded = try roundTrip(project)
        #expect(project == decoded)
        #expect(decoded.songs.count == 1)
        #expect(decoded.songs[0].tracks.count == 1)
        #expect(decoded.songs[0].tracks[0].containers.count == 1)
        #expect(decoded.sourceRecordings.count == 1)
        #expect(decoded.setlists.count == 1)
        #expect(decoded.midiMappings.count == 1)
    }
}
