import SwiftUI
import LoopsCore
import LoopsEngine

/// Inspector panel showing track-level settings: name, kind, effects, I/O routing,
/// MIDI routing, volume/pan, and automation lanes summary.
public struct TrackInspectorView: View {
    let track: Track

    // Name
    var onRename: ((String) -> Void)?

    // Effect callbacks
    var onAddEffect: ((InsertEffect) -> Void)?
    var onRemoveEffect: ((ID<InsertEffect>) -> Void)?
    var onToggleEffectBypass: ((ID<InsertEffect>) -> Void)?
    var onToggleChainBypass: (() -> Void)?
    var onReorderEffects: ((IndexSet, Int) -> Void)?

    // Routing callbacks
    var onSetInputPort: ((String?) -> Void)?
    var onSetOutputPort: ((String?) -> Void)?
    var onSetMIDIInput: ((String?, UInt8?) -> Void)?

    // Mix callbacks
    var onSetVolume: ((Float) -> Void)?
    var onSetPan: ((Float) -> Void)?

    // Port/device name resolvers
    var inputPortName: String = "Default"
    var outputPortName: String = "Default"
    var midiDeviceName: String?
    var midiChannelLabel: String?

    @State private var editingName: String = ""
    @State private var availableEffects: [AudioUnitInfo] = []
    @State private var volumeValue: Float = 1.0
    @State private var panValue: Float = 0.0

    public var body: some View {
        Form {
            // Track info
            Section("Track") {
                TextField("Name", text: $editingName)
                    .onSubmit { onRename?(editingName) }
                LabeledContent("Kind") {
                    Text(track.kind.displayName)
                }
            }

            // Effects chain
            Section("Effects") {
                effectsSummary

                let grouped = Dictionary(grouping: availableEffects) { $0.manufacturerName }
                let manufacturers = grouped.keys.sorted()
                if !manufacturers.isEmpty {
                    Menu {
                        ForEach(manufacturers, id: \.self) { manufacturer in
                            Menu(manufacturer) {
                                ForEach(grouped[manufacturer] ?? []) { effect in
                                    Button(effect.name) {
                                        let insert = InsertEffect(
                                            component: effect.componentInfo,
                                            displayName: effect.name,
                                            orderIndex: track.insertEffects.count
                                        )
                                        onAddEffect?(insert)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Add Effect", systemImage: "plus.circle")
                    }
                }
            }

            // I/O Routing
            if track.kind == .audio || track.kind == .bus || track.kind == .backing {
                Section("I/O Routing") {
                    LabeledContent("Input") {
                        Text(inputPortName)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Output") {
                        Text(outputPortName)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MIDI Routing
            if track.kind == .midi {
                Section("MIDI Routing") {
                    LabeledContent("Device") {
                        Text(midiDeviceName ?? "All Devices")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Channel") {
                        Text(midiChannelLabel ?? "Omni")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Master output
            if track.kind == .master {
                Section("Output") {
                    LabeledContent("Output") {
                        Text(outputPortName)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Volume & Pan
            Section("Mix") {
                HStack {
                    Text("Volume")
                    Slider(value: $volumeValue, in: 0...2.0, step: 0.01)
                        .onChange(of: volumeValue) { _, newValue in
                            onSetVolume?(newValue)
                        }
                    Text(volumeDisplayString(volumeValue))
                        .font(.caption.monospacedDigit())
                        .frame(width: 45, alignment: .trailing)
                }
                HStack {
                    Text("Pan")
                    Slider(value: $panValue, in: -1.0...1.0, step: 0.01)
                        .onChange(of: panValue) { _, newValue in
                            onSetPan?(newValue)
                        }
                    Text(panDisplayString(panValue))
                        .font(.caption.monospacedDigit())
                        .frame(width: 35, alignment: .trailing)
                }
            }

            // Automation summary
            Section("Automation") {
                let laneCount = track.trackAutomationLanes.count
                if laneCount == 0 {
                    HStack {
                        Image(systemName: "waveform.path")
                            .foregroundStyle(.secondary)
                        Text("No track automation")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                } else {
                    ForEach(track.trackAutomationLanes) { lane in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 6, height: 6)
                            Text(laneLabel(lane))
                                .font(.callout)
                            Spacer()
                            Text("\(lane.breakpoints.count) pt\(lane.breakpoints.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadFromTrack() }
    }

    // MARK: - Effects Summary

    @ViewBuilder
    private var effectsSummary: some View {
        let sortedEffects = track.insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        if sortedEffects.isEmpty {
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
                Text("No effects")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        } else {
            ForEach(sortedEffects) { effect in
                HStack(spacing: 6) {
                    Circle()
                        .fill(effect.isBypassed ? Color.gray : Color.green)
                        .frame(width: 6, height: 6)
                    Text(effect.displayName)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        PluginWindowManager.shared.open(
                            component: effect.component,
                            displayName: effect.displayName,
                            presetData: effect.presetData,
                            onPresetChanged: nil
                        )
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Open plugin UI")
                    Button(effect.isBypassed ? "Bypassed" : "Active") {
                        onToggleEffectBypass?(effect.id)
                    }
                    .font(.caption)
                    .foregroundStyle(effect.isBypassed ? .secondary : .primary)
                    .buttonStyle(.plain)
                    Button(role: .destructive) {
                        onRemoveEffect?(effect.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            if track.isEffectChainBypassed {
                Text("Chain bypassed")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Toggle("Bypass All Effects", isOn: Binding(
                get: { track.isEffectChainBypassed },
                set: { _ in onToggleChainBypass?() }
            ))
        }
    }

    // MARK: - Helpers

    private func loadFromTrack() {
        editingName = track.name
        volumeValue = track.volume
        panValue = track.pan
        let discovery = AudioUnitDiscovery()
        Task.detached {
            let effects = discovery.effects()
            await MainActor.run {
                availableEffects = effects
            }
        }
    }

    private func laneLabel(_ lane: AutomationLane) -> String {
        if lane.targetPath.isTrackVolume { return "Volume" }
        if lane.targetPath.isTrackPan { return "Pan" }
        return "FX\(lane.targetPath.effectIndex)"
    }

    private func volumeDisplayString(_ vol: Float) -> String {
        if vol <= 0.001 { return "-inf" }
        let db = 20.0 * log10(Double(vol))
        return String(format: "%.1f", db)
    }

    private func panDisplayString(_ pan: Float) -> String {
        if abs(pan) < 0.01 { return "C" }
        if pan < 0 { return String(format: "L%.0f", abs(pan) * 100) }
        return String(format: "R%.0f", pan * 100)
    }
}
