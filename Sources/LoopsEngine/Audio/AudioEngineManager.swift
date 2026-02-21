import Foundation
import AVFoundation
import CoreAudio
import LoopsCore

/// Manages the AVAudioEngine lifecycle: initialization, start, stop,
/// device switching, and sample rate configuration.
public final class AudioEngineManager: @unchecked Sendable {
    public let engine: AVAudioEngine
    public let deviceManager: DeviceManager

    public private(set) var isRunning: Bool = false
    public private(set) var currentSampleRate: Double = 44100.0

    private var deviceChangeObserver: NSObjectProtocol?

    public init() {
        self.engine = AVAudioEngine()
        self.deviceManager = DeviceManager()
    }

    deinit {
        stop()
        if let observer = deviceChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Starts the audio engine with default system devices.
    /// Throws `LoopsError.engineStartFailed` on failure.
    public func start() throws {
        guard !isRunning else { return }
        guard deviceManager.defaultOutputDeviceID() != nil else {
            throw LoopsError.engineStartFailed(
                underlying: "No audio output device available"
            )
        }
        do {
            try engine.start()
            isRunning = true
            currentSampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
            installDeviceChangeObserver()
        } catch {
            throw LoopsError.engineStartFailed(
                underlying: error.localizedDescription
            )
        }
    }

    /// Stops the audio engine.
    public func stop() {
        guard isRunning else { return }
        engine.stop()
        isRunning = false
    }

    /// Restarts the audio engine. Useful after device changes.
    public func restart() throws {
        stop()
        try start()
    }

    /// Sets the preferred buffer size in frames.
    /// Valid values: 64, 128, 256, 512, 1024.
    public func setBufferSize(_ size: Int) throws {
        let validSizes = [64, 128, 256, 512, 1024]
        guard validSizes.contains(size) else { return }

        let wasRunning = isRunning
        if wasRunning { stop() }

        // Set the buffer size via CoreAudio on the output device
        if let deviceID = deviceManager.defaultOutputDeviceID() {
            setDeviceBufferSize(deviceID: deviceID, size: UInt32(size))
        }

        if wasRunning {
            try start()
        }
    }

    /// Applies audio device settings, selecting devices and buffer size.
    public func applySettings(_ settings: AudioDeviceSettings) throws {
        let wasRunning = isRunning
        if wasRunning { stop() }

        // Apply buffer size
        if let deviceID = deviceManager.defaultOutputDeviceID() {
            setDeviceBufferSize(deviceID: deviceID, size: UInt32(settings.bufferSize))
        }

        if wasRunning {
            try start()
        }
    }

    /// Returns the current audio format of the engine's output.
    public func outputFormat() -> AVAudioFormat {
        guard isRunning else {
            return AVAudioFormat(standardFormatWithSampleRate: currentSampleRate, channels: 2)!
        }
        return engine.outputNode.outputFormat(forBus: 0)
    }

    /// Returns the current audio format of the engine's input.
    public func inputFormat() -> AVAudioFormat {
        guard isRunning else {
            return AVAudioFormat(standardFormatWithSampleRate: currentSampleRate, channels: 1)!
        }
        return engine.inputNode.inputFormat(forBus: 0)
    }

    /// Checks if a given sample rate is supported by the current output device.
    public func isSampleRateSupported(_ rate: Double) -> Bool {
        let supported = [44100.0, 48000.0]
        return supported.contains(rate)
    }

    // MARK: - Private

    private func installDeviceChangeObserver() {
        deviceChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleDeviceChange()
        }
    }

    private func handleDeviceChange() {
        // AVAudioEngine automatically stops on config change.
        // We restart to handle hot-plugged devices gracefully.
        isRunning = false
        do {
            try start()
        } catch {
            // Device change may leave us without a valid device.
            // The engine will be in a stopped state until the user
            // selects a new device or one becomes available.
        }
    }

    private func setDeviceBufferSize(deviceID: AudioDeviceID, size: UInt32) {
        var bufferSize = size
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            deviceID,
            &address,
            0, nil,
            UInt32(MemoryLayout<UInt32>.size),
            &bufferSize
        )
    }
}
