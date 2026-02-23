import SwiftUI
import LoopsCore

/// Transport bar with play, stop, record arm, BPM, time signature, metronome, and count-in controls.
public struct ToolbarView: View {
    @Bindable var viewModel: TransportViewModel

    /// Callback for when the user changes BPM (persists to song model).
    var onBPMChange: ((Double) -> Void)?

    /// Callback for when the user selects a new time signature.
    var onTimeSignatureChange: ((Int, Int) -> Void)?

    /// Callback for when metronome config changes (volume, subdivision, output port).
    var onMetronomeConfigChange: ((MetronomeConfig) -> Void)?

    /// Undo/redo callbacks wired to the project's UndoManager.
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var canUndo: Bool
    var canRedo: Bool
    var undoActionName: String
    var redoActionName: String

    /// Dedicated undo state observable for history panel and toast.
    var undoState: UndoState

    /// Available output ports for metronome routing.
    var availableOutputPorts: [OutputPort]

    /// Whether snap-to-grid is enabled.
    @Binding var isSnapEnabled: Bool

    /// Current grid mode (adaptive or fixed resolution).
    @Binding var gridMode: GridMode

    /// Binding to show/hide the virtual MIDI keyboard.
    @Binding var isVirtualKeyboardVisible: Bool

    @State private var showUndoHistory: Bool = false

    private static let countInOptions = [0, 1, 2, 4]

    private static let timeSignaturePresets: [(beatsPerBar: Int, beatUnit: Int)] = [
        (2, 4), (3, 4), (4, 4), (5, 4), (6, 8), (7, 8)
    ]

    public init(
        viewModel: TransportViewModel,
        onBPMChange: ((Double) -> Void)? = nil,
        onTimeSignatureChange: ((Int, Int) -> Void)? = nil,
        onMetronomeConfigChange: ((MetronomeConfig) -> Void)? = nil,
        onUndo: (() -> Void)? = nil,
        onRedo: (() -> Void)? = nil,
        canUndo: Bool = false,
        canRedo: Bool = false,
        undoActionName: String = "",
        redoActionName: String = "",
        undoState: UndoState = UndoState(),
        availableOutputPorts: [OutputPort] = [],
        isSnapEnabled: Binding<Bool> = .constant(true),
        gridMode: Binding<GridMode> = .constant(.adaptive),
        isVirtualKeyboardVisible: Binding<Bool> = .constant(false)
    ) {
        self.viewModel = viewModel
        self.onBPMChange = onBPMChange
        self.onTimeSignatureChange = onTimeSignatureChange
        self.onMetronomeConfigChange = onMetronomeConfigChange
        self.onUndo = onUndo
        self.onRedo = onRedo
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.undoActionName = undoActionName
        self.redoActionName = redoActionName
        self.undoState = undoState
        self.availableOutputPorts = availableOutputPorts
        self._isSnapEnabled = isSnapEnabled
        self._gridMode = gridMode
        self._isVirtualKeyboardVisible = isVirtualKeyboardVisible
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

            // Undo/Redo
            HStack(spacing: 4) {
                Button(action: { onUndo?() }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3)
                        .foregroundStyle(canUndo ? Color.primary : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canUndo)
                .help(undoActionName.isEmpty ? "Undo" : "Undo \(undoActionName)")

                Button(action: { onRedo?() }) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.title3)
                        .foregroundStyle(canRedo ? Color.primary : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canRedo)
                .help(redoActionName.isEmpty ? "Redo" : "Redo \(redoActionName)")

                Button(action: { showUndoHistory.toggle() }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(undoState.undoHistory.isEmpty ? Color.secondary.opacity(0.4) : Color.primary)
                }
                .buttonStyle(.plain)
                .disabled(undoState.undoHistory.isEmpty)
                .help("Undo History")
                .popover(isPresented: $showUndoHistory) {
                    UndoHistoryView(entries: undoState.undoHistory, cursor: undoState.undoHistoryCursor)
                }
            }

            Divider().frame(height: 24)

            // BPM
            DraggableBPMView(
                bpm: viewModel.bpm,
                onBPMChange: { newBPM in
                    viewModel.updateBPM(newBPM)
                },
                onBPMCommit: { newBPM in
                    viewModel.updateBPM(newBPM)
                    onBPMChange?(viewModel.bpm)
                }
            )

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

            // Metronome volume slider — only persists to model on gesture end
            Slider(value: Binding(
                get: { Double(viewModel.metronomeVolume) },
                set: { viewModel.setMetronomeVolume(Float($0)) }
            ), in: 0...1) { editing in
                if !editing {
                    // Gesture ended — persist to project model
                    onMetronomeConfigChange?(MetronomeConfig(
                        volume: viewModel.metronomeVolume,
                        subdivision: viewModel.metronomeSubdivision,
                        outputPortID: viewModel.metronomeOutputPortID
                    ))
                }
            }
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

            Divider().frame(height: 24)

            // Snap toggle
            Button(action: { isSnapEnabled.toggle() }) {
                Image(systemName: "dot.arrowtriangles.up.right.down.left.circle")
                    .foregroundStyle(isSnapEnabled ? Color.accentColor : Color.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(isSnapEnabled ? "Snap to Grid: On" : "Snap to Grid: Off")

            // Grid resolution menu
            Menu {
                Button(action: { gridMode = .adaptive }) {
                    HStack {
                        Text("Adaptive")
                        if case .adaptive = gridMode {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                ForEach(SnapResolution.straightCases, id: \.self) { res in
                    Button(action: { gridMode = .fixed(res) }) {
                        HStack {
                            Text(res.rawValue)
                            if case .fixed(let current) = gridMode, current == res {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Divider()

                ForEach(SnapResolution.tripletCases, id: \.self) { res in
                    Button(action: { gridMode = .fixed(res) }) {
                        HStack {
                            Text(res.rawValue)
                            if case .fixed(let current) = gridMode, current == res {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(gridModeLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isAdaptiveMode ? Color.secondary : Color.accentColor)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Grid Resolution")

            Divider().frame(height: 24)

            // Virtual MIDI keyboard toggle
            Button(action: { isVirtualKeyboardVisible.toggle() }) {
                Image(systemName: "pianokeys")
                    .foregroundStyle(isVirtualKeyboardVisible ? Color.accentColor : Color.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(isVirtualKeyboardVisible ? "Hide Virtual Keyboard" : "Show Virtual Keyboard")

            Spacer()

            // Position display — isolated to avoid 60fps re-renders of the whole toolbar
            TransportPositionView(viewModel: viewModel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var gridModeLabel: String {
        switch gridMode {
        case .adaptive: return "Auto"
        case .fixed(let res): return res.rawValue
        }
    }

    private var isAdaptiveMode: Bool {
        if case .adaptive = gridMode { return true }
        return false
    }
}

/// Draggable BPM control: displays BPM as text, drag up/down to adjust,
/// shift+drag for fine control, double-click to enter manual edit mode.
struct DraggableBPMView: View {
    var bpm: Double
    /// Called continuously during drag for live preview.
    var onBPMChange: (Double) -> Void
    /// Called on drag end or text field submit to persist.
    var onBPMCommit: (Double) -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var dragStartBPM: Double?
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("BPM")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isEditing {
                TextField("BPM", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .focused($textFieldFocused)
                    .onSubmit {
                        if let value = Double(editText) {
                            onBPMCommit(value)
                        }
                        isEditing = false
                    }
                    .onExitCommand {
                        isEditing = false
                    }
                    .onChange(of: textFieldFocused) { _, focused in
                        if !focused {
                            isEditing = false
                        }
                    }
            } else {
                Text(String(format: "%.1f", bpm))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 60)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .onTapGesture(count: 2) {
                        editText = String(format: "%.1f", bpm)
                        isEditing = true
                        // Delay focus to next run loop so the TextField is mounted
                        DispatchQueue.main.async {
                            textFieldFocused = true
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let anchor = dragStartBPM ?? bpm
                                if dragStartBPM == nil {
                                    dragStartBPM = bpm
                                }
                                let shift = NSEvent.modifierFlags.contains(.shift)
                                let sensitivity: Double = shift ? 0.05 : 1.0
                                // Drag up = increase BPM (negative Y = up)
                                let delta = -value.translation.height * sensitivity
                                let newBPM = min(max(anchor + delta, 20.0), 300.0)
                                onBPMChange(newBPM)
                            }
                            .onEnded { value in
                                let anchor = dragStartBPM ?? bpm
                                let shift = NSEvent.modifierFlags.contains(.shift)
                                let sensitivity: Double = shift ? 0.05 : 1.0
                                let delta = -value.translation.height * sensitivity
                                let newBPM = min(max(anchor + delta, 20.0), 300.0)
                                onBPMCommit(newBPM)
                                dragStartBPM = nil
                            }
                    )
                    .onHover { hovering in
                        if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .help("Drag to adjust BPM. Shift+drag for fine control. Double-click to type.")
            }
        }
    }
}

/// Isolates playhead-dependent display from ToolbarView so the toolbar
/// doesn't re-evaluate at 60fps during playback.
struct TransportPositionView: View {
    let viewModel: TransportViewModel

    var body: some View {
        HStack(spacing: 8) {
            if viewModel.isCountingIn {
                Text("Count: \(viewModel.countInBarsRemaining)...")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.red)
                    .bold()
            }
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
}
