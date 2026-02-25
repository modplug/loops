import SwiftUI
import AppKit
import QuartzCore
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
    var onContainerSelect: ((_ containerID: ID<Container>, _ modifiers: NSEvent.ModifierFlags) -> Void)?
    var onContainerDelete: ((_ containerID: ID<Container>) -> Void)?
    var onContainerMove: ((_ containerID: ID<Container>, _ newStartBar: Double) -> Bool)?
    var onContainerResizeLeft: ((_ containerID: ID<Container>, _ newStartBar: Double, _ newLength: Double) -> Bool)?
    var onContainerResizeRight: ((_ containerID: ID<Container>, _ newLength: Double) -> Bool)?
    var onCreateContainer: ((_ startBar: Double, _ lengthBars: Double) -> Void)?
    var onDropAudioFile: ((_ url: URL, _ startBar: Double) -> Void)?
    var onDropMIDIFile: ((_ url: URL, _ startBar: Double) -> Void)?
    var onContainerDoubleClick: ((_ containerID: ID<Container>) -> Void)?
    var onCloneContainer: ((_ containerID: ID<Container>, _ newStartBar: Double) -> Void)?
    var onCopyContainer: ((_ containerID: ID<Container>) -> Void)?
    var onCopyContainerToSong: ((_ containerID: ID<Container>, _ songID: ID<Song>) -> Void)?
    var otherSongs: [(id: ID<Song>, name: String)]
    var onDuplicateContainer: ((_ containerID: ID<Container>) -> Void)?
    var onLinkCloneContainer: ((_ containerID: ID<Container>) -> Void)?
    var onUnlinkContainer: ((_ containerID: ID<Container>) -> Void)?
    var onContainerArmToggle: ((_ containerID: ID<Container>) -> Void)?
    var onPasteAtBar: ((_ bar: Double) -> Void)?
    var hasClipboard: Bool
    /// Returns the resolved MIDI sequence for a container (inheriting from parent for clones).
    var resolvedMIDISequenceForContainer: ((_ container: Container) -> MIDISequence?)?
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
    var onReplaceBreakpoints: ((_ containerID: ID<Container>, _ laneID: ID<AutomationLane>, _ startPosition: Double, _ endPosition: Double, _ breakpoints: [AutomationBreakpoint]) -> Void)?
    var onReplaceTrackBreakpoints: ((_ laneID: ID<AutomationLane>, _ startPosition: Double, _ endPosition: Double, _ breakpoints: [AutomationBreakpoint]) -> Void)?
    var selectedAutomationTool: AutomationTool = .pointer
    var gridSpacingBars: Double = 0.25
    var onAutomationToolChange: ((_ tool: AutomationTool) -> Void)?
    var onSetEnterFade: ((_ containerID: ID<Container>, _ fade: FadeSettings?) -> Void)?
    var onSetExitFade: ((_ containerID: ID<Container>, _ fade: FadeSettings?) -> Void)?
    var onContainerTrimLeft: ((_ containerID: ID<Container>, _ newAudioStartOffset: Double, _ newStartBar: Double, _ newLength: Double) -> Bool)?
    var onContainerTrimRight: ((_ containerID: ID<Container>, _ newLength: Double) -> Bool)?
    var onContainerSplit: ((_ containerID: ID<Container>) -> Void)?
    var onGlueContainers: (() -> Void)?
    var onPlayheadTap: ((_ timelineX: CGFloat) -> Void)?
    var onTapBackground: ((_ xPosition: CGFloat) -> Void)?
    var onRangeSelect: ((_ containerID: ID<Container>, _ startBar: Double, _ endBar: Double) -> Void)?
    /// Resolves an audio file URL to its length in bars (using song tempo/time signature).
    /// Called asynchronously when a file is dragged over the track.
    var onResolveAudioFileBars: ((_ url: URL) -> Double?)?
    /// Snaps a bar value to the current grid resolution.
    var snapToGrid: ((_ bar: Double) -> Double)?
    /// Callback to change crossfade curve type.
    var onSetCrossfadeCurveType: ((_ crossfadeID: ID<Crossfade>, _ curveType: CrossfadeCurveType) -> Void)?
    /// Snap resolution for automation breakpoints (nil = snap disabled).
    var automationSnapResolution: SnapResolution?
    /// Time signature for automation snap calculations.
    var automationTimeSignature: TimeSignature?
    /// Grid mode for automation sub-lane grid lines.
    var automationGridMode: GridMode?
    /// Number of containers in the current multi-selection.
    var multiSelectCount: Int = 0
    /// Batch operations for multi-selected containers.
    var onDeleteSelected: (() -> Void)?
    var onDuplicateSelected: (() -> Void)?
    var onCopySelected: (() -> Void)?
    var onSplitSelected: (() -> Void)?
    /// Visible X range for viewport-aware rendering (with buffer).
    var visibleXMin: CGFloat = 0
    var visibleXMax: CGFloat = CGFloat.greatestFiniteMagnitude

    @State private var dragStartX: CGFloat?
    @State private var dragCurrentX: CGFloat?
    @State private var isCreatingContainer = false
    @State private var isDropTargeted = false
    @State private var dropPreviewBar: Double?
    @State private var dropPreviewLengthBars: Double?
    @State private var toolbarScrollOffset: CGFloat = 0
    @State private var toolbarViewportWidth: CGFloat = 0

    public init(
        track: Track,
        pixelsPerBar: CGFloat,
        totalBars: Int,
        height: CGFloat = 80,
        selectionState: SelectionState? = nil,
        waveformPeaksForContainer: ((_ container: Container) -> [Float]?)? = nil,
        recordingDurationBarsForContainer: ((_ container: Container) -> Double?)? = nil,
        onContainerSelect: ((_ containerID: ID<Container>, _ modifiers: NSEvent.ModifierFlags) -> Void)? = nil,
        onContainerDelete: ((_ containerID: ID<Container>) -> Void)? = nil,
        onContainerMove: ((_ containerID: ID<Container>, _ newStartBar: Double) -> Bool)? = nil,
        onContainerResizeLeft: ((_ containerID: ID<Container>, _ newStartBar: Double, _ newLength: Double) -> Bool)? = nil,
        onContainerResizeRight: ((_ containerID: ID<Container>, _ newLength: Double) -> Bool)? = nil,
        onCreateContainer: ((_ startBar: Double, _ lengthBars: Double) -> Void)? = nil,
        onDropAudioFile: ((_ url: URL, _ startBar: Double) -> Void)? = nil,
        onDropMIDIFile: ((_ url: URL, _ startBar: Double) -> Void)? = nil,
        onContainerDoubleClick: ((_ containerID: ID<Container>) -> Void)? = nil,
        onCloneContainer: ((_ containerID: ID<Container>, _ newStartBar: Double) -> Void)? = nil,
        onCopyContainer: ((_ containerID: ID<Container>) -> Void)? = nil,
        onCopyContainerToSong: ((_ containerID: ID<Container>, _ songID: ID<Song>) -> Void)? = nil,
        otherSongs: [(id: ID<Song>, name: String)] = [],
        onDuplicateContainer: ((_ containerID: ID<Container>) -> Void)? = nil,
        onLinkCloneContainer: ((_ containerID: ID<Container>) -> Void)? = nil,
        onUnlinkContainer: ((_ containerID: ID<Container>) -> Void)? = nil,
        onContainerArmToggle: ((_ containerID: ID<Container>) -> Void)? = nil,
        onPasteAtBar: ((_ bar: Double) -> Void)? = nil,
        hasClipboard: Bool = false,
        resolvedMIDISequenceForContainer: ((_ container: Container) -> MIDISequence?)? = nil,
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
        onReplaceBreakpoints: ((_ containerID: ID<Container>, _ laneID: ID<AutomationLane>, _ startPosition: Double, _ endPosition: Double, _ breakpoints: [AutomationBreakpoint]) -> Void)? = nil,
        onReplaceTrackBreakpoints: ((_ laneID: ID<AutomationLane>, _ startPosition: Double, _ endPosition: Double, _ breakpoints: [AutomationBreakpoint]) -> Void)? = nil,
        selectedAutomationTool: AutomationTool = .pointer,
        gridSpacingBars: Double = 0.25,
        onAutomationToolChange: ((_ tool: AutomationTool) -> Void)? = nil,
        onSetEnterFade: ((_ containerID: ID<Container>, _ fade: FadeSettings?) -> Void)? = nil,
        onSetExitFade: ((_ containerID: ID<Container>, _ fade: FadeSettings?) -> Void)? = nil,
        onContainerTrimLeft: ((_ containerID: ID<Container>, _ newAudioStartOffset: Double, _ newStartBar: Double, _ newLength: Double) -> Bool)? = nil,
        onContainerTrimRight: ((_ containerID: ID<Container>, _ newLength: Double) -> Bool)? = nil,
        onContainerSplit: ((_ containerID: ID<Container>) -> Void)? = nil,
        onGlueContainers: (() -> Void)? = nil,
        onPlayheadTap: ((_ timelineX: CGFloat) -> Void)? = nil,
        onTapBackground: ((_ xPosition: CGFloat) -> Void)? = nil,
        onRangeSelect: ((_ containerID: ID<Container>, _ startBar: Double, _ endBar: Double) -> Void)? = nil,
        onResolveAudioFileBars: ((_ url: URL) -> Double?)? = nil,
        snapToGrid: ((_ bar: Double) -> Double)? = nil,
        onSetCrossfadeCurveType: ((_ crossfadeID: ID<Crossfade>, _ curveType: CrossfadeCurveType) -> Void)? = nil,
        automationSnapResolution: SnapResolution? = nil,
        automationTimeSignature: TimeSignature? = nil,
        automationGridMode: GridMode? = nil,
        multiSelectCount: Int = 0,
        onDeleteSelected: (() -> Void)? = nil,
        onDuplicateSelected: (() -> Void)? = nil,
        onCopySelected: (() -> Void)? = nil,
        onSplitSelected: (() -> Void)? = nil,
        visibleXMin: CGFloat = 0,
        visibleXMax: CGFloat = .greatestFiniteMagnitude
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
        self.resolvedMIDISequenceForContainer = resolvedMIDISequenceForContainer
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
        self.onReplaceBreakpoints = onReplaceBreakpoints
        self.onReplaceTrackBreakpoints = onReplaceTrackBreakpoints
        self.selectedAutomationTool = selectedAutomationTool
        self.gridSpacingBars = gridSpacingBars
        self.onAutomationToolChange = onAutomationToolChange
        self.onSetEnterFade = onSetEnterFade
        self.onSetExitFade = onSetExitFade
        self.onContainerTrimLeft = onContainerTrimLeft
        self.onContainerTrimRight = onContainerTrimRight
        self.onContainerSplit = onContainerSplit
        self.onGlueContainers = onGlueContainers
        self.onPlayheadTap = onPlayheadTap
        self.onTapBackground = onTapBackground
        self.onRangeSelect = onRangeSelect
        self.onResolveAudioFileBars = onResolveAudioFileBars
        self.snapToGrid = snapToGrid
        self.onSetCrossfadeCurveType = onSetCrossfadeCurveType
        self.automationSnapResolution = automationSnapResolution
        self.automationTimeSignature = automationTimeSignature
        self.automationGridMode = automationGridMode
        self.multiSelectCount = multiSelectCount
        self.onDeleteSelected = onDeleteSelected
        self.onDuplicateSelected = onDuplicateSelected
        self.onCopySelected = onCopySelected
        self.onSplitSelected = onSplitSelected
        self.visibleXMin = visibleXMin
        self.visibleXMax = visibleXMax
    }

    private var baseHeight: CGFloat {
        let subLaneCount = isAutomationExpanded ? automationSubLanePaths.count : 0
        let toolbarHeight = isAutomationExpanded && subLaneCount > 0 ? TimelineViewModel.automationToolbarHeight : 0
        return height - CGFloat(subLaneCount) * TimelineViewModel.automationSubLaneHeight - toolbarHeight
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
                            onCreateContainer?(1.0, 4.0)
                        }
                        if hasClipboard {
                            Button("Paste") {
                                onPasteAtBar?(1.0)
                            }
                        }
                    }

                // Drop target highlight with snapped position and resolved width
                if isDropTargeted, let bar = dropPreviewBar {
                    let lengthBars = dropPreviewLengthBars ?? 4.0
                    let previewWidth = pixelsPerBar * CGFloat(lengthBars)
                    let previewX = CGFloat(bar - 1.0) * pixelsPerBar
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

                // Existing containers (skip off-screen ones for viewport-aware rendering)
                ForEach(track.containers.filter { container in
                    let xStart = CGFloat(container.startBar - 1) * pixelsPerBar
                    let xEnd = CGFloat(container.endBar - 1) * pixelsPerBar
                    return xEnd >= visibleXMin && xStart <= visibleXMax
                }) { container in
                    containerView(for: container)
                        .equatable()
                        .offset(x: CGFloat(container.startBar - 1) * pixelsPerBar, y: 2)
                }

                // Crossfade overlays
                ForEach(track.crossfades) { xfade in
                    crossfadeOverlay(for: xfade)
                }
            }
            .coordinateSpace(name: "trackLane")
            .frame(width: CGFloat(totalBars) * pixelsPerBar, height: baseHeight)

            // Automation toolbar + sub-lanes (when expanded)
            // Toolbar is pinned to the visible viewport (same approach as piano roll toolbar)
            if isAutomationExpanded && !automationSubLanePaths.isEmpty {
                automationToolbar
                    .frame(width: toolbarViewportWidth > 0 ? toolbarViewportWidth : CGFloat(totalBars) * pixelsPerBar, height: TimelineViewModel.automationToolbarHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: toolbarViewportWidth > 0 ? toolbarScrollOffset : 0)
                    .background(
                        HorizontalScrollObserver { offset, width in
                            toolbarScrollOffset = offset
                            toolbarViewportWidth = width
                        }
                        .frame(width: 0, height: 0)
                    )
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                    .overlay(
                        Rectangle()
                            .frame(height: 0.5)
                            .foregroundStyle(Color.secondary.opacity(0.15)),
                        alignment: .bottom
                    )
            }
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
                        onDeleteTrackBreakpoint: onDeleteTrackBreakpoint,
                        snapResolution: automationSnapResolution,
                        timeSignature: automationTimeSignature,
                        gridMode: automationGridMode,
                        selectedTool: selectedAutomationTool,
                        gridSpacingBars: gridSpacingBars,
                        onReplaceBreakpoints: onReplaceBreakpoints,
                        onReplaceTrackBreakpoints: onReplaceTrackBreakpoints,
                        visibleXMin: visibleXMin,
                        visibleXMax: visibleXMax
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

    private func containerView(for container: Container) -> ContainerView {
        ContainerView(
            container: container,
            pixelsPerBar: pixelsPerBar,
            height: baseHeight - 4,
            selectionState: selectionState,
            trackColor: trackColor,
            waveformPeaks: waveformPeaksForContainer?(container),
            isClone: container.parentContainerID != nil,
            overriddenFields: container.overriddenFields,
            resolvedMIDISequence: resolvedMIDISequenceForContainer?(container),
            recordingDurationBars: recordingDurationBarsForContainer?(container),
            onSelect: { modifiers in onContainerSelect?(container.id, modifiers) },
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
            onRangeSelect: { startBar, endBar in onRangeSelect?(container.id, startBar, endBar) },
            onGlue: { onGlueContainers?() },
            snapToGrid: snapToGrid,
            crossfades: track.crossfades.filter { $0.containerAID == container.id || $0.containerBID == container.id },
            onSetCrossfadeCurveType: onSetCrossfadeCurveType,
            multiSelectCount: multiSelectCount,
            onDeleteSelected: onDeleteSelected,
            onDuplicateSelected: onDuplicateSelected,
            onCopySelected: onCopySelected,
            onSplitSelected: onSplitSelected,
            visibleXMin: visibleXMin,
            visibleXMax: visibleXMax
        )
    }

    /// Snaps an x-position to the grid by converting to bar, snapping, and converting back.
    private func snappedX(_ x: CGFloat) -> CGFloat {
        let rawBar = Double(x) / Double(pixelsPerBar) + 1.0
        let snapped = snapToGrid?(rawBar) ?? rawBar.rounded()
        return CGFloat(snapped - 1.0) * pixelsPerBar
    }

    private var createContainerGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if !isCreatingContainer {
                    isCreatingContainer = true
                    dragStartX = snappedX(value.startLocation.x)
                }
                dragCurrentX = snappedX(value.location.x)
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
                let startBar = Double(minX) / Double(pixelsPerBar) + 1.0
                let lengthBars = max(Double(maxX - minX) / Double(pixelsPerBar), 1.0)

                onCreateContainer?(startBar, lengthBars)
            }
    }

    private var automationToolbar: some View {
        HStack(spacing: 8) {
            Text("Automation")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            ForEach(AutomationTool.allCases, id: \.self) { tool in
                Button(action: { onAutomationToolChange?(tool) }) {
                    Image(systemName: tool.iconName)
                        .font(.system(size: 10))
                        .foregroundStyle(selectedAutomationTool == tool ? .white : .secondary)
                        .frame(width: 20, height: 20)
                        .background(selectedAutomationTool == tool ? Color.purple.opacity(0.8) : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .help(tool.label)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func crossfadeOverlay(for xfade: Crossfade) -> some View {
        let containerA = track.containers.first(where: { $0.id == xfade.containerAID })
        let containerB = track.containers.first(where: { $0.id == xfade.containerBID })
        if let a = containerA, let b = containerB {
            let overlap = xfade.duration(containerA: a, containerB: b)
            if overlap > 0 {
                let xStart = CGFloat(b.startBar - 1) * pixelsPerBar
                let width = CGFloat(overlap) * pixelsPerBar
                ZStack {
                    // Semi-transparent background
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                    // X-pattern
                    CrossfadeXShape()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                }
                .frame(width: width, height: baseHeight - 4)
                .offset(x: xStart, y: 2)
                .allowsHitTesting(false)
            }
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

// MARK: - Crossfade X-Pattern Shape

/// Draws an X pattern within the crossfade region to indicate a crossfade between two containers.
private struct CrossfadeXShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Draw X: top-left to bottom-right
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Draw X: bottom-left to top-right
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

// MARK: - Audio File Drop Delegate

private struct AudioFileDropDelegate: DropDelegate {
    let pixelsPerBar: CGFloat
    @Binding var isDropTargeted: Bool
    @Binding var dropPreviewBar: Double?
    @Binding var dropPreviewLengthBars: Double?
    var onResolveAudioFileBars: ((_ url: URL) -> Double?)?
    var onDropAudioFile: ((_ url: URL, _ startBar: Double) -> Void)?
    var onDropMIDIFile: ((_ url: URL, _ startBar: Double) -> Void)?

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
        let barAtDrop = dropPreviewBar ?? max(Double(info.location.x / pixelsPerBar) + 1.0, 1.0)
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
        let bar = max(round(info.location.x / pixelsPerBar) + 1.0, 1.0)
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
        lhs.automationSnapResolution == rhs.automationSnapResolution &&
        lhs.automationTimeSignature == rhs.automationTimeSignature &&
        lhs.automationGridMode == rhs.automationGridMode &&
        lhs.selectedAutomationTool == rhs.selectedAutomationTool &&
        lhs.gridSpacingBars == rhs.gridSpacingBars &&
        lhs.otherSongs.count == rhs.otherSongs.count &&
        zip(lhs.otherSongs, rhs.otherSongs).allSatisfy { $0.id == $1.id && $0.name == $1.name } &&
        lhs.multiSelectCount == rhs.multiSelectCount &&
        lhs.visibleXMin == rhs.visibleXMin &&
        lhs.visibleXMax == rhs.visibleXMax
    }
}
