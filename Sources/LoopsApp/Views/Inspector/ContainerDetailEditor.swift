import SwiftUI
import AVFoundation
import LoopsCore
import LoopsEngine

/// Detail editor tab selection.
enum ContainerDetailTab: String, CaseIterable {
    case effects = "Effects"
    case actions = "Actions"
    case automation = "Automation"
    case fades = "Fades"
}

/// Full container configuration editor presented as a sheet with tabs.
struct ContainerDetailEditor: View {
    let container: Container
    let trackKind: TrackKind
    let containerTrack: Track
    let allContainers: [Container]
    let allTracks: [Track]

    // Effect callbacks
    var onAddEffect: ((InsertEffect) -> Void)?
    var onRemoveEffect: ((ID<InsertEffect>) -> Void)?
    var onToggleEffectBypass: ((ID<InsertEffect>) -> Void)?
    var onToggleChainBypass: (() -> Void)?
    var onReorderEffects: ((IndexSet, Int) -> Void)?
    var onSetInstrumentOverride: ((AudioComponentInfo?) -> Void)?

    // Action callbacks
    var onAddEnterAction: ((ContainerAction) -> Void)?
    var onRemoveEnterAction: ((ID<ContainerAction>) -> Void)?
    var onAddExitAction: ((ContainerAction) -> Void)?
    var onRemoveExitAction: ((ID<ContainerAction>) -> Void)?

    // Automation callbacks
    var onAddAutomationLane: ((AutomationLane) -> Void)?
    var onRemoveAutomationLane: ((ID<AutomationLane>) -> Void)?
    var onAddBreakpoint: ((ID<AutomationLane>, AutomationBreakpoint) -> Void)?
    var onRemoveBreakpoint: ((ID<AutomationLane>, ID<AutomationBreakpoint>) -> Void)?
    var onUpdateBreakpoint: ((ID<AutomationLane>, AutomationBreakpoint) -> Void)?

    // Fade callbacks
    var onSetEnterFade: ((FadeSettings?) -> Void)?
    var onSetExitFade: ((FadeSettings?) -> Void)?

    // Preset callback
    var onUpdateEffectPreset: ((ID<InsertEffect>, Data?) -> Void)?
    /// Returns the engine's live AVAudioUnit for a container effect at the given index, if available.
    var liveEffectUnit: ((Int) -> AVAudioUnit?)?
    /// Whether this container's effect chain failed to connect in the engine.
    var isEffectChainFailed: Bool = false

    var onDismiss: (() -> Void)?

    @State private var selectedTab: ContainerDetailTab = .effects
    @State private var availableEffects: [AudioUnitInfo] = []
    @State private var availableInstruments: [AudioUnitInfo] = []
    @State private var pendingAutomationLane: PendingEffectSelection?
    @State private var pendingParameterAction: PendingEffectSelection?
    @State private var enterFadeEnabled: Bool = false
    @State private var enterFadeDuration: Double = 1.0
    @State private var enterFadeCurve: CurveType = .linear
    @State private var exitFadeEnabled: Bool = false
    @State private var exitFadeDuration: Double = 1.0
    @State private var exitFadeCurve: CurveType = .linear

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit: \(container.name)")
                    .font(.headline)
                Spacer()
                Button("Done") { onDismiss?() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(ContainerDetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Tab content
            switch selectedTab {
            case .effects:
                effectsTab
            case .actions:
                actionsTab
            case .automation:
                automationTab
            case .fades:
                fadesTab
            }
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 400, idealHeight: 500)
        .onAppear {
            loadFadeState()
        }
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
                onPick: { path, paramInfo in
                    var lane = AutomationLane(targetPath: path)
                    lane.effectName = pending.effectName
                    lane.parameterName = paramInfo.displayName
                    lane.parameterMin = paramInfo.minValue
                    lane.parameterMax = paramInfo.maxValue
                    lane.parameterUnit = paramInfo.unit
                    onAddAutomationLane?(lane)
                    pendingAutomationLane = nil
                },
                onCancel: { pendingAutomationLane = nil }
            )
        }
        .sheet(item: $pendingParameterAction) { pending in
            ParameterPickerView(
                pending: pending,
                onPick: { path, _ in
                    pendingParameterActionCallback?(path)
                    pendingParameterAction = nil
                },
                onCancel: { pendingParameterAction = nil }
            )
        }
    }

    /// Stores the callback for the pending parameter action pick.
    @State private var pendingParameterActionCallback: ((EffectPath) -> Void)?

    // MARK: - Effects Tab

    private var effectsTab: some View {
        Form {
            Section("Insert Effects") {
                let sortedEffects = container.insertEffects.sorted { $0.orderIndex < $1.orderIndex }
                if sortedEffects.isEmpty {
                    Text("No effects — use the button below to add one")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(Array(sortedEffects.enumerated()), id: \.element.id) { index, effect in
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                            Button {
                                onToggleEffectBypass?(effect.id)
                            } label: {
                                Circle()
                                    .fill(effect.isBypassed ? Color.gray : (isEffectChainFailed ? Color.red : Color.green))
                                    .frame(width: 8, height: 8)
                            }
                            .buttonStyle(.plain)
                            .help(effect.isBypassed ? "Enable effect" : "Bypass effect")
                            Text(effect.displayName)
                                .foregroundStyle(effect.isBypassed ? .secondary : .primary)
                            Spacer()
                            Button {
                                let activeIndex = sortedEffects[0..<index].filter { !$0.isBypassed }.count
                                let liveAU = effect.isBypassed ? nil : liveEffectUnit?(activeIndex)
                                PluginWindowManager.shared.open(
                                    component: effect.component,
                                    displayName: effect.displayName,
                                    presetData: effect.presetData,
                                    liveAudioUnit: liveAU,
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
                            Button(role: .destructive) {
                                onRemoveEffect?(effect.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .draggable(effect.id.rawValue.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let draggedID = items.first.flatMap(UUID.init).map({ ID<InsertEffect>(rawValue: $0) }),
                                  let fromIndex = sortedEffects.firstIndex(where: { $0.id == draggedID }) else { return false }
                            if fromIndex != index {
                                onReorderEffects?(IndexSet(integer: fromIndex), index > fromIndex ? index + 1 : index)
                            }
                            return true
                        }
                    }

                    Toggle("Bypass All Effects", isOn: Binding(
                        get: { container.isEffectChainBypassed },
                        set: { _ in onToggleChainBypass?() }
                    ))
                }
            }

            Section("Add Effect") {
                if availableEffects.isEmpty {
                    Text("No Audio Unit effects available")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    effectBrowser
                }
            }

            if trackKind == .midi {
                Section("Instrument Override") {
                    instrumentOverrideView
                }
            }
        }
        .formStyle(.grouped)
    }

    private var effectBrowser: some View {
        let grouped = Dictionary(grouping: availableEffects) { $0.manufacturerName }
        let manufacturers = grouped.keys.sorted()
        return ForEach(manufacturers, id: \.self) { manufacturer in
            DisclosureGroup(manufacturer) {
                ForEach(grouped[manufacturer] ?? []) { effect in
                    Button {
                        let insert = InsertEffect(
                            component: effect.componentInfo,
                            displayName: effect.name,
                            orderIndex: container.insertEffects.count
                        )
                        onAddEffect?(insert)
                    } label: {
                        Text(effect.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var instrumentOverrideView: some View {
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

    // MARK: - Actions Tab

    private var actionsTab: some View {
        Form {
            Section("Enter Actions") {
                actionListView(
                    actions: container.onEnterActions,
                    onAdd: onAddEnterAction,
                    onRemove: onRemoveEnterAction
                )
            }

            Section("Exit Actions") {
                actionListView(
                    actions: container.onExitActions,
                    onAdd: onAddExitAction,
                    onRemove: onRemoveExitAction
                )
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Automation Tab

    private var automationTab: some View {
        Form {
            Section("Automation Lanes") {
                automationLanesView
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Fades Tab

    private var fadesTab: some View {
        Form {
            Section("Enter Fade") {
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

            Section("Exit Fade") {
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
        .formStyle(.grouped)
    }

    // MARK: - Shared Action Views

    private var triggerTargets: [Container] {
        allContainers.filter { $0.id != container.id }
    }

    private struct ParameterTarget {
        let track: Track
        let containers: [Container]
    }

    /// All tracks with effects — used for cross-track parameter actions (enter/exit).
    private var parameterTargets: [ParameterTarget] {
        allTracks.compactMap { track in
            let containersWithEffects = track.containers.filter { !$0.insertEffects.isEmpty }
            let hasEffects = !track.insertEffects.isEmpty || !containersWithEffects.isEmpty
            guard hasEffects else { return nil }
            return ParameterTarget(track: track, containers: containersWithEffects)
        }
    }

    /// Only the container's own track — used for automation lanes (self-targeting only).
    private var automationTargets: [ParameterTarget] {
        let containersWithEffects = containerTrack.containers.filter { !$0.insertEffects.isEmpty }
        let hasEffects = !containerTrack.insertEffects.isEmpty || !containersWithEffects.isEmpty
        guard hasEffects else { return [] }
        return [ParameterTarget(track: containerTrack, containers: containersWithEffects)]
    }

    private func containerName(for targetID: ID<Container>) -> String {
        allContainers.first(where: { $0.id == targetID })?.name ?? "Unknown"
    }

    private func parameterTargetDescription(_ path: EffectPath, lane: AutomationLane? = nil) -> String {
        if let effectName = lane?.effectName, let paramName = lane?.parameterName {
            return "\(effectName) → \(paramName)"
        }
        let trackName = allTracks.first(where: { $0.id == path.trackID })?.name ?? "Unknown Track"
        if let containerID = path.containerID {
            let cName = allContainers.first(where: { $0.id == containerID })?.name ?? "Unknown"
            return "\(trackName) → \(cName) [FX \(path.effectIndex)]"
        } else {
            return "\(trackName) [Track FX \(path.effectIndex)]"
        }
    }

    @ViewBuilder
    private func actionListView(
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

    // MARK: - Automation Views

    @ViewBuilder
    private var automationLanesView: some View {
        if container.automationLanes.isEmpty {
            Text("No automation lanes — use the button below to add one")
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            ForEach(container.automationLanes) { lane in
                DisclosureGroup {
                    // Breakpoint table
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
                        Text(parameterTargetDescription(lane.targetPath, lane: lane))
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

    // MARK: - Fade Helpers

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

// MARK: - Fade Curve Preview

/// Visual preview of a fade curve.
struct FadeCurvePreview: View {
    let curve: CurveType
    let isFadeIn: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            Path { path in
                let steps = 100
                for i in 0...steps {
                    let t = Double(i) / Double(steps)
                    let gain = curve.gain(at: isFadeIn ? t : 1.0 - t)
                    let x = CGFloat(t) * width
                    let y = height - CGFloat(gain) * height
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.accentColor, lineWidth: 2)

            // Axis lines
            Path { path in
                path.move(to: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: width, y: height))
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: height))
            }
            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
