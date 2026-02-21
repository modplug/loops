import SwiftUI
import LoopsCore
import LoopsEngine

/// View model for the audio device settings view.
@Observable
@MainActor
public final class SettingsViewModel {
    public static let validBufferSizes = [64, 128, 256, 512, 1024]

    public var inputDevices: [AudioDevice] = []
    public var outputDevices: [AudioDevice] = []
    public var isEngineRunning: Bool = false
    public var currentSampleRate: Double = 44100.0

    public var selectedInputUID: String? {
        didSet { applyDeviceChange() }
    }

    public var selectedOutputUID: String? {
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

    /// Refreshes the device lists from CoreAudio.
    public func refreshDevices() {
        inputDevices = engineManager.deviceManager.inputDevices()
        outputDevices = engineManager.deviceManager.outputDevices()
    }

    /// Syncs view model state from the engine's current state.
    public func syncFromEngine() {
        isEngineRunning = engineManager.isRunning
        currentSampleRate = engineManager.currentSampleRate
    }

    /// Returns the current settings as an AudioDeviceSettings value.
    public func currentSettings() -> AudioDeviceSettings {
        AudioDeviceSettings(
            inputDeviceUID: selectedInputUID,
            outputDeviceUID: selectedOutputUID,
            bufferSize: bufferSize
        )
    }

    /// Applies persisted settings to the view model.
    public func apply(settings: AudioDeviceSettings) {
        selectedInputUID = settings.inputDeviceUID
        selectedOutputUID = settings.outputDeviceUID
        bufferSize = settings.bufferSize
    }

    private func applyDeviceChange() {
        let settings = currentSettings()
        do {
            try engineManager.applySettings(settings)
            syncFromEngine()
        } catch {
            // Device change failed — engine may have stopped
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
