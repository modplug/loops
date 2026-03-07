import SwiftUI
import LoopsCore
import LoopsEngine

/// Coordinate mapping helpers for the piano roll grid.
enum PianoRollLayout {
    /// Default visible pitch range.
    static let defaultLowPitch: UInt8 = 36  // C2
    static let defaultHighPitch: UInt8 = 96 // C7

    static let defaultRowHeight: CGFloat = 14
    static let minRowHeight: CGFloat = 6
    static let maxRowHeight: CGFloat = 40
    static let minDetailLaneHeight: CGFloat = 56
    static let maxDetailLaneHeight: CGFloat = 220
    static let keyboardWidth: CGFloat = 48
    static let defaultPixelsPerBeat: CGFloat = 40

    /// Y position for a given pitch (higher pitch = lower Y, piano convention).
    static func yPosition(forPitch pitch: UInt8, lowPitch: UInt8, highPitch: UInt8, rowHeight: CGFloat = defaultRowHeight) -> CGFloat {
        let row = Int(highPitch) - Int(pitch)
        return CGFloat(row) * rowHeight
    }

    /// Pitch for a given Y position.
    static func pitch(forY y: CGFloat, lowPitch: UInt8, highPitch: UInt8, rowHeight: CGFloat = defaultRowHeight) -> UInt8 {
        let row = Int(y / rowHeight)
        let p = Int(highPitch) - row
        return UInt8(clamping: max(Int(lowPitch), min(Int(highPitch), p)))
    }

    /// X position for a given beat.
    static func xPosition(forBeat beat: Double, pixelsPerBeat: CGFloat) -> CGFloat {
        CGFloat(beat) * pixelsPerBeat
    }

    /// Beat for a given X position.
    static func beat(forX x: CGFloat, pixelsPerBeat: CGFloat) -> Double {
        max(0, Double(x / pixelsPerBeat))
    }

    /// Total height for the visible pitch range.
    static func totalHeight(lowPitch: UInt8, highPitch: UInt8, rowHeight: CGFloat = defaultRowHeight) -> CGFloat {
        CGFloat(Int(highPitch) - Int(lowPitch) + 1) * rowHeight
    }
}

/// Piano roll sheet wrapper for MIDI containers.
/// Uses PianoRollContentView for the actual grid + notes + gestures.
public struct PianoRollView: View {
    let containerID: ID<Container>
    let sequence: MIDISequence
    let lengthBars: Double
    let timeSignature: TimeSignature
    let containerStartBar: Double

    var playheadBeat: Double?
    var onAddNote: ((MIDINoteEvent) -> Void)?
    var onUpdateNote: ((MIDINoteEvent) -> Void)?
    var onRemoveNote: ((ID<MIDINoteEvent>) -> Void)?
    var onAddControllerEvent: ((MIDIControllerEvent) -> Void)?
    var onUpdateControllerEvent: ((MIDIControllerEvent) -> Void)?
    var onRemoveControllerEvent: ((ID<MIDIControllerEvent>) -> Void)?
    var onNotePreview: ((_ pitch: UInt8, _ isNoteOn: Bool) -> Void)?
    /// Called to dismiss the view. When hosted in NSWindow, closes the window.
    var onDismiss: (() -> Void)?

    @State private var selectedNoteIDs: Set<ID<MIDINoteEvent>> = []
    @State private var pixelsPerBeat: CGFloat = PianoRollLayout.defaultPixelsPerBeat
    @State private var lowPitch: UInt8 = PianoRollLayout.defaultLowPitch
    @State private var highPitch: UInt8 = PianoRollLayout.defaultHighPitch
    @State private var rowHeight: CGFloat = PianoRollLayout.defaultRowHeight
    @State private var selectedTool: MIDITool = .pointer
    @State private var selectedExpressionLane: MIDINoteExpressionLane = .velocity
    @State private var visibleExpressionLanes: [MIDINoteExpressionLane] = [.velocity]
    @State private var noteExpressionLaneHeights: [MIDINoteExpressionLane: CGFloat] = [:]
    @State private var snapResolution: SnapResolution = .sixteenth

    public init(
        containerID: ID<Container>,
        sequence: MIDISequence,
        lengthBars: Double,
        timeSignature: TimeSignature,
        snapResolution: SnapResolution = .sixteenth,
        containerStartBar: Double = 1.0,
        playheadBeat: Double? = nil,
        onAddNote: ((MIDINoteEvent) -> Void)? = nil,
        onUpdateNote: ((MIDINoteEvent) -> Void)? = nil,
        onRemoveNote: ((ID<MIDINoteEvent>) -> Void)? = nil,
        onAddControllerEvent: ((MIDIControllerEvent) -> Void)? = nil,
        onUpdateControllerEvent: ((MIDIControllerEvent) -> Void)? = nil,
        onRemoveControllerEvent: ((ID<MIDIControllerEvent>) -> Void)? = nil,
        onNotePreview: ((_ pitch: UInt8, _ isNoteOn: Bool) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.containerID = containerID
        self.sequence = sequence
        self.lengthBars = lengthBars
        self.timeSignature = timeSignature
        self._snapResolution = State(initialValue: snapResolution)
        self.containerStartBar = containerStartBar
        self.playheadBeat = playheadBeat
        self.onAddNote = onAddNote
        self.onUpdateNote = onUpdateNote
        self.onRemoveNote = onRemoveNote
        self.onAddControllerEvent = onAddControllerEvent
        self.onUpdateControllerEvent = onUpdateControllerEvent
        self.onRemoveControllerEvent = onRemoveControllerEvent
        self.onNotePreview = onNotePreview
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            PianoRollContentView(
                sequence: sequence,
                lengthBars: lengthBars,
                timeSignature: timeSignature,
                snapResolution: $snapResolution,
                pixelsPerBeat: $pixelsPerBeat,
                lowPitch: $lowPitch,
                highPitch: $highPitch,
                rowHeight: $rowHeight,
                selectedTool: $selectedTool,
                selectedExpressionLane: $selectedExpressionLane,
                visibleExpressionLanes: $visibleExpressionLanes,
                noteExpressionLaneHeights: $noteExpressionLaneHeights,
                selectedNoteIDs: $selectedNoteIDs,
                playheadBeat: playheadBeat,
                containerStartBar: containerStartBar,
                onAddNote: onAddNote,
                onUpdateNote: onUpdateNote,
                onRemoveNote: onRemoveNote,
                onAddControllerEvent: onAddControllerEvent,
                onUpdateControllerEvent: onUpdateControllerEvent,
                onRemoveControllerEvent: onRemoveControllerEvent,
                onNotePreview: onNotePreview
            )
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Piano Roll")
                .font(.headline)

            Spacer()

            // Snap resolution picker
            Text("Snap:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $snapResolution) {
                ForEach(SnapResolution.allCases, id: \.self) { res in
                    Text(res.rawValue).tag(res)
                }
            }
            .frame(width: 60)

            Divider().frame(height: 16)

            // Horizontal zoom
            Button(action: { pixelsPerBeat = max(10, pixelsPerBeat - 10) }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Zoom Out")

            Button(action: { pixelsPerBeat = min(120, pixelsPerBeat + 10) }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Zoom In")

            Divider().frame(height: 16)

            ForEach(MIDITool.allCases, id: \.self) { tool in
                Button(action: { selectedTool = tool }) {
                    Image(systemName: tool.iconName)
                        .foregroundStyle(selectedTool == tool ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(tool.label)
            }

            Divider().frame(height: 16)

            Menu {
                ForEach(MIDINoteExpressionLane.allCases, id: \.self) { lane in
                    Button {
                        selectedExpressionLane = lane
                        if !visibleExpressionLanes.contains(lane) {
                            visibleExpressionLanes.append(lane)
                            visibleExpressionLanes.sort { lhs, rhs in
                                MIDINoteExpressionLane.allCases.firstIndex(of: lhs)! < MIDINoteExpressionLane.allCases.firstIndex(of: rhs)!
                            }
                        }
                    } label: {
                        Label(lane.label, systemImage: visibleExpressionLanes.contains(lane) ? "checkmark.circle.fill" : lane.iconName)
                    }
                }
            } label: {
                Label(selectedExpressionLane.shortLabel, systemImage: selectedExpressionLane.iconName)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(!visibleExpressionLanes.isEmpty ? Color.primary : Color.secondary)
            }
            .menuStyle(.borderlessButton)

            Button(action: {
                if visibleExpressionLanes.contains(selectedExpressionLane) {
                    visibleExpressionLanes.removeAll { $0 == selectedExpressionLane }
                    if visibleExpressionLanes.isEmpty == false {
                        selectedExpressionLane = visibleExpressionLanes[0]
                    }
                } else {
                    visibleExpressionLanes.append(selectedExpressionLane)
                    visibleExpressionLanes.sort { lhs, rhs in
                        MIDINoteExpressionLane.allCases.firstIndex(of: lhs)! < MIDINoteExpressionLane.allCases.firstIndex(of: rhs)!
                    }
                }
            }) {
                Image(systemName: visibleExpressionLanes.contains(selectedExpressionLane) ? "rectangle.bottomthird.inset.filled" : "rectangle.bottomthird.inset")
                    .foregroundStyle(visibleExpressionLanes.contains(selectedExpressionLane) ? Color.primary : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(visibleExpressionLanes.contains(selectedExpressionLane) ? "Hide Active MIDI Lane" : "Show Active MIDI Lane")

            Button("Vel") {
                focusLane(.velocity)
            }
            .buttonStyle(.plain)
            .help("Show and focus velocity lane")

            // Vertical zoom
            Button(action: {
                rowHeight = max(PianoRollLayout.minRowHeight, rowHeight - 2)
            }) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(.plain)
            .help("Vertical Zoom Out")

            Button(action: {
                rowHeight = min(PianoRollLayout.maxRowHeight, rowHeight + 2)
            }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .help("Vertical Zoom In")

            Button("-Range") {
                adjustVisiblePitchSpan(by: -6)
            }
            .buttonStyle(.plain)
            .help("Show fewer notes")

            Button("+Range") {
                adjustVisiblePitchSpan(by: 6)
            }
            .buttonStyle(.plain)
            .help("Show more notes")

            Button(action: {
                fitToContent()
            }) {
                Text("Fit")
            }
            .buttonStyle(.plain)
            .help("Fit pitch range to content")

            Divider().frame(height: 16)

            Button("Done") {
                onDismiss?()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func fitToContent() {
        let padding: UInt8 = 6
        if let low = sequence.lowestPitch, let high = sequence.highestPitch {
            lowPitch = UInt8(max(0, Int(low) - Int(padding)))
            highPitch = UInt8(min(127, Int(high) + Int(padding)))
        }
    }

    private func focusLane(_ lane: MIDINoteExpressionLane) {
        selectedExpressionLane = lane
        if !visibleExpressionLanes.contains(lane) {
            visibleExpressionLanes.append(lane)
            visibleExpressionLanes.sort { lhs, rhs in
                MIDINoteExpressionLane.allCases.firstIndex(of: lhs)! < MIDINoteExpressionLane.allCases.firstIndex(of: rhs)!
            }
        }
    }

    private func adjustVisiblePitchSpan(by semitones: Int) {
        let low = Int(lowPitch)
        let high = Int(highPitch)
        let currentSpan = max(12, high - low + 1)
        let nextSpan = min(84, max(12, currentSpan + semitones))
        let center = low + (currentSpan / 2)
        let newLow = max(0, min(127 - nextSpan + 1, center - (nextSpan / 2)))
        let newHigh = newLow + nextSpan - 1
        lowPitch = UInt8(clamping: newLow)
        highPitch = UInt8(clamping: newHigh)
    }
}

// MARK: - Live Window Content

/// Reactive wrapper for hosting PianoRollView in an NSWindow.
/// Reads the container's MIDI sequence from the live model on every render,
/// so notes added/removed are immediately visible.
struct LivePianoRollWindowContent: View {
    @Bindable var projectViewModel: ProjectViewModel
    let containerID: ID<Container>
    let trackID: ID<Track>
    let timeSignature: TimeSignature
    let snapResolution: SnapResolution
    var transportViewModel: TransportViewModel?
    var onDismiss: (() -> Void)?

    private var container: Container? {
        projectViewModel.findContainer(id: containerID)
            .map { projectViewModel.resolveContainer($0) }
    }

    var body: some View {
        if let container {
            PianoRollView(
                containerID: containerID,
                sequence: container.midiSequence ?? MIDISequence(),
                lengthBars: container.lengthBars,
                timeSignature: timeSignature,
                snapResolution: snapResolution,
                containerStartBar: container.startBar,
                onAddNote: { note in
                    projectViewModel.addMIDINote(containerID: containerID, note: note)
                },
                onUpdateNote: { note in
                    projectViewModel.updateMIDINote(containerID: containerID, note: note)
                },
                onRemoveNote: { noteID in
                    projectViewModel.removeMIDINote(containerID: containerID, noteID: noteID)
                },
                onAddControllerEvent: { event in
                    projectViewModel.addMIDIControllerEvent(containerID: containerID, event: event)
                },
                onUpdateControllerEvent: { event in
                    projectViewModel.updateMIDIControllerEvent(containerID: containerID, event: event)
                },
                onRemoveControllerEvent: { eventID in
                    projectViewModel.removeMIDIControllerEvent(containerID: containerID, eventID: eventID)
                },
                onNotePreview: { pitch, isNoteOn in
                    let message: MIDIActionMessage = isNoteOn
                        ? .noteOn(channel: 0, note: pitch, velocity: 100)
                        : .noteOff(channel: 0, note: pitch, velocity: 0)
                    transportViewModel?.sendVirtualNote(trackID: trackID, message: message)
                },
                onDismiss: onDismiss
            )
        } else {
            Text("Container not found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
