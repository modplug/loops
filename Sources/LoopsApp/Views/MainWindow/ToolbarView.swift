import SwiftUI
import LoopsCore

/// Transport bar with play, stop, record arm, BPM, time signature, metronome, and count-in controls.
public struct ToolbarView: View {
    @Bindable var viewModel: TransportViewModel
    @State private var bpmText: String = "120.0"

    /// Callback for when the user selects a new time signature.
    var onTimeSignatureChange: ((Int, Int) -> Void)?

    /// Callback for when metronome config changes (volume, subdivision, output port).
    var onMetronomeConfigChange: ((MetronomeConfig) -> Void)?

    /// Available output ports for metronome routing.
    var availableOutputPorts: [OutputPort]

    private static let countInOptions = [0, 1, 2, 4]

    private static let timeSignaturePresets: [(beatsPerBar: Int, beatUnit: Int)] = [
        (2, 4), (3, 4), (4, 4), (5, 4), (6, 8), (7, 8)
    ]

    public init(
        viewModel: TransportViewModel,
        onTimeSignatureChange: ((Int, Int) -> Void)? = nil,
        onMetronomeConfigChange: ((MetronomeConfig) -> Void)? = nil,
        availableOutputPorts: [OutputPort] = []
    ) {
        self.viewModel = viewModel
        self.onTimeSignatureChange = onTimeSignatureChange
        self.onMetronomeConfigChange = onMetronomeConfigChange
        self.availableOutputPorts = availableOutputPorts
        _bpmText = State(initialValue: String(format: "%.1f", viewModel.bpm))
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Transport controls
            HStack(spacing: 8) {
                // Record arm
                Button(action: { viewModel.toggleRecordArm() }) {
                    Image(systemName: "record.circle")
                        .foregroundStyle(viewModel.isRecordArmed ? .red : .secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("Record Arm")

                // Play/Pause
                Button(action: { viewModel.togglePlayPause() }) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(viewModel.isPlaying ? Color.accentColor : Color.primary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help(viewModel.isPlaying ? "Pause" : "Play")

                // Stop
                Button(action: { viewModel.stop() }) {
                    Image(systemName: "stop.fill")
                        .foregroundStyle(.primary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("Stop")

                // Return to start position toggle
                Button(action: { viewModel.returnToStartEnabled.toggle() }) {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundStyle(viewModel.returnToStartEnabled ? Color.accentColor : Color.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(viewModel.returnToStartEnabled ? "Return to Start Position: On" : "Return to Start Position: Off")
            }

            Divider().frame(height: 24)

            // BPM
            HStack(spacing: 4) {
                Text("BPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("BPM", text: $bpmText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .onSubmit {
                        if let value = Double(bpmText) {
                            viewModel.updateBPM(value)
                        }
                        bpmText = String(format: "%.1f", viewModel.bpm)
                    }
            }

            // Time signature picker
            Menu {
                ForEach(Self.timeSignaturePresets, id: \.beatsPerBar) { preset in
                    Button(action: {
                        onTimeSignatureChange?(preset.beatsPerBar, preset.beatUnit)
                    }) {
                        HStack {
                            Text("\(preset.beatsPerBar)/\(preset.beatUnit)")
                            if viewModel.timeSignature.beatsPerBar == preset.beatsPerBar
                                && viewModel.timeSignature.beatUnit == preset.beatUnit {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text("\(viewModel.timeSignature.beatsPerBar)/\(viewModel.timeSignature.beatUnit)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Time Signature")

            Divider().frame(height: 24)

            // Metronome toggle
            Button(action: { viewModel.toggleMetronome() }) {
                Image(systemName: "metronome")
                    .foregroundStyle(viewModel.isMetronomeEnabled ? Color.accentColor : Color.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Metronome")

            // Metronome volume slider
            Slider(value: Binding(
                get: { Double(viewModel.metronomeVolume) },
                set: { viewModel.setMetronomeVolume(Float($0))
                    onMetronomeConfigChange?(MetronomeConfig(
                        volume: Float($0),
                        subdivision: viewModel.metronomeSubdivision,
                        outputPortID: viewModel.metronomeOutputPortID
                    ))
                }
            ), in: 0...1)
            .frame(width: 60)
            .help("Metronome Volume: \(Int(viewModel.metronomeVolume * 100))%")

            // Metronome subdivision picker
            Menu {
                ForEach(MetronomeSubdivision.allCases, id: \.self) { sub in
                    Button(action: {
                        viewModel.setMetronomeSubdivision(sub)
                        onMetronomeConfigChange?(MetronomeConfig(
                            volume: viewModel.metronomeVolume,
                            subdivision: sub,
                            outputPortID: viewModel.metronomeOutputPortID
                        ))
                    }) {
                        HStack {
                            Text(sub.displayName)
                            if viewModel.metronomeSubdivision == sub {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                if !availableOutputPorts.isEmpty {
                    Divider()
                    Menu("Output") {
                        Button(action: {
                            viewModel.setMetronomeOutputPort(nil)
                            onMetronomeConfigChange?(MetronomeConfig(
                                volume: viewModel.metronomeVolume,
                                subdivision: viewModel.metronomeSubdivision,
                                outputPortID: nil
                            ))
                        }) {
                            HStack {
                                Text("Main Output")
                                if viewModel.metronomeOutputPortID == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        ForEach(availableOutputPorts) { port in
                            Button(action: {
                                viewModel.setMetronomeOutputPort(port.id)
                                onMetronomeConfigChange?(MetronomeConfig(
                                    volume: viewModel.metronomeVolume,
                                    subdivision: viewModel.metronomeSubdivision,
                                    outputPortID: port.id
                                ))
                            }) {
                                HStack {
                                    Text(port.displayName)
                                    if viewModel.metronomeOutputPortID == port.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                Text(viewModel.metronomeSubdivision.displayName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(viewModel.metronomeSubdivision != .quarter ? Color.accentColor : Color.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Metronome Subdivision")

            // Count-in picker
            Menu {
                ForEach(Self.countInOptions, id: \.self) { bars in
                    Button(action: { viewModel.countInBars = bars }) {
                        HStack {
                            Text(bars == 0 ? "Off" : "\(bars) bars")
                            if viewModel.countInBars == bars {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                    Text(viewModel.countInBars > 0 ? "\(viewModel.countInBars)" : "—")
                        .font(.system(.caption, design: .monospaced))
                }
                .foregroundStyle(viewModel.countInBars > 0 ? Color.accentColor : Color.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Count-in: \(viewModel.countInBars == 0 ? "Off" : "\(viewModel.countInBars) bars")")

            Spacer()

            // Count-in countdown display
            if viewModel.isCountingIn {
                Text("Count: \(viewModel.countInBarsRemaining)...")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.red)
                    .bold()
            }

            // Position display
            HStack(spacing: 8) {
                Text("Bar \(String(format: "%.1f", viewModel.playheadBar))")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(WallTimeConverter.formattedTime(
                    forBar: viewModel.playheadBar,
                    bpm: viewModel.bpm,
                    beatsPerBar: viewModel.timeSignature.beatsPerBar
                ))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
