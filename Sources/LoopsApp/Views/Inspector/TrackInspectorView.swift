import SwiftUI
import AVFoundation
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

    // MIDI Learn callbacks
    var onMIDILearn: ((EffectPath) -> Void)?
    var onRemoveMIDIMapping: ((EffectPath) -> Void)?

    // Expression pedal callbacks
    var onAssignExpressionPedal: ((UInt8, EffectPath?) -> Void)?
    var onRemoveExpressionPedal: (() -> Void)?

    // MIDI parameter mappings for highlighting learned parameters
    var midiParameterMappings: [MIDIParameterMapping] = []

    // Whether MIDI learn is currently active
    var isMIDILearning: Bool = false

    // Available ports and devices for interactive pickers
    var availableInputPorts: [InputPort] = []
    var availableOutputPorts: [OutputPort] = []
    var availableMIDIDevices: [MIDIInputDevice] = []

    /// Returns the engine's live AVAudioUnit for a track effect at the given index, if available.
    var liveTrackEffectUnit: ((Int) -> AVAudioUnit?)?

    @State private var editingName: String = ""
    @State private var availableEffects: [AudioUnitInfo] = []
    @State private var volumeValue: Float = 1.0
    @State private var panValue: Float = 0.0

    public var body: some View {
        Form {
            trackInfoSection
            effectsSection
            routingSection
            mixSection
            expressionPedalSection
            midiParameterMappingsSection
            automationSection
        }
        .formStyle(.grouped)
        .onAppear { loadFromTrack() }
    }

    // MARK: - Track Info Section

    @ViewBuilder
    private var trackInfoSection: some View {
        Section("Track") {
            TextField("Name", text: $editingName)
                .onSubmit { onRename?(editingName) }
            LabeledContent("Kind") {
                Text(track.kind.displayName)
            }
        }
    }

    // MARK: - Effects Section

    @ViewBuilder
    private var effectsSection: some View {
        Section("Effects") {
            effectsSummary
            effectsAddMenu
        }
    }

    @ViewBuilder
    private var effectsAddMenu: some View {
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

    // MARK: - Routing Section

    @ViewBuilder
    private var routingSection: some View {
        if track.kind == .audio || track.kind == .bus || track.kind == .backing {
            Section("I/O Routing") {
                inputPortPicker
                outputPortPicker
            }
        }

        if track.kind == .midi {
            Section("MIDI Routing") {
                midiDevicePicker
                midiChannelPicker
            }
        }

        if track.kind == .master {
            Section("Output") {
                outputPortPicker
            }
        }
    }

    @ViewBuilder
    private var inputPortPicker: some View {
        Menu {
            Button("Default") { onSetInputPort?(nil) }
            if !availableInputPorts.isEmpty { Divider() }
            ForEach(availableInputPorts) { port in
                Button(port.displayName) { onSetInputPort?(port.id) }
            }
        } label: {
            LabeledContent("Input") {
                Text(inputPortDisplayName)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var outputPortPicker: some View {
        Menu {
            Button("Default") { onSetOutputPort?(nil) }
            if !availableOutputPorts.isEmpty { Divider() }
            ForEach(availableOutputPorts) { port in
                Button(port.displayName) { onSetOutputPort?(port.id) }
            }
        } label: {
            LabeledContent("Output") {
                Text(outputPortDisplayName)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var midiDevicePicker: some View {
        Menu {
            Button("All Devices") {
                onSetMIDIInput?(nil, track.midiInputChannel)
            }
            if !availableMIDIDevices.isEmpty { Divider() }
            ForEach(availableMIDIDevices) { device in
                Button(device.displayName) {
                    onSetMIDIInput?(device.id, track.midiInputChannel)
                }
            }
        } label: {
            LabeledContent("Device") {
                Text(midiDeviceDisplayName)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var midiChannelPicker: some View {
        Menu {
            Button("Omni") {
                onSetMIDIInput?(track.midiInputDeviceID, nil)
            }
            Divider()
            ForEach(1...16, id: \.self) { ch in
                Button("Ch \(ch)") {
                    onSetMIDIInput?(track.midiInputDeviceID, UInt8(ch))
                }
            }
        } label: {
            LabeledContent("Channel") {
                Text(midiChannelDisplayName)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inputPortDisplayName: String {
        guard let portID = track.inputPortID else { return "Default" }
        return availableInputPorts.first { $0.id == portID }?.displayName ?? "Default"
    }

    private var outputPortDisplayName: String {
        guard let portID = track.outputPortID else { return "Default" }
        return availableOutputPorts.first { $0.id == portID }?.displayName ?? "Default"
    }

    private var midiDeviceDisplayName: String {
        guard let deviceID = track.midiInputDeviceID else { return "All Devices" }
        return availableMIDIDevices.first { $0.id == deviceID }?.displayName ?? deviceID
    }

    private var midiChannelDisplayName: String {
        guard let ch = track.midiInputChannel else { return "Omni" }
        return "Ch \(ch)"
    }

    // MARK: - Mix Section

    @ViewBuilder
    private var mixSection: some View {
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
            effectRows(sortedEffects)
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

    @ViewBuilder
    private func effectRows(_ sortedEffects: [InsertEffect]) -> some View {
        ForEach(Array(sortedEffects.enumerated()), id: \.element.id) { effectIndex, effect in
            effectRow(effect: effect, effectIndex: effectIndex)
        }
    }

    @ViewBuilder
    private func effectRow(effect: InsertEffect, effectIndex: Int) -> some View {
        let effectPath = EffectPath(trackID: track.id, effectIndex: effectIndex, parameterAddress: 0)
        let hasMIDIMapping = midiParameterMappings.contains { $0.targetPath.trackID == track.id && $0.targetPath.containerID == nil && $0.targetPath.effectIndex == effectIndex }
        HStack(spacing: 6) {
            Circle()
                .fill(effect.isBypassed ? Color.gray : Color.green)
                .frame(width: 6, height: 6)
            Text(effect.displayName)
                .font(.callout)
                .lineLimit(1)
            if hasMIDIMapping {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 6, height: 6)
                    .help("MIDI mapped")
            }
            Spacer()
            effectRowButtons(effect: effect, effectIndex: effectIndex)
        }
        .contextMenu {
            if hasMIDIMapping {
                Button("Remove MIDI Mapping") {
                    onRemoveMIDIMapping?(effectPath)
                }
            } else {
                Button(isMIDILearning ? "Waiting for MIDI..." : "MIDI Learn") {
                    onMIDILearn?(effectPath)
                }
                .disabled(isMIDILearning)
            }
        }
    }

    @ViewBuilder
    private func effectRowButtons(effect: InsertEffect, effectIndex: Int) -> some View {
        Button {
            PluginWindowManager.shared.open(
                component: effect.component,
                displayName: effect.displayName,
                presetData: effect.presetData,
                liveAudioUnit: liveTrackEffectUnit?(effectIndex),
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

    // MARK: - Expression Pedal Section

    @ViewBuilder
    private var expressionPedalSection: some View {
        Section("Expression Pedal") {
            if let cc = track.expressionPedalCC {
                let targetLabel = expressionPedalTargetLabel(track.expressionPedalTarget)
                HStack(spacing: 6) {
                    Image(systemName: "dial.low")
                        .foregroundStyle(.teal)
                    Text("CC #\(cc) → \(targetLabel)")
                        .font(.callout)
                    Spacer()
                    Button(role: .destructive) {
                        onRemoveExpressionPedal?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove Expression Pedal")
                }
            } else {
                HStack {
                    Image(systemName: "dial.low")
                        .foregroundStyle(.secondary)
                    Text("Not assigned")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            expressionPedalAssignMenu
        }
    }

    @ViewBuilder
    private var expressionPedalAssignMenu: some View {
        let commonCCs: [(String, UInt8)] = [
            ("CC #7 (Volume)", 7),
            ("CC #11 (Expression)", 11),
            ("CC #1 (Mod Wheel)", 1),
            ("CC #2 (Breath)", 2),
            ("CC #4 (Foot)", 4),
        ]
        Menu {
            Menu("Track Volume") {
                ForEach(commonCCs, id: \.1) { label, cc in
                    Button(label) {
                        onAssignExpressionPedal?(cc, nil)
                    }
                }
            }
            let sortedEffects = track.insertEffects.sorted { $0.orderIndex < $1.orderIndex }
            if !sortedEffects.isEmpty {
                ForEach(Array(sortedEffects.enumerated()), id: \.element.id) { effectIndex, effect in
                    Menu(effect.displayName) {
                        ForEach(commonCCs, id: \.1) { label, cc in
                            Button(label) {
                                let path = EffectPath(trackID: track.id, effectIndex: effectIndex, parameterAddress: 0)
                                onAssignExpressionPedal?(cc, path)
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Assign Expression Pedal", systemImage: "plus.circle")
        }
    }

    private func expressionPedalTargetLabel(_ target: EffectPath?) -> String {
        guard let target else { return "Volume" }
        if target.isTrackVolume { return "Volume" }
        if target.isTrackPan { return "Pan" }
        let sortedEffects = track.insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        if target.effectIndex >= 0, target.effectIndex < sortedEffects.count {
            return sortedEffects[target.effectIndex].displayName
        }
        return "FX\(target.effectIndex)"
    }

    // MARK: - MIDI Parameter Mappings Section

    @ViewBuilder
    private var midiParameterMappingsSection: some View {
        let trackMappings = midiParameterMappings.filter { $0.targetPath.trackID == track.id }
        Section("MIDI Mappings") {
            if trackMappings.isEmpty {
                HStack {
                    Image(systemName: "pianokeys")
                        .foregroundStyle(.secondary)
                    Text("No parameter mappings")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            } else {
                ForEach(trackMappings) { mapping in
                    midiMappingRow(mapping)
                }
            }
        }
    }

    @ViewBuilder
    private func midiMappingRow(_ mapping: MIDIParameterMapping) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.cyan)
                .frame(width: 6, height: 6)
            Text(mapping.trigger.displayString)
                .font(.callout)
            Text("→")
                .foregroundStyle(.secondary)
            Text(mappingTargetLabel(mapping.targetPath))
                .font(.callout)
            Spacer()
            Button(role: .destructive) {
                onRemoveMIDIMapping?(mapping.targetPath)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove mapping")
        }
    }

    private func mappingTargetLabel(_ path: EffectPath) -> String {
        if path.isTrackVolume { return "Volume" }
        if path.isTrackPan { return "Pan" }
        let sortedEffects = track.insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        if path.effectIndex >= 0, path.effectIndex < sortedEffects.count {
            return sortedEffects[path.effectIndex].displayName
        }
        return "FX\(path.effectIndex)"
    }

    // MARK: - Automation Section

    @ViewBuilder
    private var automationSection: some View {
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
