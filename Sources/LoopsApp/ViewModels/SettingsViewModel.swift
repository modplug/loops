import SwiftUI
import LoopsCore
import LoopsEngine

/// View model for the audio device settings view.
@Observable
@MainActor
public final class SettingsViewModel {
    public static let validBufferSizes = [64, 128, 256, 512, 1024]

    public var allDevices: [AudioDevice] = []
    public var isEngineRunning: Bool = false
    public var currentSampleRate: Double = 44100.0

    public var inputPorts: [InputPort] = []
    public var outputPorts: [OutputPort] = []
    public var availableSampleRates: [Double] = []

    public var selectedDeviceUID: String? {
        didSet {
            if oldValue != selectedDeviceUID {
                onDeviceChanged()
            }
        }
    }

    public var selectedSampleRate: Double? {
        didSet { applyDeviceChange() }
    }

    public var bufferSize: Int = 256 {
        didSet { applyBufferSizeChange() }
    }

    private let engineManager: AudioEngineManager

    public init(engineManager: AudioEngineManager) {
        self.engineManager = engineManager
        refreshDevices()
        syncFromEngine()
    }

    /// Refreshes the device list from CoreAudio.
    public func refreshDevices() {
        allDevices = engineManager.deviceManager.allDevices()
            .filter { $0.hasOutput }
    }

    /// Syncs view model state from the engine's current state.
    public func syncFromEngine() {
        isEngineRunning = engineManager.isRunning
        currentSampleRate = engineManager.currentSampleRate
    }

    /// Returns the current settings as an AudioDeviceSettings value.
    public func currentSettings() -> AudioDeviceSettings {
        AudioDeviceSettings(
            deviceUID: selectedDeviceUID,
            sampleRate: selectedSampleRate,
            bufferSize: bufferSize,
            inputPorts: inputPorts,
            outputPorts: outputPorts
        )
    }

    /// Applies persisted settings to the view model.
    public func apply(settings: AudioDeviceSettings) {
        // Set device without triggering onDeviceChanged (we'll merge ports manually)
        let uid = settings.deviceUID
        selectedDeviceUID = uid
        selectedSampleRate = settings.sampleRate
        bufferSize = settings.bufferSize

        // Enumerate fresh ports, then merge saved custom names
        if let uid, let device = engineManager.deviceManager.device(forUID: uid) {
            let freshInputs = engineManager.deviceManager.inputPorts(for: device)
            let freshOutputs = engineManager.deviceManager.outputPorts(for: device)
            inputPorts = mergePorts(fresh: freshInputs, saved: settings.inputPorts)
            outputPorts = mergePorts(fresh: freshOutputs, saved: settings.outputPorts)
            availableSampleRates = device.supportedSampleRates
        } else {
            inputPorts = []
            outputPorts = []
            availableSampleRates = []
        }
    }

    /// Renames an input port by its stable ID.
    public func renameInputPort(portID: String, name: String) {
        guard let index = inputPorts.firstIndex(where: { $0.id == portID }) else { return }
        inputPorts[index].customName = name.isEmpty ? nil : name
    }

    /// Renames an output port by its stable ID.
    public func renameOutputPort(portID: String, name: String) {
        guard let index = outputPorts.firstIndex(where: { $0.id == portID }) else { return }
        outputPorts[index].customName = name.isEmpty ? nil : name
    }

    /// Calculated latency in milliseconds based on buffer size and sample rate.
    public var latencyMs: Double {
        let rate = selectedSampleRate ?? currentSampleRate
        guard rate > 0 else { return 0 }
        return Double(bufferSize) / rate * 1000.0
    }

    // MARK: - Private

    /// Called when the selected device changes.
    private func onDeviceChanged() {
        if let uid = selectedDeviceUID,
           let device = engineManager.deviceManager.device(forUID: uid) {
            let freshInputs = engineManager.deviceManager.inputPorts(for: device)
            let freshOutputs = engineManager.deviceManager.outputPorts(for: device)
            // Merge with any existing saved names
            inputPorts = mergePorts(fresh: freshInputs, saved: inputPorts)
            outputPorts = mergePorts(fresh: freshOutputs, saved: outputPorts)
            availableSampleRates = device.supportedSampleRates
            if let rate = selectedSampleRate, !availableSampleRates.contains(rate) {
                selectedSampleRate = availableSampleRates.first
            }
        } else {
            inputPorts = []
            outputPorts = []
            availableSampleRates = []
        }
        applyDeviceChange()
    }

    /// Merges freshly enumerated ports with saved ports, preserving custom names.
    private func mergePorts<Direction: Sendable>(
        fresh: [ChannelPort<Direction>],
        saved: [ChannelPort<Direction>]
    ) -> [ChannelPort<Direction>] {
        let savedByID = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        return fresh.map { port in
            var merged = port
            if let saved = savedByID[port.id] {
                merged.customName = saved.customName
            }
            return merged
        }
    }

    private func applyDeviceChange() {
        let settings = currentSettings()
        do {
            try engineManager.applySettings(settings)
            syncFromEngine()
        } catch {
            syncFromEngine()
        }
    }

    private func applyBufferSizeChange() {
        do {
            try engineManager.setBufferSize(bufferSize)
            syncFromEngine()
        } catch {
            syncFromEngine()
        }
    }
}
