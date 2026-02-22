import Foundation
import CoreMIDI
import AVFoundation
import LoopsCore

/// Sends MIDI messages via CoreMIDI to external destinations
/// and via AUAudioUnit.scheduleMIDIEvent to internal AU instruments.
public final class CoreMIDIOutput: @unchecked Sendable, MIDIOutput {
    private let lock = NSLock()
    private var client: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0
    private var isSetup = false

    /// Lookup for internal AU instrument nodes, keyed by track ID.
    /// Set by the PlaybackScheduler before playback starts.
    private var _trackInstrumentUnits: [ID<Track>: AVAudioUnit] = [:]
    public var trackInstrumentUnits: [ID<Track>: AVAudioUnit] {
        get {
            lock.lock()
            let units = _trackInstrumentUnits
            lock.unlock()
            return units
        }
        set {
            lock.lock()
            _trackInstrumentUnits = newValue
            lock.unlock()
        }
    }

    public init() {}

    deinit {
        teardown()
    }

    public func setup() {
        guard !isSetup else { return }
        MIDIClientCreateWithBlock("LoopsActionOutput" as CFString, &client, nil)
        MIDIOutputPortCreate(client, "LoopsActionOutputPort" as CFString, &outputPort)
        isSetup = true
    }

    public func teardown() {
        guard isSetup else { return }
        MIDIPortDispose(outputPort)
        MIDIClientDispose(client)
        outputPort = 0
        client = 0
        isSetup = false
    }

    public func send(_ message: MIDIActionMessage, toExternalPort name: String) {
        guard isSetup else { return }
        guard let destination = findDestination(named: name) else { return }

        let bytes = message.midiBytes
        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, bytes.count, bytes)
        MIDISend(outputPort, destination, &packetList)
    }

    public func send(_ message: MIDIActionMessage, toTrack trackID: ID<Track>) {
        lock.lock()
        let unit = _trackInstrumentUnits[trackID]
        lock.unlock()
        guard let unit else { return }
        let bytes = message.midiBytes
        let auUnit = unit.auAudioUnit
        auUnit.scheduleMIDIEventBlock?(AUEventSampleTimeImmediate, 0, bytes.count, bytes)
    }

    private func findDestination(named name: String) -> MIDIEndpointRef? {
        let count = MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let dest = MIDIGetDestination(i)
            var cfName: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(dest, kMIDIPropertyDisplayName, &cfName)
            if let displayName = cfName?.takeRetainedValue() as String?, displayName == name {
                return dest
            }
        }
        return nil
    }
}

extension MIDIActionMessage {
    /// Converts to raw MIDI bytes for CoreMIDI transmission.
    var midiBytes: [UInt8] {
        switch self {
        case .programChange(let channel, let program):
            return [0xC0 | (channel & 0x0F), program & 0x7F]
        case .controlChange(let channel, let controller, let value):
            return [0xB0 | (channel & 0x0F), controller & 0x7F, value & 0x7F]
        case .noteOn(let channel, let note, let velocity):
            return [0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F]
        case .noteOff(let channel, let note, let velocity):
            return [0x80 | (channel & 0x0F), note & 0x7F, velocity & 0x7F]
        }
    }
}
