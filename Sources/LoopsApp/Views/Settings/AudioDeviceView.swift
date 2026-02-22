import SwiftUI
import LoopsCore
import LoopsEngine

/// Bitwig-style audio device settings view.
/// Accessible via Cmd+, (Settings menu).
public struct AudioDeviceView: View {
    @Bindable var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section("Audio Device") {
                Picker("Device", selection: $viewModel.selectedDeviceUID) {
                    Text("System Default").tag(String?.none)
                    ForEach(viewModel.allDevices) { device in
                        Text(device.name).tag(Optional(device.uid))
                    }
                }
            }

            if !viewModel.inputPorts.isEmpty {
                Section("Inputs") {
                    PortTable(
                        ports: viewModel.inputPorts,
                        onRename: { portID, name in
                            viewModel.renameInputPort(portID: portID, name: name)
                        }
                    )
                }
            }

            if !viewModel.outputPorts.isEmpty {
                Section("Outputs") {
                    PortTable(
                        ports: viewModel.outputPorts,
                        onRename: { portID, name in
                            viewModel.renameOutputPort(portID: portID, name: name)
                        }
                    )
                }
            }

            Section("Audio Engine") {
                if !viewModel.availableSampleRates.isEmpty {
                    Picker("Sample Rate", selection: $viewModel.selectedSampleRate) {
                        Text("Device Default").tag(Double?.none)
                        ForEach(viewModel.availableSampleRates, id: \.self) { rate in
                            Text(String(format: "%.0f Hz", rate)).tag(Optional(rate))
                        }
                    }
                }

                Picker("Buffer Size", selection: $viewModel.bufferSize) {
                    ForEach(SettingsViewModel.validBufferSizes, id: \.self) { size in
                        Text("\(size) samples").tag(size)
                    }
                }

                HStack {
                    Text("Latency")
                    Spacer()
                    Text(String(format: "%.1f ms", viewModel.latencyMs))
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
        .frame(width: 560, height: 600)
    }
}

// MARK: - Bitwig-style two-column port table

/// Groups ports into stereo+mono rows like Bitwig:
/// | Stereo          | Mono              |
/// | In 1 L/2 R  [name] | In 1 L  [name]   |
/// |                     | In 2 R  [name]   |
private struct PortTable<Direction: Sendable>: View {
    let ports: [ChannelPort<Direction>]
    let onRename: (String, String) -> Void

    /// Groups the flat port list into rows, where each row has an optional
    /// stereo port and its corresponding mono ports.
    private var rows: [PortGroup<Direction>] {
        var groups: [PortGroup<Direction>] = []
        var i = 0
        while i < ports.count {
            let port = ports[i]
            if port.layout == .stereo {
                // Collect the following mono ports that belong to this stereo pair
                var monos: [ChannelPort<Direction>] = []
                var j = i + 1
                while j < ports.count && ports[j].layout == .mono
                    && ports[j].streamIndex == port.streamIndex
                    && (ports[j].channelOffset == port.channelOffset
                        || ports[j].channelOffset == port.channelOffset + 1) {
                    monos.append(ports[j])
                    j += 1
                }
                groups.append(PortGroup(stereo: port, monos: monos))
                i = j
            } else {
                // Standalone mono (odd channel)
                groups.append(PortGroup(stereo: nil, monos: [port]))
                i += 1
            }
        }
        return groups
    }

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
            // Header
            GridRow {
                Text("Stereo")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("Mono")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(rows) { group in
                GridRow {
                    // Stereo column
                    if let stereo = group.stereo {
                        PortCell(port: stereo, onRename: onRename)
                    } else {
                        Color.clear.frame(height: 1)
                    }

                    // Mono column — stack the mono ports vertically
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(group.monos) { mono in
                            PortCell(port: mono, onRename: onRename)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A group of related ports: one stereo pair and its constituent mono channels.
private struct PortGroup<Direction: Sendable>: Identifiable {
    let stereo: ChannelPort<Direction>?
    let monos: [ChannelPort<Direction>]

    var id: String {
        stereo?.id ?? monos.first?.id ?? UUID().uuidString
    }
}

/// A single port cell with default name label and editable custom name.
private struct PortCell<Direction: Sendable>: View {
    let port: ChannelPort<Direction>
    let onRename: (String, String) -> Void

    @State private var editedName: String = ""

    var body: some View {
        HStack(spacing: 4) {
            Text(port.defaultName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
                .lineLimit(1)

            TextField("Name", text: $editedName)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(minWidth: 80, maxWidth: 120)
                .onSubmit { onRename(port.id, editedName) }
                .onChange(of: editedName) { _, newValue in
                    onRename(port.id, newValue)
                }
        }
        .onAppear {
            editedName = port.customName ?? ""
        }
    }
}
