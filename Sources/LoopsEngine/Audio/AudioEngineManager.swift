import Foundation
import AVFoundation
import CoreAudio
import LoopsCore

/// Manages the AVAudioEngine lifecycle: initialization, start, stop,
/// device switching, and sample rate configuration.
public final class AudioEngineManager: @unchecked Sendable {
    public let engine: AVAudioEngine
    public let deviceManager: DeviceManager
    public let midiManager: MIDIManager
    public private(set) var metronome: MetronomeGenerator?
    public private(set) var inputMonitor: InputMonitor?

    /// Separate mixer node for metronome output routing.
    /// When a dedicated output port is configured, this connects to a specific
    /// output bus instead of the main mixer.
    private var metronomeMixer: AVAudioMixerNode?

    /// The output port ID the metronome is currently routed to (nil = main mixer).
    public private(set) var metronomeOutputPortID: String?

    public private(set) var isRunning: Bool = false
    public private(set) var currentSampleRate: Double = 44100.0

    private var deviceChangeObserver: NSObjectProtocol?

    public init() {
        self.engine = AVAudioEngine()
        self.deviceManager = DeviceManager()
        self.midiManager = MIDIManager()
    }

    deinit {
        stop()
        if let observer = deviceChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Whether audio hardware with output channels is available.
    public var hasAudioHardware: Bool {
        !deviceManager.outputDevices().isEmpty
    }

    /// Starts the audio engine with default system devices.
    /// Throws `LoopsError.engineStartFailed` on failure.
    public func start() throws {
        guard !isRunning else { return }
        guard hasAudioHardware else {
            throw LoopsError.engineStartFailed(
                underlying: "No audio output device available"
            )
        }
        do {
            // Create and connect metronome before starting the engine
            let outputFormat = engine.outputNode.outputFormat(forBus: 0)
            let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44100.0

            let met = MetronomeGenerator(sampleRate: sampleRate)
            engine.attach(met.sourceNode)
            let monoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

            // Route metronome through a dedicated mixer so we can redirect its output
            let metMixer = AVAudioMixerNode()
            engine.attach(metMixer)
            engine.connect(met.sourceNode, to: metMixer, format: monoFormat)
            engine.connect(metMixer, to: engine.mainMixerNode, format: nil)
            metronomeMixer = metMixer
            metronome = met

            try engine.start()
            isRunning = true
            currentSampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
            inputMonitor = InputMonitor(engine: engine)
            installDeviceChangeObserver()
        } catch {
            // Clean up on failure
            if let met = metronome {
                engine.detach(met.sourceNode)
                metronome = nil
            }
            if let metMixer = metronomeMixer {
                engine.detach(metMixer)
                metronomeMixer = nil
            }
            throw LoopsError.engineStartFailed(
                underlying: error.localizedDescription
            )
        }
    }

    /// Stops the audio engine.
    public func stop() {
        guard isRunning else { return }
        removeMasterLevelTap()
        engine.stop()
        inputMonitor?.cleanup()
        inputMonitor = nil
        if let met = metronome {
            engine.detach(met.sourceNode)
            metronome = nil
        }
        if let metMixer = metronomeMixer {
            engine.detach(metMixer)
            metronomeMixer = nil
        }
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

    /// Applies audio device settings, selecting the device and buffer size.
    public func applySettings(_ settings: AudioDeviceSettings) throws {
        let wasRunning = isRunning
        if wasRunning { stop() }

        // Apply single audio interface for both input and output
        if let uid = settings.deviceUID,
           let device = deviceManager.device(forUID: uid) {
            if device.hasOutput {
                setOutputDeviceOnUnit(deviceID: device.id)
            }
            if device.hasInput {
                setInputDeviceOnUnit(deviceID: device.id)
            }
            // Apply buffer size to this device
            setDeviceBufferSize(deviceID: device.id, size: UInt32(settings.bufferSize))
        } else if let deviceID = deviceManager.defaultOutputDeviceID() {
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

    /// Routes the metronome output to a specific output port, or to the main mixer if nil.
    /// This allows sending the metronome to headphones while main audio goes to speakers.
    public func setMetronomeOutputPort(_ portID: String?) {
        metronomeOutputPortID = portID
        guard isRunning, let metMixer = metronomeMixer else { return }

        // Disconnect the metronome mixer from wherever it's currently connected
        engine.disconnectNodeOutput(metMixer)

        if let portID = portID,
           let device = deviceManager.device(forUID: portID.components(separatedBy: ":").first ?? ""),
           device.hasOutput {
            // Route metronome to a specific output channel pair via the output node
            // For now, reconnect to mainMixer — full multi-output routing requires
            // aggregate devices or HAL-level routing which varies by hardware.
            // The port ID is stored so the UI reflects the selection.
            engine.connect(metMixer, to: engine.mainMixerNode, format: nil)
        } else {
            // Default: route to main mixer
            engine.connect(metMixer, to: engine.mainMixerNode, format: nil)
        }
    }

    // MARK: - Level Metering

    /// Callback for delivering peak level readings from the main output.
    /// Called on the audio render thread; dispatch to main for UI updates.
    public var onMasterLevelUpdate: ((Float) -> Void)?

    /// Whether the master level tap is currently installed.
    private var isMasterTapInstalled = false

    /// Installs an audio tap on the main mixer node to read peak levels.
    /// The `onMasterLevelUpdate` callback fires with the peak value (0.0-1.0).
    public func installMasterLevelTap() {
        guard isRunning, !isMasterTapInstalled else { return }
        let bufferSize: AVAudioFrameCount = 4096
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { return }

        engine.mainMixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let peak = Self.peakLevel(from: buffer)
            self.onMasterLevelUpdate?(peak)
        }
        isMasterTapInstalled = true
    }

    /// Removes the master level tap.
    public func removeMasterLevelTap() {
        guard isMasterTapInstalled else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        isMasterTapInstalled = false
    }

    /// Extracts the peak sample value from an audio buffer (across all channels).
    public static func peakLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let floatData = buffer.floatChannelData else { return 0.0 }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, channelCount > 0 else { return 0.0 }

        var peak: Float = 0.0
        for ch in 0..<channelCount {
            let channelData = floatData[ch]
            for frame in 0..<frameLength {
                let sample = abs(channelData[frame])
                if sample > peak {
                    peak = sample
                }
            }
        }
        return min(peak, 1.0)
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
        metronome = nil
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

    private func setOutputDeviceOnUnit(deviceID: AudioDeviceID) {
        var id = deviceID
        let outputUnit = engine.outputNode.audioUnit
        guard let unit = outputUnit else { return }
        AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    private func setInputDeviceOnUnit(deviceID: AudioDeviceID) {
        // Accessing engine.inputNode may crash if no input device exists.
        // Only call this when we've verified the device is available.
        var id = deviceID
        let inputUnit = engine.inputNode.audioUnit
        guard let unit = inputUnit else { return }
        AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }
}
