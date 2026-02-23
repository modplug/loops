import SwiftUI
import UniformTypeIdentifiers
import LoopsCore

/// Renders a single track's horizontal lane on the timeline.
/// Supports container rendering and click-drag to create new containers.
public struct TrackLaneView: View {
    let track: Track
    let pixelsPerBar: CGFloat
    let totalBars: Int
    let height: CGFloat
    var selectionState: SelectionState?
    /// Closure to look up waveform peaks for a container.
    var waveformPeaksForContainer: ((_ container: Container) -> [Float]?)?
    /// Closure to look up the total recording duration in bars for a container.
    var recordingDurationBarsForContainer: ((_ container: Container) -> Double?)?
    var onContainerSelect: ((_ containerID: ID<Container>) -> Void)?
    var onContainerDelete: ((_ containerID: ID<Container>) -> Void)?
    var onContainerMove: ((_ containerID: ID<Container>, _ newStartBar: Int) -> Bool)?
    var onContainerResizeLeft: ((_ containerID: ID<Container>, _ newStartBar: Int, _ newLength: Int) -> Bool)?
    var onContainerResizeRight: ((_ containerID: ID<Container>, _ newLength: Int) -> Bool)?
    var onCreateContainer: ((_ startBar: Int, _ lengthBars: Int) -> Void)?
    var onDropAudioFile: ((_ url: URL, _ startBar: Int) -> Void)?
    var onDropMIDIFile: ((_ url: URL, _ startBar: Int) -> Void)?
    var onContainerDoubleClick: ((_ containerID: ID<Container>) -> Void)?
    var onCloneContainer: ((_ containerID: ID<Container>, _ newStartBar: Int) -> Void)?
    var onCopyContainer: ((_ containerID: ID<Container>) -> Void)?
    var onCopyContainerToSong: ((_ containerID: ID<Container>, _ songID: ID<Song>) -> Void)?
    var otherSongs: [(id: ID<Song>, name: String)]
    var onDuplicateContainer: ((_ containerID: ID<Container>) -> Void)?
    var onLinkCloneContainer: ((_ containerID: ID<Container>) -> Void)?
    var onUnlinkContainer: ((_ containerID: ID<Container>) -> Void)?
    var onContainerArmToggle: ((_ containerID: ID<Container>) -> Void)?
    var onPasteAtBar: ((_ bar: Int) -> Void)?
    var hasClipboard: Bool
    var isAutomationExpanded: Bool
    var automationSubLanePaths: [EffectPath]
    var selectedBreakpointID: ID<AutomationBreakpoint>?
    var onAddBreakpoint: ((_ containerID: ID<Container>, _ laneID: ID<AutomationLane>, _ breakpoint: AutomationBreakpoint) -> Void)?
    var onUpdateBreakpoint: ((_ containerID: ID<Container>, _ laneID: ID<AutomationLane>, _ breakpoint: AutomationBreakpoint) -> Void)?
    var onDeleteBreakpoint: ((_ containerID: ID<Container>, _ laneID: ID<AutomationLane>, _ breakpointID: ID<AutomationBreakpoint>) -> Void)?
    var onSelectBreakpoint: ((_ breakpointID: ID<AutomationBreakpoint>?) -> Void)?
    var onAddTrackBreakpoint: ((_ laneID: ID<AutomationLane>, _ breakpoint: AutomationBreakpoint) -> Void)?
    var onUpdateTrackBreakpoint: ((_ laneID: ID<AutomationLane>, _ breakpoint: AutomationBreakpoint) -> Void)?
    var onDeleteTrackBreakpoint: ((_ laneID: ID<AutomationLane>, _ breakpointID: ID<AutomationBreakpoint>) -> Void)?
    var onSetEnterFade: ((_ containerID: ID<Container>, _ fade: FadeSettings?) -> Void)?
    var onSetExitFade: ((_ containerID: ID<Container>, _ fade: FadeSettings?) -> Void)?
    var onContainerTrimLeft: ((_ containerID: ID<Container>, _ newAudioStartOffset: Double, _ newStartBar: Int, _ newLength: Int) -> Bool)?
    var onContainerTrimRight: ((_ containerID: ID<Container>, _ newLength: Int) -> Bool)?
    var onContainerSplit: ((_ containerID: ID<Container>) -> Void)?
    var onPlayheadTap: ((_ timelineX: CGFloat) -> Void)?
    var onTapBackground: ((_ xPosition: CGFloat) -> Void)?
    var onRangeSelect: ((_ containerID: ID<Container>, _ startBar: Int, _ endBar: Int) -> Void)?
    /// Resolves an audio file URL to its length in bars (using song tempo/time signature).
    /// Called asynchronously when a file is dragged over the track.
    var onResolveAudioFileBars: ((_ url: URL) -> Int?)?

    @State private var dragStartX: CGFloat?
    @State private var dragCurrentX: CGFloat?
    @State private var isCreatingContainer = false
    @State private var isDropTargeted = false
    @State private var dropPreviewBar: Int?
    @State private var dropPreviewLengthBars: Int?

    public init(
        track: Track,
        pixelsPerBar: CGFloat,
        totalBars: Int,
        height: CGFloat = 80,
        selectionState: SelectionState? = nil,
        waveformPeaksForContainer: ((_ container: Container) -> [Float]?)? = nil,
        recordingDurationBarsForContainer: ((_ container: Container) -> Double?)? = nil,
        onContainerSelect: ((_ containerID: ID<Container>) -> Void)? = nil,
        onContainerDelete: ((_ containerID: ID<Container>) -> Void)? = nil,
        onContainerMove: ((_ containerID: ID<Container>, _ newStartBar: Int) -> Bool)? = nil,
        onContainerResizeLeft: ((_ containerID: ID<Container>, _ newStartBar: Int, _ newLength: Int) -> Bool)? = nil,
        onContainerResizeRight: ((_ containerID: ID<Container>, _ newLength: Int) -> Bool)? = nil,
        onCreateContainer: ((_ startBar: Int, _ lengthBars: Int) -> Void)? = nil,
        onDropAudioFile: ((_ url: URL, _ startBar: Int) -> Void)? = nil,
        onDropMIDIFile: ((_ url: URL, _ startBar: Int) -> Void)? = nil,
        onContainerDoubleClick: ((_ containerID: ID<Container>) -> Void)? = nil,
        onCloneContainer: ((_ containerID: ID<Container>, _ newStartBar: Int) -> Void)? = nil,
        onCopyContainer: ((_ containerID: ID<Container>) -> Void)? = nil,
        onCopyContainerToSong: ((_ containerID: ID<Container>, _ songID: ID<Song>) -> Void)? = nil,
        otherSongs: [(id: ID<Song>, name: String)] = [],
        onDuplicateContainer: ((_ containerID: ID<Container>) -> Void)? = nil,
        onLinkCloneContainer: ((_ containerID: ID<Container>) -> Void)? = nil,
        onUnlinkContainer: ((_ containerID: ID<Container>) -> Void)? = nil,
        onContainerArmToggle: ((_ containerID: ID<Container>) -> Void)? = nil,
        onPasteAtBar: ((_ bar: Int) -> Void)? = nil,
        hasClipboard: Bool = false,
        isAutomationExpanded: Bool = false,
        automationSubLanePaths: [EffectPath] = [],
        selectedBreakpointID: ID<AutomationBreakpoint>? = nil,
        onAddBreakpoint: ((_ containerID: ID<Container>, _ laneID: ID<AutomationLane>, _ breakpoint: AutomationBreakpoint) -> Void)? = nil,
        onUpdateBreakpoint: ((_ containerID: ID<Container>, _ laneID: ID<AutomationLane>, _ breakpoint: AutomationBreakpoint) -> Void)? = nil,
        onDeleteBreakpoint: ((_ containerID: ID<Container>, _ laneID: ID<AutomationLane>, _ breakpointID: ID<AutomationBreakpoint>) -> Void)? = nil,
        onSelectBreakpoint: ((_ breakpointID: ID<AutomationBreakpoint>?) -> Void)? = nil,
        onAddTrackBreakpoint: ((_ laneID: ID<AutomationLane>, _ breakpoint: AutomationBreakpoint) -> Void)? = nil,
        onUpdateTrackBreakpoint: ((_ laneID: ID<AutomationLane>, _ breakpoint: AutomationBreakpoint) -> Void)? = nil,
        onDeleteTrackBreakpoint: ((_ laneID: ID<AutomationLane>, _ breakpointID: ID<AutomationBreakpoint>) -> Void)? = nil,
        onSetEnterFade: ((_ containerID: ID<Container>, _ fade: FadeSettings?) -> Void)? = nil,
        onSetExitFade: ((_ containerID: ID<Container>, _ fade: FadeSettings?) -> Void)? = nil,
        onContainerTrimLeft: ((_ containerID: ID<Container>, _ newAudioStartOffset: Double, _ newStartBar: Int, _ newLength: Int) -> Bool)? = nil,
        onContainerTrimRight: ((_ containerID: ID<Container>, _ newLength: Int) -> Bool)? = nil,
        onContainerSplit: ((_ containerID: ID<Container>) -> Void)? = nil,
        onPlayheadTap: ((_ timelineX: CGFloat) -> Void)? = nil,
        onTapBackground: ((_ xPosition: CGFloat) -> Void)? = nil,
        onRangeSelect: ((_ containerID: ID<Container>, _ startBar: Int, _ endBar: Int) -> Void)? = nil,
        onResolveAudioFileBars: ((_ url: URL) -> Int?)? = nil
    ) {
        self.track = track
        self.pixelsPerBar = pixelsPerBar
        self.totalBars = totalBars
        self.height = height
        self.selectionState = selectionState
        self.waveformPeaksForContainer = waveformPeaksForContainer
        self.recordingDurationBarsForContainer = recordingDurationBarsForContainer
        self.onContainerSelect = onContainerSelect
        self.onContainerDelete = onContainerDelete
        self.onContainerMove = onContainerMove
        self.onContainerResizeLeft = onContainerResizeLeft
        self.onContainerResizeRight = onContainerResizeRight
        self.onCreateContainer = onCreateContainer
        self.onDropAudioFile = onDropAudioFile
        self.onDropMIDIFile = onDropMIDIFile
        self.onContainerDoubleClick = onContainerDoubleClick
        self.onCloneContainer = onCloneContainer
        self.onCopyContainer = onCopyContainer
        self.onCopyContainerToSong = onCopyContainerToSong
        self.otherSongs = otherSongs
        self.onDuplicateContainer = onDuplicateContainer
        self.onLinkCloneContainer = onLinkCloneContainer
        self.onUnlinkContainer = onUnlinkContainer
        self.onContainerArmToggle = onContainerArmToggle
        self.onPasteAtBar = onPasteAtBar
        self.hasClipboard = hasClipboard
        self.isAutomationExpanded = isAutomationExpanded
        self.automationSubLanePaths = automationSubLanePaths
        self.selectedBreakpointID = selectedBreakpointID
        self.onAddBreakpoint = onAddBreakpoint
        self.onUpdateBreakpoint = onUpdateBreakpoint
        self.onDeleteBreakpoint = onDeleteBreakpoint
        self.onSelectBreakpoint = onSelectBreakpoint
        self.onAddTrackBreakpoint = onAddTrackBreakpoint
        self.onUpdateTrackBreakpoint = onUpdateTrackBreakpoint
        self.onDeleteTrackBreakpoint = onDeleteTrackBreakpoint
        self.onSetEnterFade = onSetEnterFade
        self.onSetExitFade = onSetExitFade
        self.onContainerTrimLeft = onContainerTrimLeft
        self.onContainerTrimRight = onContainerTrimRight
        self.onContainerSplit = onContainerSplit
        self.onPlayheadTap = onPlayheadTap
        self.onTapBackground = onTapBackground
        self.onRangeSelect = onRangeSelect
        self.onResolveAudioFileBars = onResolveAudioFileBars
    }

    private var baseHeight: CGFloat {
        let subLaneCount = isAutomationExpanded ? automationSubLanePaths.count : 0
        return height - CGFloat(subLaneCount) * TimelineViewModel.automationSubLaneHeight
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Main track lane
            ZStack(alignment: .topLeading) {
                // Track background — also handles drag-to-create
                Rectangle()
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.3))
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        onTapBackground?(location.x)
                    }
                    .gesture(createContainerGesture)
                    .contextMenu {
                        Button("Create Container Here") {
                            onCreateContainer?(1, 4)
                        }
                        if hasClipboard {
                            Button("Paste") {
                                onPasteAtBar?(1)
                            }
                        }
                    }

                // Drop target highlight with snapped position and resolved width
                if isDropTargeted, let bar = dropPreviewBar {
                    let lengthBars = CGFloat(dropPreviewLengthBars ?? 4)
                    let previewWidth = pixelsPerBar * lengthBars
                    let previewX = CGFloat(bar - 1) * pixelsPerBar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(trackColor.opacity(0.12))
                        .strokeBorder(trackColor.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
                        .frame(width: previewWidth, height: baseHeight - 4)
                        .offset(x: previewX, y: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .allowsHitTesting(false)
                }

                // Draw-to-create preview
                if isCreatingContainer, let startX = dragStartX, let currentX = dragCurrentX {
                    let minX = min(startX, currentX)
                    let maxX = max(startX, currentX)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(trackColor.opacity(0.2))
                        .strokeBorder(trackColor.opacity(0.5), lineWidth: 1, antialiased: true)
                        .frame(width: maxX - minX, height: baseHeight - 4)
                        .offset(x: minX, y: 2)
                }

                // Existing containers
                ForEach(track.containers) { container in
                    ContainerView(
                        container: container,
                        pixelsPerBar: pixelsPerBar,
                        height: baseHeight - 4,
                        selectionState: selectionState,
                        trackColor: trackColor,
                        waveformPeaks: waveformPeaksForContainer?(container),
                        isClone: container.parentContainerID != nil,
                        overriddenFields: container.overriddenFields,
                        recordingDurationBars: recordingDurationBarsForContainer?(container),
                        onSelect: { onContainerSelect?(container.id) },
                        onPlayheadTap: onPlayheadTap,
                        onDelete: { onContainerDelete?(container.id) },
                        onMove: { newStart in onContainerMove?(container.id, newStart) ?? false },
                        onResizeLeft: { start, len in onContainerResizeLeft?(container.id, start, len) ?? false },
                        onResizeRight: { len in onContainerResizeRight?(container.id, len) ?? false },
                        onTrimLeft: { offset, start, len in onContainerTrimLeft?(container.id, offset, start, len) ?? false },
                        onTrimRight: { len in onContainerTrimRight?(container.id, len) ?? false },
                        onDoubleClick: { onContainerDoubleClick?(container.id) },
                        onClone: { newStart in onCloneContainer?(container.id, newStart) },
                        onCopy: { onCopyContainer?(container.id) },
                        onCopyToSong: { songID in onCopyContainerToSong?(container.id, songID) },
                        otherSongs: otherSongs,
                        onDuplicate: { onDuplicateContainer?(container.id) },
                        onLinkClone: { onLinkCloneContainer?(container.id) },
                        onUnlink: { onUnlinkContainer?(container.id) },
                        onArmToggle: { onContainerArmToggle?(container.id) },
                        onSetEnterFade: { fade in onSetEnterFade?(container.id, fade) },
                        onSetExitFade: { fade in onSetExitFade?(container.id, fade) },
                        onSplit: { onContainerSplit?(container.id) },
                        onRangeSelect: { startBar, endBar in onRangeSelect?(container.id, startBar, endBar) }
                    )
                    .equatable()
                    .offset(x: CGFloat(container.startBar - 1) * pixelsPerBar, y: 2)
                }
            }
            .coordinateSpace(name: "trackLane")
            .frame(width: CGFloat(totalBars) * pixelsPerBar, height: baseHeight)

            // Automation sub-lanes (when expanded)
            if isAutomationExpanded {
                ForEach(Array(automationSubLanePaths.enumerated()), id: \.element) { index, targetPath in
                    AutomationSubLaneView(
                        targetPath: targetPath,
                        containers: track.containers,
                        laneColorIndex: index,
                        pixelsPerBar: pixelsPerBar,
                        totalBars: totalBars,
                        height: TimelineViewModel.automationSubLaneHeight,
                        selectedBreakpointID: selectedBreakpointID,
                        onAddBreakpoint: onAddBreakpoint,
                        onUpdateBreakpoint: onUpdateBreakpoint,
                        onDeleteBreakpoint: onDeleteBreakpoint,
                        onSelectBreakpoint: onSelectBreakpoint,
                        trackAutomationLane: track.trackAutomationLanes.first(where: { $0.targetPath == targetPath }),
                        onAddTrackBreakpoint: onAddTrackBreakpoint,
                        onUpdateTrackBreakpoint: onUpdateTrackBreakpoint,
                        onDeleteTrackBreakpoint: onDeleteTrackBreakpoint
                    )
                    .overlay(
                        Rectangle()
                            .frame(height: 0.5)
                            .foregroundStyle(Color.secondary.opacity(0.15)),
                        alignment: .bottom
                    )
                }
            }
        }
        .frame(width: CGFloat(totalBars) * pixelsPerBar, height: height)
        .onDrop(of: [.fileURL], delegate: AudioFileDropDelegate(
            pixelsPerBar: pixelsPerBar,
            isDropTargeted: $isDropTargeted,
            dropPreviewBar: $dropPreviewBar,
            dropPreviewLengthBars: $dropPreviewLengthBars,
            onResolveAudioFileBars: onResolveAudioFileBars,
            onDropAudioFile: onDropAudioFile,
            onDropMIDIFile: onDropMIDIFile
        ))
    }

    private var createContainerGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if !isCreatingContainer {
                    isCreatingContainer = true
                    // Snap start to bar boundary
                    let snappedStart = round(value.startLocation.x / pixelsPerBar) * pixelsPerBar
                    dragStartX = snappedStart
                }
                // Snap current to bar boundary
                let snappedCurrent = round(value.location.x / pixelsPerBar) * pixelsPerBar
                dragCurrentX = snappedCurrent
            }
            .onEnded { value in
                defer {
                    isCreatingContainer = false
                    dragStartX = nil
                    dragCurrentX = nil
                }

                guard let startX = dragStartX, let currentX = dragCurrentX else { return }

                let minX = min(startX, currentX)
                let maxX = max(startX, currentX)
                let startBar = Int(minX / pixelsPerBar) + 1
                let lengthBars = max(Int(round((maxX - minX) / pixelsPerBar)), 1)

                onCreateContainer?(startBar, lengthBars)
            }
    }

    private var trackColor: Color {
        switch track.kind {
        case .audio: return .blue
        case .midi: return .purple
        case .bus: return .green
        case .backing: return .orange
        case .master: return .gray
        }
    }
}

// MARK: - Audio File Drop Delegate

private struct AudioFileDropDelegate: DropDelegate {
    let pixelsPerBar: CGFloat
    @Binding var isDropTargeted: Bool
    @Binding var dropPreviewBar: Int?
    @Binding var dropPreviewLengthBars: Int?
    var onResolveAudioFileBars: ((_ url: URL) -> Int?)?
    var onDropAudioFile: ((_ url: URL, _ startBar: Int) -> Void)?
    var onDropMIDIFile: ((_ url: URL, _ startBar: Int) -> Void)?

    func dropEntered(info: DropInfo) {
        isDropTargeted = true
        updatePreviewBar(info: info)
        resolveFileLength(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updatePreviewBar(info: info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        isDropTargeted = false
        dropPreviewBar = nil
        dropPreviewLengthBars = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        isDropTargeted = false
        let barAtDrop = dropPreviewBar ?? max(Int(info.location.x / pixelsPerBar) + 1, 1)
        dropPreviewBar = nil
        dropPreviewLengthBars = nil

        guard let provider = info.itemProviders(for: [.fileURL]).first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data = data as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            let ext = url.pathExtension.lowercased()
            let audioFormats: Set<String> = ["wav", "aiff", "aif", "caf", "mp3", "m4a"]
            let midiFormats: Set<String> = ["mid", "midi"]
            if midiFormats.contains(ext) {
                DispatchQueue.main.async { onDropMIDIFile?(url, barAtDrop) }
            } else if audioFormats.contains(ext) {
                DispatchQueue.main.async { onDropAudioFile?(url, barAtDrop) }
            }
        }
        return true
    }

    private func updatePreviewBar(info: DropInfo) {
        let bar = max(Int(round(info.location.x / pixelsPerBar)) + 1, 1)
        dropPreviewBar = bar
    }

    /// Async-loads the dragged file URL, reads audio metadata (header only — fast),
    /// and computes the container length in bars.
    private func resolveFileLength(info: DropInfo) {
        guard let provider = info.itemProviders(for: [.fileURL]).first else { return }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data = data as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            let bars = onResolveAudioFileBars?(url)
            DispatchQueue.main.async {
                dropPreviewLengthBars = bars
            }
        }
    }
}

// MARK: - Equatable

extension TrackLaneView: Equatable {
    public static func == (lhs: TrackLaneView, rhs: TrackLaneView) -> Bool {
        // selectionState is not compared — it's the same object reference.
        // Selection is observed directly by ContainerView via @Observable.
        lhs.track == rhs.track &&
        lhs.pixelsPerBar == rhs.pixelsPerBar &&
        lhs.totalBars == rhs.totalBars &&
        lhs.height == rhs.height &&
        lhs.hasClipboard == rhs.hasClipboard &&
        lhs.isAutomationExpanded == rhs.isAutomationExpanded &&
        lhs.automationSubLanePaths == rhs.automationSubLanePaths &&
        lhs.selectedBreakpointID == rhs.selectedBreakpointID &&
        lhs.otherSongs.count == rhs.otherSongs.count &&
        zip(lhs.otherSongs, rhs.otherSongs).allSatisfy { $0.id == $1.id && $0.name == $1.name }
    }
}
