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
    let lengthBars: Int
    let timeSignature: TimeSignature
    let containerStartBar: Int

    var playheadBeat: Double?
    var onAddNote: ((MIDINoteEvent) -> Void)?
    var onUpdateNote: ((MIDINoteEvent) -> Void)?
    var onRemoveNote: ((ID<MIDINoteEvent>) -> Void)?
    var onNotePreview: ((_ pitch: UInt8, _ isNoteOn: Bool) -> Void)?
    /// Called to dismiss the view. When hosted in NSWindow, closes the window.
    var onDismiss: (() -> Void)?

    @State private var selectedNoteIDs: Set<ID<MIDINoteEvent>> = []
    @State private var pixelsPerBeat: CGFloat = PianoRollLayout.defaultPixelsPerBeat
    @State private var lowPitch: UInt8 = PianoRollLayout.defaultLowPitch
    @State private var highPitch: UInt8 = PianoRollLayout.defaultHighPitch
    @State private var rowHeight: CGFloat = PianoRollLayout.defaultRowHeight
    @State private var snapResolution: SnapResolution = .sixteenth

    public init(
        containerID: ID<Container>,
        sequence: MIDISequence,
        lengthBars: Int,
        timeSignature: TimeSignature,
        snapResolution: SnapResolution = .sixteenth,
        containerStartBar: Int = 1,
        playheadBeat: Double? = nil,
        onAddNote: ((MIDINoteEvent) -> Void)? = nil,
        onUpdateNote: ((MIDINoteEvent) -> Void)? = nil,
        onRemoveNote: ((ID<MIDINoteEvent>) -> Void)? = nil,
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
                selectedNoteIDs: $selectedNoteIDs,
                playheadBeat: playheadBeat,
                containerStartBar: containerStartBar,
                onAddNote: onAddNote,
                onUpdateNote: onUpdateNote,
                onRemoveNote: onRemoveNote,
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

            // Fit to content
            Button(action: {
                fitToContent()
            }) {
                Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
            }
            .buttonStyle(.plain)
            .help("Fit to Content")

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

// MARK: - Velocity Editor

/// Bottom lane showing velocity bars for each note.
struct VelocityLaneView: View {
    let sequence: MIDISequence
    let totalBeats: Double
    let pixelsPerBeat: CGFloat
    let height: CGFloat = 60

    var onUpdateVelocity: ((ID<MIDINoteEvent>, UInt8) -> Void)?

    var body: some View {
        Canvas { context, size in
            // Background
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.gray.opacity(0.05))
            )

            // Velocity bars
            for note in sequence.notes {
                let x = PianoRollLayout.xPosition(forBeat: note.startBeat, pixelsPerBeat: pixelsPerBeat)
                let w = max(4, CGFloat(note.duration) * pixelsPerBeat - 1)
                let barHeight = CGFloat(note.velocity) / 127.0 * (size.height - 4)
                let y = size.height - barHeight - 2

                context.fill(
                    Path(CGRect(x: x, y: y, width: w, height: barHeight)),
                    with: .color(.accentColor.opacity(0.6))
                )
            }

            // Horizontal reference lines at 50% and 100%
            let midY = size.height / 2
            context.stroke(
                Path { p in p.move(to: CGPoint(x: 0, y: midY)); p.addLine(to: CGPoint(x: size.width, y: midY)) },
                with: .color(.gray.opacity(0.2)),
                style: StrokeStyle(lineWidth: 0.5, dash: [4, 4])
            )
        }
        .frame(height: height)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let beat = PianoRollLayout.beat(forX: value.location.x, pixelsPerBeat: pixelsPerBeat)
                    let velocity = UInt8(clamping: Int((1.0 - value.location.y / height) * 127))
                    // Find note at this beat position
                    if let note = sequence.notes.first(where: { beat >= $0.startBeat && beat < $0.endBeat }) {
                        onUpdateVelocity?(note.id, max(1, velocity))
                    }
                }
        )
    }
}
