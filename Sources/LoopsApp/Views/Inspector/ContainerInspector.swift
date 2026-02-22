import SwiftUI
import LoopsCore
import LoopsEngine

/// Inspector panel for editing a selected container's loop settings.
public struct ContainerInspector: View {
    let container: Container
    let trackKind: TrackKind
    var onUpdateLoopSettings: ((LoopSettings) -> Void)?
    var onUpdateName: ((String) -> Void)?
    var onAddEffect: ((InsertEffect) -> Void)?
    var onRemoveEffect: ((ID<InsertEffect>) -> Void)?
    var onToggleEffectBypass: ((ID<InsertEffect>) -> Void)?
    var onToggleChainBypass: (() -> Void)?
    var onSetInstrumentOverride: ((AudioComponentInfo?) -> Void)?
    var onSetEnterFade: ((FadeSettings?) -> Void)?
    var onSetExitFade: ((FadeSettings?) -> Void)?

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
        onUpdateLoopSettings: ((LoopSettings) -> Void)? = nil,
        onUpdateName: ((String) -> Void)? = nil,
        onAddEffect: ((InsertEffect) -> Void)? = nil,
        onRemoveEffect: ((ID<InsertEffect>) -> Void)? = nil,
        onToggleEffectBypass: ((ID<InsertEffect>) -> Void)? = nil,
        onToggleChainBypass: (() -> Void)? = nil,
        onSetInstrumentOverride: ((AudioComponentInfo?) -> Void)? = nil,
        onSetEnterFade: ((FadeSettings?) -> Void)? = nil,
        onSetExitFade: ((FadeSettings?) -> Void)? = nil
    ) {
        self.container = container
        self.trackKind = trackKind
        self.onUpdateLoopSettings = onUpdateLoopSettings
        self.onUpdateName = onUpdateName
        self.onAddEffect = onAddEffect
        self.onRemoveEffect = onRemoveEffect
        self.onToggleEffectBypass = onToggleEffectBypass
        self.onToggleChainBypass = onToggleChainBypass
        self.onSetInstrumentOverride = onSetInstrumentOverride
        self.onSetEnterFade = onSetEnterFade
        self.onSetExitFade = onSetExitFade
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
        }
        .formStyle(.grouped)
        .onAppear {
            loadFromContainer()
            if trackKind == .midi {
                availableInstruments = AudioUnitDiscovery().instruments()
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
