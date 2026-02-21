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
