import Testing
import Foundation
import AVFoundation
@testable import LoopsEngine
@testable import LoopsCore

/// Audio hardware tests require a live AVAudioEngine which can crash with an
/// unrecoverable ObjC exception in sandboxed test runners (SPM, CI).
/// Opt in with: LOOPS_AUDIO_TESTS=1 swift test
private let audioHardwareTestsEnabled =
    ProcessInfo.processInfo.environment["LOOPS_AUDIO_TESTS"] != nil

@Suite("AudioEngineManager Tests", .serialized)
struct AudioEngineManagerTests {

    @Test("Engine can be created")
    func engineCreation() {
        let manager = AudioEngineManager()
        #expect(!manager.isRunning)
    }

    @Test("Engine starts and stops cleanly",
          .enabled(if: audioHardwareTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func engineStartStop() throws {
        let manager = AudioEngineManager()
        try manager.start()
        #expect(manager.isRunning)
        #expect(manager.currentSampleRate > 0)

        manager.stop()
        #expect(!manager.isRunning)
    }

    @Test("Engine restarts cleanly",
          .enabled(if: audioHardwareTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func engineRestart() throws {
        let manager = AudioEngineManager()
        try manager.start()
        #expect(manager.isRunning)

        try manager.restart()
        #expect(manager.isRunning)

        manager.stop()
        #expect(!manager.isRunning)
    }

    @Test("Engine start is idempotent",
          .enabled(if: audioHardwareTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func engineStartIdempotent() throws {
        let manager = AudioEngineManager()
        try manager.start()
        try manager.start()
        #expect(manager.isRunning)
        manager.stop()
    }

    @Test("Engine stop is idempotent")
    func engineStopIdempotent() {
        let manager = AudioEngineManager()
        manager.stop()
        #expect(!manager.isRunning)
    }

    @Test("Engine reports output format",
          .enabled(if: audioHardwareTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
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
        let _ = deviceManager.allDevices()
        let _ = deviceManager.inputDevices()
        let _ = deviceManager.outputDevices()
    }

    @Test("DeviceManager default device queries don't crash")
    func defaultDeviceQueries() {
        let deviceManager = DeviceManager()
        let _ = deviceManager.defaultInputDeviceID()
        let _ = deviceManager.defaultOutputDeviceID()
    }

    @Test("Buffer size validation",
          .enabled(if: audioHardwareTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func bufferSizeValidation() throws {
        let manager = AudioEngineManager()
        try manager.start()
        try manager.setBufferSize(256)
        try manager.setBufferSize(100)
        manager.stop()
    }

    @Test("Apply settings does not crash",
          .enabled(if: audioHardwareTestsEnabled, "Set LOOPS_AUDIO_TESTS=1 to run"))
    func applySettings() throws {
        let manager = AudioEngineManager()
        try manager.start()
        let settings = AudioDeviceSettings(bufferSize: 512)
        try manager.applySettings(settings)
        #expect(manager.isRunning)
        manager.stop()
    }
}
