import SwiftUI
import LoopsCore
import LoopsEngine

/// Settings view for audio device and buffer size selection.
/// Accessible via Cmd+, (Settings menu).
public struct AudioDeviceView: View {
    @Bindable var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section("Input Device") {
                Picker("Input", selection: $viewModel.selectedInputUID) {
                    Text("System Default").tag(String?.none)
                    ForEach(viewModel.inputDevices) { device in
                        Text(device.name).tag(Optional(device.uid))
                    }
                }
            }

            Section("Output Device") {
                Picker("Output", selection: $viewModel.selectedOutputUID) {
                    Text("System Default").tag(String?.none)
                    ForEach(viewModel.outputDevices) { device in
                        Text(device.name).tag(Optional(device.uid))
                    }
                }
            }

            Section("Buffer Size") {
                Picker("Buffer Size", selection: $viewModel.bufferSize) {
                    ForEach(SettingsViewModel.validBufferSizes, id: \.self) { size in
                        Text("\(size) samples").tag(size)
                    }
                }
            }

            Section("Engine Status") {
                HStack {
                    Text("Sample Rate")
                    Spacer()
                    Text(String(format: "%.0f Hz", viewModel.currentSampleRate))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Engine")
                    Spacer()
                    Text(viewModel.isEngineRunning ? "Running" : "Stopped")
                        .foregroundStyle(viewModel.isEngineRunning ? .green : .red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
    }
}
