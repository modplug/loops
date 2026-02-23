import SwiftUI
import AVFoundation
import LoopsCore
import LoopsEngine

/// Inspector panel with inline editing for all container properties.
public struct ContainerInspector: View {
    let container: Container
    let trackKind: TrackKind
    let containerTrack: Track
    let allContainers: [Container]
    let allTracks: [Track]
    let bpm: Double
    let beatsPerBar: Int
    var onUpdateLoopSettings: ((LoopSettings) -> Void)?
    var onUpdateName: ((String) -> Void)?
    var onAddEffect: ((InsertEffect) -> Void)?
    var onRemoveEffect: ((ID<InsertEffect>) -> Void)?
    var onToggleEffectBypass: ((ID<InsertEffect>) -> Void)?
    var onToggleChainBypass: (() -> Void)?
    var onReorderEffects: ((IndexSet, Int) -> Void)?
    var onSetInstrumentOverride: ((AudioComponentInfo?) -> Void)?
    var onSetEnterFade: ((FadeSettings?) -> Void)?
    var onSetExitFade: ((FadeSettings?) -> Void)?
    var onAddEnterAction: ((ContainerAction) -> Void)?
    var onRemoveEnterAction: ((ID<ContainerAction>) -> Void)?
    var onAddExitAction: ((ContainerAction) -> Void)?
    var onRemoveExitAction: ((ID<ContainerAction>) -> Void)?
    var onAddAutomationLane: ((AutomationLane) -> Void)?
    var onRemoveAutomationLane: ((ID<AutomationLane>) -> Void)?
    var onAddBreakpoint: ((ID<AutomationLane>, AutomationBreakpoint) -> Void)?
    var onRemoveBreakpoint: ((ID<AutomationLane>, ID<AutomationBreakpoint>) -> Void)?
    var onUpdateBreakpoint: ((ID<AutomationLane>, AutomationBreakpoint) -> Void)?
    var onUpdateEffectPreset: ((ID<InsertEffect>, Data?) -> Void)?
    /// Returns the engine's live AVAudioUnit for a container effect at the given index, if available.
    var liveEffectUnit: ((Int) -> AVAudioUnit?)?
    var onNavigateToParent: (() -> Void)?
    var onResetField: ((ContainerField) -> Void)?
    let parentContainer: Container?
    var isMIDIActive: Bool
    var playheadBar: Double

    @Binding var showDetailEditor: Bool

    @State private var editingName: String = ""
    @State private var selectedBoundaryMode: BoundaryMode = .hardCut
    @State private var loopCountMode: LoopCountMode = .fill
    @State private var loopCountValue: Int = 1
    @State private var crossfadeDuration: Double = 10.0

    // Fade state
    @State private var enterFadeEnabled: Bool = false
    @State private var enterFadeDuration: Double = 1.0
    @State private var enterFadeCurve: CurveType = .linear
    @State private var exitFadeEnabled: Bool = false
    @State private var exitFadeDuration: Double = 1.0
    @State private var exitFadeCurve: CurveType = .linear

    // Effect browser state
    @State private var availableEffects: [AudioUnitInfo] = []
    @State private var availableInstruments: [AudioUnitInfo] = []

    // Automation/parameter picker state
    @State private var pendingAutomationLane: PendingEffectSelection?
    @State private var pendingParameterAction: PendingEffectSelection?
    @State private var pendingParameterActionCallback: ((EffectPath) -> Void)?

    enum LoopCountMode: String, CaseIterable {
        case fill = "Fill"
        case count = "Count"
    }

    public init(
        container: Container,
        trackKind: TrackKind = .audio,
        containerTrack: Track = Track(name: "", kind: .audio),
        allContainers: [Container] = [],
        allTracks: [Track] = [],
        bpm: Double = 120.0,
        beatsPerBar: Int = 4,
        showDetailEditor: Binding<Bool>,
        onUpdateLoopSettings: ((LoopSettings) -> Void)? = nil,
        onUpdateName: ((String) -> Void)? = nil,
        onAddEffect: ((InsertEffect) -> Void)? = nil,
        onRemoveEffect: ((ID<InsertEffect>) -> Void)? = nil,
        onToggleEffectBypass: ((ID<InsertEffect>) -> Void)? = nil,
        onToggleChainBypass: (() -> Void)? = nil,
        onReorderEffects: ((IndexSet, Int) -> Void)? = nil,
        onSetInstrumentOverride: ((AudioComponentInfo?) -> Void)? = nil,
        onSetEnterFade: ((FadeSettings?) -> Void)? = nil,
        onSetExitFade: ((FadeSettings?) -> Void)? = nil,
        onAddEnterAction: ((ContainerAction) -> Void)? = nil,
        onRemoveEnterAction: ((ID<ContainerAction>) -> Void)? = nil,
        onAddExitAction: ((ContainerAction) -> Void)? = nil,
        onRemoveExitAction: ((ID<ContainerAction>) -> Void)? = nil,
        onAddAutomationLane: ((AutomationLane) -> Void)? = nil,
        onRemoveAutomationLane: ((ID<AutomationLane>) -> Void)? = nil,
        onAddBreakpoint: ((ID<AutomationLane>, AutomationBreakpoint) -> Void)? = nil,
        onRemoveBreakpoint: ((ID<AutomationLane>, ID<AutomationBreakpoint>) -> Void)? = nil,
        onUpdateBreakpoint: ((ID<AutomationLane>, AutomationBreakpoint) -> Void)? = nil,
        onUpdateEffectPreset: ((ID<InsertEffect>, Data?) -> Void)? = nil,
        liveEffectUnit: ((Int) -> AVAudioUnit?)? = nil,
        onNavigateToParent: (() -> Void)? = nil,
        onResetField: ((ContainerField) -> Void)? = nil,
        parentContainer: Container? = nil,
        isMIDIActive: Bool = false,
        playheadBar: Double = 1.0
    ) {
        self.container = container
        self.trackKind = trackKind
        self.containerTrack = containerTrack
        self.allContainers = allContainers
        self.allTracks = allTracks
        self.bpm = bpm
        self.beatsPerBar = beatsPerBar
        self._showDetailEditor = showDetailEditor
        self.onUpdateLoopSettings = onUpdateLoopSettings
        self.onUpdateName = onUpdateName
        self.onAddEffect = onAddEffect
        self.onRemoveEffect = onRemoveEffect
        self.onToggleEffectBypass = onToggleEffectBypass
        self.onToggleChainBypass = onToggleChainBypass
        self.onReorderEffects = onReorderEffects
        self.onSetInstrumentOverride = onSetInstrumentOverride
        self.onSetEnterFade = onSetEnterFade
        self.onSetExitFade = onSetExitFade
        self.onAddEnterAction = onAddEnterAction
        self.onRemoveEnterAction = onRemoveEnterAction
        self.onAddExitAction = onAddExitAction
        self.onRemoveExitAction = onRemoveExitAction
        self.onAddAutomationLane = onAddAutomationLane
        self.onRemoveAutomationLane = onRemoveAutomationLane
        self.onAddBreakpoint = onAddBreakpoint
        self.onRemoveBreakpoint = onRemoveBreakpoint
        self.onUpdateBreakpoint = onUpdateBreakpoint
        self.onUpdateEffectPreset = onUpdateEffectPreset
        self.liveEffectUnit = liveEffectUnit
        self.onNavigateToParent = onNavigateToParent
        self.onResetField = onResetField
        self.parentContainer = parentContainer
        self.isMIDIActive = isMIDIActive
        self.playheadBar = playheadBar
    }

    public var body: some View {
        Form {
            // Linked clone info (shown only for clones)
            if container.isClone {
                LinkedClipInspectorView(
                    container: container,
                    parentContainer: parentContainer,
                    onNavigateToParent: onNavigateToParent,
                    onResetField: onResetField
                )
            }

            // Container info
            Section("Container") {
                HStack {
                    TextField("Name", text: $editingName)
                        .onSubmit { onUpdateName?(editingName) }

                    if isFieldInherited(.name) { inheritedBadge() }

                    if showMIDIBadge {
                        Text("MIDI")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green))
                    }
                }

                LabeledContent("Position") {
                    Text("Bar \(container.startBar) — \(container.endBar)")
                }
                LabeledContent("Time") {
                    let startTime = WallTimeConverter.formattedTime(
                        forBar: Double(container.startBar),
                        bpm: bpm,
                        beatsPerBar: beatsPerBar
                    )
                    let endTime = WallTimeConverter.formattedTime(
                        forBar: Double(container.endBar),
                        bpm: bpm,
                        beatsPerBar: beatsPerBar
                    )
                    Text("\(startTime) — \(endTime)")
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Length") {
                    Text("\(container.lengthBars) bar\(container.lengthBars == 1 ? "" : "s")")
                }

                if container.sourceRecordingID != nil {
                    LabeledContent("Recording") {
                        Text("Recorded")
                            .foregroundStyle(.green)
                    }
                } else {
                    LabeledContent("Recording") {
                        Text("Empty")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Inline effects editing
            Section {
                effectsEditor
            } header: {
                HStack {
                    Text("Effects")
                    if isFieldInherited(.effects) { inheritedBadge() }
                }
            }

            // Inline actions editing
            Section {
                actionListEditor(
                    actions: container.onEnterActions,
                    onAdd: onAddEnterAction,
                    onRemove: onRemoveEnterAction
                )
            } header: {
                HStack {
                    Text("Enter Actions")
                    if isFieldInherited(.enterActions) { inheritedBadge() }
                }
            }

            Section {
                actionListEditor(
                    actions: container.onExitActions,
                    onAdd: onAddExitAction,
                    onRemove: onRemoveExitAction
                )
            } header: {
                HStack {
                    Text("Exit Actions")
                    if isFieldInherited(.exitActions) { inheritedBadge() }
                }
            }

            // Inline fades editing
            Section {
                enterFadeEditor
            } header: {
                HStack {
                    Text("Enter Fade")
                    if isFieldInherited(.fades) { inheritedBadge() }
                }
            }

            Section {
                exitFadeEditor
            } header: {
                HStack {
                    Text("Exit Fade")
                    if isFieldInherited(.fades) { inheritedBadge() }
                }
            }

            // Inline automation editing
            Section {
                automationEditor
            } header: {
                HStack {
                    Text("Automation")
                    if isFieldInherited(.automation) { inheritedBadge() }
                }
            }

            // Full detail editor button
            Section {
                Button {
                    showDetailEditor = true
                } label: {
                    Label("Open Detail Editor", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            // Loop settings
            Section {
                Picker("Loop Mode", selection: $loopCountMode) {
                    ForEach(LoopCountMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .onChange(of: loopCountMode) { _, _ in commitLoopSettings() }

                if loopCountMode == .count {
                    Stepper("Repeats: \(loopCountValue)", value: $loopCountValue, in: 1...99)
                        .onChange(of: loopCountValue) { _, _ in commitLoopSettings() }
                }
            } header: {
                HStack {
                    Text("Loop Settings")
                    if isFieldInherited(.loopSettings) { inheritedBadge() }
                }
            }

            Section {
                Picker("Mode", selection: $selectedBoundaryMode) {
                    ForEach(BoundaryMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .onChange(of: selectedBoundaryMode) { _, _ in commitLoopSettings() }

                if selectedBoundaryMode == .crossfade {
                    HStack {
                        Text("Duration")
                        Slider(value: $crossfadeDuration, in: 1...500, step: 1)
                        Text("\(Int(crossfadeDuration)) ms")
                            .frame(width: 50, alignment: .trailing)
                    }
                    .onChange(of: crossfadeDuration) { _, _ in commitLoopSettings() }
                }

                Text(selectedBoundaryMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                HStack {
                    Text("Boundary Mode")
                    if isFieldInherited(.loopSettings) { inheritedBadge() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadFromContainer() }
        .task {
            let discovery = AudioUnitDiscovery()
            let effects = await Task.detached { discovery.effects() }.value
            let instruments = trackKind == .midi
                ? await Task.detached { discovery.instruments() }.value
                : []
            availableEffects = effects
            availableInstruments = instruments
        }
        .sheet(item: $pendingAutomationLane) { pending in
            ParameterPickerView(
                pending: pending,
                onPick: { path in
                    onAddAutomationLane?(AutomationLane(targetPath: path))
                    pendingAutomationLane = nil
                },
                onCancel: { pendingAutomationLane = nil }
            )
        }
        .sheet(item: $pendingParameterAction) { pending in
            ParameterPickerView(
                pending: pending,
                onPick: { path in
                    pendingParameterActionCallback?(path)
                    pendingParameterAction = nil
                },
                onCancel: { pendingParameterAction = nil }
            )
        }
    }

    // MARK: - Inline Effects Editor

    private var effectsEditor: some View {
        Group {
            let sortedEffects = container.insertEffects.sorted { $0.orderIndex < $1.orderIndex }
            if sortedEffects.isEmpty {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                    Text("No effects")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            } else {
                ForEach(Array(sortedEffects.enumerated()), id: \.element.id) { index, effect in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        Circle()
                            .fill(effect.isBypassed ? Color.gray : Color.green)
                            .frame(width: 8, height: 8)
                        Text(effect.displayName)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            PluginWindowManager.shared.open(
                                component: effect.component,
                                displayName: effect.displayName,
                                presetData: effect.presetData,
                                liveAudioUnit: liveEffectUnit?(index),
                                onPresetChanged: { data in
                                    onUpdateEffectPreset?(effect.id, data)
                                }
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
                .onMove { from, to in
                    onReorderEffects?(from, to)
                }

                Toggle("Bypass All Effects", isOn: Binding(
                    get: { container.isEffectChainBypassed },
                    set: { _ in onToggleChainBypass?() }
                ))
            }

            if !availableEffects.isEmpty {
                effectBrowser
            }

            if trackKind == .midi {
                instrumentOverrideEditor
            }
        }
    }

    private var effectBrowser: some View {
        let grouped = Dictionary(grouping: availableEffects) { $0.manufacturerName }
        let manufacturers = grouped.keys.sorted()
        return Group {
            Menu("Add Effect") {
                ForEach(manufacturers, id: \.self) { manufacturer in
                    Menu(manufacturer) {
                        ForEach(grouped[manufacturer] ?? []) { effect in
                            Button(effect.name) {
                                let insert = InsertEffect(
                                    component: effect.componentInfo,
                                    displayName: effect.name,
                                    orderIndex: container.insertEffects.count
                                )
                                onAddEffect?(insert)
                            }
                        }
                    }
                }
            }
            .font(.callout)
        }
    }

    private var instrumentOverrideEditor: some View {
        Group {
            if let override = container.instrumentOverride {
                let name = availableInstruments.first(where: { $0.componentInfo == override })?.name ?? "Unknown AU"
                HStack {
                    Image(systemName: "pianokeys")
                        .foregroundStyle(.blue)
                    Text(name)
                    Spacer()
                    Button {
                        PluginWindowManager.shared.open(
                            component: override,
                            displayName: name,
                            presetData: nil,
                            onPresetChanged: nil
                        )
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Open instrument UI")
                    Button(role: .destructive) {
                        onSetInstrumentOverride?(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Using track instrument")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Menu("Set Instrument") {
                ForEach(availableInstruments) { instrument in
                    Button(instrument.name) {
                        onSetInstrumentOverride?(instrument.componentInfo)
                    }
                }
            }
            .font(.callout)
        }
    }

    // MARK: - Inline Actions Editor

    @ViewBuilder
    private func actionListEditor(
        actions: [ContainerAction],
        onAdd: ((ContainerAction) -> Void)?,
        onRemove: ((ID<ContainerAction>) -> Void)?
    ) -> some View {
        if actions.isEmpty {
            Text("No actions")
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            ForEach(actions) { action in
                HStack {
                    actionRowView(action: action)
                    Spacer()
                    Button(role: .destructive) {
                        onRemove?(action.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        addMIDIActionMenu(onAdd: onAdd)
        if !triggerTargets.isEmpty {
            addTriggerActionMenu(onAdd: onAdd)
        }
        if !parameterTargets.isEmpty {
            addParameterActionMenu(onAdd: onAdd)
        }
    }

    @ViewBuilder
    private func actionRowView(action: ContainerAction) -> some View {
        switch action {
        case .sendMIDI(_, let message, let destination):
            Image(systemName: "music.note")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.summary)
                Text(destination.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .triggerContainer(_, let targetID, let triggerAction):
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(triggerAction.summary)
                Text(containerName(for: targetID))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .setParameter(_, let target, let value):
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set param \(target.parameterAddress) → \(value, specifier: "%.2f")")
                Text(parameterTargetDescription(target))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Action Menu Helpers

    /// Shows MIDI badge when track has MIDI activity AND playhead is within this container's bar range.
    private var showMIDIBadge: Bool {
        guard trackKind == .midi, isMIDIActive else { return false }
        let bar = Int(playheadBar)
        return bar >= container.startBar && bar < container.endBar
    }

    private var triggerTargets: [Container] {
        allContainers.filter { $0.id != container.id }
    }

    private var parameterTargets: [ParameterTarget] {
        allTracks.compactMap { track in
            let containersWithEffects = track.containers.filter { !$0.insertEffects.isEmpty }
            let hasEffects = !track.insertEffects.isEmpty || !containersWithEffects.isEmpty
            guard hasEffects else { return nil }
            return ParameterTarget(track: track, containers: containersWithEffects)
        }
    }

    private var automationTargets: [ParameterTarget] {
        let containersWithEffects = containerTrack.containers.filter { !$0.insertEffects.isEmpty }
        let hasEffects = !containerTrack.insertEffects.isEmpty || !containersWithEffects.isEmpty
        guard hasEffects else { return [] }
        return [ParameterTarget(track: containerTrack, containers: containersWithEffects)]
    }

    private struct ParameterTarget {
        let track: Track
        let containers: [Container]
    }

    private func containerName(for targetID: ID<Container>) -> String {
        allContainers.first(where: { $0.id == targetID })?.name ?? "Unknown"
    }

    private func parameterTargetDescription(_ path: EffectPath) -> String {
        let trackName = allTracks.first(where: { $0.id == path.trackID })?.name ?? "Unknown Track"
        if let containerID = path.containerID {
            let cName = allContainers.first(where: { $0.id == containerID })?.name ?? "Unknown"
            return "\(trackName) → \(cName) [FX \(path.effectIndex)]"
        } else {
            return "\(trackName) [Track FX \(path.effectIndex)]"
        }
    }

    private func addMIDIActionMenu(onAdd: ((ContainerAction) -> Void)?) -> some View {
        Menu("Add MIDI Action") {
            Menu("Program Change") {
                ForEach(Array(stride(from: 0, to: 128, by: 1)), id: \.self) { program in
                    Button("PC \(program)") {
                        let action = ContainerAction.makeSendMIDI(
                            message: .programChange(channel: 0, program: UInt8(program)),
                            destination: .externalPort(name: "MIDI Out")
                        )
                        onAdd?(action)
                    }
                }
            }
            Menu("Control Change") {
                ForEach([0, 1, 7, 10, 11, 64, 91, 93], id: \.self) { cc in
                    Button("CC \(cc) = 127") {
                        let action = ContainerAction.makeSendMIDI(
                            message: .controlChange(channel: 0, controller: UInt8(cc), value: 127),
                            destination: .externalPort(name: "MIDI Out")
                        )
                        onAdd?(action)
                    }
                }
            }
            Menu("Note On") {
                ForEach([36, 48, 60, 72, 84], id: \.self) { note in
                    Button("Note \(note) vel 127") {
                        let action = ContainerAction.makeSendMIDI(
                            message: .noteOn(channel: 0, note: UInt8(note), velocity: 127),
                            destination: .externalPort(name: "MIDI Out")
                        )
                        onAdd?(action)
                    }
                }
            }
            Menu("Note Off") {
                ForEach([36, 48, 60, 72, 84], id: \.self) { note in
                    Button("Note Off \(note)") {
                        let action = ContainerAction.makeSendMIDI(
                            message: .noteOff(channel: 0, note: UInt8(note), velocity: 0),
                            destination: .externalPort(name: "MIDI Out")
                        )
                        onAdd?(action)
                    }
                }
            }
        }
        .font(.callout)
    }

    private func addTriggerActionMenu(onAdd: ((ContainerAction) -> Void)?) -> some View {
        Menu("Add Trigger Action") {
            ForEach(triggerTargets) { target in
                Menu(target.name) {
                    Button("Start") {
                        onAdd?(.makeTriggerContainer(targetID: target.id, action: .start))
                    }
                    Button("Stop") {
                        onAdd?(.makeTriggerContainer(targetID: target.id, action: .stop))
                    }
                    Button("Arm Record") {
                        onAdd?(.makeTriggerContainer(targetID: target.id, action: .armRecord))
                    }
                    Button("Disarm Record") {
                        onAdd?(.makeTriggerContainer(targetID: target.id, action: .disarmRecord))
                    }
                }
            }
        }
        .font(.callout)
    }

    private func addParameterActionMenu(onAdd: ((ContainerAction) -> Void)?) -> some View {
        Menu("Add Parameter Action") {
            ForEach(parameterTargets, id: \.track.id) { target in
                Menu(target.track.name) {
                    if !target.track.insertEffects.isEmpty {
                        Menu("Track Effects") {
                            ForEach(Array(target.track.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }).enumerated()), id: \.element.id) { index, effect in
                                Button(effect.displayName) {
                                    pendingParameterActionCallback = { path in
                                        onAdd?(.makeSetParameter(target: path, value: 0.5))
                                    }
                                    pendingParameterAction = PendingEffectSelection(
                                        trackID: target.track.id,
                                        containerID: nil,
                                        effectIndex: index,
                                        component: effect.component,
                                        effectName: effect.displayName
                                    )
                                }
                            }
                        }
                    }
                    ForEach(target.containers, id: \.id) { cont in
                        if !cont.insertEffects.isEmpty {
                            Menu(cont.name) {
                                ForEach(Array(cont.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }).enumerated()), id: \.element.id) { index, effect in
                                    Button(effect.displayName) {
                                        pendingParameterActionCallback = { path in
                                            onAdd?(.makeSetParameter(target: path, value: 0.5))
                                        }
                                        pendingParameterAction = PendingEffectSelection(
                                            trackID: target.track.id,
                                            containerID: cont.id,
                                            effectIndex: index,
                                            component: effect.component,
                                            effectName: effect.displayName
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .font(.callout)
    }

    // MARK: - Inline Fades Editor

    private var enterFadeEditor: some View {
        Group {
            Toggle("Enable Fade In", isOn: $enterFadeEnabled)
                .onChange(of: enterFadeEnabled) { _, enabled in
                    commitEnterFade(enabled: enabled)
                }

            if enterFadeEnabled {
                HStack {
                    Text("Duration")
                    Slider(value: $enterFadeDuration, in: 0.25...16.0, step: 0.25)
                    Text("\(enterFadeDuration, specifier: "%.2g") bar\(enterFadeDuration == 1 ? "" : "s")")
                        .frame(width: 60, alignment: .trailing)
                        .font(.callout)
                }
                .onChange(of: enterFadeDuration) { _, _ in commitEnterFade(enabled: true) }

                Picker("Curve", selection: $enterFadeCurve) {
                    ForEach(CurveType.allCases, id: \.self) { curve in
                        Text(curve.displayName).tag(curve)
                    }
                }
                .onChange(of: enterFadeCurve) { _, _ in commitEnterFade(enabled: true) }

                FadeCurvePreview(curve: enterFadeCurve, isFadeIn: true)
                    .frame(height: 80)
                    .padding(.vertical, 4)
            }
        }
    }

    private var exitFadeEditor: some View {
        Group {
            Toggle("Enable Fade Out", isOn: $exitFadeEnabled)
                .onChange(of: exitFadeEnabled) { _, enabled in
                    commitExitFade(enabled: enabled)
                }

            if exitFadeEnabled {
                HStack {
                    Text("Duration")
                    Slider(value: $exitFadeDuration, in: 0.25...16.0, step: 0.25)
                    Text("\(exitFadeDuration, specifier: "%.2g") bar\(exitFadeDuration == 1 ? "" : "s")")
                        .frame(width: 60, alignment: .trailing)
                        .font(.callout)
                }
                .onChange(of: exitFadeDuration) { _, _ in commitExitFade(enabled: true) }

                Picker("Curve", selection: $exitFadeCurve) {
                    ForEach(CurveType.allCases, id: \.self) { curve in
                        Text(curve.displayName).tag(curve)
                    }
                }
                .onChange(of: exitFadeCurve) { _, _ in commitExitFade(enabled: true) }

                FadeCurvePreview(curve: exitFadeCurve, isFadeIn: false)
                    .frame(height: 80)
                    .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Inline Automation Editor

    @ViewBuilder
    private var automationEditor: some View {
        if container.automationLanes.isEmpty {
            HStack {
                Image(systemName: "waveform.path")
                    .foregroundStyle(.secondary)
                Text("No automation lanes")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        } else {
            ForEach(container.automationLanes) { lane in
                DisclosureGroup {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        GridRow {
                            Text("Position")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text("Value")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text("Curve")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text("")
                        }
                        ForEach(lane.breakpoints.sorted(by: { $0.position < $1.position })) { bp in
                            GridRow {
                                Text("Bar \(bp.position, specifier: "%.1f")")
                                    .font(.callout)
                                Text("\(bp.value, specifier: "%.2f")")
                                    .font(.callout)
                                Text(bp.curve.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    onRemoveBreakpoint?(lane.id, bp.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button("Add Breakpoint") {
                        let nextPos: Double
                        if let last = lane.breakpoints.max(by: { $0.position < $1.position }) {
                            nextPos = last.position + 1.0
                        } else {
                            nextPos = 0.0
                        }
                        let bp = AutomationBreakpoint(
                            position: min(nextPos, Double(container.lengthBars)),
                            value: 0.5
                        )
                        onAddBreakpoint?(lane.id, bp)
                    }
                    .font(.callout)
                } label: {
                    HStack {
                        Image(systemName: "waveform.path")
                            .foregroundStyle(.cyan)
                        Text(parameterTargetDescription(lane.targetPath))
                        Spacer()
                        Text("\(lane.breakpoints.count) pt\(lane.breakpoints.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            onRemoveAutomationLane?(lane.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        if !automationTargets.isEmpty {
            Menu("Add Automation Lane") {
                ForEach(automationTargets, id: \.track.id) { target in
                    if !target.track.insertEffects.isEmpty {
                        Menu("Track Effects") {
                            ForEach(Array(target.track.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }).enumerated()), id: \.element.id) { index, effect in
                                Button(effect.displayName) {
                                    pendingAutomationLane = PendingEffectSelection(
                                        trackID: target.track.id,
                                        containerID: nil,
                                        effectIndex: index,
                                        component: effect.component,
                                        effectName: effect.displayName
                                    )
                                }
                            }
                        }
                    }
                    ForEach(target.containers, id: \.id) { cont in
                        if !cont.insertEffects.isEmpty {
                            Menu(cont.name) {
                                ForEach(Array(cont.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex }).enumerated()), id: \.element.id) { index, effect in
                                    Button(effect.displayName) {
                                        pendingAutomationLane = PendingEffectSelection(
                                            trackID: target.track.id,
                                            containerID: cont.id,
                                            effectIndex: index,
                                            component: effect.component,
                                            effectName: effect.displayName
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .font(.callout)
        }
    }

    // MARK: - Inherited Field Helpers

    private func isFieldInherited(_ field: ContainerField) -> Bool {
        container.isClone && !container.overriddenFields.contains(field)
    }

    @ViewBuilder
    private func inheritedBadge() -> some View {
        Label("Inherited", systemImage: "arrow.down.circle")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.1))
            )
    }

    // MARK: - State Management

    private func loadFromContainer() {
        editingName = container.name
        selectedBoundaryMode = container.loopSettings.boundaryMode
        crossfadeDuration = container.loopSettings.crossfadeDurationMs

        switch container.loopSettings.loopCount {
        case .fill:
            loopCountMode = .fill
        case .count(let n):
            loopCountMode = .count
            loopCountValue = n
        }

        loadFadeState()
    }

    private func commitLoopSettings() {
        let loopCount: LoopCount = loopCountMode == .fill ? .fill : .count(loopCountValue)
        let settings = LoopSettings(
            loopCount: loopCount,
            boundaryMode: selectedBoundaryMode,
            crossfadeDurationMs: crossfadeDuration
        )
        onUpdateLoopSettings?(settings)
    }

    private func loadFadeState() {
        if let fade = container.enterFade {
            enterFadeEnabled = true
            enterFadeDuration = fade.duration
            enterFadeCurve = fade.curve
        } else {
            enterFadeEnabled = false
        }
        if let fade = container.exitFade {
            exitFadeEnabled = true
            exitFadeDuration = fade.duration
            exitFadeCurve = fade.curve
        } else {
            exitFadeEnabled = false
        }
    }

    private func commitEnterFade(enabled: Bool) {
        if enabled {
            onSetEnterFade?(FadeSettings(duration: enterFadeDuration, curve: enterFadeCurve))
        } else {
            onSetEnterFade?(nil)
        }
    }

    private func commitExitFade(enabled: Bool) {
        if enabled {
            onSetExitFade?(FadeSettings(duration: exitFadeDuration, curve: exitFadeCurve))
        } else {
            onSetExitFade?(nil)
        }
    }
}

extension CurveType {
    public var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .exponential: return "Exponential"
        case .sCurve: return "S-Curve"
        }
    }
}

extension BoundaryMode {
    public var displayName: String {
        switch self {
        case .hardCut: return "Hard Cut"
        case .crossfade: return "Crossfade"
        case .overdub: return "Overdub"
        }
    }

    public var description: String {
        switch self {
        case .hardCut: return "Audio stops and restarts cleanly at loop boundaries."
        case .crossfade: return "Smooth crossfade between end of one pass and start of next."
        case .overdub: return "Each loop pass layers on top of previous passes."
        }
    }
}

extension MIDIActionMessage {
    var summary: String {
        switch self {
        case .programChange(let channel, let program):
            return "PC \(program) ch \(channel + 1)"
        case .controlChange(let channel, let controller, let value):
            return "CC \(controller) = \(value) ch \(channel + 1)"
        case .noteOn(let channel, let note, let velocity):
            return "Note On \(note) vel \(velocity) ch \(channel + 1)"
        case .noteOff(let channel, let note, _):
            return "Note Off \(note) ch \(channel + 1)"
        }
    }
}

extension MIDIDestination {
    var summary: String {
        switch self {
        case .externalPort(let name):
            return "→ \(name)"
        case .internalTrack(let trackID):
            return "→ Track \(trackID.rawValue.uuidString.prefix(8))"
        }
    }
}

extension TriggerAction {
    var summary: String {
        switch self {
        case .start: return "Start"
        case .stop: return "Stop"
        case .armRecord: return "Arm Record"
        case .disarmRecord: return "Disarm Record"
        }
    }
}
