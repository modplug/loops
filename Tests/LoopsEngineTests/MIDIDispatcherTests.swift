import Testing
import Foundation
@testable import LoopsEngine
@testable import LoopsCore

@Suite("MIDIDispatcher Tests")
struct MIDIDispatcherTests {

    @Test("Dispatch mapped control triggers callback")
    func dispatchMappedControl() {
        let dispatcher = MIDIDispatcher()
        let mapping = MIDIMapping(
            control: .playPause,
            trigger: .controlChange(channel: 0, controller: 64)
        )
        dispatcher.updateMappings([mapping])

        var triggered: MappableControl?
        dispatcher.onControlTriggered = { control in
            triggered = control
        }

        dispatcher.dispatch(.controlChange(channel: 0, controller: 64))
        #expect(triggered == .playPause)
    }

    @Test("Dispatch unmapped trigger does nothing")
    func dispatchUnmappedTrigger() {
        let dispatcher = MIDIDispatcher()
        let mapping = MIDIMapping(
            control: .playPause,
            trigger: .controlChange(channel: 0, controller: 64)
        )
        dispatcher.updateMappings([mapping])

        var triggered: MappableControl?
        dispatcher.onControlTriggered = { control in
            triggered = control
        }

        dispatcher.dispatch(.controlChange(channel: 0, controller: 65))
        #expect(triggered == nil)
    }

    @Test("Learn mode routes to learn callback")
    func learnModeRouting() {
        let dispatcher = MIDIDispatcher()
        dispatcher.isLearning = true

        var learnedTrigger: MIDITrigger?
        dispatcher.onMIDILearnEvent = { trigger in
            learnedTrigger = trigger
        }

        var controlTriggered: MappableControl?
        dispatcher.onControlTriggered = { control in
            controlTriggered = control
        }

        let mapping = MIDIMapping(
            control: .stop,
            trigger: .controlChange(channel: 0, controller: 64)
        )
        dispatcher.updateMappings([mapping])

        dispatcher.dispatch(.controlChange(channel: 0, controller: 64))
        #expect(learnedTrigger == .controlChange(channel: 0, controller: 64))
        #expect(controlTriggered == nil) // Should not trigger mapped control in learn mode
    }

    @Test("Multiple mappings dispatch correctly")
    func multipleMappings() {
        let dispatcher = MIDIDispatcher()
        let mappings = [
            MIDIMapping(control: .playPause, trigger: .controlChange(channel: 0, controller: 64)),
            MIDIMapping(control: .stop, trigger: .controlChange(channel: 0, controller: 65)),
            MIDIMapping(control: .recordArm, trigger: .noteOn(channel: 0, note: 60)),
            MIDIMapping(control: .nextSong, trigger: .controlChange(channel: 0, controller: 67)),
        ]
        dispatcher.updateMappings(mappings)

        var controls: [MappableControl] = []
        dispatcher.onControlTriggered = { control in
            controls.append(control)
        }

        dispatcher.dispatch(.controlChange(channel: 0, controller: 64))
        dispatcher.dispatch(.controlChange(channel: 0, controller: 65))
        dispatcher.dispatch(.noteOn(channel: 0, note: 60))
        dispatcher.dispatch(.controlChange(channel: 0, controller: 67))

        #expect(controls == [.playPause, .stop, .recordArm, .nextSong])
    }

    @Test("Update mappings replaces previous mappings")
    func updateMappingsReplaces() {
        let dispatcher = MIDIDispatcher()

        let oldMapping = MIDIMapping(
            control: .playPause,
            trigger: .controlChange(channel: 0, controller: 64)
        )
        dispatcher.updateMappings([oldMapping])

        let newMapping = MIDIMapping(
            control: .stop,
            trigger: .controlChange(channel: 0, controller: 64)
        )
        dispatcher.updateMappings([newMapping])

        var triggered: MappableControl?
        dispatcher.onControlTriggered = { control in
            triggered = control
        }

        dispatcher.dispatch(.controlChange(channel: 0, controller: 64))
        #expect(triggered == .stop)
    }

    @Test("NoteOn trigger dispatches correctly")
    func noteOnTrigger() {
        let dispatcher = MIDIDispatcher()
        let mapping = MIDIMapping(
            control: .metronomeToggle,
            trigger: .noteOn(channel: 1, note: 48)
        )
        dispatcher.updateMappings([mapping])

        var triggered: MappableControl?
        dispatcher.onControlTriggered = { control in
            triggered = control
        }

        // Wrong channel should not trigger
        dispatcher.dispatch(.noteOn(channel: 0, note: 48))
        #expect(triggered == nil)

        // Correct channel and note should trigger
        dispatcher.dispatch(.noteOn(channel: 1, note: 48))
        #expect(triggered == .metronomeToggle)
    }

    // MARK: - Concurrent Stress Tests

    @Test("Concurrent dispatch vs updateMappings")
    func concurrentDispatchVsUpdateMappings() async {
        let dispatcher = MIDIDispatcher()
        let triggers: [MIDITrigger] = (0..<20).map { .controlChange(channel: 0, controller: UInt8($0)) }
        let mappings = triggers.map { MIDIMapping(control: .playPause, trigger: $0) }
        dispatcher.updateMappings(mappings)

        // Background: hammer dispatch (reads mappings dictionary)
        let reader = Task.detached(priority: .high) {
            for i in 0..<10000 {
                let trigger = triggers[i % triggers.count]
                dispatcher.dispatch(trigger)
            }
        }

        // Foreground: repeatedly update mappings (writes mappings dictionary)
        for _ in 0..<1000 {
            dispatcher.updateMappings(mappings)
        }

        await reader.value
    }

    @Test("Concurrent dispatch with CC vs updateParameterMappings")
    func concurrentDispatchCCVsUpdateParameterMappings() async {
        let dispatcher = MIDIDispatcher()
        let triggers: [MIDITrigger] = (0..<20).map { .controlChange(channel: 0, controller: UInt8($0)) }
        let trackID = ID<Track>()
        let paramMappings = triggers.map {
            MIDIParameterMapping(
                trigger: $0,
                targetPath: EffectPath(trackID: trackID, effectIndex: 0, parameterAddress: 0),
                minValue: 0.0,
                maxValue: 1.0
            )
        }
        dispatcher.updateParameterMappings(paramMappings)

        // Background: hammer dispatch with CC values (reads parameterMappings dictionary)
        let reader = Task.detached(priority: .high) {
            for i in 0..<10000 {
                let trigger = triggers[i % triggers.count]
                dispatcher.dispatch(trigger, ccValue: UInt8(i % 128))
            }
        }

        // Foreground: repeatedly update parameter mappings (writes parameterMappings dictionary)
        for _ in 0..<1000 {
            dispatcher.updateParameterMappings(paramMappings)
        }

        await reader.value
    }

    @Test("Concurrent dispatch vs isLearning toggle")
    func concurrentDispatchVsLearningToggle() async {
        let dispatcher = MIDIDispatcher()
        let mappings = [
            MIDIMapping(control: .playPause, trigger: .controlChange(channel: 0, controller: 64)),
            MIDIMapping(control: .stop, trigger: .controlChange(channel: 0, controller: 65)),
        ]
        dispatcher.updateMappings(mappings)

        // Background: hammer dispatch (reads isLearning + mappings)
        let reader = Task.detached(priority: .high) {
            for i in 0..<10000 {
                dispatcher.dispatch(.controlChange(channel: 0, controller: UInt8(64 + (i % 2))))
            }
        }

        // Foreground: toggle isLearning + update mappings
        for _ in 0..<1000 {
            dispatcher.isLearning = true
            dispatcher.updateMappings(mappings)
            dispatcher.isLearning = false
        }

        await reader.value
    }
}

@Suite("MIDILearnController Tests")
struct MIDILearnControllerTests {

    @Test("Start and cancel learning")
    func startAndCancelLearning() {
        let dispatcher = MIDIDispatcher()
        let controller = MIDILearnController(dispatcher: dispatcher)

        controller.startLearning(for: .playPause)
        #expect(controller.learningControl == .playPause)
        #expect(dispatcher.isLearning)

        controller.cancelLearning()
        #expect(controller.learningControl == nil)
        #expect(!dispatcher.isLearning)
    }

    @Test("Learning creates mapping on MIDI event")
    func learningCreatesMapping() {
        let dispatcher = MIDIDispatcher()
        let controller = MIDILearnController(dispatcher: dispatcher)

        var learnedMapping: MIDIMapping?
        controller.onMappingLearned = { mapping in
            learnedMapping = mapping
        }

        controller.startLearning(for: .recordArm)
        dispatcher.dispatch(.controlChange(channel: 0, controller: 66))

        #expect(learnedMapping != nil)
        #expect(learnedMapping?.control == .recordArm)
        #expect(learnedMapping?.trigger == .controlChange(channel: 0, controller: 66))
        #expect(controller.learningControl == nil)
        #expect(!dispatcher.isLearning)
    }

    @Test("Learning for trackVolume creates mapping")
    func learningTrackVolume() {
        let dispatcher = MIDIDispatcher()
        let controller = MIDILearnController(dispatcher: dispatcher)

        var learnedMapping: MIDIMapping?
        controller.onMappingLearned = { mapping in
            learnedMapping = mapping
        }

        controller.startLearning(for: .trackVolume(trackIndex: 2))
        dispatcher.dispatch(.controlChange(channel: 0, controller: 3))

        #expect(learnedMapping != nil)
        #expect(learnedMapping?.control == .trackVolume(trackIndex: 2))
        #expect(learnedMapping?.trigger == .controlChange(channel: 0, controller: 3))
    }
}

@Suite("MappableControl Extended Tests")
struct MappableControlExtendedTests {

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

    @Test("MappableControl trackVolume Codable round-trip")
    func trackVolumeRoundTrip() throws {
        let control = MappableControl.trackVolume(trackIndex: 3)
        let decoded = try roundTrip(control)
        #expect(decoded == control)
    }

    @Test("MappableControl trackPan Codable round-trip")
    func trackPanRoundTrip() throws {
        let control = MappableControl.trackPan(trackIndex: 1)
        let decoded = try roundTrip(control)
        #expect(decoded == control)
    }

    @Test("MappableControl trackMute Codable round-trip")
    func trackMuteRoundTrip() throws {
        let control = MappableControl.trackMute(trackIndex: 5)
        let decoded = try roundTrip(control)
        #expect(decoded == control)
    }

    @Test("MappableControl trackSolo Codable round-trip")
    func trackSoloRoundTrip() throws {
        let control = MappableControl.trackSolo(trackIndex: 2)
        let decoded = try roundTrip(control)
        #expect(decoded == control)
    }

    @Test("MappableControl trackSend Codable round-trip")
    func trackSendRoundTrip() throws {
        let control = MappableControl.trackSend(trackIndex: 1, sendIndex: 2)
        let decoded = try roundTrip(control)
        #expect(decoded == control)
    }

    @Test("MappableControl trackSelect Codable round-trip")
    func trackSelectRoundTrip() throws {
        let control = MappableControl.trackSelect(trackIndex: 4)
        let decoded = try roundTrip(control)
        #expect(decoded == control)
    }

    @Test("MappableControl songSelect Codable round-trip")
    func songSelectRoundTrip() throws {
        let control = MappableControl.songSelect(songIndex: 7)
        let decoded = try roundTrip(control)
        #expect(decoded == control)
    }

    @Test("MappableControl transport cases round-trip")
    func transportCasesRoundTrip() throws {
        for control in MappableControl.transportControls {
            let decoded = try roundTrip(control)
            #expect(decoded == control)
        }
    }

    @Test("MappableControl backward-compatible decode from legacy string format")
    func legacyStringDecode() throws {
        // Simulate old format: plain string value
        let legacyCases: [(String, MappableControl)] = [
            ("\"playPause\"", .playPause),
            ("\"stop\"", .stop),
            ("\"recordArm\"", .recordArm),
            ("\"nextSong\"", .nextSong),
            ("\"previousSong\"", .previousSong),
            ("\"metronomeToggle\"", .metronomeToggle),
        ]
        for (json, expected) in legacyCases {
            let data = json.data(using: .utf8)!
            let decoded = try decoder.decode(MappableControl.self, from: data)
            #expect(decoded == expected, "Failed to decode legacy \(json)")
        }
    }

    @Test("MIDIMapping with new control types round-trip")
    func mappingWithNewControlsRoundTrip() throws {
        let mapping = MIDIMapping(
            control: .trackVolume(trackIndex: 0),
            trigger: .controlChange(channel: 0, controller: 1)
        )
        let decoded = try roundTrip(mapping)
        #expect(decoded.control == .trackVolume(trackIndex: 0))
        #expect(decoded.trigger == .controlChange(channel: 0, controller: 1))
    }

    @Test("MappableControl isContinuous property")
    func isContinuousProperty() {
        #expect(MappableControl.trackVolume(trackIndex: 0).isContinuous)
        #expect(MappableControl.trackPan(trackIndex: 0).isContinuous)
        #expect(MappableControl.trackSend(trackIndex: 0, sendIndex: 0).isContinuous)
        #expect(!MappableControl.playPause.isContinuous)
        #expect(!MappableControl.trackMute(trackIndex: 0).isContinuous)
        #expect(!MappableControl.trackSolo(trackIndex: 0).isContinuous)
        #expect(!MappableControl.trackSelect(trackIndex: 0).isContinuous)
        #expect(!MappableControl.songSelect(songIndex: 0).isContinuous)
    }

    @Test("MappableControl valueRange for volume")
    func volumeValueRange() {
        let range = MappableControl.trackVolume(trackIndex: 0).valueRange
        #expect(range.min == 0.0)
        #expect(range.max == 2.0)
    }

    @Test("MappableControl valueRange for pan")
    func panValueRange() {
        let range = MappableControl.trackPan(trackIndex: 0).valueRange
        #expect(range.min == -1.0)
        #expect(range.max == 1.0)
    }

    @Test("MappableControl displayName for new cases")
    func displayNames() {
        #expect(MappableControl.trackVolume(trackIndex: 0).displayName == "Track 1 Volume")
        #expect(MappableControl.trackPan(trackIndex: 2).displayName == "Track 3 Pan")
        #expect(MappableControl.trackMute(trackIndex: 0).displayName == "Track 1 Mute")
        #expect(MappableControl.trackSolo(trackIndex: 1).displayName == "Track 2 Solo")
        #expect(MappableControl.trackSend(trackIndex: 0, sendIndex: 1).displayName == "Track 1 Send 2")
        #expect(MappableControl.trackSelect(trackIndex: 3).displayName == "Select Track 4")
        #expect(MappableControl.songSelect(songIndex: 0).displayName == "Song 1")
    }

    @Test("MappableControl transportControls returns all 6 transport controls")
    func transportControlsList() {
        let controls = MappableControl.transportControls
        #expect(controls.count == 6)
        #expect(controls.contains(.playPause))
        #expect(controls.contains(.stop))
        #expect(controls.contains(.recordArm))
        #expect(controls.contains(.nextSong))
        #expect(controls.contains(.previousSong))
        #expect(controls.contains(.metronomeToggle))
    }

    @Test("MappableControl mixerControls generates 4 controls per track")
    func mixerControlsList() {
        let controls = MappableControl.mixerControls(trackCount: 3)
        #expect(controls.count == 12)
        #expect(controls.contains(.trackVolume(trackIndex: 0)))
        #expect(controls.contains(.trackPan(trackIndex: 2)))
        #expect(controls.contains(.trackMute(trackIndex: 1)))
        #expect(controls.contains(.trackSolo(trackIndex: 2)))
    }

    @Test("MappableControl navigationControls generates track and song controls")
    func navigationControlsList() {
        let controls = MappableControl.navigationControls(trackCount: 2, songCount: 3)
        #expect(controls.count == 5)
        #expect(controls.contains(.trackSelect(trackIndex: 0)))
        #expect(controls.contains(.trackSelect(trackIndex: 1)))
        #expect(controls.contains(.songSelect(songIndex: 0)))
        #expect(controls.contains(.songSelect(songIndex: 2)))
    }
}

@Suite("MIDIDispatcher Extended Routing Tests")
struct MIDIDispatcherExtendedRoutingTests {

    @Test("Dispatcher routes CC to track volume via continuous callback")
    func dispatchTrackVolume() {
        let dispatcher = MIDIDispatcher()
        let mapping = MIDIMapping(
            control: .trackVolume(trackIndex: 0),
            trigger: .controlChange(channel: 0, controller: 7)
        )
        dispatcher.updateMappings([mapping])

        var receivedControl: MappableControl?
        var receivedValue: Float?
        dispatcher.onContinuousControlTriggered = { control, value in
            receivedControl = control
            receivedValue = value
        }
        var toggleTriggered = false
        dispatcher.onControlTriggered = { _ in
            toggleTriggered = true
        }

        dispatcher.dispatch(.controlChange(channel: 0, controller: 7), ccValue: 127)
        #expect(receivedControl == .trackVolume(trackIndex: 0))
        // Volume range 0-2, CC 127 = 2.0
        #expect(receivedValue != nil)
        #expect(abs(receivedValue! - 2.0) < 0.001)
        #expect(!toggleTriggered, "Continuous control should not trigger toggle callback")
    }

    @Test("Dispatcher routes CC to track pan via continuous callback")
    func dispatchTrackPan() {
        let dispatcher = MIDIDispatcher()
        let mapping = MIDIMapping(
            control: .trackPan(trackIndex: 1),
            trigger: .controlChange(channel: 0, controller: 10)
        )
        dispatcher.updateMappings([mapping])

        var receivedValue: Float?
        dispatcher.onContinuousControlTriggered = { _, value in
            receivedValue = value
        }

        // CC 0 = -1.0 (pan left)
        dispatcher.dispatch(.controlChange(channel: 0, controller: 10), ccValue: 0)
        #expect(receivedValue != nil)
        #expect(abs(receivedValue! - (-1.0)) < 0.001)

        // CC 64 = center (approximately 0.0)
        dispatcher.dispatch(.controlChange(channel: 0, controller: 10), ccValue: 64)
        let expectedMid: Float = -1.0 + (64.0 / 127.0) * 2.0
        #expect(abs(receivedValue! - expectedMid) < 0.01)
    }

    @Test("Dispatcher routes toggle controls via onControlTriggered even with CC value")
    func dispatchToggleMute() {
        let dispatcher = MIDIDispatcher()
        let mapping = MIDIMapping(
            control: .trackMute(trackIndex: 0),
            trigger: .controlChange(channel: 0, controller: 20)
        )
        dispatcher.updateMappings([mapping])

        var toggledControl: MappableControl?
        dispatcher.onControlTriggered = { control in
            toggledControl = control
        }
        var continuousTriggered = false
        dispatcher.onContinuousControlTriggered = { _, _ in
            continuousTriggered = true
        }

        dispatcher.dispatch(.controlChange(channel: 0, controller: 20), ccValue: 127)
        #expect(toggledControl == .trackMute(trackIndex: 0))
        #expect(!continuousTriggered, "Toggle control should not trigger continuous callback")
    }

    @Test("Dispatcher routes songSelect via onControlTriggered")
    func dispatchSongSelect() {
        let dispatcher = MIDIDispatcher()
        let mapping = MIDIMapping(
            control: .songSelect(songIndex: 2),
            trigger: .controlChange(channel: 0, controller: 50)
        )
        dispatcher.updateMappings([mapping])

        var triggered: MappableControl?
        dispatcher.onControlTriggered = { control in
            triggered = control
        }

        dispatcher.dispatch(.controlChange(channel: 0, controller: 50), ccValue: 127)
        #expect(triggered == .songSelect(songIndex: 2))
    }

    @Test("Bank-style mapping: sequential CCs to sequential tracks")
    func bankStyleMapping() {
        let dispatcher = MIDIDispatcher()
        let mappings = (0..<4).map { idx in
            MIDIMapping(
                control: .trackVolume(trackIndex: idx),
                trigger: .controlChange(channel: 0, controller: UInt8(1 + idx))
            )
        }
        dispatcher.updateMappings(mappings)

        var received: [(MappableControl, Float)] = []
        dispatcher.onContinuousControlTriggered = { control, value in
            received.append((control, value))
        }

        for i in 0..<4 {
            dispatcher.dispatch(.controlChange(channel: 0, controller: UInt8(1 + i)), ccValue: 64)
        }

        #expect(received.count == 4)
        #expect(received[0].0 == .trackVolume(trackIndex: 0))
        #expect(received[1].0 == .trackVolume(trackIndex: 1))
        #expect(received[2].0 == .trackVolume(trackIndex: 2))
        #expect(received[3].0 == .trackVolume(trackIndex: 3))
    }
}

@Suite("FootPedalPresets Tests")
struct FootPedalPresetsTests {

    @Test("Generic 2-button preset has correct mappings")
    func generic2Button() {
        let mappings = FootPedalPreset.generic2Button.mappings
        #expect(mappings.count == 2)
        #expect(mappings[0].control == .playPause)
        #expect(mappings[1].control == .recordArm)
    }

    @Test("Generic 4-button preset has correct mappings")
    func generic4Button() {
        let mappings = FootPedalPreset.generic4Button.mappings
        #expect(mappings.count == 4)
        #expect(mappings[0].control == .playPause)
        #expect(mappings[1].control == .stop)
        #expect(mappings[2].control == .recordArm)
        #expect(mappings[3].control == .nextSong)
    }

    @Test("All presets have valid triggers")
    func allPresetsValid() {
        for preset in FootPedalPreset.allCases {
            let mappings = preset.mappings
            #expect(!mappings.isEmpty)
            for mapping in mappings {
                // Each mapping should have a unique control
                let sameControlCount = mappings.filter { $0.control == mapping.control }.count
                #expect(sameControlCount == 1, "Duplicate control \(mapping.control) in preset \(preset)")
            }
        }
    }
}
