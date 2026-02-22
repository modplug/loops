import Testing
import Foundation
@testable import LoopsEngine
@testable import LoopsCore

/// Audio hardware tests are skipped on CI where no real audio device is available.
private let isCI = ProcessInfo.processInfo.environment["CI"] != nil

@Suite("AudioEngineManager Tests")
struct AudioEngineManagerTests {

    @Test("Engine can be created")
    func engineCreation() {
        let manager = AudioEngineManager()
        #expect(!manager.isRunning)
    }

    @Test("Engine starts and stops cleanly", .disabled(if: isCI, "No audio hardware on CI"))
    func engineStartStop() throws {
        let manager = AudioEngineManager()
        try manager.start()
        #expect(manager.isRunning)
        #expect(manager.currentSampleRate > 0)

        manager.stop()
        #expect(!manager.isRunning)
    }

    @Test("Engine restarts cleanly", .disabled(if: isCI, "No audio hardware on CI"))
    func engineRestart() throws {
        let manager = AudioEngineManager()
        try manager.start()
        #expect(manager.isRunning)

        try manager.restart()
        #expect(manager.isRunning)

        manager.stop()
        #expect(!manager.isRunning)
    }

    @Test("Engine start is idempotent", .disabled(if: isCI, "No audio hardware on CI"))
    func engineStartIdempotent() throws {
        let manager = AudioEngineManager()
        try manager.start()
        try manager.start() // second start should be a no-op
        #expect(manager.isRunning)
        manager.stop()
    }

    @Test("Engine stop is idempotent")
    func engineStopIdempotent() {
        let manager = AudioEngineManager()
        manager.stop() // stop when not running should be a no-op
        #expect(!manager.isRunning)
    }

    @Test("Engine reports output format", .disabled(if: isCI, "No audio hardware on CI"))
    func engineOutputFormat() throws {
        let manager = AudioEngineManager()
        try manager.start()
        let format = manager.outputFormat()
        #expect(format.sampleRate > 0)
        #expect(format.channelCount > 0)
        manager.stop()
    }

    @Test("Engine supports standard sample rates")
    func standardSampleRates() {
        let manager = AudioEngineManager()
        #expect(manager.isSampleRateSupported(44100.0))
        #expect(manager.isSampleRateSupported(48000.0))
        #expect(!manager.isSampleRateSupported(22050.0))
    }

    @Test("DeviceManager can enumerate devices")
    func deviceEnumeration() {
        let deviceManager = DeviceManager()
        // CI may not have audio devices, so just check it doesn't crash
        let _  = deviceManager.allDevices()
        let _ = deviceManager.inputDevices()
        let _ = deviceManager.outputDevices()
    }

    @Test("DeviceManager default device queries don't crash")
    func defaultDeviceQueries() {
        let deviceManager = DeviceManager()
        // These may return nil on CI but should not crash
        let _ = deviceManager.defaultInputDeviceID()
        let _ = deviceManager.defaultOutputDeviceID()
    }

    @Test("Buffer size validation", .disabled(if: isCI, "No audio hardware on CI"))
    func bufferSizeValidation() throws {
        let manager = AudioEngineManager()
        try manager.start()
        // Valid buffer size should not throw
        try manager.setBufferSize(256)
        // Invalid buffer size should be silently ignored
        try manager.setBufferSize(100)
        manager.stop()
    }

    @Test("Apply settings does not crash", .disabled(if: isCI, "No audio hardware on CI"))
    func applySettings() throws {
        let manager = AudioEngineManager()
        try manager.start()
        let settings = AudioDeviceSettings(bufferSize: 512)
        try manager.applySettings(settings)
        #expect(manager.isRunning)
        manager.stop()
    }
}
