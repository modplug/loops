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

    @Test("Container with effects round-trips")
    func containerWithEffectsRoundTrip() throws {
        let effects = [
            InsertEffect(
                component: AudioComponentInfo(
                    componentType: 0x61756678,
                    componentSubType: 0x64656C79,
                    componentManufacturer: 0x6170706C
                ),
                displayName: "AUDelay",
                isBypassed: false,
                presetData: Data([0x01, 0x02]),
                orderIndex: 0
            ),
            InsertEffect(
                component: AudioComponentInfo(
                    componentType: 0x61756678,
                    componentSubType: 0x72767262,
                    componentManufacturer: 0x6170706C
                ),
                displayName: "AUReverb",
                isBypassed: true,
                orderIndex: 1
            ),
        ]
        let container = Container(
            name: "Chorus",
            startBar: 9,
            lengthBars: 8,
            loopSettings: LoopSettings(loopCount: .fill),
            insertEffects: effects,
            isEffectChainBypassed: true
        )
        let decoded = try roundTrip(container)
        #expect(container == decoded)
        #expect(decoded.insertEffects.count == 2)
        #expect(decoded.insertEffects[0].displayName == "AUDelay")
        #expect(decoded.insertEffects[1].isBypassed == true)
        #expect(decoded.isEffectChainBypassed == true)
    }

    @Test("Container with instrument override round-trips")
    func containerWithInstrumentOverrideRoundTrip() throws {
        let override = AudioComponentInfo(
            componentType: 0x61756D75, // 'aumu' (kAudioUnitType_MusicDevice)
            componentSubType: 0x646C7332, // 'dls2'
            componentManufacturer: 0x6170706C // 'appl'
        )
        let container = Container(
            name: "Verse",
            startBar: 1,
            lengthBars: 8,
            loopSettings: LoopSettings(loopCount: .fill),
            instrumentOverride: override
        )
        let decoded = try roundTrip(container)
        #expect(container == decoded)
        #expect(decoded.instrumentOverride != nil)
        #expect(decoded.instrumentOverride?.componentType == 0x61756D75)
        #expect(decoded.instrumentOverride?.componentSubType == 0x646C7332)
        #expect(decoded.instrumentOverride?.componentManufacturer == 0x6170706C)
    }

    @Test("Container without instrument override round-trips with nil")
    func containerWithoutInstrumentOverrideRoundTrip() throws {
        let container = Container(
            name: "Chorus",
            startBar: 5,
            lengthBars: 4,
            loopSettings: LoopSettings(loopCount: .fill)
        )
        let decoded = try roundTrip(container)
        #expect(decoded.instrumentOverride == nil)
    }

    @Test("Container with enter and exit fades round-trips")
    func containerWithFadesRoundTrip() throws {
        let container = Container(
            name: "Bridge",
            startBar: 9,
            lengthBars: 4,
            loopSettings: LoopSettings(loopCount: .fill),
            enterFade: FadeSettings(duration: 2.0, curve: .exponential),
            exitFade: FadeSettings(duration: 1.5, curve: .sCurve)
        )
        let decoded = try roundTrip(container)
        #expect(container == decoded)
        #expect(decoded.enterFade != nil)
        #expect(decoded.enterFade?.duration == 2.0)
        #expect(decoded.enterFade?.curve == .exponential)
        #expect(decoded.exitFade != nil)
        #expect(decoded.exitFade?.duration == 1.5)
        #expect(decoded.exitFade?.curve == .sCurve)
    }

    @Test("Container without fades round-trips with nil")
    func containerWithoutFadesRoundTrip() throws {
        let container = Container(
            name: "Verse",
            startBar: 1,
            lengthBars: 8,
            loopSettings: LoopSettings(loopCount: .fill)
        )
        let decoded = try roundTrip(container)
        #expect(decoded.enterFade == nil)
        #expect(decoded.exitFade == nil)
    }

    @Test("Container decodes from legacy JSON without effect fields")
    func containerLegacyDecoding() throws {
        let legacyJSON = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Intro",
            "startBar": 1,
            "lengthBars": 4,
            "loopSettings": {
                "loopCount": { "fill": {} },
                "boundaryMode": "hardCut",
                "crossfadeDurationMs": 10.0
            },
            "isRecordArmed": false
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let decoded = try decoder.decode(Container.self, from: data)
        #expect(decoded.name == "Intro")
        #expect(decoded.insertEffects.isEmpty)
        #expect(decoded.isEffectChainBypassed == false)
        #expect(decoded.instrumentOverride == nil)
        #expect(decoded.enterFade == nil)
        #expect(decoded.exitFade == nil)
        #expect(decoded.onEnterActions.isEmpty)
        #expect(decoded.onExitActions.isEmpty)
    }

    // MARK: - ContainerAction

    @Test("ContainerAction sendMIDI program change round-trips")
    func containerActionProgramChangeRoundTrip() throws {
        let action = ContainerAction.sendMIDI(
            id: ID(),
            message: .programChange(channel: 0, program: 5),
            destination: .externalPort(name: "MIDI Out 1")
        )
        let decoded = try roundTrip(action)
        #expect(action == decoded)
        if case .sendMIDI(_, let message, let destination) = decoded {
            #expect(message == .programChange(channel: 0, program: 5))
            #expect(destination == .externalPort(name: "MIDI Out 1"))
        } else {
            Issue.record("Expected .sendMIDI case")
        }
    }

    @Test("ContainerAction sendMIDI CC round-trips")
    func containerActionCCRoundTrip() throws {
        let action = ContainerAction.makeSendMIDI(
            message: .controlChange(channel: 1, controller: 64, value: 127),
            destination: .externalPort(name: "Pedal Port")
        )
        let decoded = try roundTrip(action)
        #expect(action == decoded)
    }

    @Test("ContainerAction sendMIDI noteOn/noteOff round-trips")
    func containerActionNoteRoundTrip() throws {
        let noteOn = ContainerAction.makeSendMIDI(
            message: .noteOn(channel: 0, note: 60, velocity: 100),
            destination: .internalTrack(trackID: ID())
        )
        let noteOff = ContainerAction.makeSendMIDI(
            message: .noteOff(channel: 0, note: 60, velocity: 0),
            destination: .internalTrack(trackID: ID())
        )
        let decodedNoteOn = try roundTrip(noteOn)
        let decodedNoteOff = try roundTrip(noteOff)
        #expect(noteOn == decodedNoteOn)
        #expect(noteOff == decodedNoteOff)
    }

    @Test("ContainerAction with internal track destination round-trips")
    func containerActionInternalTrackRoundTrip() throws {
        let trackID = ID<Track>()
        let action = ContainerAction.makeSendMIDI(
            message: .programChange(channel: 0, program: 42),
            destination: .internalTrack(trackID: trackID)
        )
        let decoded = try roundTrip(action)
        #expect(action == decoded)
        if case .sendMIDI(_, _, let dest) = decoded {
            #expect(dest == .internalTrack(trackID: trackID))
        }
    }

    @Test("Container with enter/exit actions round-trips")
    func containerWithActionsRoundTrip() throws {
        let enterAction = ContainerAction.makeSendMIDI(
            message: .programChange(channel: 0, program: 5),
            destination: .externalPort(name: "MIDI Out 1")
        )
        let exitAction = ContainerAction.makeSendMIDI(
            message: .controlChange(channel: 0, controller: 64, value: 0),
            destination: .externalPort(name: "MIDI Out 1")
        )
        let container = Container(
            name: "Verse",
            startBar: 1,
            lengthBars: 8,
            loopSettings: LoopSettings(loopCount: .fill),
            onEnterActions: [enterAction],
            onExitActions: [exitAction]
        )
        let decoded = try roundTrip(container)
        #expect(container == decoded)
        #expect(decoded.onEnterActions.count == 1)
        #expect(decoded.onExitActions.count == 1)
        #expect(decoded.onEnterActions[0].message == .programChange(channel: 0, program: 5))
        #expect(decoded.onExitActions[0].message == .controlChange(channel: 0, controller: 64, value: 0))
    }

    @Test("Container without actions round-trips with empty arrays")
    func containerWithoutActionsRoundTrip() throws {
        let container = Container(
            name: "Chorus",
            startBar: 5,
            lengthBars: 4,
            loopSettings: LoopSettings(loopCount: .fill)
        )
        let decoded = try roundTrip(container)
        #expect(decoded.onEnterActions.isEmpty)
        #expect(decoded.onExitActions.isEmpty)
    }

    @Test("MIDIActionMessage all cases round-trip")
    func midiActionMessageAllCasesRoundTrip() throws {
        let messages: [MIDIActionMessage] = [
            .programChange(channel: 0, program: 127),
            .controlChange(channel: 15, controller: 0, value: 64),
            .noteOn(channel: 9, note: 60, velocity: 100),
            .noteOff(channel: 9, note: 60, velocity: 0),
        ]
        for message in messages {
            let decoded = try roundTrip(message)
            #expect(message == decoded)
        }
    }

    @Test("MIDIDestination all cases round-trip")
    func midiDestinationAllCasesRoundTrip() throws {
        let destinations: [MIDIDestination] = [
            .externalPort(name: "USB MIDI"),
            .internalTrack(trackID: ID()),
        ]
        for dest in destinations {
            let decoded = try roundTrip(dest)
            #expect(dest == decoded)
        }
    }

    // MARK: - Track

    @Test("Track round-trips with port IDs")
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
            inputPortID: "device:0:0",
            outputPortID: "device:0:2",
            orderIndex: 0
        )
        let decoded = try roundTrip(track)
        #expect(track == decoded)
        #expect(decoded.inputPortID == "device:0:0")
        #expect(decoded.outputPortID == "device:0:2")
    }

    @Test("Track migrates from legacy inputDeviceUID")
    func trackLegacyMigration() throws {
        // Simulate the old format with inputDeviceUID
        let legacyJSON = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Guitar",
            "kind": "audio",
            "volume": 1.0,
            "pan": 0.0,
            "isMuted": false,
            "isSoloed": false,
            "containers": [],
            "insertEffects": [],
            "sendLevels": [],
            "inputDeviceUID": "BuiltInMic",
            "orderIndex": 0
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let decoded = try decoder.decode(Track.self, from: data)
        // Legacy inputDeviceUID is discarded (can't map to port)
        #expect(decoded.inputPortID == nil)
        #expect(decoded.outputPortID == nil)
        #expect(decoded.name == "Guitar")
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

    // MARK: - FadeSettings

    @Test("FadeSettings round-trips")
    func fadeSettingsRoundTrip() throws {
        let settings = FadeSettings(duration: 2.5, curve: .sCurve)
        let decoded = try roundTrip(settings)
        #expect(settings == decoded)
    }

    @Test("CurveType all cases round-trip")
    func curveTypeRoundTrip() throws {
        for curve in CurveType.allCases {
            let decoded = try roundTrip(curve)
            #expect(curve == decoded)
        }
    }

    @Test("CurveType.linear produces correct gain values")
    func linearCurveGainValues() {
        let curve = CurveType.linear
        #expect(curve.gain(at: 0.0) == 0.0)
        #expect(curve.gain(at: 0.5) == 0.5)
        #expect(curve.gain(at: 1.0) == 1.0)
        // Clamping
        #expect(curve.gain(at: -0.5) == 0.0)
        #expect(curve.gain(at: 1.5) == 1.0)
    }

    @Test("CurveType.exponential produces correct gain values")
    func exponentialCurveGainValues() {
        let curve = CurveType.exponential
        #expect(curve.gain(at: 0.0) == 0.0)
        #expect(curve.gain(at: 1.0) == 1.0)
        // t^3: 0.5^3 = 0.125
        #expect(abs(curve.gain(at: 0.5) - 0.125) < 1e-10)
        // At midpoint, exponential should be below linear
        #expect(curve.gain(at: 0.5) < 0.5)
    }

    @Test("CurveType.sCurve produces correct gain values")
    func sCurveGainValues() {
        let curve = CurveType.sCurve
        #expect(curve.gain(at: 0.0) == 0.0)
        #expect(curve.gain(at: 1.0) == 1.0)
        // smoothstep at 0.5: 3*(0.25) - 2*(0.125) = 0.75 - 0.25 = 0.5
        #expect(abs(curve.gain(at: 0.5) - 0.5) < 1e-10)
        // S-curve should be below 0.5 before midpoint
        #expect(curve.gain(at: 0.25) < 0.25)
        // S-curve should be above 0.5 after midpoint
        #expect(curve.gain(at: 0.75) > 0.75)
    }

    @Test("All curve types start at 0 and end at 1")
    func curveTypeEndpoints() {
        for curve in CurveType.allCases {
            #expect(curve.gain(at: 0.0) == 0.0, "Curve \(curve) should start at 0")
            #expect(curve.gain(at: 1.0) == 1.0, "Curve \(curve) should end at 1")
        }
    }

    @Test("All curve types are monotonically increasing")
    func curveTypeMonotonicity() {
        for curve in CurveType.allCases {
            var previous = curve.gain(at: 0.0)
            for i in 1...100 {
                let t = Double(i) / 100.0
                let current = curve.gain(at: t)
                #expect(current >= previous, "Curve \(curve) should be monotonically increasing at t=\(t)")
                previous = current
            }
        }
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

    // MARK: - ChannelPort

    @Test("InputPort round-trips")
    func inputPortRoundTrip() throws {
        let port = InputPort(
            deviceUID: "TestDevice:0",
            streamIndex: 0,
            channelOffset: 0,
            layout: .stereo,
            defaultName: "In 1/2",
            customName: "Guitar"
        )
        let decoded = try roundTrip(port)
        #expect(port == decoded)
        #expect(decoded.id == "TestDevice:0:0:0")
        #expect(decoded.displayName == "Guitar")
    }

    @Test("OutputPort round-trips with nil customName")
    func outputPortRoundTrip() throws {
        let port = OutputPort(
            deviceUID: "TestDevice:0",
            streamIndex: 1,
            channelOffset: 2,
            layout: .mono,
            defaultName: "Out 3"
        )
        let decoded = try roundTrip(port)
        #expect(port == decoded)
        #expect(decoded.customName == nil)
        #expect(decoded.displayName == "Out 3")
    }

    // MARK: - AudioDeviceSettings

    @Test("AudioDeviceSettings round-trips")
    func audioDeviceSettingsRoundTrip() throws {
        let settings = AudioDeviceSettings(
            deviceUID: "MyInterface",
            sampleRate: 48000.0,
            bufferSize: 512,
            inputPorts: [
                InputPort(deviceUID: "MyInterface", streamIndex: 0, channelOffset: 0, layout: .stereo, defaultName: "In 1/2", customName: "Guitar")
            ],
            outputPorts: [
                OutputPort(deviceUID: "MyInterface", streamIndex: 0, channelOffset: 0, layout: .stereo, defaultName: "Out 1/2", customName: "Main Mix")
            ]
        )
        let decoded = try roundTrip(settings)
        #expect(settings == decoded)
        #expect(decoded.inputPorts.count == 1)
        #expect(decoded.outputPorts.count == 1)
        #expect(decoded.inputPorts[0].customName == "Guitar")
    }

    @Test("AudioDeviceSettings migrates from legacy format")
    func audioDeviceSettingsLegacyMigration() throws {
        let legacyJSON = """
        {
            "inputDeviceUID": "BuiltInMic",
            "outputDeviceUID": "BuiltInSpeaker",
            "bufferSize": 256
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let decoded = try decoder.decode(AudioDeviceSettings.self, from: data)
        // Legacy outputDeviceUID becomes deviceUID
        #expect(decoded.deviceUID == "BuiltInSpeaker")
        #expect(decoded.bufferSize == 256)
        #expect(decoded.inputPorts.isEmpty)
        #expect(decoded.outputPorts.isEmpty)
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
