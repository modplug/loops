import SwiftUI
import LoopsCore

/// Inspector panel for editing a selected container's loop settings.
public struct ContainerInspector: View {
    let container: Container
    var onUpdateLoopSettings: ((LoopSettings) -> Void)?
    var onUpdateName: ((String) -> Void)?
    var onAddEffect: ((InsertEffect) -> Void)?
    var onRemoveEffect: ((ID<InsertEffect>) -> Void)?
    var onToggleEffectBypass: ((ID<InsertEffect>) -> Void)?
    var onToggleChainBypass: (() -> Void)?

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
        onUpdateLoopSettings: ((LoopSettings) -> Void)? = nil,
        onUpdateName: ((String) -> Void)? = nil,
        onAddEffect: ((InsertEffect) -> Void)? = nil,
        onRemoveEffect: ((ID<InsertEffect>) -> Void)? = nil,
        onToggleEffectBypass: ((ID<InsertEffect>) -> Void)? = nil,
        onToggleChainBypass: (() -> Void)? = nil
    ) {
        self.container = container
        self.onUpdateLoopSettings = onUpdateLoopSettings
        self.onUpdateName = onUpdateName
        self.onAddEffect = onAddEffect
        self.onRemoveEffect = onRemoveEffect
        self.onToggleEffectBypass = onToggleEffectBypass
        self.onToggleChainBypass = onToggleChainBypass
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
