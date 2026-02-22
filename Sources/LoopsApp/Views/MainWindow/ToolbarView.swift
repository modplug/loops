import SwiftUI
import LoopsCore

/// Transport bar with play, stop, record arm, BPM, time signature, metronome, and count-in controls.
public struct ToolbarView: View {
    @Bindable var viewModel: TransportViewModel
    @State private var bpmText: String = "120.0"

    private static let countInOptions = [0, 1, 2, 4]

    public init(viewModel: TransportViewModel) {
        self.viewModel = viewModel
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

            // Time signature display
            HStack(spacing: 2) {
                Text("\(viewModel.timeSignature.beatsPerBar)/\(viewModel.timeSignature.beatUnit)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Divider().frame(height: 24)

            // Metronome toggle
            Button(action: { viewModel.toggleMetronome() }) {
                Image(systemName: "metronome")
                    .foregroundStyle(viewModel.isMetronomeEnabled ? Color.accentColor : Color.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Metronome")

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
            Text("Bar \(String(format: "%.1f", viewModel.playheadBar))")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
