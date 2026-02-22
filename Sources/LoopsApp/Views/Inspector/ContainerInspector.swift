import SwiftUI
import LoopsCore
import LoopsEngine

/// Inspector panel showing a container summary with an "Edit Container" button
/// that opens the full detail editor sheet.
public struct ContainerInspector: View {
    let container: Container
    let trackKind: TrackKind
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

    @Binding var showDetailEditor: Bool

    @State private var editingName: String = ""
    @State private var selectedBoundaryMode: BoundaryMode = .hardCut
    @State private var loopCountMode: LoopCountMode = .fill
    @State private var loopCountValue: Int = 1
    @State private var crossfadeDuration: Double = 10.0

    enum LoopCountMode: String, CaseIterable {
        case fill = "Fill"
        case count = "Count"
    }

    public init(
        container: Container,
        trackKind: TrackKind = .audio,
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
        onUpdateBreakpoint: ((ID<AutomationLane>, AutomationBreakpoint) -> Void)? = nil
    ) {
        self.container = container
        self.trackKind = trackKind
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
    }

    public var body: some View {
        Form {
            // Container info
            Section("Container") {
                TextField("Name", text: $editingName)
                    .onSubmit { onUpdateName?(editingName) }

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

            // Summary cards
            Section("Effects") {
                effectsSummary
            }

            Section("Actions") {
                actionsSummary
            }

            Section("Fades") {
                fadesSummary
            }

            Section("Automation") {
                automationSummary
            }

            // Edit button
            Section {
                Button {
                    showDetailEditor = true
                } label: {
                    Label("Edit Container", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            // Loop settings inline (simple enough for inspector)
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
        }
        .formStyle(.grouped)
        .onAppear { loadFromContainer() }
    }

    // MARK: - Summary Cards

    private var effectsSummary: some View {
        Group {
            if container.insertEffects.isEmpty {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                    Text("No effects")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            } else {
                ForEach(container.insertEffects.sorted(by: { $0.orderIndex < $1.orderIndex })) { effect in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(effect.isBypassed ? Color.gray : Color.green)
                            .frame(width: 6, height: 6)
                        Text(effect.displayName)
                            .font(.callout)
                            .lineLimit(1)
                    }
                }
                if container.isEffectChainBypassed {
                    Text("Chain bypassed")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            HStack {
                Spacer()
                Text("\(container.insertEffects.count) effect\(container.insertEffects.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionsSummary: some View {
        Group {
            let enterCount = container.onEnterActions.count
            let exitCount = container.onExitActions.count
            let totalCount = enterCount + exitCount

            if totalCount == 0 {
                HStack {
                    Image(systemName: "bolt")
                        .foregroundStyle(.secondary)
                    Text("No actions")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            } else {
                if enterCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("\(enterCount) enter")
                            .font(.callout)
                        Spacer()
                        actionTypeSummary(container.onEnterActions)
                    }
                }
                if exitCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.circle")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text("\(exitCount) exit")
                            .font(.callout)
                        Spacer()
                        actionTypeSummary(container.onExitActions)
                    }
                }
            }
        }
    }

    private func actionTypeSummary(_ actions: [ContainerAction]) -> some View {
        let types = Set(actions.map { action -> String in
            switch action {
            case .sendMIDI: return "MIDI"
            case .triggerContainer: return "Trigger"
            case .setParameter: return "Param"
            }
        })
        return Text(types.sorted().joined(separator: ", "))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var fadesSummary: some View {
        Group {
            if container.enterFade == nil && container.exitFade == nil {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(.secondary)
                    Text("No fades")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            } else {
                if let fade = container.enterFade {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("In: \(fade.duration, specifier: "%.2g") bar\(fade.duration == 1 ? "" : "s")")
                            .font(.callout)
                        Text(fade.curve.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let fade = container.exitFade {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.right")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text("Out: \(fade.duration, specifier: "%.2g") bar\(fade.duration == 1 ? "" : "s")")
                            .font(.callout)
                        Text(fade.curve.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var automationSummary: some View {
        Group {
            let count = container.automationLanes.count
            if count == 0 {
                HStack {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(.secondary)
                    Text("No automation")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            } else {
                HStack {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(.cyan)
                    Text("\(count) lane\(count == 1 ? "" : "s")")
                        .font(.callout)
                    Spacer()
                    let totalPoints = container.automationLanes.reduce(0) { $0 + $1.breakpoints.count }
                    Text("\(totalPoints) breakpoint\(totalPoints == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
