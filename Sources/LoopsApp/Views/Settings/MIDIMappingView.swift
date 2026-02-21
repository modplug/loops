import SwiftUI
import LoopsCore
import LoopsEngine

/// View for managing MIDI mappings, learn mode, and foot pedal presets.
public struct MIDIMappingView: View {
    @Bindable var projectViewModel: ProjectViewModel
    let midiManager: MIDIManager
    let dispatcher: MIDIDispatcher
    let learnController: MIDILearnController

    @State private var learningForControl: MappableControl?

    public init(
        projectViewModel: ProjectViewModel,
        midiManager: MIDIManager,
        dispatcher: MIDIDispatcher,
        learnController: MIDILearnController
    ) {
        self.projectViewModel = projectViewModel
        self.midiManager = midiManager
        self.dispatcher = dispatcher
        self.learnController = learnController
    }

    public var body: some View {
        Form {
            Section("MIDI Devices") {
                let sources = midiManager.sourceNames()
                if sources.isEmpty {
                    Text("No MIDI devices connected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sources, id: \.self) { name in
                        HStack {
                            Image(systemName: "pianokeys")
                                .foregroundStyle(.secondary)
                            Text(name)
                        }
                    }
                }
            }

            Section("Control Mappings") {
                ForEach(MappableControl.allCases, id: \.self) { control in
                    mappingRow(for: control)
                }
            }

            Section("Foot Pedal Presets") {
                ForEach(FootPedalPreset.allCases, id: \.self) { preset in
                    Button(preset.rawValue) {
                        applyPreset(preset)
                    }
                }
                .buttonStyle(.link)

                Text("Loading a preset replaces all current mappings. You can customize individual assignments afterwards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            learnController.onMappingLearned = { mapping in
                handleLearnedMapping(mapping)
            }
        }
    }

    @ViewBuilder
    private func mappingRow(for control: MappableControl) -> some View {
        let mapping = projectViewModel.project.midiMappings.first(where: { $0.control == control })
        let isLearning = learningForControl == control

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(control.displayName)
                    .font(.body)
                if let mapping = mapping {
                    Text(mapping.trigger.displayString)
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if isLearning {
                    Text("Waiting for MIDI input...")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Not assigned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isLearning {
                Button("Cancel") {
                    cancelLearn()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Learn") {
                    startLearn(for: control)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if mapping != nil {
                    Button(role: .destructive) {
                        clearMapping(for: control)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Clear mapping")
                }
            }
        }
    }

    private func startLearn(for control: MappableControl) {
        learningForControl = control
        learnController.startLearning(for: control)
    }

    private func cancelLearn() {
        learningForControl = nil
        learnController.cancelLearning()
    }

    private func handleLearnedMapping(_ mapping: MIDIMapping) {
        // Remove any existing mapping for this control
        projectViewModel.project.midiMappings.removeAll { $0.control == mapping.control }
        // Also remove any mapping with the same trigger (one trigger = one control)
        projectViewModel.project.midiMappings.removeAll { $0.trigger == mapping.trigger }
        projectViewModel.project.midiMappings.append(mapping)
        dispatcher.updateMappings(projectViewModel.project.midiMappings)
        projectViewModel.hasUnsavedChanges = true
        learningForControl = nil
    }

    private func clearMapping(for control: MappableControl) {
        projectViewModel.project.midiMappings.removeAll { $0.control == control }
        dispatcher.updateMappings(projectViewModel.project.midiMappings)
        projectViewModel.hasUnsavedChanges = true
    }

    private func applyPreset(_ preset: FootPedalPreset) {
        projectViewModel.project.midiMappings = preset.mappings
        dispatcher.updateMappings(projectViewModel.project.midiMappings)
        projectViewModel.hasUnsavedChanges = true
    }
}

// MARK: - Display Helpers

extension MappableControl {
    public var displayName: String {
        switch self {
        case .playPause: return "Play / Pause"
        case .stop: return "Stop"
        case .recordArm: return "Record Arm"
        case .nextSong: return "Next Song"
        case .previousSong: return "Previous Song"
        case .metronomeToggle: return "Metronome Toggle"
        }
    }
}

extension MIDITrigger {
    public var displayString: String {
        switch self {
        case .controlChange(let channel, let controller):
            return "CC \(controller) Ch \(channel + 1)"
        case .noteOn(let channel, let note):
            return "Note \(note) Ch \(channel + 1)"
        }
    }
}
