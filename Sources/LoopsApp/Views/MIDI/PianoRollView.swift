import SwiftUI
import LoopsCore

/// Coordinate mapping helpers for the piano roll grid.
enum PianoRollLayout {
    /// Default visible pitch range.
    static let defaultLowPitch: UInt8 = 36  // C2
    static let defaultHighPitch: UInt8 = 96 // C7

    static let rowHeight: CGFloat = 14
    static let keyboardWidth: CGFloat = 48
    static let defaultPixelsPerBeat: CGFloat = 40

    /// Y position for a given pitch (higher pitch = lower Y, piano convention).
    static func yPosition(forPitch pitch: UInt8, lowPitch: UInt8, highPitch: UInt8) -> CGFloat {
        let row = Int(highPitch) - Int(pitch)
        return CGFloat(row) * rowHeight
    }

    /// Pitch for a given Y position.
    static func pitch(forY y: CGFloat, lowPitch: UInt8, highPitch: UInt8) -> UInt8 {
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
    static func totalHeight(lowPitch: UInt8, highPitch: UInt8) -> CGFloat {
        CGFloat(Int(highPitch) - Int(lowPitch) + 1) * rowHeight
    }
}

/// Piano roll note editor for MIDI containers.
/// Vertical axis: pitch (MIDI notes). Horizontal axis: time (beats).
public struct PianoRollView: View {
    let containerID: ID<Container>
    let sequence: MIDISequence
    let lengthBars: Int
    let timeSignature: TimeSignature
    let snapResolution: SnapResolution

    var onAddNote: ((MIDINoteEvent) -> Void)?
    var onUpdateNote: ((MIDINoteEvent) -> Void)?
    var onRemoveNote: ((ID<MIDINoteEvent>) -> Void)?

    @State private var selectedNoteIDs: Set<ID<MIDINoteEvent>> = []
    @State private var dragState: DragState?
    @State private var pixelsPerBeat: CGFloat = PianoRollLayout.defaultPixelsPerBeat
    @State private var lowPitch: UInt8 = PianoRollLayout.defaultLowPitch
    @State private var highPitch: UInt8 = PianoRollLayout.defaultHighPitch

    private var totalBeats: Double {
        Double(lengthBars * timeSignature.beatsPerBar)
    }

    private var totalWidth: CGFloat {
        PianoRollLayout.xPosition(forBeat: totalBeats, pixelsPerBeat: pixelsPerBeat)
    }

    private var totalHeight: CGFloat {
        PianoRollLayout.totalHeight(lowPitch: lowPitch, highPitch: highPitch)
    }

    private enum DragState {
        case moving(noteID: ID<MIDINoteEvent>, startPitch: UInt8, startBeat: Double, offsetBeat: Double, offsetPitch: Int)
        case resizing(noteID: ID<MIDINoteEvent>, originalEnd: Double)
        case creating(pitch: UInt8, startBeat: Double, currentBeat: Double)
    }

    public init(
        containerID: ID<Container>,
        sequence: MIDISequence,
        lengthBars: Int,
        timeSignature: TimeSignature,
        snapResolution: SnapResolution = .sixteenth,
        onAddNote: ((MIDINoteEvent) -> Void)? = nil,
        onUpdateNote: ((MIDINoteEvent) -> Void)? = nil,
        onRemoveNote: ((ID<MIDINoteEvent>) -> Void)? = nil
    ) {
        self.containerID = containerID
        self.sequence = sequence
        self.lengthBars = lengthBars
        self.timeSignature = timeSignature
        self.snapResolution = snapResolution
        self.onAddNote = onAddNote
        self.onUpdateNote = onUpdateNote
        self.onRemoveNote = onRemoveNote
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView([.horizontal, .vertical]) {
                HStack(spacing: 0) {
                    pianoKeyboard
                    ZStack(alignment: .topLeading) {
                        gridBackground
                        notesOverlay
                        interactionLayer
                    }
                    .frame(width: totalWidth, height: totalHeight)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Piano Roll")
                .font(.headline)

            Spacer()

            Text("Snap:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(snapResolution.rawValue)
                .font(.system(.caption, design: .monospaced))

            Divider().frame(height: 16)

            // Zoom controls
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Piano Keyboard (Y-axis labels)

    private var pianoKeyboard: some View {
        VStack(spacing: 0) {
            ForEach((Int(lowPitch)...Int(highPitch)).reversed(), id: \.self) { pitch in
                let note = UInt8(pitch)
                let isBlack = PianoLayout.isBlackKey(note: note)
                let isC = note % 12 == 0
                ZStack {
                    Rectangle()
                        .fill(isBlack ? Color.gray.opacity(0.3) : Color(nsColor: .controlBackgroundColor))
                    if isC || !isBlack {
                        Text(PianoLayout.noteName(note))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(isC ? .primary : .secondary)
                    }
                }
                .frame(width: PianoRollLayout.keyboardWidth, height: PianoRollLayout.rowHeight)
            }
        }
    }

    // MARK: - Grid Background

    private var gridBackground: some View {
        Canvas { context, size in
            let beatsPerBar = timeSignature.beatsPerBar

            // Horizontal lines (pitch rows)
            for pitch in Int(lowPitch)...Int(highPitch) {
                let y = PianoRollLayout.yPosition(forPitch: UInt8(pitch), lowPitch: lowPitch, highPitch: highPitch)
                let isBlack = PianoLayout.isBlackKey(note: UInt8(pitch))
                let isC = UInt8(pitch) % 12 == 0

                // Row background
                if isBlack {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: PianoRollLayout.rowHeight)),
                        with: .color(.gray.opacity(0.08))
                    )
                }
                // C note separator
                if isC {
                    context.stroke(
                        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) },
                        with: .color(.gray.opacity(0.4)),
                        lineWidth: 0.5
                    )
                }
            }

            // Vertical lines (beat/bar grid)
            let totalB = Int(totalBeats)
            for beat in 0...totalB {
                let x = PianoRollLayout.xPosition(forBeat: Double(beat), pixelsPerBeat: pixelsPerBeat)
                let isBarLine = beat % beatsPerBar == 0
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                    with: .color(.gray.opacity(isBarLine ? 0.4 : 0.15)),
                    lineWidth: isBarLine ? 1 : 0.5
                )
            }
        }
        .frame(width: totalWidth, height: totalHeight)
    }

    // MARK: - Notes Overlay

    private var notesOverlay: some View {
        ForEach(sequence.notes) { note in
            noteRect(for: note)
        }
    }

    private func noteRect(for note: MIDINoteEvent) -> some View {
        let x = PianoRollLayout.xPosition(forBeat: note.startBeat, pixelsPerBeat: pixelsPerBeat)
        let y = PianoRollLayout.yPosition(forPitch: note.pitch, lowPitch: lowPitch, highPitch: highPitch)
        let w = CGFloat(note.duration) * pixelsPerBeat
        let isSelected = selectedNoteIDs.contains(note.id)
        let velocityOpacity = 0.4 + Double(note.velocity) / 127.0 * 0.6

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(velocityOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(isSelected ? Color.white : Color.accentColor.opacity(0.8), lineWidth: isSelected ? 1.5 : 0.5)
                )

            // Resize handle on right edge
            Rectangle()
                .fill(Color.clear)
                .frame(width: 6)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
        .frame(width: max(4, w), height: PianoRollLayout.rowHeight - 1)
        .position(x: x + max(4, w) / 2, y: y + PianoRollLayout.rowHeight / 2)
        .gesture(noteDragGesture(note: note))
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.shift) {
                if selectedNoteIDs.contains(note.id) {
                    selectedNoteIDs.remove(note.id)
                } else {
                    selectedNoteIDs.insert(note.id)
                }
            } else {
                selectedNoteIDs = [note.id]
            }
        }
    }

    // MARK: - Gestures

    private func noteDragGesture(note: MIDINoteEvent) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let isResizeArea = value.startLocation.x > (CGFloat(note.duration) * pixelsPerBeat - 6)

                if dragState == nil {
                    if isResizeArea {
                        dragState = .resizing(noteID: note.id, originalEnd: note.endBeat)
                    } else {
                        dragState = .moving(
                            noteID: note.id,
                            startPitch: note.pitch,
                            startBeat: note.startBeat,
                            offsetBeat: 0,
                            offsetPitch: 0
                        )
                    }
                }

                switch dragState {
                case .moving(let id, let startPitch, let startBeat, _, _):
                    let beatDelta = Double(value.translation.width / pixelsPerBeat)
                    let pitchDelta = -Int(value.translation.height / PianoRollLayout.rowHeight)
                    let newBeat = snapResolution.snap(max(0, startBeat + beatDelta))
                    let newPitch = UInt8(clamping: max(Int(lowPitch), min(Int(highPitch), Int(startPitch) + pitchDelta)))
                    var updated = note
                    updated.startBeat = newBeat
                    updated.pitch = newPitch
                    dragState = .moving(noteID: id, startPitch: startPitch, startBeat: startBeat, offsetBeat: beatDelta, offsetPitch: pitchDelta)
                    onUpdateNote?(updated)
                case .resizing(_, let originalEnd):
                    let beatDelta = Double(value.translation.width / pixelsPerBeat)
                    let newEnd = snapResolution.snap(max(note.startBeat + snapResolution.beatsPerUnit, originalEnd + beatDelta))
                    var updated = note
                    updated.duration = newEnd - note.startBeat
                    onUpdateNote?(updated)
                default:
                    break
                }
            }
            .onEnded { _ in
                dragState = nil
            }
    }

    private var interactionLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let beat = snapResolution.snap(PianoRollLayout.beat(forX: value.startLocation.x, pixelsPerBeat: pixelsPerBeat))
                        let pitch = PianoRollLayout.pitch(forY: value.startLocation.y, lowPitch: lowPitch, highPitch: highPitch)
                        let currentBeat = snapResolution.snap(PianoRollLayout.beat(forX: value.location.x, pixelsPerBeat: pixelsPerBeat))

                        if case .creating = dragState {
                            dragState = .creating(pitch: pitch, startBeat: beat, currentBeat: currentBeat)
                        } else {
                            dragState = .creating(pitch: pitch, startBeat: beat, currentBeat: currentBeat)
                        }
                    }
                    .onEnded { value in
                        if case .creating(let pitch, let startBeat, let currentBeat) = dragState {
                            let duration = max(snapResolution.beatsPerUnit, currentBeat - startBeat)
                            let newNote = MIDINoteEvent(
                                pitch: pitch,
                                velocity: 100,
                                startBeat: startBeat,
                                duration: duration
                            )
                            onAddNote?(newNote)
                        }
                        dragState = nil
                    }
            )
            .onTapGesture(count: 2) { location in
                // Double-click to create note
                let beat = snapResolution.snap(PianoRollLayout.beat(forX: location.x, pixelsPerBeat: pixelsPerBeat))
                let pitch = PianoRollLayout.pitch(forY: location.y, lowPitch: lowPitch, highPitch: highPitch)
                let newNote = MIDINoteEvent(
                    pitch: pitch,
                    velocity: 100,
                    startBeat: beat,
                    duration: snapResolution.beatsPerUnit
                )
                onAddNote?(newNote)
            }
            .onTapGesture {
                // Single click on empty space deselects
                selectedNoteIDs.removeAll()
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
