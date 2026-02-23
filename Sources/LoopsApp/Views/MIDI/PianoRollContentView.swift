import SwiftUI
import LoopsCore

/// Drag state for piano roll interactions.
enum PianoRollDragState: Equatable {
    case moving(noteID: ID<MIDINoteEvent>, startPitch: UInt8, startBeat: Double, offsetBeat: Double, offsetPitch: Int)
    case resizing(noteID: ID<MIDINoteEvent>, originalEnd: Double)
    case resizingLeft(noteID: ID<MIDINoteEvent>, originalStart: Double, originalDuration: Double)
    case creating(pitch: UInt8, startBeat: Double, currentBeat: Double)
    case selecting(origin: CGPoint, current: CGPoint)
}

/// Which zone of a note the cursor/click is in.
enum NoteHitZone {
    case leftEdge
    case rightEdge
    case body
}

/// A layer of ghost notes rendered behind the editable notes in the piano roll.
struct PianoRollGhostLayer {
    let notes: [MIDINoteEvent]   // Pre-offset to track-absolute beats
    let opacity: Double          // 0.25 normal ghost, 0.15 linked/inherited
}

/// Observes the vertical scroll offset of the enclosing NSScrollView that directly
/// hosts PianoRollContentView's vertical ScrollView (not the outer track-area scroll).
private struct VerticalScrollObserver: NSViewRepresentable {
    let onOffsetChanged: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-attach if the view moved in the hierarchy (e.g., after layout changes)
        context.coordinator.reattachIfNeeded(from: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOffsetChanged: onOffsetChanged)
    }

    final class Coordinator: NSObject {
        let onOffsetChanged: (CGFloat) -> Void
        private var observation: NSObjectProtocol?
        private weak var observedScrollView: NSScrollView?

        init(onOffsetChanged: @escaping (CGFloat) -> Void) {
            self.onOffsetChanged = onOffsetChanged
        }

        func attach(to view: NSView) {
            // Walk up the view hierarchy to find the nearest NSScrollView
            // whose document is taller than its frame (vertically scrollable).
            // Skip horizontal-only scroll views.
            var candidate: NSView? = view.superview
            while let current = candidate {
                if let sv = current as? NSScrollView,
                   let docHeight = sv.documentView?.frame.height,
                   docHeight > sv.frame.height + 1 {
                    observe(scrollView: sv)
                    return
                }
                candidate = current.superview
            }
        }

        func reattachIfNeeded(from view: NSView) {
            if observedScrollView == nil {
                attach(to: view)
            }
        }

        private func observe(scrollView: NSScrollView) {
            guard observedScrollView !== scrollView else { return }
            // Remove old observation
            if let observation { NotificationCenter.default.removeObserver(observation) }
            observedScrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            // Report initial offset
            onOffsetChanged(-scrollView.contentView.bounds.origin.y)
            observation = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] notification in
                guard let clipView = notification.object as? NSClipView else { return }
                self?.onOffsetChanged(-clipView.bounds.origin.y)
            }
        }

        deinit {
            if let observation { NotificationCenter.default.removeObserver(observation) }
        }
    }
}

/// Reusable piano roll content: grid + notes + gestures + playhead + ruler.
/// Used by both the sheet wrapper (PianoRollView) and inline wrapper (InlinePianoRollView).
///
/// All gestures and hover are handled on the parent container with manual hit testing
/// against note model coordinates. Notes are rendered as a Canvas with no hit testing.
/// This avoids SwiftUI's broken hit testing with `.position()` inside ZStack.
struct PianoRollContentView: View {
    let sequence: MIDISequence
    let lengthBars: Int
    let timeSignature: TimeSignature
    @Binding var snapResolution: SnapResolution
    @Binding var pixelsPerBeat: CGFloat
    @Binding var lowPitch: UInt8
    @Binding var highPitch: UInt8
    @Binding var rowHeight: CGFloat
    @Binding var selectedNoteIDs: Set<ID<MIDINoteEvent>>

    /// Container-relative playhead beat (nil = not visible).
    var playheadBeat: Double?
    /// Absolute bar number for the container start (1-based), used for ruler labels.
    var containerStartBar: Int = 1

    /// Opacity multiplier for note fills (1.0 = full, 0.75 = inline transparency).
    var noteOpacity: Double = 1.0
    /// Whether to show the piano keyboard column on the left.
    var showKeyboard: Bool = true
    /// When true, disables all editing gestures and renders notes at reduced opacity.
    var isReadOnly: Bool = false
    /// Beat offset added to all editable note x-positions (for track-wide display).
    var editableBeatOffset: Double = 0
    /// Ghost note layers rendered behind editable notes (not interactive).
    var ghostLayers: [PianoRollGhostLayer] = []
    /// Constrains note creation/movement to this beat range (track-absolute). Dims areas outside.
    var editableRegion: ClosedRange<Double>?
    /// Called when clicking outside the editable region (beat in track-absolute coords).
    var onClickOutsideEditableRegion: ((Double) -> Void)?
    /// Called when the piano roll gains or loses keyboard focus.
    var onFocusChanged: ((Bool) -> Void)?
    /// Called when the vertical scroll offset changes (for syncing external keyboard labels).
    var onVerticalScrollChanged: ((CGFloat) -> Void)?

    var onAddNote: ((MIDINoteEvent) -> Void)?
    var onUpdateNote: ((MIDINoteEvent) -> Void)?
    var onRemoveNote: ((ID<MIDINoteEvent>) -> Void)?
    var onNotePreview: ((_ pitch: UInt8, _ isNoteOn: Bool) -> Void)?

    @State private var dragState: PianoRollDragState?
    /// Tracks the last preview pitch during move drags to avoid repeated noteOn.
    @State private var lastPreviewPitch: UInt8?
    /// Note currently being hovered (for highlight when nothing is selected).
    @State private var hoveredNoteID: ID<MIDINoteEvent>?
    /// Live previews of notes being dragged (rendered instead of originals).
    /// Maps original note ID to its preview state. Only committed to the model on drag end.
    @State private var dragPreviews: [ID<MIDINoteEvent>: MIDINoteEvent] = [:]
    /// True when Option is held during a move drag (copy instead of move).
    @State private var isCopying = false

    private var effectiveNoteOpacity: Double {
        isReadOnly ? noteOpacity * 0.5 : noteOpacity
    }

    private var totalBeats: Double {
        Double(lengthBars * timeSignature.beatsPerBar)
    }

    private var totalWidth: CGFloat {
        PianoRollLayout.xPosition(forBeat: totalBeats, pixelsPerBeat: pixelsPerBeat)
    }

    private var totalHeight: CGFloat {
        PianoRollLayout.totalHeight(lowPitch: lowPitch, highPitch: highPitch, rowHeight: rowHeight)
    }

    /// Converts a container-relative beat to a display beat (track-absolute).
    private func displayBeat(for note: MIDINoteEvent) -> Double {
        note.startBeat + editableBeatOffset
    }

    /// Converts a display beat (track-absolute) back to container-relative.
    private func containerRelativeBeat(_ beat: Double) -> Double {
        beat - editableBeatOffset
    }

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                if showKeyboard {
                    pianoKeyboard
                }
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        rulerView
                        Divider()
                        ZStack(alignment: .topLeading) {
                            gridBackground
                            editableRegionOverlay
                                .allowsHitTesting(false)
                            notesCanvas
                                .allowsHitTesting(false)
                            creationPreview
                                .allowsHitTesting(false)
                            marqueeOverlay
                                .allowsHitTesting(false)
                            playheadOverlay
                                .allowsHitTesting(false)
                        }
                        .frame(width: totalWidth, height: totalHeight)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            if !isReadOnly { handleHover(phase) }
                        }
                        .gesture(isReadOnly ? nil : unifiedDragGesture)
                        .onTapGesture(count: 2) { location in
                            if !isReadOnly { handleDoubleClick(at: location) }
                        }
                        .onTapGesture { location in
                            if !isReadOnly { handleSingleClick(at: location) }
                        }
                    }
                }
            }
            .background(
                VerticalScrollObserver { offset in
                    onVerticalScrollChanged?(offset)
                }
                .frame(width: 0, height: 0)
            )
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.delete) {
            guard !isReadOnly, !selectedNoteIDs.isEmpty else { return .ignored }
            for noteID in selectedNoteIDs {
                onRemoveNote?(noteID)
            }
            selectedNoteIDs.removeAll()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard !isReadOnly else { return .ignored }
            return moveSelectedNotes(beatDelta: -snapResolution.beatsPerUnit, pitchDelta: 0)
        }
        .onKeyPress(.rightArrow) {
            guard !isReadOnly else { return .ignored }
            return moveSelectedNotes(beatDelta: snapResolution.beatsPerUnit, pitchDelta: 0)
        }
        .onKeyPress(.upArrow) {
            guard !isReadOnly else { return .ignored }
            return moveSelectedNotes(beatDelta: 0, pitchDelta: 1)
        }
        .onKeyPress(.downArrow) {
            guard !isReadOnly else { return .ignored }
            return moveSelectedNotes(beatDelta: 0, pitchDelta: -1)
        }
    }

    // MARK: - Arrow Key Movement

    private func moveSelectedNotes(beatDelta: Double, pitchDelta: Int) -> KeyPress.Result {
        guard !selectedNoteIDs.isEmpty else { return .ignored }
        for noteID in selectedNoteIDs {
            guard let note = sequence.notes.first(where: { $0.id == noteID }) else { continue }
            var updated = note
            updated.startBeat = max(0, note.startBeat + beatDelta)
            if let region = editableRegion {
                let maxBeat = containerRelativeBeat(region.upperBound)
                updated.startBeat = max(0, min(maxBeat - updated.duration, updated.startBeat))
            }
            let newPitch = Int(note.pitch) + pitchDelta
            updated.pitch = UInt8(clamping: max(Int(lowPitch), min(Int(highPitch), newPitch)))
            onUpdateNote?(updated)
            if pitchDelta != 0 {
                onNotePreview?(note.pitch, false)
                onNotePreview?(updated.pitch, true)
                let previewPitch = updated.pitch
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [onNotePreview] in
                    onNotePreview?(previewPitch, false)
                }
            }
        }
        return .handled
    }

    // MARK: - Ruler

    private var rulerView: some View {
        PianoRollRulerView(
            totalBeats: totalBeats,
            pixelsPerBeat: pixelsPerBeat,
            beatsPerBar: timeSignature.beatsPerBar,
            containerStartBar: containerStartBar
        )
        .frame(height: 20)
    }

    // MARK: - Piano Keyboard (locked left)

    private var pianoKeyboard: some View {
        VStack(spacing: 0) {
            Color.clear.frame(width: PianoRollLayout.keyboardWidth, height: 21)
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
                .frame(width: PianoRollLayout.keyboardWidth, height: rowHeight)
            }
        }
    }

    // MARK: - Grid Background

    private var gridBackground: some View {
        Canvas { context, size in
            let beatsPerBar = timeSignature.beatsPerBar

            for pitch in Int(lowPitch)...Int(highPitch) {
                let y = PianoRollLayout.yPosition(forPitch: UInt8(pitch), lowPitch: lowPitch, highPitch: highPitch, rowHeight: rowHeight)
                let isBlack = PianoLayout.isBlackKey(note: UInt8(pitch))
                let isC = UInt8(pitch) % 12 == 0

                if isBlack {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: rowHeight)),
                        with: .color(.gray.opacity(0.08))
                    )
                }
                if isC {
                    context.stroke(
                        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) },
                        with: .color(.gray.opacity(0.4)),
                        lineWidth: 0.5
                    )
                }
            }

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

    // MARK: - Notes Canvas (purely visual, no hit testing)

    private var notesCanvas: some View {
        Canvas { context, _ in
            // Ghost layers (behind editable notes)
            for layer in ghostLayers {
                for note in layer.notes {
                    let gx = PianoRollLayout.xPosition(forBeat: note.startBeat, pixelsPerBeat: pixelsPerBeat)
                    let gy = PianoRollLayout.yPosition(forPitch: note.pitch, lowPitch: lowPitch, highPitch: highPitch, rowHeight: rowHeight)
                    let gw = max(4, CGFloat(note.duration) * pixelsPerBeat)
                    let ghostRect = CGRect(x: gx, y: gy, width: gw, height: rowHeight - 1)
                    let ghostPath = Path(roundedRect: ghostRect, cornerRadius: 2)
                    context.fill(ghostPath, with: .color(.gray.opacity(layer.opacity)))
                    context.stroke(ghostPath, with: .color(.gray.opacity(layer.opacity * 0.8)), lineWidth: 0.5)
                }
            }

            for note in sequence.notes {
                // When copying, render the original at its position;
                // when moving, replace with the drag preview.
                let preview = dragPreviews[note.id]
                let displayNote = (preview != nil && !isCopying) ? preview! : note

                let x = PianoRollLayout.xPosition(forBeat: displayNote.startBeat + editableBeatOffset, pixelsPerBeat: pixelsPerBeat)
                let y = PianoRollLayout.yPosition(forPitch: displayNote.pitch, lowPitch: lowPitch, highPitch: highPitch, rowHeight: rowHeight)
                let w = max(4, CGFloat(displayNote.duration) * pixelsPerBeat)
                let isSelected = selectedNoteIDs.contains(note.id)
                let isHovered = hoveredNoteID == note.id && selectedNoteIDs.isEmpty

                let noteRect = CGRect(x: x, y: y, width: w, height: rowHeight - 1)
                let path = Path(roundedRect: noteRect, cornerRadius: 2)

                let velocityOpacity = 0.4 + Double(displayNote.velocity) / 127.0 * 0.6
                context.fill(path, with: .color(.accentColor.opacity(velocityOpacity * effectiveNoteOpacity)))

                let strokeColor: Color = isSelected ? .white : (isHovered ? .white.opacity(0.6) : .accentColor.opacity(0.8))
                let strokeWidth: CGFloat = isSelected ? 1.5 : (isHovered ? 1.0 : 0.5)
                context.stroke(path, with: .color(strokeColor), lineWidth: strokeWidth)

                if w > 28 && rowHeight >= 12 {
                    let text = Text(PianoLayout.noteName(displayNote.pitch))
                        .font(.system(size: min(rowHeight - 4, 10), design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                    context.draw(text, at: CGPoint(x: x + 4, y: y + rowHeight / 2), anchor: .leading)
                }
            }

            // Draw copy ghosts when Option-dragging
            if isCopying {
                for preview in dragPreviews.values {
                    let px = PianoRollLayout.xPosition(forBeat: preview.startBeat + editableBeatOffset, pixelsPerBeat: pixelsPerBeat)
                    let py = PianoRollLayout.yPosition(forPitch: preview.pitch, lowPitch: lowPitch, highPitch: highPitch, rowHeight: rowHeight)
                    let pw = max(4, CGFloat(preview.duration) * pixelsPerBeat)

                    let previewRect = CGRect(x: px, y: py, width: pw, height: rowHeight - 1)
                    let previewPath = Path(roundedRect: previewRect, cornerRadius: 2)

                    let velocityOpacity = 0.4 + Double(preview.velocity) / 127.0 * 0.6
                    context.fill(previewPath, with: .color(.accentColor.opacity(velocityOpacity * effectiveNoteOpacity)))
                    context.stroke(previewPath, with: .color(.white), lineWidth: 1.5)

                    if pw > 28 && rowHeight >= 12 {
                        let text = Text(PianoLayout.noteName(preview.pitch))
                            .font(.system(size: min(rowHeight - 4, 10), design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                        context.draw(text, at: CGPoint(x: px + 4, y: py + rowHeight / 2), anchor: .leading)
                    }
                }
            }
        }
        .frame(width: totalWidth, height: totalHeight)
    }

    // MARK: - Creation Preview

    @ViewBuilder
    private var creationPreview: some View {
        if case .creating(let pitch, let startBeat, let currentBeat) = dragState {
            let minBeat = min(startBeat, currentBeat)
            let duration = abs(currentBeat - startBeat)
            let x = PianoRollLayout.xPosition(forBeat: minBeat + editableBeatOffset, pixelsPerBeat: pixelsPerBeat)
            let y = PianoRollLayout.yPosition(forPitch: pitch, lowPitch: lowPitch, highPitch: highPitch, rowHeight: rowHeight)
            let w = max(4, CGFloat(duration) * pixelsPerBeat)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
                )
                .frame(width: w, height: rowHeight - 1)
                .position(x: x + w / 2, y: y + rowHeight / 2)
        }
    }

    // MARK: - Marquee Selection Overlay

    @ViewBuilder
    private var marqueeOverlay: some View {
        if case .selecting(let origin, let current) = dragState {
            let rect = CGRect(
                x: min(origin.x, current.x),
                y: min(origin.y, current.y),
                width: abs(current.x - origin.x),
                height: abs(current.y - origin.y)
            )
            Rectangle()
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .background(Color.accentColor.opacity(0.08))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    // MARK: - Editable Region Overlay

    @ViewBuilder
    private var editableRegionOverlay: some View {
        if let region = editableRegion {
            let startX = PianoRollLayout.xPosition(forBeat: region.lowerBound, pixelsPerBeat: pixelsPerBeat)
            let endX = PianoRollLayout.xPosition(forBeat: region.upperBound, pixelsPerBeat: pixelsPerBeat)
            Canvas { context, size in
                // Dim areas outside the editable region
                if startX > 0 {
                    context.fill(
                        Path(CGRect(x: 0, y: 0, width: startX, height: size.height)),
                        with: .color(.black.opacity(0.15))
                    )
                }
                if endX < size.width {
                    context.fill(
                        Path(CGRect(x: endX, y: 0, width: size.width - endX, height: size.height)),
                        with: .color(.black.opacity(0.15))
                    )
                }
                // Accent-colored border lines at region edges
                let borderColor = Color.accentColor.opacity(0.4)
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: startX, y: 0)); p.addLine(to: CGPoint(x: startX, y: size.height)) },
                    with: .color(borderColor),
                    lineWidth: 1
                )
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: endX, y: 0)); p.addLine(to: CGPoint(x: endX, y: size.height)) },
                    with: .color(borderColor),
                    lineWidth: 1
                )
            }
            .frame(width: totalWidth, height: totalHeight)
        }
    }

    // MARK: - Playhead Overlay

    @ViewBuilder
    private var playheadOverlay: some View {
        if let beat = playheadBeat, beat >= 0, beat < totalBeats {
            let x = PianoRollLayout.xPosition(forBeat: beat, pixelsPerBeat: pixelsPerBeat)
            Rectangle()
                .fill(Color.red)
                .frame(width: 1.5, height: totalHeight)
                .offset(x: x)
        }
    }

    // MARK: - Hit Testing

    /// Threshold in pixels for edge resize zones. Returns 0 for notes too small to resize.
    private func edgeThreshold(noteWidth: CGFloat) -> CGFloat {
        noteWidth >= 16 ? min(6, noteWidth * 0.2) : 0
    }

    /// Hit-tests a point against all notes, returning the topmost match and the zone.
    /// Iterates in reverse so later-drawn (higher z) notes are tested first.
    private func hitTestNote(at point: CGPoint) -> (MIDINoteEvent, NoteHitZone)? {
        for note in sequence.notes.reversed() {
            let x = PianoRollLayout.xPosition(forBeat: note.startBeat + editableBeatOffset, pixelsPerBeat: pixelsPerBeat)
            let y = PianoRollLayout.yPosition(forPitch: note.pitch, lowPitch: lowPitch, highPitch: highPitch, rowHeight: rowHeight)
            let w = max(4, CGFloat(note.duration) * pixelsPerBeat)
            let noteRect = CGRect(x: x, y: y, width: w, height: rowHeight)

            guard noteRect.contains(point) else { continue }

            let threshold = edgeThreshold(noteWidth: w)
            let localX = point.x - x

            if threshold > 0 && localX < threshold {
                return (note, .leftEdge)
            } else if threshold > 0 && localX > w - threshold {
                return (note, .rightEdge)
            } else {
                return (note, .body)
            }
        }
        return nil
    }

    // MARK: - Hover

    private func handleHover(_ phase: HoverPhase) {
        switch phase {
        case .active(let location):
            if let (note, zone) = hitTestNote(at: location) {
                hoveredNoteID = note.id
                switch zone {
                case .leftEdge, .rightEdge:
                    NSCursor.resizeLeftRight.set()
                case .body:
                    NSCursor.arrow.set()
                }
            } else {
                hoveredNoteID = nil
                NSCursor.arrow.set()
            }
        case .ended:
            hoveredNoteID = nil
            NSCursor.arrow.set()
        }
    }

    // MARK: - Click Handling

    private func handleSingleClick(at location: CGPoint) {
        if let (note, _) = hitTestNote(at: location) {
            onFocusChanged?(true)
            if NSEvent.modifierFlags.contains(.shift) {
                if selectedNoteIDs.contains(note.id) {
                    selectedNoteIDs.remove(note.id)
                } else {
                    selectedNoteIDs.insert(note.id)
                }
            } else {
                selectedNoteIDs = [note.id]
            }
            // Preview the clicked note
            onNotePreview?(note.pitch, true)
            let pitch = note.pitch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [onNotePreview] in
                onNotePreview?(pitch, false)
            }
        } else {
            if let region = editableRegion {
                let beat = PianoRollLayout.beat(forX: location.x, pixelsPerBeat: pixelsPerBeat)
                if !region.contains(beat) {
                    onClickOutsideEditableRegion?(beat)
                    return
                }
            }
            selectedNoteIDs.removeAll()
            onFocusChanged?(false)
        }
    }

    private func handleDoubleClick(at location: CGPoint) {
        // Double-click on a note could open properties; on empty space creates a note
        if hitTestNote(at: location) != nil { return }
        let snappedDisplayBeat = snapResolution.snap(PianoRollLayout.beat(forX: location.x, pixelsPerBeat: pixelsPerBeat))
        if let region = editableRegion, !region.contains(snappedDisplayBeat) { return }
        let beat = containerRelativeBeat(snappedDisplayBeat)
        let pitch = PianoRollLayout.pitch(forY: location.y, lowPitch: lowPitch, highPitch: highPitch, rowHeight: rowHeight)
        let newNote = MIDINoteEvent(
            pitch: pitch,
            velocity: 100,
            startBeat: beat,
            duration: snapResolution.beatsPerUnit
        )
        onAddNote?(newNote)
        onNotePreview?(pitch, true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [onNotePreview] in
            onNotePreview?(pitch, false)
        }
    }

    // MARK: - Unified Drag Gesture

    private var unifiedDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                // First frame: determine what was clicked
                if dragState == nil {
                    if let (note, zone) = hitTestNote(at: value.startLocation) {
                        switch zone {
                        case .rightEdge:
                            dragState = .resizing(noteID: note.id, originalEnd: note.endBeat)
                        case .leftEdge:
                            dragState = .resizingLeft(noteID: note.id, originalStart: note.startBeat, originalDuration: note.duration)
                        case .body:
                            dragState = .moving(
                                noteID: note.id,
                                startPitch: note.pitch,
                                startBeat: note.startBeat,
                                offsetBeat: 0,
                                offsetPitch: 0
                            )
                            lastPreviewPitch = note.pitch
                            onNotePreview?(note.pitch, true)
                        }
                        // Select the note if not already selected
                        if !selectedNoteIDs.contains(note.id) {
                            selectedNoteIDs = [note.id]
                        }
                        onFocusChanged?(true)
                    } else if NSEvent.modifierFlags.contains(.command) {
                        dragState = .selecting(origin: value.startLocation, current: value.location)
                    } else {
                        let startDisplayBeat = snapResolution.snap(PianoRollLayout.beat(forX: value.startLocation.x, pixelsPerBeat: pixelsPerBeat))
                        if editableRegion == nil || editableRegion!.contains(startDisplayBeat) {
                            let beat = containerRelativeBeat(startDisplayBeat)
                            let pitch = PianoRollLayout.pitch(forY: value.startLocation.y, lowPitch: lowPitch, highPitch: highPitch, rowHeight: rowHeight)
                            let currentBeat = containerRelativeBeat(snapResolution.snap(PianoRollLayout.beat(forX: value.location.x, pixelsPerBeat: pixelsPerBeat)))
                            dragState = .creating(pitch: pitch, startBeat: beat, currentBeat: currentBeat)
                            onNotePreview?(pitch, true)
                        }
                    }
                }

                // Subsequent frames: update the drag preview (no model update yet)
                switch dragState {
                case .moving(let id, let startPitch, let startBeat, _, _):
                    guard sequence.notes.contains(where: { $0.id == id }) else { break }
                    let beatDelta = Double(value.translation.width / pixelsPerBeat)
                    let pitchDelta = -Int(value.translation.height / rowHeight)
                    let snappedBeatOffset = snapResolution.snap(max(0, startBeat + beatDelta)) - startBeat
                    dragState = .moving(noteID: id, startPitch: startPitch, startBeat: startBeat, offsetBeat: beatDelta, offsetPitch: pitchDelta)

                    // Build previews for all selected notes using the same delta
                    var previews: [ID<MIDINoteEvent>: MIDINoteEvent] = [:]
                    for selected in sequence.notes where selectedNoteIDs.contains(selected.id) {
                        var moved = selected
                        moved.startBeat = max(0, selected.startBeat + snappedBeatOffset)
                        if let region = editableRegion {
                            let maxBeat = containerRelativeBeat(region.upperBound)
                            moved.startBeat = max(0, min(maxBeat - moved.duration, moved.startBeat))
                        }
                        moved.pitch = UInt8(clamping: max(Int(lowPitch), min(Int(highPitch), Int(selected.pitch) + pitchDelta)))
                        previews[selected.id] = moved
                    }
                    dragPreviews = previews

                    let optionHeld = NSEvent.modifierFlags.contains(.option)
                    if optionHeld != isCopying {
                        isCopying = optionHeld
                        if optionHeld {
                            NSCursor.dragCopy.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }

                    let anchorPitch = previews[id]?.pitch ?? startPitch
                    if anchorPitch != lastPreviewPitch {
                        if let oldPitch = lastPreviewPitch {
                            onNotePreview?(oldPitch, false)
                        }
                        onNotePreview?(anchorPitch, true)
                        lastPreviewPitch = anchorPitch
                    }

                case .resizing(let id, let originalEnd):
                    guard let note = sequence.notes.first(where: { $0.id == id }) else { break }
                    let beatDelta = Double(value.translation.width / pixelsPerBeat)
                    let newEnd = snapResolution.snap(max(note.startBeat + snapResolution.beatsPerUnit, originalEnd + beatDelta))
                    var updated = note
                    updated.duration = newEnd - note.startBeat
                    dragPreviews = [id: updated]

                case .resizingLeft(let id, let originalStart, let originalDuration):
                    guard let note = sequence.notes.first(where: { $0.id == id }) else { break }
                    let beatDelta = Double(value.translation.width / pixelsPerBeat)
                    let originalEnd = originalStart + originalDuration
                    let newStart = snapResolution.snap(max(0, min(originalEnd - snapResolution.beatsPerUnit, originalStart + beatDelta)))
                    var updated = note
                    updated.startBeat = newStart
                    updated.duration = originalEnd - newStart
                    dragPreviews = [id: updated]

                case .creating(let pitch, let startBeat, _):
                    let currentBeat = containerRelativeBeat(snapResolution.snap(PianoRollLayout.beat(forX: value.location.x, pixelsPerBeat: pixelsPerBeat)))
                    dragState = .creating(pitch: pitch, startBeat: startBeat, currentBeat: currentBeat)

                case .selecting:
                    dragState = .selecting(origin: value.startLocation, current: value.location)

                case .none:
                    break
                }
            }
            .onEnded { value in
                // Commit all drag previews to model
                if !dragPreviews.isEmpty {
                    if isCopying {
                        for preview in dragPreviews.values {
                            var copy = preview
                            copy.id = ID<MIDINoteEvent>()
                            onAddNote?(copy)
                        }
                    } else {
                        for preview in dragPreviews.values {
                            onUpdateNote?(preview)
                        }
                    }
                    dragPreviews = [:]
                }
                if isCopying {
                    NSCursor.arrow.set()
                }
                isCopying = false

                switch dragState {
                case .moving:
                    if let pitch = lastPreviewPitch {
                        onNotePreview?(pitch, false)
                    }
                    lastPreviewPitch = nil

                case .creating(let pitch, let startBeat, let currentBeat):
                    let minBeat = min(startBeat, currentBeat)
                    let duration = max(snapResolution.beatsPerUnit, abs(currentBeat - startBeat))
                    let newNote = MIDINoteEvent(
                        pitch: pitch,
                        velocity: 100,
                        startBeat: minBeat,
                        duration: duration
                    )
                    onAddNote?(newNote)
                    onNotePreview?(pitch, false)

                case .selecting(let origin, _):
                    let endPoint = value.location
                    let rect = CGRect(
                        x: min(origin.x, endPoint.x),
                        y: min(origin.y, endPoint.y),
                        width: abs(endPoint.x - origin.x),
                        height: abs(endPoint.y - origin.y)
                    )
                    var ids = Set<ID<MIDINoteEvent>>()
                    for note in sequence.notes {
                        let nx = PianoRollLayout.xPosition(forBeat: note.startBeat + editableBeatOffset, pixelsPerBeat: pixelsPerBeat)
                        let ny = PianoRollLayout.yPosition(forPitch: note.pitch, lowPitch: lowPitch, highPitch: highPitch, rowHeight: rowHeight)
                        let nw = max(4, CGFloat(note.duration) * pixelsPerBeat)
                        let noteRect = CGRect(x: nx, y: ny, width: nw, height: rowHeight)
                        if rect.intersects(noteRect) {
                            ids.insert(note.id)
                        }
                    }
                    selectedNoteIDs = ids
                    if !ids.isEmpty {
                        onFocusChanged?(true)
                        // Preview the selection as a chord, capped to avoid blowing speakers.
                        // Collect unique pitches sorted low→high, limit to 6 voices.
                        let pitches: [UInt8] = Array(
                            Set(sequence.notes.filter { ids.contains($0.id) }.map(\.pitch))
                        ).sorted().suffix(6)
                        for pitch in pitches {
                            onNotePreview?(pitch, true)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [onNotePreview] in
                            for pitch in pitches {
                                onNotePreview?(pitch, false)
                            }
                        }
                    }

                default:
                    break
                }
                dragState = nil
            }
    }
}

// MARK: - Piano Roll Ruler

/// Beat/bar ruler for the piano roll.
struct PianoRollRulerView: View {
    let totalBeats: Double
    let pixelsPerBeat: CGFloat
    let beatsPerBar: Int
    /// 1-based bar number where the container starts (for absolute labels).
    var containerStartBar: Int = 1

    var body: some View {
        Canvas { context, size in
            let totalB = Int(totalBeats)
            for beat in 0...totalB {
                let x = CGFloat(Double(beat)) * pixelsPerBeat
                let isBarLine = beat % beatsPerBar == 0

                if isBarLine {
                    context.stroke(
                        Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                        with: .color(.gray.opacity(0.5)),
                        lineWidth: 1
                    )
                    let barNumber = containerStartBar + beat / beatsPerBar
                    context.draw(
                        Text("\(barNumber)").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary),
                        at: CGPoint(x: x + 4, y: size.height / 2),
                        anchor: .leading
                    )
                } else {
                    context.stroke(
                        Path { p in p.move(to: CGPoint(x: x, y: size.height * 0.6)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                        with: .color(.gray.opacity(0.2)),
                        lineWidth: 0.5
                    )
                }
            }
        }
        .frame(width: CGFloat(totalBeats) * pixelsPerBeat, height: 20)
    }
}
