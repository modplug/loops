import Testing
import Foundation
@testable import LoopsEngine
@testable import LoopsCore

/// Mock MIDI output that records all sent messages for verification.
final class MockMIDIOutput: MIDIOutput, @unchecked Sendable {
    struct SentMessage: Equatable {
        let message: MIDIActionMessage
        let externalPort: String?
        let trackID: ID<Track>?
    }

    var sentMessages: [SentMessage] = []

    func send(_ message: MIDIActionMessage, toExternalPort name: String) {
        sentMessages.append(SentMessage(message: message, externalPort: name, trackID: nil))
    }

    func send(_ message: MIDIActionMessage, toTrack trackID: ID<Track>) {
        sentMessages.append(SentMessage(message: message, externalPort: nil, trackID: trackID))
    }
}

@Suite("ActionDispatcher Tests")
struct ActionDispatcherTests {

    @Test("Container enter fires enter actions")
    func containerEnterFiresActions() {
        let mock = MockMIDIOutput()
        let dispatcher = ActionDispatcher(midiOutput: mock)

        let action = ContainerAction.makeSendMIDI(
            message: .programChange(channel: 0, program: 5),
            destination: .externalPort(name: "MIDI Out 1")
        )
        let container = Container(
            name: "Verse",
            startBar: 1,
            lengthBars: 8,
            onEnterActions: [action]
        )

        dispatcher.containerDidEnter(container)

        #expect(mock.sentMessages.count == 1)
        #expect(mock.sentMessages[0].message == .programChange(channel: 0, program: 5))
        #expect(mock.sentMessages[0].externalPort == "MIDI Out 1")
    }

    @Test("Container exit fires exit actions")
    func containerExitFiresActions() {
        let mock = MockMIDIOutput()
        let dispatcher = ActionDispatcher(midiOutput: mock)

        let action = ContainerAction.makeSendMIDI(
            message: .controlChange(channel: 0, controller: 64, value: 0),
            destination: .externalPort(name: "Pedal Port")
        )
        let container = Container(
            name: "Chorus",
            startBar: 5,
            lengthBars: 4,
            onExitActions: [action]
        )

        dispatcher.containerDidExit(container)

        #expect(mock.sentMessages.count == 1)
        #expect(mock.sentMessages[0].message == .controlChange(channel: 0, controller: 64, value: 0))
        #expect(mock.sentMessages[0].externalPort == "Pedal Port")
    }

    @Test("Multiple actions fire in order")
    func multipleActionsFireInOrder() {
        let mock = MockMIDIOutput()
        let dispatcher = ActionDispatcher(midiOutput: mock)

        let actions = [
            ContainerAction.makeSendMIDI(
                message: .programChange(channel: 0, program: 1),
                destination: .externalPort(name: "Port A")
            ),
            ContainerAction.makeSendMIDI(
                message: .controlChange(channel: 0, controller: 7, value: 100),
                destination: .externalPort(name: "Port A")
            ),
            ContainerAction.makeSendMIDI(
                message: .noteOn(channel: 0, note: 60, velocity: 127),
                destination: .externalPort(name: "Port B")
            ),
        ]
        let container = Container(
            name: "Bridge",
            startBar: 9,
            lengthBars: 4,
            onEnterActions: actions
        )

        dispatcher.containerDidEnter(container)

        #expect(mock.sentMessages.count == 3)
        #expect(mock.sentMessages[0].message == .programChange(channel: 0, program: 1))
        #expect(mock.sentMessages[1].message == .controlChange(channel: 0, controller: 7, value: 100))
        #expect(mock.sentMessages[2].message == .noteOn(channel: 0, note: 60, velocity: 127))
    }

    @Test("Container with no actions does not send messages")
    func noActionsDoesNothing() {
        let mock = MockMIDIOutput()
        let dispatcher = ActionDispatcher(midiOutput: mock)

        let container = Container(
            name: "Empty",
            startBar: 1,
            lengthBars: 4
        )

        dispatcher.containerDidEnter(container)
        dispatcher.containerDidExit(container)

        #expect(mock.sentMessages.isEmpty)
    }

    @Test("Internal track destination routes to track")
    func internalTrackDestination() {
        let mock = MockMIDIOutput()
        let dispatcher = ActionDispatcher(midiOutput: mock)

        let trackID = ID<Track>()
        let action = ContainerAction.makeSendMIDI(
            message: .programChange(channel: 0, program: 42),
            destination: .internalTrack(trackID: trackID)
        )
        let container = Container(
            name: "Verse",
            startBar: 1,
            lengthBars: 8,
            onEnterActions: [action]
        )

        dispatcher.containerDidEnter(container)

        #expect(mock.sentMessages.count == 1)
        #expect(mock.sentMessages[0].trackID == trackID)
        #expect(mock.sentMessages[0].externalPort == nil)
    }

    @Test("Enter actions do not fire on exit and vice versa")
    func enterExitSeparation() {
        let mock = MockMIDIOutput()
        let dispatcher = ActionDispatcher(midiOutput: mock)

        let enterAction = ContainerAction.makeSendMIDI(
            message: .programChange(channel: 0, program: 1),
            destination: .externalPort(name: "Out")
        )
        let exitAction = ContainerAction.makeSendMIDI(
            message: .programChange(channel: 0, program: 2),
            destination: .externalPort(name: "Out")
        )
        let container = Container(
            name: "Test",
            startBar: 1,
            lengthBars: 4,
            onEnterActions: [enterAction],
            onExitActions: [exitAction]
        )

        dispatcher.containerDidEnter(container)
        #expect(mock.sentMessages.count == 1)
        #expect(mock.sentMessages[0].message == .programChange(channel: 0, program: 1))

        dispatcher.containerDidExit(container)
        #expect(mock.sentMessages.count == 2)
        #expect(mock.sentMessages[1].message == .programChange(channel: 0, program: 2))
    }

    @Test("NoteOff action sends correctly")
    func noteOffAction() {
        let mock = MockMIDIOutput()
        let dispatcher = ActionDispatcher(midiOutput: mock)

        let action = ContainerAction.makeSendMIDI(
            message: .noteOff(channel: 0, note: 60, velocity: 0),
            destination: .externalPort(name: "Out")
        )
        let container = Container(
            name: "Test",
            startBar: 1,
            lengthBars: 4,
            onExitActions: [action]
        )

        dispatcher.containerDidExit(container)

        #expect(mock.sentMessages.count == 1)
        #expect(mock.sentMessages[0].message == .noteOff(channel: 0, note: 60, velocity: 0))
    }
}

/// Mock trigger delegate that records all trigger calls for verification.
final class MockTriggerDelegate: ContainerTriggerDelegate, @unchecked Sendable {
    enum TriggerCall: Equatable {
        case start(ID<Container>)
        case stop(ID<Container>)
        case setRecordArmed(ID<Container>, Bool)
    }

    var calls: [TriggerCall] = []

    func triggerStart(containerID: ID<Container>) {
        calls.append(.start(containerID))
    }

    func triggerStop(containerID: ID<Container>) {
        calls.append(.stop(containerID))
    }

    func setRecordArmed(containerID: ID<Container>, armed: Bool) {
        calls.append(.setRecordArmed(containerID, armed))
    }
}

@Suite("ActionDispatcher Trigger Tests")
struct ActionDispatcherTriggerTests {

    @Test("Trigger start dispatches to delegate")
    func triggerStartDispatches() {
        let mock = MockMIDIOutput()
        let triggerMock = MockTriggerDelegate()
        let dispatcher = ActionDispatcher(midiOutput: mock)
        dispatcher.triggerDelegate = triggerMock

        let targetID = ID<Container>()
        let action = ContainerAction.makeTriggerContainer(targetID: targetID, action: .start)
        let container = Container(
            name: "Verse",
            startBar: 1,
            lengthBars: 8,
            onEnterActions: [action]
        )

        dispatcher.containerDidEnter(container)

        #expect(triggerMock.calls.count == 1)
        #expect(triggerMock.calls[0] == .start(targetID))
        #expect(mock.sentMessages.isEmpty)
    }

    @Test("Trigger stop dispatches to delegate")
    func triggerStopDispatches() {
        let mock = MockMIDIOutput()
        let triggerMock = MockTriggerDelegate()
        let dispatcher = ActionDispatcher(midiOutput: mock)
        dispatcher.triggerDelegate = triggerMock

        let targetID = ID<Container>()
        let action = ContainerAction.makeTriggerContainer(targetID: targetID, action: .stop)
        let container = Container(
            name: "Verse",
            startBar: 1,
            lengthBars: 8,
            onExitActions: [action]
        )

        dispatcher.containerDidExit(container)

        #expect(triggerMock.calls.count == 1)
        #expect(triggerMock.calls[0] == .stop(targetID))
    }

    @Test("Trigger armRecord dispatches to delegate")
    func triggerArmRecordDispatches() {
        let mock = MockMIDIOutput()
        let triggerMock = MockTriggerDelegate()
        let dispatcher = ActionDispatcher(midiOutput: mock)
        dispatcher.triggerDelegate = triggerMock

        let targetID = ID<Container>()
        let action = ContainerAction.makeTriggerContainer(targetID: targetID, action: .armRecord)
        let container = Container(
            name: "Verse",
            startBar: 1,
            lengthBars: 8,
            onEnterActions: [action]
        )

        dispatcher.containerDidEnter(container)

        #expect(triggerMock.calls.count == 1)
        #expect(triggerMock.calls[0] == .setRecordArmed(targetID, true))
    }

    @Test("Trigger disarmRecord dispatches to delegate")
    func triggerDisarmRecordDispatches() {
        let mock = MockMIDIOutput()
        let triggerMock = MockTriggerDelegate()
        let dispatcher = ActionDispatcher(midiOutput: mock)
        dispatcher.triggerDelegate = triggerMock

        let targetID = ID<Container>()
        let action = ContainerAction.makeTriggerContainer(targetID: targetID, action: .disarmRecord)
        let container = Container(
            name: "Verse",
            startBar: 1,
            lengthBars: 8,
            onExitActions: [action]
        )

        dispatcher.containerDidExit(container)

        #expect(triggerMock.calls.count == 1)
        #expect(triggerMock.calls[0] == .setRecordArmed(targetID, false))
    }

    @Test("Trigger without delegate does nothing (graceful)")
    func triggerWithoutDelegateIsGraceful() {
        let mock = MockMIDIOutput()
        let dispatcher = ActionDispatcher(midiOutput: mock)
        // No triggerDelegate set

        let targetID = ID<Container>()
        let action = ContainerAction.makeTriggerContainer(targetID: targetID, action: .start)
        let container = Container(
            name: "Verse",
            startBar: 1,
            lengthBars: 8,
            onEnterActions: [action]
        )

        dispatcher.containerDidEnter(container)

        #expect(mock.sentMessages.isEmpty)
        // No crash = pass
    }

    @Test("Mixed MIDI and trigger actions fire correctly")
    func mixedActionsFireCorrectly() {
        let mock = MockMIDIOutput()
        let triggerMock = MockTriggerDelegate()
        let dispatcher = ActionDispatcher(midiOutput: mock)
        dispatcher.triggerDelegate = triggerMock

        let targetID = ID<Container>()
        let actions: [ContainerAction] = [
            .makeSendMIDI(
                message: .programChange(channel: 0, program: 5),
                destination: .externalPort(name: "Out")
            ),
            .makeTriggerContainer(targetID: targetID, action: .start),
            .makeSendMIDI(
                message: .noteOn(channel: 0, note: 60, velocity: 127),
                destination: .externalPort(name: "Out")
            ),
        ]
        let container = Container(
            name: "Bridge",
            startBar: 1,
            lengthBars: 4,
            onEnterActions: actions
        )

        dispatcher.containerDidEnter(container)

        #expect(mock.sentMessages.count == 2)
        #expect(mock.sentMessages[0].message == .programChange(channel: 0, program: 5))
        #expect(mock.sentMessages[1].message == .noteOn(channel: 0, note: 60, velocity: 127))
        #expect(triggerMock.calls.count == 1)
        #expect(triggerMock.calls[0] == .start(targetID))
    }

    @Test("Multiple trigger actions fire in order")
    func multipleTriggerActionsFireInOrder() {
        let mock = MockMIDIOutput()
        let triggerMock = MockTriggerDelegate()
        let dispatcher = ActionDispatcher(midiOutput: mock)
        dispatcher.triggerDelegate = triggerMock

        let target1 = ID<Container>()
        let target2 = ID<Container>()
        let actions: [ContainerAction] = [
            .makeTriggerContainer(targetID: target1, action: .start),
            .makeTriggerContainer(targetID: target2, action: .armRecord),
        ]
        let container = Container(
            name: "Verse",
            startBar: 1,
            lengthBars: 8,
            onEnterActions: actions
        )

        dispatcher.containerDidEnter(container)

        #expect(triggerMock.calls.count == 2)
        #expect(triggerMock.calls[0] == .start(target1))
        #expect(triggerMock.calls[1] == .setRecordArmed(target2, true))
    }
}

@Suite("MIDIActionMessage MIDI Bytes Tests")
struct MIDIActionMessageBytesTests {

    @Test("Program change produces correct bytes")
    func programChangeBytes() {
        let message = MIDIActionMessage.programChange(channel: 0, program: 5)
        let bytes = message.midiBytes
        #expect(bytes == [0xC0, 0x05])
    }

    @Test("Program change with channel produces correct bytes")
    func programChangeWithChannelBytes() {
        let message = MIDIActionMessage.programChange(channel: 3, program: 42)
        let bytes = message.midiBytes
        #expect(bytes == [0xC3, 42])
    }

    @Test("Control change produces correct bytes")
    func controlChangeBytes() {
        let message = MIDIActionMessage.controlChange(channel: 0, controller: 64, value: 127)
        let bytes = message.midiBytes
        #expect(bytes == [0xB0, 64, 127])
    }

    @Test("Note on produces correct bytes")
    func noteOnBytes() {
        let message = MIDIActionMessage.noteOn(channel: 9, note: 60, velocity: 100)
        let bytes = message.midiBytes
        #expect(bytes == [0x99, 60, 100])
    }

    @Test("Note off produces correct bytes")
    func noteOffBytes() {
        let message = MIDIActionMessage.noteOff(channel: 0, note: 60, velocity: 0)
        let bytes = message.midiBytes
        #expect(bytes == [0x80, 60, 0])
    }

    @Test("Values are masked to 7-bit range")
    func valuesMaskedTo7Bit() {
        let message = MIDIActionMessage.controlChange(channel: 0, controller: 200, value: 200)
        let bytes = message.midiBytes
        // 200 & 0x7F = 72
        #expect(bytes[1] == 72)
        #expect(bytes[2] == 72)
    }

    @Test("Channel is masked to 4-bit range")
    func channelMaskedTo4Bit() {
        let message = MIDIActionMessage.programChange(channel: 18, program: 0)
        let bytes = message.midiBytes
        // 18 & 0x0F = 2
        #expect(bytes[0] == 0xC2)
    }
}
