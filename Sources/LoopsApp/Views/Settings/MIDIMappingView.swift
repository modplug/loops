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

    private var trackCount: Int {
        let tracks = projectViewModel.currentSong?.tracks.filter { $0.kind != .master } ?? []
        return tracks.count
    }

    private var songCount: Int {
        projectViewModel.project.songs.count
    }

    private var trackNames: [String] {
        let tracks = projectViewModel.currentSong?.tracks.filter { $0.kind != .master } ?? []
        return tracks.map(\.name)
    }

    private var songNames: [String] {
        projectViewModel.project.songs.map(\.name)
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

            Section("Transport") {
                ForEach(MappableControl.transportControls, id: \.self) { control in
                    mappingRow(for: control)
                }
            }

            Section("Mixer") {
                if trackCount == 0 {
                    Text("No tracks in current song")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(0..<trackCount, id: \.self) { idx in
                        let name = idx < trackNames.count ? trackNames[idx] : "Track \(idx + 1)"
                        DisclosureGroup(name) {
                            mappingRow(for: .trackVolume(trackIndex: idx))
                            mappingRow(for: .trackPan(trackIndex: idx))
                            mappingRow(for: .trackMute(trackIndex: idx))
                            mappingRow(for: .trackSolo(trackIndex: idx))
                        }
                    }
                    bankMappingMenu()
                }
            }

            Section("Navigation") {
                ForEach(0..<trackCount, id: \.self) { idx in
                    mappingRow(for: .trackSelect(trackIndex: idx))
                }
                ForEach(0..<songCount, id: \.self) { idx in
                    mappingRow(for: .songSelect(songIndex: idx))
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

    @ViewBuilder
    private func bankMappingMenu() -> some View {
        Menu("Bank Assign...") {
            Button("Volume: CC 1–\(trackCount) → Tracks 1–\(trackCount)") {
                applyBankMapping(control: { .trackVolume(trackIndex: $0) }, startCC: 1)
            }
            Button("Pan: CC \(trackCount + 1)–\(trackCount * 2) → Tracks 1–\(trackCount)") {
                applyBankMapping(control: { .trackPan(trackIndex: $0) }, startCC: UInt8(trackCount + 1))
            }
            Button("Mute: CC \(trackCount * 2 + 1)–\(trackCount * 3) → Tracks 1–\(trackCount)") {
                applyBankMapping(control: { .trackMute(trackIndex: $0) }, startCC: UInt8(trackCount * 2 + 1))
            }
            Button("Solo: CC \(trackCount * 3 + 1)–\(trackCount * 4) → Tracks 1–\(trackCount)") {
                applyBankMapping(control: { .trackSolo(trackIndex: $0) }, startCC: UInt8(trackCount * 3 + 1))
            }
        }
        .help("Map sequential CCs to sequential tracks")
    }

    private func applyBankMapping(control: (Int) -> MappableControl, startCC: UInt8) {
        for i in 0..<trackCount {
            let cc = startCC + UInt8(i)
            guard cc <= 127 else { break }
            let ctrl = control(i)
            let trigger = MIDITrigger.controlChange(channel: 0, controller: cc)
            // Remove existing mapping for this control and trigger
            projectViewModel.project.midiMappings.removeAll { $0.control == ctrl }
            projectViewModel.project.midiMappings.removeAll { $0.trigger == trigger }
            projectViewModel.project.midiMappings.append(
                MIDIMapping(control: ctrl, trigger: trigger)
            )
        }
        dispatcher.updateMappings(projectViewModel.project.midiMappings)
        projectViewModel.hasUnsavedChanges = true
        projectViewModel.onMIDIMappingsChanged?()
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
        projectViewModel.onMIDIMappingsChanged?()
        learningForControl = nil
    }

    private func clearMapping(for control: MappableControl) {
        projectViewModel.project.midiMappings.removeAll { $0.control == control }
        dispatcher.updateMappings(projectViewModel.project.midiMappings)
        projectViewModel.hasUnsavedChanges = true
        projectViewModel.onMIDIMappingsChanged?()
    }

    private func applyPreset(_ preset: FootPedalPreset) {
        projectViewModel.project.midiMappings = preset.mappings
        dispatcher.updateMappings(projectViewModel.project.midiMappings)
        projectViewModel.hasUnsavedChanges = true
        projectViewModel.onMIDIMappingsChanged?()
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
        case .trackVolume(let idx): return "Track \(idx + 1) Volume"
        case .trackPan(let idx): return "Track \(idx + 1) Pan"
        case .trackMute(let idx): return "Track \(idx + 1) Mute"
        case .trackSolo(let idx): return "Track \(idx + 1) Solo"
        case .trackSend(let trackIdx, let sendIdx): return "Track \(trackIdx + 1) Send \(sendIdx + 1)"
        case .trackSelect(let idx): return "Select Track \(idx + 1)"
        case .songSelect(let idx): return "Song \(idx + 1)"
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
