import SwiftUI
import LoopsCore

/// Inline piano roll shown below a track lane in the timeline.
/// Shows notes from all containers on the track, with ghost notes for non-active containers.
struct InlinePianoRollView: View {
    let containers: [Container]
    let activeContainerID: ID<Container>
    let totalTimelineBars: Int
    let timeSignature: TimeSignature
    let trackHeaderWidth: CGFloat
    let timelinePixelsPerBar: CGFloat
    let totalTimelineWidth: CGFloat
    @Bindable var editorState: PianoRollEditorState

    var onAddNote: ((ID<Container>, MIDINoteEvent) -> Void)?
    var onUpdateNote: ((ID<Container>, MIDINoteEvent) -> Void)?
    var onRemoveNote: ((ID<Container>, ID<MIDINoteEvent>) -> Void)?
    var onNotePreview: ((_ pitch: UInt8, _ isNoteOn: Bool) -> Void)?
    var onOpenSheet: (() -> Void)?
    var onOverrideMIDI: (() -> Void)?
    var onNavigateToParent: (() -> Void)?
    var onSelectContainer: ((ID<Container>) -> Void)?

    @State private var resizeDragStartHeight: CGFloat = 0
    @State private var resizePreviewHeight: CGFloat?
    @State private var scrollOffset: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    // MARK: - Computed Properties

    private var activeContainer: Container? {
        containers.first { $0.id == activeContainerID }
    }

    private var beatsPerBar: Int {
        timeSignature.beatsPerBar
    }

    private var pixelsPerBeat: CGFloat {
        timelinePixelsPerBar / CGFloat(beatsPerBar)
    }

    private var activeSequence: MIDISequence {
        activeContainer?.midiSequence ?? MIDISequence()
    }

    private var activeBeatOffset: Double {
        guard let active = activeContainer else { return 0 }
        return (active.startBar - 1.0) * Double(beatsPerBar)
    }

    private var editableRegionBeatRange: ClosedRange<Double>? {
        guard let active = activeContainer else { return nil }
        let start = (active.startBar - 1.0) * Double(beatsPerBar)
        let end = start + active.lengthBars * Double(beatsPerBar)
        return start...end
    }

    private var activeIsLinkedInherited: Bool {
        guard let active = activeContainer else { return false }
        return active.parentContainerID != nil && !active.overriddenFields.contains(.midiSequence)
    }

    private var computedGhostLayers: [PianoRollGhostLayer] {
        containers.compactMap { container in
            guard container.id != activeContainerID,
                  let seq = container.midiSequence,
                  !seq.notes.isEmpty else { return nil }
            let isLinked = container.parentContainerID != nil && !container.overriddenFields.contains(.midiSequence)
            let offset = (container.startBar - 1.0) * Double(beatsPerBar)
            let offsetNotes = seq.notes.map { note in
                var offsetNote = note
                offsetNote.startBeat = note.startBeat + offset
                return offsetNote
            }
            return PianoRollGhostLayer(notes: offsetNotes, opacity: isLinked ? 0.15 : 0.25)
        }
    }

    private var totalHeight: CGFloat {
        PianoRollLayout.totalHeight(
            lowPitch: editorState.lowPitch,
            highPitch: editorState.highPitch,
            rowHeight: editorState.rowHeight
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                inlineToolbar
                    .frame(width: viewportWidth > 0 ? viewportWidth : nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: viewportWidth > 0 ? scrollOffset : 0)
                Divider()
            }
            .background(
                HorizontalScrollObserver { offset, width in
                    scrollOffset = offset
                    viewportWidth = width
                }
                .frame(width: 0, height: 0)
            )
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear {
                        editorState.toolbarHeight = geo.size.height.rounded()
                    }
                    .onChange(of: geo.size.height) { _, newHeight in
                        let rounded = newHeight.rounded()
                        if abs(editorState.toolbarHeight - rounded) > 0.5 {
                            editorState.toolbarHeight = rounded
                        }
                    }
                }
            )
            PianoRollContentView(
                sequence: activeSequence,
                lengthBars: Double(totalTimelineBars),
                timeSignature: timeSignature,
                snapResolution: $editorState.snapResolution,
                pixelsPerBeat: .init(
                    get: { pixelsPerBeat },
                    set: { _ in } // read-only — synced from timeline
                ),
                lowPitch: $editorState.lowPitch,
                highPitch: $editorState.highPitch,
                rowHeight: $editorState.rowHeight,
                selectedNoteIDs: $editorState.selectedNoteIDs,
                playheadBeat: nil,
                containerStartBar: 1,
                noteOpacity: 0.75,
                showKeyboard: false,
                isReadOnly: activeIsLinkedInherited,
                editableBeatOffset: activeBeatOffset,
                ghostLayers: computedGhostLayers,
                editableRegion: editableRegionBeatRange,
                onClickOutsideEditableRegion: { beat in
                    if let target = containerAtBeat(beat) {
                        onSelectContainer?(target.id)
                    }
                },
                onFocusChanged: { editorState.isFocused = $0 },
                onVerticalScrollChanged: { editorState.verticalScrollOffset = $0 },
                onAddNote: activeIsLinkedInherited ? nil : { note in
                    onAddNote?(activeContainerID, note)
                },
                onUpdateNote: activeIsLinkedInherited ? nil : { note in
                    onUpdateNote?(activeContainerID, note)
                },
                onRemoveNote: activeIsLinkedInherited ? nil : { noteID in
                    onRemoveNote?(activeContainerID, noteID)
                },
                onNotePreview: onNotePreview
            )
            .frame(height: resizePreviewHeight ?? editorState.inlineHeight)

            // Bottom resize handle
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 4)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if resizeDragStartHeight == 0 {
                                resizeDragStartHeight = editorState.inlineHeight
                            }
                            resizePreviewHeight = max(100, resizeDragStartHeight + value.translation.height)
                        }
                        .onEnded { _ in
                            if let preview = resizePreviewHeight {
                                editorState.inlineHeight = preview
                            }
                            resizePreviewHeight = nil
                            resizeDragStartHeight = 0
                        }
                )
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Helpers

    private func containerAtBeat(_ beat: Double) -> Container? {
        containers.first { container in
            let start = (container.startBar - 1.0) * Double(beatsPerBar)
            let end = start + container.lengthBars * Double(beatsPerBar)
            return beat >= start && beat < end
        }
    }

    // MARK: - Inline Toolbar

    private var inlineToolbar: some View {
        HStack(spacing: 8) {
            Text("Piano Roll")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(activeContainer?.name ?? "")
                .font(.caption.bold())

            if activeIsLinkedInherited {
                linkedCloneIndicator
            }

            Spacer()

            // Snap resolution
            Picker("", selection: $editorState.snapResolution) {
                ForEach(SnapResolution.allCases, id: \.self) { res in
                    Text(res.rawValue).tag(res)
                }
            }
            .frame(width: 56)
            .controlSize(.small)

            Divider().frame(height: 14)

            // Vertical zoom
            Button(action: {
                editorState.rowHeight = max(PianoRollLayout.minRowHeight, editorState.rowHeight - 2)
            }) {
                Image(systemName: "minus")
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .help("Vertical Zoom Out")

            Button(action: {
                editorState.rowHeight = min(PianoRollLayout.maxRowHeight, editorState.rowHeight + 2)
            }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .help("Vertical Zoom In")

            Button(action: {
                editorState.fitToNotes(sequence: activeSequence)
            }) {
                Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .help("Fit to Content")

            Divider().frame(height: 14)

            // Pop-out to sheet
            Button(action: { onOpenSheet?() }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .help("Open in Window (Cmd+Return)")

            // Close inline
            Button(action: { editorState.close() }) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .help("Close Piano Roll")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Linked Clone Indicator

    private var linkedCloneIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.caption2)
            Text("Linked")
                .font(.caption2)

            Button("Edit Locally") {
                onOverrideMIDI?()
            }
            .font(.caption2)
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Copy inherited MIDI and edit locally")

            Button(action: { onNavigateToParent?() }) {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .help("Go to Parent Container")
        }
        .foregroundStyle(.orange)
    }
}

// MARK: - Horizontal Scroll Observer

/// Observes the horizontal scroll offset and visible width of the nearest
/// horizontally-scrollable NSScrollView in the view hierarchy.
private struct HorizontalScrollObserver: NSViewRepresentable {
    let onScrollChanged: (_ offset: CGFloat, _ visibleWidth: CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.reattachIfNeeded(from: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollChanged: onScrollChanged)
    }

    final class Coordinator: NSObject {
        let onScrollChanged: (_ offset: CGFloat, _ visibleWidth: CGFloat) -> Void
        private var boundsObservation: NSObjectProtocol?
        private var frameObservation: NSObjectProtocol?
        private weak var observedScrollView: NSScrollView?

        init(onScrollChanged: @escaping (_ offset: CGFloat, _ visibleWidth: CGFloat) -> Void) {
            self.onScrollChanged = onScrollChanged
        }

        func attach(to view: NSView) {
            var candidate: NSView? = view.superview
            while let current = candidate {
                if let sv = current as? NSScrollView,
                   let docWidth = sv.documentView?.frame.width,
                   docWidth > sv.frame.width + 1 {
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

        private func report() {
            guard let sv = observedScrollView else { return }
            onScrollChanged(sv.contentView.bounds.origin.x, sv.contentView.bounds.width)
        }

        private func observe(scrollView: NSScrollView) {
            guard observedScrollView !== scrollView else { return }
            if let boundsObservation { NotificationCenter.default.removeObserver(boundsObservation) }
            if let frameObservation { NotificationCenter.default.removeObserver(frameObservation) }
            observedScrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollView.contentView.postsFrameChangedNotifications = true
            report()
            boundsObservation = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in self?.report() }
            frameObservation = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in self?.report() }
        }

        deinit {
            if let boundsObservation { NotificationCenter.default.removeObserver(boundsObservation) }
            if let frameObservation { NotificationCenter.default.removeObserver(frameObservation) }
        }
    }
}
