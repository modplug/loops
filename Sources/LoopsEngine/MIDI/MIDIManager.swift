import Foundation
import CoreMIDI
import LoopsCore

/// Manages CoreMIDI client, input ports, and connects to all available sources.
public final class MIDIManager: @unchecked Sendable {
    private let lock = NSLock()
    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    public private(set) var isActive: Bool = false

    /// Mapping from CoreMIDI source unique ID (used as connRefCon) to string device ID.
    private var sourceRefToDeviceID: [Int: String] = [:]

    /// Callback for received MIDI events (legacy, no device info).
    public var onMIDIEvent: ((MIDITrigger) -> Void)?

    /// Callback for received MIDI events with source device ID.
    /// Parameters: (trigger, sourceDeviceID)
    public var onMIDIEventFromDevice: ((MIDITrigger, String?) -> Void)?

    /// Callback for CC events that includes the CC value (0–127).
    /// Parameters: (trigger, ccValue)
    public var onMIDICCWithValue: ((MIDITrigger, UInt8) -> Void)?

    /// Callback for every received MIDI word with parsed status/channel/data and source device ID.
    /// Parameters: (word, deviceID)
    public var onRawMIDIMessage: ((UInt32, String?) -> Void)?

    public init() {}

    deinit {
        stop()
    }

    /// Initializes CoreMIDI client and input port, connects to all sources.
    public func start() throws {
        guard !isActive else { return }

        var status = MIDIClientCreateWithBlock("Loops" as CFString, &client) { [weak self] notification in
            self?.handleNotification(notification)
        }
        guard status == noErr else {
            throw LoopsError.midiClientCreationFailed(status: status)
        }

        status = MIDIInputPortCreateWithProtocol(
            client,
            "LoopsInput" as CFString,
            ._1_0,
            &inputPort
        ) { [weak self] eventList, srcConnRefCon in
            guard let self else { return }
            let deviceID: String?
            if let refCon = srcConnRefCon {
                let uniqueID = Int(bitPattern: refCon)
                self.lock.lock()
                deviceID = self.sourceRefToDeviceID[uniqueID]
                self.lock.unlock()
            } else {
                deviceID = nil
            }
            self.handleEventList(eventList, deviceID: deviceID)
        }
        guard status == noErr else {
            throw LoopsError.midiPortCreationFailed(status: status)
        }

        connectAllSources()
        isActive = true
    }

    /// Disconnects from all sources and disposes of the client.
    public func stop() {
        guard isActive else { return }
        MIDIPortDispose(inputPort)
        MIDIClientDispose(client)
        inputPort = 0
        client = 0
        lock.lock()
        sourceRefToDeviceID.removeAll()
        lock.unlock()
        isActive = false
    }

    /// Returns the names of all connected MIDI sources.
    public func sourceNames() -> [String] {
        let count = MIDIGetNumberOfSources()
        var names: [String] = []
        for i in 0..<count {
            let source = MIDIGetSource(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name)
            if let cfName = name?.takeRetainedValue() {
                names.append(cfName as String)
            }
        }
        return names
    }

    /// Returns all available MIDI input devices with unique IDs and display names.
    public func availableInputDevices() -> [MIDIInputDevice] {
        let count = MIDIGetNumberOfSources()
        var devices: [MIDIInputDevice] = []
        for i in 0..<count {
            let source = MIDIGetSource(i)
            var uniqueID: MIDIUniqueID = 0
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &uniqueID)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name)
            let displayName = (name?.takeRetainedValue() as String?) ?? "Unknown"
            devices.append(MIDIInputDevice(id: String(uniqueID), displayName: displayName))
        }
        return devices
    }

    // MARK: - Private

    private func connectAllSources() {
        let count = MIDIGetNumberOfSources()
        var newMapping: [Int: String] = [:]
        for i in 0..<count {
            let source = MIDIGetSource(i)
            var uniqueID: MIDIUniqueID = 0
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &uniqueID)
            let idInt = Int(uniqueID)
            newMapping[idInt] = String(uniqueID)
            let refCon = UnsafeMutableRawPointer(bitPattern: idInt)
            MIDIPortConnectSource(inputPort, source, refCon)
        }
        lock.lock()
        sourceRefToDeviceID = newMapping
        lock.unlock()
    }

    private func handleNotification(_ notification: UnsafePointer<MIDINotification>) {
        if notification.pointee.messageID == .msgSetupChanged {
            connectAllSources()
        }
    }

    private func handleEventList(_ eventList: UnsafePointer<MIDIEventList>, deviceID: String?) {
        let list = eventList.pointee
        withUnsafePointer(to: list.packet) { firstPacket in
            var packet = firstPacket
            for _ in 0..<list.numPackets {
                let words = packet.pointee.words
                parseMessage(word: words.0, deviceID: deviceID)
                packet = UnsafePointer(MIDIEventPacketNext(packet))
            }
        }
    }

    private func parseMessage(word: UInt32, deviceID: String?) {
        // Fire raw callback for every message before parsing
        onRawMIDIMessage?(word, deviceID)

        let status = UInt8((word >> 16) & 0xF0)
        let channel = UInt8((word >> 16) & 0x0F)
        let data1 = UInt8((word >> 8) & 0xFF)
        let data2 = UInt8(word & 0xFF)

        switch status {
        case 0x80: // Note Off
            let trigger = MIDITrigger.noteOn(channel: channel, note: data1)
            onMIDIEvent?(trigger)
            onMIDIEventFromDevice?(trigger, deviceID)
        case 0x90: // Note On
            let trigger = MIDITrigger.noteOn(channel: channel, note: data1)
            onMIDIEvent?(trigger)
            onMIDIEventFromDevice?(trigger, deviceID)
        case 0xB0: // Control Change
            let trigger = MIDITrigger.controlChange(channel: channel, controller: data1)
            onMIDIEvent?(trigger)
            onMIDIEventFromDevice?(trigger, deviceID)
            onMIDICCWithValue?(trigger, data2)
        case 0xC0: // Program Change
            let trigger = MIDITrigger.controlChange(channel: channel, controller: data1)
            onMIDIEvent?(trigger)
            onMIDIEventFromDevice?(trigger, deviceID)
        case 0xE0: // Pitch Bend
            let trigger = MIDITrigger.controlChange(channel: channel, controller: data1)
            onMIDIEvent?(trigger)
            onMIDIEventFromDevice?(trigger, deviceID)
        default:
            break
        }
    }
}
