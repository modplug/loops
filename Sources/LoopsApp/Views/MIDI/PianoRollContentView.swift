import SwiftUI
import LoopsCore

/// Drag state for piano roll interactions.
enum PianoRollDragState: Equatable {
    case moving(noteID: ID<MIDINoteEvent>, startPitch: UInt8, startBeat: Double, offsetBeat: Double, offsetPitch: Int)
    case resizing(noteID: ID<MIDINoteEvent>, originalEnd: Double)
    case resizingLeft(noteID: ID<MIDINoteEvent>, originalStart: Double, originalDuration: Double)
    case creating(pitch: UInt8, startBeat: Double, currentBeat: Double)
    case selecting(origin: CGPoint, current: CGPoint, additive: Bool)
    case adjustingVelocity(noteIDs: [ID<MIDINoteEvent>], originalNotes: [MIDINoteEvent], startY: CGFloat)
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

private struct PianoRollNoteExpressionLaneDragState {
    let noteIDs: [ID<MIDINoteEvent>]
    let originalNotes: [MIDINoteEvent]
    let startY: CGFloat
}

private struct PianoRollControllerLaneDragState {
    let lane: MIDINoteExpressionLane
    let eventIDs: [ID<MIDIControllerEvent>]
    let originalEvents: [MIDIControllerEvent]
    let startBeat: Double
    let startY: CGFloat
}

private struct PianoRollLaneResizeState {
    let lane: MIDINoteExpressionLane
    let startHeight: CGFloat
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
    let lengthBars: Double
    let timeSignature: TimeSignature
    @Binding var snapResolution: SnapResolution
    @Binding var pixelsPerBeat: CGFloat
    @Binding var lowPitch: UInt8
    @Binding var highPitch: UInt8
    @Binding var rowHeight: CGFloat
    @Binding var selectedTool: MIDITool
    @Binding var selectedExpressionLane: MIDINoteExpressionLane
    @Binding var visibleExpressionLanes: [MIDINoteExpressionLane]
    @Binding var noteExpressionLaneHeights: [MIDINoteExpressionLane: CGFloat]
    @Binding var selectedNoteIDs: Set<ID<MIDINoteEvent>>

    /// Container-relative playhead beat (nil = not visible).
    var playheadBeat: Double?
    /// Absolute bar number for the container start (1-based), used for ruler labels.
    var containerStartBar: Double = 1.0

    /// Opacity multiplier for note fills (1.0 = full, 0.75 = inline transparency).
    var noteOpacity: Double = 1.0
    /// Whether to show the piano keyboard column on the left.
    var showKeyboard: Bool = true
    /// When true, disables all editing gestures and renders notes at reduced opacity.
    var isReadOnly: Bool = false
    /// When true, wraps content in its own horizontal ScrollView. Set false for inline use
    /// where the parent already provides horizontal scrolling (e.g., timeline ScrollView).
    var useOwnHorizontalScroll: Bool = true
    /// When false, hides the ruler bar indicator at the top. Inline mode uses the timeline ruler.
    var showRuler: Bool = true
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
    var onAddControllerEvent: ((MIDIControllerEvent) -> Void)?
    var onUpdateControllerEvent: ((MIDIControllerEvent) -> Void)?
    var onRemoveControllerEvent: ((ID<MIDIControllerEvent>) -> Void)?
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
    @State private var noteExpressionLaneDragState: PianoRollNoteExpressionLaneDragState?
    @State private var controllerLaneDragState: PianoRollControllerLaneDragState?
    @State private var laneResizeState: PianoRollLaneResizeState?
    @State private var laneResizePreviewHeights: [MIDINoteExpressionLane: CGFloat] = [:]
    @State private var selectedControllerEventIDs: Set<ID<MIDIControllerEvent>> = []
    @State private var controllerEventDragPreviews: [ID<MIDIControllerEvent>: MIDIControllerEvent] = [:]

    private var effectiveNoteOpacity: Double {
        isReadOnly ? noteOpacity * 0.5 : noteOpacity
    }

    private var totalBeats: Double {
        lengthBars * Double(timeSignature.beatsPerBar)
    }

    private var totalWidth: CGFloat {
        PianoRollLayout.xPosition(forBeat: totalBeats, pixelsPerBeat: pixelsPerBeat)
    }

    private var totalHeight: CGFloat {
        PianoRollLayout.totalHeight(lowPitch: lowPitch, highPitch: highPitch, rowHeight: rowHeight)
    }

    private func noteExpressionLaneHeight(for lane: MIDINoteExpressionLane) -> CGFloat {
        laneResizePreviewHeights[lane] ?? noteExpressionLaneHeights[lane] ?? defaultNoteExpressionLaneHeight(for: lane)
    }

    private var selectedNotesInSequence: [MIDINoteEvent] {
        sequence.notes.filter { selectedNoteIDs.contains($0.id) }
    }

    private func defaultNoteExpressionLaneHeight(for lane: MIDINoteExpressionLane) -> CGFloat {
        switch lane {
        case .velocity:
            return 96
        case .channel:
            return 84
        case .sustain:
            return 72
        case .expression:
            return 96
        }
    }

    private func noteExpressionUpperLabel(for lane: MIDINoteExpressionLane) -> String {
        switch lane {
        case .velocity:
            return "127"
        case .channel:
            return "16"
        case .sustain:
            return "On"
        case .expression:
            return "127"
        }
    }

    private func noteExpressionLowerLabel(for lane: MIDINoteExpressionLane) -> String {
        switch lane {
        case .velocity, .expression:
            return "0"
        case .channel:
            return "1"
        case .sustain:
            return "Off"
        }
    }

    private func noteExpressionSummaryLabel(for lane: MIDINoteExpressionLane) -> String {
        switch lane {
        case .velocity:
            let notes = selectedNotesInSequence
            guard !notes.isEmpty else { return lane.label }
            let average = Int((notes.map { Int($0.velocity) }.reduce(0, +) / max(notes.count, 1)))
            return notes.count == 1 ? "Vel \(average)" : "\(notes.count) notes · avg \(average)"
        case .channel:
            let notes = selectedNotesInSequence
            guard !notes.isEmpty else { return lane.label }
            let uniqueChannels = Set(notes.map { Int($0.channel) + 1 }).sorted()
            if uniqueChannels.count == 1, let channel = uniqueChannels.first {
                return "Ch \(channel)"
            }
            return "\(uniqueChannels.count) ch"
        case .sustain, .expression:
            let events = selectedControllerEvents(in: lane)
            if let event = events.first, events.count == 1 {
                return "\(lane.shortLabel) \(event.value)"
            }
            if !events.isEmpty {
                let average = Int(events.map { Int($0.value) }.reduce(0, +) / max(events.count, 1))
                return "\(events.count) pts · avg \(average)"
            }
            return "\(controllerEvents(for: lane).count) pts"
        }
    }

    /// Converts a container-relative beat to a display beat (track-absolute).
    private func displayBeat(for note: MIDINoteEvent) -> Double {
        note.startBeat + editableBeatOffset
    }

    /// Converts a display beat (track-absolute) back to container-relative.
    private func containerRelativeBeat(_ beat: Double) -> Double {
        beat - editableBeatOffset
    }

    private var pianoRollContent: some View {
        VStack(spacing: 0) {
            if showRuler {
                rulerView
                Divider()
            }
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

            if !visibleExpressionLanes.isEmpty {
                ForEach(visibleExpressionLanes, id: \.self) { lane in
                    Divider()
                    noteExpressionLane(lane)
                }
            }
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                if showKeyboard {
                    VStack(spacing: 0) {
                        pianoKeyboard
                        if !visibleExpressionLanes.isEmpty {
                            ForEach(visibleExpressionLanes, id: \.self) { lane in
                                noteExpressionSidebar(for: lane)
                            }
                        }
                    }
                }
                if useOwnHorizontalScroll {
                    ScrollView(.horizontal) {
                        pianoRollContent
                    }
                } else {
                    pianoRollContent
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
            guard !isReadOnly else { return .ignored }
            let hasSelectedNotes = !selectedNoteIDs.isEmpty
            let hasSelectedControllerEvents = !selectedControllerEventIDs.isEmpty
            guard hasSelectedNotes || hasSelectedControllerEvents else { return .ignored }
            for noteID in selectedNoteIDs {
                onRemoveNote?(noteID)
            }
            selectedNoteIDs.removeAll()
            for eventID in selectedControllerEventIDs {
                onRemoveControllerEvent?(eventID)
            }
            selectedControllerEventIDs.removeAll()
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
            containerStartBar: Int(containerStartBar)
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
                PianoRollKeyboardRow(
                    note: note,
                    rowHeight: rowHeight,
                    isBlack: isBlack,
                    isC: isC
                )
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.17, blue: 0.19),
                    Color(red: 0.08, green: 0.09, blue: 0.11)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
    }

    private func noteExpressionSidebar(for lane: MIDINoteExpressionLane) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.13, blue: 0.16),
                                Color(red: 0.07, green: 0.08, blue: 0.10)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Label(lane.shortLabel, systemImage: lane.iconName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.84))

                    Text(noteExpressionUpperLabel(for: lane))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.38))

                    Spacer()

                    Text(noteExpressionSummaryLabel(for: lane))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle((selectedExpressionLane == lane ? laneColor(for: lane) : Color.white).opacity(0.85))
                        .lineLimit(2)

                    Text(noteExpressionLowerLabel(for: lane))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.32))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            .frame(width: PianoRollLayout.keyboardWidth, height: noteExpressionLaneHeight(for: lane))

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: PianoRollLayout.keyboardWidth, height: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedExpressionLane = lane
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
    }

    // MARK: - Grid Background

    private var gridBackground: some View {
        Canvas { context, size in
            let backgroundRect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(backgroundRect),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.15, green: 0.17, blue: 0.21),
                        Color(red: 0.10, green: 0.11, blue: 0.14)
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )

            let beatsPerBar = timeSignature.beatsPerBar

            for pitch in Int(lowPitch)...Int(highPitch) {
                let y = PianoRollLayout.yPosition(forPitch: UInt8(pitch), lowPitch: lowPitch, highPitch: highPitch, rowHeight: rowHeight)
                let isBlack = PianoLayout.isBlackKey(note: UInt8(pitch))
                let isC = UInt8(pitch) % 12 == 0
                let rowRect = CGRect(x: 0, y: y, width: size.width, height: rowHeight)

                context.fill(
                    Path(rowRect),
                    with: .color(
                        isBlack
                        ? Color.black.opacity(0.22)
                        : Color.white.opacity(((pitch - Int(lowPitch)) % 2 == 0) ? 0.02 : 0.012)
                    )
                )

                if rowHeight >= 10 {
                    context.fill(
                        Path(CGRect(x: 0, y: y + max(1, rowHeight * 0.12), width: size.width, height: max(1, rowHeight * 0.08))),
                        with: .color(isBlack ? Color.white.opacity(0.02) : Color.black.opacity(0.05))
                    )
                }

                if isC {
                    context.stroke(
                        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) },
                        with: .color(Color(red: 0.28, green: 0.56, blue: 0.86).opacity(0.28)),
                        lineWidth: 0.8
                    )
                    context.stroke(
                        Path { p in p.move(to: CGPoint(x: 0, y: y + rowHeight - 1)); p.addLine(to: CGPoint(x: size.width, y: y + rowHeight - 1)) },
                        with: .color(Color.white.opacity(0.04)),
                        lineWidth: 0.5
                    )
                }
            }

            let totalB = Int(totalBeats)
            for beat in 0...totalB {
                let x = PianoRollLayout.xPosition(forBeat: Double(beat), pixelsPerBeat: pixelsPerBeat)
                let isBarLine = beat % beatsPerBar == 0
                let isHalfBeat = pixelsPerBeat >= 42 && beat < totalB
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                    with: .color(isBarLine ? Color.white.opacity(0.20) : Color.white.opacity(0.055)),
                    lineWidth: isBarLine ? 1.0 : 0.6
                )

                if isHalfBeat {
                    let halfBeatX = x + (pixelsPerBeat * 0.5)
                    context.stroke(
                        Path { p in p.move(to: CGPoint(x: halfBeatX, y: 0)); p.addLine(to: CGPoint(x: halfBeatX, y: size.height)) },
                        with: .color(Color.white.opacity(0.022)),
                        lineWidth: 0.5
                    )
                }
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
                let noteBodyRect = noteRect.insetBy(dx: 1, dy: 1)
                let outerPath = Path(roundedRect: noteRect, cornerRadius: max(1.2, min(rowHeight * 0.16, 3.5)))
                let bodyPath = Path(roundedRect: noteBodyRect, cornerRadius: max(1.0, min(rowHeight * 0.12, 3.0)))
                let velocityFactor = Double(displayNote.velocity) / 127.0
                let baseColor = Color.accentColor
                let bodyOpacity = (0.58 + velocityFactor * 0.28) * effectiveNoteOpacity

                context.fill(
                    outerPath,
                    with: .color(Color.black.opacity(isSelected ? 0.48 : 0.30))
                )
                context.fill(
                    bodyPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            baseColor.opacity(bodyOpacity + 0.10),
                            baseColor.opacity(bodyOpacity)
                        ]),
                        startPoint: CGPoint(x: noteBodyRect.minX, y: noteBodyRect.minY),
                        endPoint: CGPoint(x: noteBodyRect.maxX, y: noteBodyRect.maxY)
                    )
                )
                context.fill(
                    Path(roundedRect: CGRect(
                        x: noteBodyRect.minX,
                        y: noteBodyRect.minY,
                        width: noteBodyRect.width,
                        height: max(1, min(noteBodyRect.height * 0.22, 4))
                    ), cornerRadius: 1.4),
                    with: .color(Color.white.opacity(isSelected ? 0.32 : 0.20))
                )

                let strokeColor: Color = isSelected
                    ? .white.opacity(0.92)
                    : (isHovered ? .white.opacity(0.52) : baseColor.opacity(0.56))
                context.stroke(outerPath, with: .color(strokeColor), lineWidth: isSelected ? 1.3 : 0.75)

                if w > 28 && rowHeight >= 12 {
                    let text = Text(PianoLayout.noteName(displayNote.pitch))
                        .font(.system(size: min(rowHeight - 4, 10), weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(isSelected ? 0.95 : 0.78))
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
                    let previewOuter = Path(roundedRect: previewRect, cornerRadius: max(1.2, min(rowHeight * 0.16, 3.5)))
                    let previewInnerRect = previewRect.insetBy(dx: 1, dy: 1)
                    let previewInner = Path(roundedRect: previewInnerRect, cornerRadius: max(1.0, min(rowHeight * 0.12, 3.0)))

                    context.fill(previewOuter, with: .color(Color.black.opacity(0.34)))
                    context.fill(previewInner, with: .color(Color.accentColor.opacity(0.74 * effectiveNoteOpacity)))
                    context.fill(
                        Path(roundedRect: CGRect(
                            x: previewInnerRect.minX,
                            y: previewInnerRect.minY,
                            width: previewInnerRect.width,
                            height: max(1, min(previewInnerRect.height * 0.22, 4))
                        ), cornerRadius: 1.4),
                        with: .color(Color.white.opacity(0.26))
                    )
                    context.stroke(previewOuter, with: .color(.white.opacity(0.94)), lineWidth: 1.4)

                    if pw > 28 && rowHeight >= 12 {
                        let text = Text(PianoLayout.noteName(preview.pitch))
                            .font(.system(size: min(rowHeight - 4, 10), weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.84))
                        context.draw(text, at: CGPoint(x: px + 4, y: py + rowHeight / 2), anchor: .leading)
                    }
                }
            }
        }
        .frame(width: totalWidth, height: totalHeight)
    }

    private func noteExpressionLane(_ lane: MIDINoteExpressionLane) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                noteExpressionLaneBackground(for: lane)
                noteExpressionLaneCanvas(for: lane)
            }
            .frame(width: totalWidth, height: noteExpressionLaneHeight(for: lane))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { location in
                guard !isReadOnly else { return }
                handleNoteExpressionLaneDoubleClick(at: location, lane: lane)
            }
            .onTapGesture { location in
                guard !isReadOnly else { return }
                handleNoteExpressionLaneClick(at: location, lane: lane)
            }
            .gesture(isReadOnly ? nil : noteExpressionLaneDragGesture(for: lane))

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 4)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if laneResizeState?.lane != lane {
                                laneResizeState = PianoRollLaneResizeState(lane: lane, startHeight: noteExpressionLaneHeight(for: lane))
                            }
                            let startHeight = laneResizeState?.startHeight ?? noteExpressionLaneHeight(for: lane)
                            laneResizePreviewHeights[lane] = min(
                                max(startHeight + value.translation.height, PianoRollLayout.minDetailLaneHeight),
                                PianoRollLayout.maxDetailLaneHeight
                            )
                        }
                        .onEnded { _ in
                            let height = laneResizePreviewHeights[lane] ?? noteExpressionLaneHeight(for: lane)
                            noteExpressionLaneHeights[lane] = min(
                                max(height, PianoRollLayout.minDetailLaneHeight),
                                PianoRollLayout.maxDetailLaneHeight
                            )
                            laneResizePreviewHeights.removeValue(forKey: lane)
                            laneResizeState = nil
                        }
                )
        }
    }

    private func noteExpressionLaneBackground(for lane: MIDINoteExpressionLane) -> some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.11, green: 0.12, blue: 0.15),
                        Color(red: 0.08, green: 0.09, blue: 0.11)
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )

            let beatsPerBar = timeSignature.beatsPerBar
            let totalB = Int(totalBeats)
            for beat in 0...totalB {
                let x = PianoRollLayout.xPosition(forBeat: Double(beat), pixelsPerBeat: pixelsPerBeat)
                let isBarLine = beat % beatsPerBar == 0
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(isBarLine ? Color.white.opacity(0.12) : Color.white.opacity(0.035)),
                    lineWidth: isBarLine ? 1 : 0.5
                )
            }

            for fraction: CGFloat in [0.25, 0.5, 0.75] {
                let y = size.height - 8 - ((size.height - 16) * fraction)
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    },
                    with: .color(Color.white.opacity(fraction == 0.5 ? 0.10 : 0.05)),
                    lineWidth: 0.5
                )
            }

            if lane == .channel {
                let bands = 16
                let usableHeight = size.height - 16
                let bandHeight = usableHeight / CGFloat(bands)
                for channel in 0..<bands {
                    let y = size.height - 8 - (CGFloat(channel + 1) * bandHeight)
                    context.stroke(
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: size.width, y: y))
                        },
                        with: .color(Color.white.opacity(channel % 4 == 0 ? 0.08 : 0.035)),
                        lineWidth: 0.5
                    )
                }
            } else if lane == .sustain {
                let midpoint = noteExpressionCenterY(forNormalizedValue: 0.5, laneHeight: size.height)
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: midpoint))
                        p.addLine(to: CGPoint(x: size.width, y: midpoint))
                    },
                    with: .color(Color.white.opacity(0.08)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            }
        }
    }

    private func noteExpressionLaneCanvas(for lane: MIDINoteExpressionLane) -> some View {
        if lane.isControllerLane {
            return AnyView(controllerLaneCanvas(for: lane))
        }
        return AnyView(noteAttributeLaneCanvas(for: lane))
    }

    private func noteAttributeLaneCanvas(for lane: MIDINoteExpressionLane) -> some View {
        Canvas { context, size in
            let laneBottom = size.height - 7
            for note in sequence.notes {
                let displayNote = displayNoteForRendering(note)
                let handleRect = noteExpressionHandleRect(for: displayNote, lane: lane)
                let barX = handleRect.midX
                let isSelected = selectedNoteIDs.contains(note.id)
                let isHovered = hoveredNoteID == note.id && selectedNoteIDs.isEmpty
                let laneColor = laneColor(for: lane)
                let stemColor = laneColor.opacity(isSelected ? 0.92 : 0.64)
                let handleColor = isSelected
                    ? Color.white.opacity(0.96)
                    : (isHovered ? Color.white.opacity(0.72) : laneColor.opacity(0.92))

                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: barX, y: laneBottom))
                        p.addLine(to: CGPoint(x: barX, y: handleRect.midY))
                    },
                    with: .color(stemColor),
                    lineWidth: isSelected ? 2.2 : 1.4
                )

                context.fill(
                    Path(ellipseIn: handleRect),
                    with: .color(handleColor)
                )
                context.stroke(
                    Path(ellipseIn: handleRect.insetBy(dx: -0.5, dy: -0.5)),
                    with: .color(Color.black.opacity(0.34)),
                    lineWidth: 1
                )
            }

            if !selectedNotesInSequence.isEmpty {
                let normalized = averageSelectedExpressionNormalizedValue(for: lane)
                let y = noteExpressionCenterY(forNormalizedValue: normalized, laneHeight: noteExpressionLaneHeight(for: lane))
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    },
                    with: .color(laneColor(for: lane).opacity(0.18)),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
            }
        }
    }

    private func controllerLaneCanvas(for lane: MIDINoteExpressionLane) -> some View {
        Canvas { context, size in
            let events = controllerEvents(for: lane)
            let laneBottom = size.height - 7
            let color = laneColor(for: lane)

            if events.count >= 2 {
                var path = Path()
                let first = displayControllerEventForRendering(events[0])
                var previousPoint = CGPoint(
                    x: controllerEventX(for: first),
                    y: noteExpressionCenterY(
                        forNormalizedValue: controllerEventNormalizedValue(for: first, lane: lane),
                        laneHeight: noteExpressionLaneHeight(for: lane)
                    )
                )
                path.move(to: previousPoint)
                for event in events.dropFirst() {
                    let displayEvent = displayControllerEventForRendering(event)
                    let nextPoint = CGPoint(
                        x: controllerEventX(for: displayEvent),
                        y: noteExpressionCenterY(
                            forNormalizedValue: controllerEventNormalizedValue(for: displayEvent, lane: lane),
                            laneHeight: noteExpressionLaneHeight(for: lane)
                        )
                    )
                    if lane == .sustain {
                        path.addLine(to: CGPoint(x: nextPoint.x, y: previousPoint.y))
                    }
                    path.addLine(to: nextPoint)
                    previousPoint = nextPoint
                }
                context.stroke(path, with: .color(color.opacity(0.36)), lineWidth: lane == .sustain ? 2.2 : 1.6)
            }

            for event in events {
                let displayEvent = displayControllerEventForRendering(event)
                let handleRect = controllerEventHandleRect(for: displayEvent, lane: lane)
                let barX = handleRect.midX
                let isSelected = selectedControllerEventIDs.contains(event.id)
                let stemColor = color.opacity(isSelected ? 0.94 : 0.66)
                let handleColor = isSelected ? Color.white.opacity(0.96) : color.opacity(0.92)

                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: barX, y: laneBottom))
                        p.addLine(to: CGPoint(x: barX, y: handleRect.midY))
                    },
                    with: .color(stemColor),
                    lineWidth: isSelected ? 2.2 : 1.4
                )

                if lane == .sustain {
                    let width = max(8, pixelsPerBeat * 0.35)
                    let blockRect = CGRect(
                        x: handleRect.midX - (width * 0.5),
                        y: handleRect.midY - 4,
                        width: width,
                        height: 8
                    )
                    context.fill(
                        Path(roundedRect: blockRect, cornerRadius: 2),
                        with: .color(handleColor.opacity(displayEvent.value >= 64 ? 0.95 : 0.55))
                    )
                }

                context.fill(Path(ellipseIn: handleRect), with: .color(handleColor))
                context.stroke(
                    Path(ellipseIn: handleRect.insetBy(dx: -0.5, dy: -0.5)),
                    with: .color(Color.black.opacity(0.34)),
                    lineWidth: 1
                )
            }

            if !selectedControllerEvents(in: lane).isEmpty {
                let normalized = averageSelectedExpressionNormalizedValue(for: lane)
                let y = noteExpressionCenterY(forNormalizedValue: normalized, laneHeight: noteExpressionLaneHeight(for: lane))
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    },
                    with: .color(color.opacity(0.18)),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
            }
        }
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
        if case .selecting(let origin, let current, _) = dragState {
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

    private func displayNoteForRendering(_ note: MIDINoteEvent) -> MIDINoteEvent {
        if let preview = dragPreviews[note.id], !isCopying {
            return preview
        }
        return note
    }

    private func velocityAnchorX(for note: MIDINoteEvent) -> CGFloat {
        let x = PianoRollLayout.xPosition(forBeat: note.startBeat + editableBeatOffset, pixelsPerBeat: pixelsPerBeat)
        let width = max(4, CGFloat(note.duration) * pixelsPerBeat)
        let leadingAnchor = min(max(6, width * 0.18), max(width - 4, 2))
        return x + leadingAnchor
    }

    private func controllerEvents(for lane: MIDINoteExpressionLane) -> [MIDIControllerEvent] {
        guard let controller = lane.controllerNumber else { return [] }
        return sequence.sortedControllerEvents.filter { $0.controller == controller }
    }

    private func displayControllerEventForRendering(_ event: MIDIControllerEvent) -> MIDIControllerEvent {
        controllerEventDragPreviews[event.id] ?? event
    }

    private func selectedControllerEvents(in lane: MIDINoteExpressionLane) -> [MIDIControllerEvent] {
        controllerEvents(for: lane).filter { selectedControllerEventIDs.contains($0.id) }
    }

    private func controllerEventX(for event: MIDIControllerEvent) -> CGFloat {
        PianoRollLayout.xPosition(forBeat: event.beat + editableBeatOffset, pixelsPerBeat: pixelsPerBeat)
    }

    private func laneColor(for lane: MIDINoteExpressionLane) -> Color {
        switch lane {
        case .velocity:
            return .accentColor
        case .channel:
            return Color(red: 0.48, green: 0.80, blue: 0.94)
        case .sustain:
            return Color(red: 0.53, green: 0.86, blue: 0.58)
        case .expression:
            return Color(red: 0.94, green: 0.72, blue: 0.38)
        }
    }

    private func averageSelectedExpressionNormalizedValue(for lane: MIDINoteExpressionLane) -> CGFloat {
        let values: [CGFloat]
        if lane.isControllerLane {
            let events = selectedControllerEvents(in: lane)
            guard !events.isEmpty else { return 0 }
            values = events.map { controllerEventNormalizedValue(for: $0, lane: lane) }
        } else {
            let notes = selectedNotesInSequence
            guard !notes.isEmpty else { return 0 }
            values = notes.map { noteExpressionNormalizedValue(for: $0, lane: lane) }
        }
        return values.reduce(0, +) / CGFloat(values.count)
    }

    private func noteExpressionNormalizedValue(for note: MIDINoteEvent, lane: MIDINoteExpressionLane) -> CGFloat {
        switch lane {
        case .velocity:
            return CGFloat(max(1, Int(note.velocity))) / 127.0
        case .channel:
            return CGFloat(max(0, Int(note.channel))) / 15.0
        case .sustain, .expression:
            return 0
        }
    }

    private func controllerEventNormalizedValue(for event: MIDIControllerEvent, lane: MIDINoteExpressionLane) -> CGFloat {
        switch lane {
        case .sustain:
            return event.value >= 64 ? 1.0 : 0.0
        case .expression:
            return CGFloat(event.value) / 127.0
        case .velocity, .channel:
            return 0
        }
    }

    private func controllerEventValue(for lane: MIDINoteExpressionLane, normalized: CGFloat) -> UInt8 {
        switch lane {
        case .sustain:
            return normalized >= 0.5 ? 127 : 0
        case .expression:
            return UInt8(clamping: Int((max(0, min(normalized, 1)) * 127.0).rounded()))
        case .velocity, .channel:
            return 0
        }
    }

    private func noteExpressionCenterY(forNormalizedValue normalized: CGFloat, laneHeight: CGFloat) -> CGFloat {
        let topPadding: CGFloat = 10
        let bottomPadding: CGFloat = 8
        let usableHeight = max(12, laneHeight - topPadding - bottomPadding)
        return (laneHeight - bottomPadding) - (usableHeight * max(0, min(normalized, 1)))
    }

    private func noteExpressionHandleRect(for note: MIDINoteEvent, lane: MIDINoteExpressionLane) -> CGRect {
        let centerY = noteExpressionCenterY(
            forNormalizedValue: noteExpressionNormalizedValue(for: note, lane: lane),
            laneHeight: noteExpressionLaneHeight(for: lane)
        )
        let diameter: CGFloat = selectedNoteIDs.contains(note.id) ? 8.5 : 7
        return CGRect(
            x: velocityAnchorX(for: note) - (diameter * 0.5),
            y: centerY - (diameter * 0.5),
            width: diameter,
            height: diameter
        )
    }

    private func controllerEventHandleRect(for event: MIDIControllerEvent, lane: MIDINoteExpressionLane) -> CGRect {
        let displayEvent = displayControllerEventForRendering(event)
        let centerY = noteExpressionCenterY(
            forNormalizedValue: controllerEventNormalizedValue(for: displayEvent, lane: lane),
            laneHeight: noteExpressionLaneHeight(for: lane)
        )
        let diameter: CGFloat = selectedControllerEventIDs.contains(event.id) ? 8.5 : 7
        return CGRect(
            x: controllerEventX(for: displayEvent) - (diameter * 0.5),
            y: centerY - (diameter * 0.5),
            width: diameter,
            height: diameter
        )
    }

    private func hitTestNoteExpressionLane(at point: CGPoint, lane: MIDINoteExpressionLane) -> MIDINoteEvent? {
        let sorted = sequence.notes.sorted { lhs, rhs in
            velocityAnchorX(for: displayNoteForRendering(lhs)) > velocityAnchorX(for: displayNoteForRendering(rhs))
        }
        for note in sorted {
            let displayNote = displayNoteForRendering(note)
            let handleRect = noteExpressionHandleRect(for: displayNote, lane: lane)
            let stemRect = CGRect(
                x: handleRect.midX - 4,
                y: handleRect.minY,
                width: 8,
                height: noteExpressionLaneHeight(for: lane) - handleRect.minY
            )
            if handleRect.insetBy(dx: -6, dy: -6).contains(point) || stemRect.contains(point) {
                return note
            }
        }
        return nil
    }

    private func hitTestControllerEvent(at point: CGPoint, lane: MIDINoteExpressionLane) -> MIDIControllerEvent? {
        let sorted = controllerEvents(for: lane).sorted { lhs, rhs in
            controllerEventX(for: displayControllerEventForRendering(lhs)) > controllerEventX(for: displayControllerEventForRendering(rhs))
        }
        for event in sorted {
            let handleRect = controllerEventHandleRect(for: event, lane: lane)
            let stemRect = CGRect(
                x: handleRect.midX - 4,
                y: handleRect.minY,
                width: 8,
                height: noteExpressionLaneHeight(for: lane) - handleRect.minY
            )
            if handleRect.insetBy(dx: -6, dy: -6).contains(point) || stemRect.contains(point) {
                return event
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
                if selectedTool == .pencil {
                    NSCursor.crosshair.set()
                } else {
                    NSCursor.arrow.set()
                }
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
            selectedControllerEventIDs.removeAll()
            if NSEvent.modifierFlags.contains(.command) {
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
            selectedControllerEventIDs.removeAll()
            onFocusChanged?(false)
        }
    }

    private func handleNoteExpressionLaneClick(at location: CGPoint, lane: MIDINoteExpressionLane) {
        selectedExpressionLane = lane
        if lane.isControllerLane {
            guard let event = hitTestControllerEvent(at: location, lane: lane) else {
                selectedControllerEventIDs.removeAll()
                return
            }
            if NSEvent.modifierFlags.contains(.option) {
                onRemoveControllerEvent?(event.id)
                selectedControllerEventIDs.remove(event.id)
                return
            }
            selectedNoteIDs.removeAll()
            onFocusChanged?(true)
            if NSEvent.modifierFlags.contains(.command) {
                if selectedControllerEventIDs.contains(event.id) {
                    selectedControllerEventIDs.remove(event.id)
                } else {
                    selectedControllerEventIDs.insert(event.id)
                }
            } else {
                selectedControllerEventIDs = [event.id]
            }
            return
        }
        selectedControllerEventIDs.removeAll()
        guard let note = hitTestNoteExpressionLane(at: location, lane: lane) else { return }
        onFocusChanged?(true)
        if NSEvent.modifierFlags.contains(.command) {
            if selectedNoteIDs.contains(note.id) {
                selectedNoteIDs.remove(note.id)
            } else {
                selectedNoteIDs.insert(note.id)
            }
        } else {
            selectedNoteIDs = [note.id]
        }
    }

    private func handleNoteExpressionLaneDoubleClick(at location: CGPoint, lane: MIDINoteExpressionLane) {
        guard lane.isControllerLane, let controller = lane.controllerNumber else { return }
        if hitTestControllerEvent(at: location, lane: lane) != nil { return }

        let snappedDisplayBeat = snapResolution.snap(PianoRollLayout.beat(forX: location.x, pixelsPerBeat: pixelsPerBeat))
        if let region = editableRegion, !region.contains(snappedDisplayBeat) { return }
        let beat = containerRelativeBeat(snappedDisplayBeat)
        let normalized = noteExpressionNormalizedValue(at: location.y, lane: lane)
        let newEvent = MIDIControllerEvent(
            controller: controller,
            value: controllerEventValue(for: lane, normalized: normalized),
            beat: max(0, beat)
        )
        selectedNoteIDs.removeAll()
        selectedControllerEventIDs = [newEvent.id]
        onAddControllerEvent?(newEvent)
    }

    private func updatedNoteExpressionValue(
        note: MIDINoteEvent,
        lane: MIDINoteExpressionLane,
        deltaFromStartY startY: CGFloat,
        currentY: CGFloat
    ) -> MIDINoteEvent {
        var updated = note
        switch lane {
        case .velocity:
            let deltaVelocity = Int(((startY - currentY) * 0.85).rounded())
            updated.velocity = UInt8(clamping: max(1, min(127, Int(note.velocity) + deltaVelocity)))
        case .channel:
            let laneHeight = noteExpressionLaneHeight(for: lane)
            let topPadding: CGFloat = 10
            let bottomPadding: CGFloat = 8
            let usableHeight = max(12, laneHeight - topPadding - bottomPadding)
            let normalized = 1.0 - ((max(topPadding, min(laneHeight - bottomPadding, currentY)) - topPadding) / usableHeight)
            let channel = Int((normalized * 15.0).rounded())
            updated.channel = UInt8(clamping: max(0, min(15, channel)))
        case .sustain, .expression:
            break
        }
        return updated
    }

    private func noteExpressionNormalizedValue(at y: CGFloat, lane: MIDINoteExpressionLane) -> CGFloat {
        let laneHeight = noteExpressionLaneHeight(for: lane)
        let topPadding: CGFloat = 10
        let bottomPadding: CGFloat = 8
        let usableHeight = max(12, laneHeight - topPadding - bottomPadding)
        return 1.0 - ((max(topPadding, min(laneHeight - bottomPadding, y)) - topPadding) / usableHeight)
    }

    private func updatedControllerEvent(
        _ event: MIDIControllerEvent,
        lane: MIDINoteExpressionLane,
        beatDelta: Double,
        currentY: CGFloat
    ) -> MIDIControllerEvent {
        var updated = event
        var nextBeat = max(0, event.beat + beatDelta)
        if let region = editableRegion {
            let lower = containerRelativeBeat(region.lowerBound)
            let upper = containerRelativeBeat(region.upperBound)
            nextBeat = min(max(lower, nextBeat), upper)
        }
        updated.beat = nextBeat
        updated.value = controllerEventValue(for: lane, normalized: noteExpressionNormalizedValue(at: currentY, lane: lane))
        return updated
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
        selectedControllerEventIDs.removeAll()
        onAddNote?(newNote)
        onNotePreview?(pitch, true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [onNotePreview] in
            onNotePreview?(pitch, false)
        }
    }

    private func noteExpressionLaneDragGesture(for lane: MIDINoteExpressionLane) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                selectedExpressionLane = lane
                if lane.isControllerLane {
                    if controllerLaneDragState == nil {
                        guard let event = hitTestControllerEvent(at: value.startLocation, lane: lane) else { return }
                        let targetIDs: Set<ID<MIDIControllerEvent>>
                        if selectedControllerEventIDs.contains(event.id) {
                            targetIDs = selectedControllerEventIDs
                        } else {
                            targetIDs = [event.id]
                            selectedControllerEventIDs = [event.id]
                        }
                        selectedNoteIDs.removeAll()
                        let originals = controllerEvents(for: lane).filter { targetIDs.contains($0.id) }
                        controllerLaneDragState = PianoRollControllerLaneDragState(
                            lane: lane,
                            eventIDs: Array(targetIDs),
                            originalEvents: originals,
                            startBeat: snapResolution.snap(PianoRollLayout.beat(forX: value.startLocation.x, pixelsPerBeat: pixelsPerBeat)),
                            startY: value.startLocation.y
                        )
                        onFocusChanged?(true)
                    }

                    guard let drag = controllerLaneDragState else { return }
                    let currentBeat = snapResolution.snap(PianoRollLayout.beat(forX: value.location.x, pixelsPerBeat: pixelsPerBeat))
                    let beatDelta = currentBeat - drag.startBeat
                    var previews: [ID<MIDIControllerEvent>: MIDIControllerEvent] = [:]
                    for event in drag.originalEvents {
                        let updated = updatedControllerEvent(
                            event,
                            lane: lane,
                            beatDelta: beatDelta,
                            currentY: value.location.y
                        )
                        previews[updated.id] = updated
                    }
                    controllerEventDragPreviews.merge(previews) { _, new in new }
                    return
                }
                if noteExpressionLaneDragState == nil {
                    guard let note = hitTestNoteExpressionLane(at: value.startLocation, lane: lane) else { return }
                    let targetIDs: Set<ID<MIDINoteEvent>>
                    if selectedNoteIDs.contains(note.id) {
                        targetIDs = selectedNoteIDs
                    } else {
                        targetIDs = [note.id]
                        selectedNoteIDs = [note.id]
                    }
                    let originals = sequence.notes.filter { targetIDs.contains($0.id) }
                    noteExpressionLaneDragState = PianoRollNoteExpressionLaneDragState(
                        noteIDs: Array(targetIDs),
                        originalNotes: originals,
                        startY: value.startLocation.y
                    )
                    onFocusChanged?(true)
                }

                guard let drag = noteExpressionLaneDragState else { return }
                var previews: [ID<MIDINoteEvent>: MIDINoteEvent] = [:]
                for note in drag.originalNotes {
                    let updated = updatedNoteExpressionValue(
                        note: note,
                        lane: lane,
                        deltaFromStartY: drag.startY,
                        currentY: value.location.y
                    )
                    previews[updated.id] = updated
                }
                dragPreviews.merge(previews) { _, new in new }
            }
            .onEnded { _ in
                if lane.isControllerLane {
                    guard let drag = controllerLaneDragState else { return }
                    for eventID in drag.eventIDs {
                        if let preview = controllerEventDragPreviews[eventID] {
                            onUpdateControllerEvent?(preview)
                        }
                        controllerEventDragPreviews.removeValue(forKey: eventID)
                    }
                    controllerLaneDragState = nil
                    return
                }
                guard let drag = noteExpressionLaneDragState else { return }
                for noteID in drag.noteIDs {
                    if let preview = dragPreviews[noteID] {
                        onUpdateNote?(preview)
                    }
                    dragPreviews.removeValue(forKey: noteID)
                }
                noteExpressionLaneDragState = nil
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
                            if NSEvent.modifierFlags.contains(.control) {
                                let targetIDs = selectedNoteIDs.contains(note.id) ? selectedNoteIDs : [note.id]
                                let originals = sequence.notes.filter { targetIDs.contains($0.id) }
                                dragState = .adjustingVelocity(
                                    noteIDs: Array(targetIDs),
                                    originalNotes: originals,
                                    startY: value.startLocation.y
                                )
                            } else {
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
                        }
                        // Select the note if not already selected
                        if !selectedNoteIDs.contains(note.id) {
                            selectedNoteIDs = [note.id]
                        }
                        onFocusChanged?(true)
                    } else {
                        if selectedTool == .pointer {
                            dragState = .selecting(
                                origin: value.startLocation,
                                current: value.location,
                                additive: NSEvent.modifierFlags.contains(.shift)
                            )
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

                case let .selecting(origin, _, additive):
                    dragState = .selecting(origin: origin, current: value.location, additive: additive)

                case let .adjustingVelocity(_, originalNotes, startY):
                    let deltaVelocity = Int(((startY - value.location.y) * 0.6).rounded())
                    var previews: [ID<MIDINoteEvent>: MIDINoteEvent] = [:]
                    for note in originalNotes {
                        var updated = note
                        updated.velocity = UInt8(clamping: max(1, min(127, Int(note.velocity) + deltaVelocity)))
                        previews[updated.id] = updated
                    }
                    dragPreviews = previews

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

                case let .selecting(origin, _, additive):
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
                    selectedNoteIDs = additive ? selectedNoteIDs.union(ids) : ids
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

private struct PianoRollKeyboardRow: View {
    let note: UInt8
    let rowHeight: CGFloat
    let isBlack: Bool
    let isC: Bool

    private var labelFontSize: CGFloat {
        max(7, min(rowHeight - 2, 10))
    }

    private var blackKeyWidth: CGFloat {
        max(22, PianoRollLayout.keyboardWidth - 10)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            whiteKeyBody

            if isBlack {
                blackKeyBody
            }

            labelOverlay
        }
        .frame(width: PianoRollLayout.keyboardWidth, height: rowHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isBlack ? Color.black.opacity(0.58) : Color.black.opacity(0.14))
                .frame(height: 0.5)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isC ? Color(red: 0.27, green: 0.63, blue: 0.94).opacity(0.92) : Color.clear)
                .frame(width: isC ? 2 : 0)
        }
    }

    private var whiteKeyBody: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isBlack ? 0.18 : 0.96),
                        Color.white.opacity(isBlack ? 0.11 : 0.86),
                        Color.black.opacity(isBlack ? 0.16 : 0.09)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(isBlack ? 0.06 : 0.36))
                    .frame(width: 1)
            }
    }

    private var blackKeyBody: some View {
        RoundedRectangle(cornerRadius: max(2, min(rowHeight * 0.18, 4)), style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.23, green: 0.24, blue: 0.28),
                        Color(red: 0.08, green: 0.09, blue: 0.12)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: blackKeyWidth, height: max(rowHeight - 1, 4))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, 2)
            }
            .shadow(color: Color.black.opacity(0.28), radius: 1.2, x: 0, y: 0.8)
    }

    private var labelOverlay: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            if isC {
                Text(PianoLayout.noteName(note))
                    .font(.system(size: labelFontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isBlack ? Color.white.opacity(0.92) : Color.black.opacity(0.82))
                    .padding(.horizontal, 4)
                    .padding(.vertical, max(1, rowHeight * 0.08))
                    .background(
                        Capsule(style: .continuous)
                            .fill(isBlack ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                    )
            } else if !isBlack, rowHeight >= 11 {
                Text(PianoLayout.noteName(note))
                    .font(.system(size: labelFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.50))
            } else if isBlack, rowHeight >= 11 {
                Text(PianoLayout.noteName(note))
                    .font(.system(size: labelFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.56))
            }
        }
        .padding(.leading, 2)
        .padding(.trailing, isBlack ? 4 : 3)
    }
}
