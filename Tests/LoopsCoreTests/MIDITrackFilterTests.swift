import Testing
@testable import LoopsCore

@Suite("MIDITrackFilter Tests")
struct MIDITrackFilterTests {

    @Test("Matching device and channel passes")
    func matchingDeviceAndChannel() {
        let result = MIDITrackFilter.matches(
            eventDeviceID: "device-1",
            eventChannel: 2,
            trackDeviceID: "device-1",
            trackChannel: 3 // 1-based: channel 3 = 0-based channel 2
        )
        #expect(result == true)
    }

    @Test("Non-matching device blocks")
    func nonMatchingDeviceBlocks() {
        let result = MIDITrackFilter.matches(
            eventDeviceID: "device-2",
            eventChannel: 0,
            trackDeviceID: "device-1",
            trackChannel: nil
        )
        #expect(result == false)
    }

    @Test("Non-matching channel blocks")
    func nonMatchingChannelBlocks() {
        let result = MIDITrackFilter.matches(
            eventDeviceID: "device-1",
            eventChannel: 5,
            trackDeviceID: "device-1",
            trackChannel: 3 // expects 0-based channel 2, got 5
        )
        #expect(result == false)
    }

    @Test("Omni mode passes all channels")
    func omniModePassesAllChannels() {
        for ch: UInt8 in 0...15 {
            let result = MIDITrackFilter.matches(
                eventDeviceID: "device-1",
                eventChannel: ch,
                trackDeviceID: "device-1",
                trackChannel: nil // omni
            )
            #expect(result == true, "Channel \(ch) should pass in omni mode")
        }
    }

    @Test("No device filter passes all devices")
    func noDeviceFilterPassesAll() {
        let result = MIDITrackFilter.matches(
            eventDeviceID: "any-device",
            eventChannel: 0,
            trackDeviceID: nil, // no device filter
            trackChannel: 1 // channel 1 = 0-based channel 0
        )
        #expect(result == true)
    }

    @Test("No device filter and omni channel passes everything")
    func noFilterPassesEverything() {
        let result = MIDITrackFilter.matches(
            eventDeviceID: "any-device",
            eventChannel: 15,
            trackDeviceID: nil,
            trackChannel: nil
        )
        #expect(result == true)
    }

    @Test("Unknown event device with device filter blocks")
    func unknownEventDeviceWithFilterBlocks() {
        let result = MIDITrackFilter.matches(
            eventDeviceID: nil,
            eventChannel: 0,
            trackDeviceID: "device-1",
            trackChannel: nil
        )
        #expect(result == false)
    }

    @Test("Unknown event device without device filter passes")
    func unknownEventDeviceWithoutFilterPasses() {
        let result = MIDITrackFilter.matches(
            eventDeviceID: nil,
            eventChannel: 5,
            trackDeviceID: nil,
            trackChannel: 6 // 1-based: channel 6 = 0-based channel 5
        )
        #expect(result == true)
    }
}
