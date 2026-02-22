import SwiftUI
import LoopsCore
import LoopsEngine

/// Inspector panel for editing a selected container's loop settings.
public struct ContainerInspector: View {
    let container: Container
    let trackKind: TrackKind
    /// All containers in the current song, used for trigger target picking.
    let allContainers: [Container]
    var onUpdateLoopSettings: ((LoopSettings) -> Void)?
    var onUpdateName: ((String) -> Void)?
    var onAddEffect: ((InsertEffect) -> Void)?
    var onRemoveEffect: ((ID<InsertEffect>) -> Void)?
    var onToggleEffectBypass: ((ID<InsertEffect>) -> Void)?
    var onToggleChainBypass: (() -> Void)?
    var onSetInstrumentOverride: ((AudioComponentInfo?) -> Void)?
    var onSetEnterFade: ((FadeSettings?) -> Void)?
    var onSetExitFade: ((FadeSettings?) -> Void)?
    var onAddEnterAction: ((ContainerAction) -> Void)?
    var onRemoveEnterAction: ((ID<ContainerAction>) -> Void)?
    var onAddExitAction: ((ContainerAction) -> Void)?
    var onRemoveExitAction: ((ID<ContainerAction>) -> Void)?

    @State private var editingName: String = ""
    @State private var selectedBoundaryMode: BoundaryMode = .hardCut
    @State private var loopCountMode: LoopCountMode = .fill
    @State private var loopCountValue: Int = 1
    @State private var crossfadeDuration: Double = 10.0
    @State private var availableInstruments: [AudioUnitInfo] = []
    @State private var enterFadeEnabled: Bool = false
    @State private var enterFadeDuration: Double = 1.0
    @State private var enterFadeCurve: CurveType = .linear
    @State private var exitFadeEnabled: Bool = false
    @State private var exitFadeDuration: Double = 1.0
    @State private var exitFadeCurve: CurveType = .linear

    enum LoopCountMode: String, CaseIterable {
        case fill = "Fill"
        case count = "Count"
    }

    public init(
        container: Container,
        trackKind: TrackKind = .audio,
        allContainers: [Container] = [],
        onUpdateLoopSettings: ((LoopSettings) -> Void)? = nil,
        onUpdateName: ((String) -> Void)? = nil,
        onAddEffect: ((InsertEffect) -> Void)? = nil,
        onRemoveEffect: ((ID<InsertEffect>) -> Void)? = nil,
        onToggleEffectBypass: ((ID<InsertEffect>) -> Void)? = nil,
        onToggleChainBypass: (() -> Void)? = nil,
        onSetInstrumentOverride: ((AudioComponentInfo?) -> Void)? = nil,
        onSetEnterFade: ((FadeSettings?) -> Void)? = nil,
        onSetExitFade: ((FadeSettings?) -> Void)? = nil,
        onAddEnterAction: ((ContainerAction) -> Void)? = nil,
        onRemoveEnterAction: ((ID<ContainerAction>) -> Void)? = nil,
        onAddExitAction: ((ContainerAction) -> Void)? = nil,
        onRemoveExitAction: ((ID<ContainerAction>) -> Void)? = nil
    ) {
        self.container = container
        self.trackKind = trackKind
        self.allContainers = allContainers
        self.onUpdateLoopSettings = onUpdateLoopSettings
        self.onUpdateName = onUpdateName
        self.onAddEffect = onAddEffect
        self.onRemoveEffect = onRemoveEffect
        self.onToggleEffectBypass = onToggleEffectBypass
        self.onToggleChainBypass = onToggleChainBypass
        self.onSetInstrumentOverride = onSetInstrumentOverride
        self.onSetEnterFade = onSetEnterFade
        self.onSetExitFade = onSetExitFade
        self.onAddEnterAction = onAddEnterAction
        self.onRemoveEnterAction = onRemoveEnterAction
        self.onAddExitAction = onAddExitAction
        self.onRemoveExitAction = onRemoveExitAction
    }

    public var body: some View {
        Form {
            Section("Container") {
                TextField("Name", text: $editingName)
                    .onSubmit { onUpdateName?(editingName) }

                LabeledContent("Position") {
                    Text("Bar \(container.startBar) — \(container.endBar)")
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

            Section("Insert Effects") {
                if container.insertEffects.isEmpty {
                    Text("No effects")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(container.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex })) { effect in
                        HStack {
                            Circle()
                                .fill(effect.isBypassed ? Color.gray : Color.green)
                                .frame(width: 8, height: 8)
                            Text(effect.displayName)
                                .font(.callout)
                            Spacer()
                            Button {
                                onToggleEffectBypass?(effect.id)
                            } label: {
                                Text(effect.isBypassed ? "Off" : "On")
                                    .font(.caption)
                                    .foregroundStyle(effect.isBypassed ? .secondary : .primary)
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) {
                                onRemoveEffect?(effect.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    if !container.insertEffects.isEmpty {
                        Toggle("Bypass All", isOn: Binding(
                            get: { container.isEffectChainBypassed },
                            set: { _ in onToggleChainBypass?() }
                        ))
                        .font(.caption)
                    }
                    Spacer()
                    LabeledContent("Effects") {
                        Text("\(container.insertEffects.count)")
                    }
                    .font(.caption)
                }
            }

            if trackKind == .midi {
                Section("Instrument Override") {
                    if let override = container.instrumentOverride {
                        let name = availableInstruments.first(where: { $0.componentInfo == override })?.name ?? "Unknown AU"
                        HStack {
                            Image(systemName: "pianokeys")
                                .foregroundStyle(.blue)
                            Text(name)
                                .font(.callout)
                            Spacer()
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
                            .font(.caption)
                    }
                    Menu("Set Instrument") {
                        ForEach(availableInstruments) { instrument in
                            Button(instrument.name) {
                                onSetInstrumentOverride?(instrument.componentInfo)
                            }
                        }
                    }
                    .font(.caption)
                }
            }

            Section("Loop Settings") {
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
            }

            Section("Boundary Mode") {
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
            }

            Section("Fades") {
                Toggle("Fade In", isOn: $enterFadeEnabled)
                    .onChange(of: enterFadeEnabled) { _, enabled in
                        commitEnterFade(enabled: enabled)
                    }

                if enterFadeEnabled {
                    HStack {
                        Text("Duration")
                        Slider(value: $enterFadeDuration, in: 0.25...16.0, step: 0.25)
                        Text("\(enterFadeDuration, specifier: "%.2g") bar\(enterFadeDuration == 1 ? "" : "s")")
                            .frame(width: 60, alignment: .trailing)
                            .font(.caption)
                    }
                    .onChange(of: enterFadeDuration) { _, _ in commitEnterFade(enabled: true) }

                    Picker("Curve", selection: $enterFadeCurve) {
                        ForEach(CurveType.allCases, id: \.self) { curve in
                            Text(curve.displayName).tag(curve)
                        }
                    }
                    .onChange(of: enterFadeCurve) { _, _ in commitEnterFade(enabled: true) }
                }

                Toggle("Fade Out", isOn: $exitFadeEnabled)
                    .onChange(of: exitFadeEnabled) { _, enabled in
                        commitExitFade(enabled: enabled)
                    }

                if exitFadeEnabled {
                    HStack {
                        Text("Duration")
                        Slider(value: $exitFadeDuration, in: 0.25...16.0, step: 0.25)
                        Text("\(exitFadeDuration, specifier: "%.2g") bar\(exitFadeDuration == 1 ? "" : "s")")
                            .frame(width: 60, alignment: .trailing)
                            .font(.caption)
                    }
                    .onChange(of: exitFadeDuration) { _, _ in commitExitFade(enabled: true) }

                    Picker("Curve", selection: $exitFadeCurve) {
                        ForEach(CurveType.allCases, id: \.self) { curve in
                            Text(curve.displayName).tag(curve)
                        }
                    }
                    .onChange(of: exitFadeCurve) { _, _ in commitExitFade(enabled: true) }
                }
            }

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
        .onAppear {
            loadFromContainer()
            if trackKind == .midi {
                availableInstruments = AudioUnitDiscovery().instruments()
            }
        }
    }

    /// Other containers in the song that can be targeted by trigger actions.
    private var triggerTargets: [Container] {
        allContainers.filter { $0.id != container.id }
    }

    /// Look up a container name by ID from allContainers.
    private func containerName(for targetID: ID<Container>) -> String {
        allContainers.first(where: { $0.id == targetID })?.name ?? "Unknown"
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
                .font(.caption)
        } else {
            ForEach(actions) { action in
                HStack {
                    actionRowView(action: action)
                    Spacer()
                    Button(role: .destructive) {
                        onRemove?(action.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
        .font(.caption)
        if !triggerTargets.isEmpty {
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
            .font(.caption)
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
                    .font(.callout)
                Text(destination.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .triggerContainer(_, let targetID, let triggerAction):
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(triggerAction.summary)
                    .font(.callout)
                Text(containerName(for: targetID))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

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

    private func commitLoopSettings() {
        let loopCount: LoopCount = loopCountMode == .fill ? .fill : .count(loopCountValue)
        let settings = LoopSettings(
            loopCount: loopCount,
            boundaryMode: selectedBoundaryMode,
            crossfadeDurationMs: crossfadeDuration
        )
        onUpdateLoopSettings?(settings)
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
