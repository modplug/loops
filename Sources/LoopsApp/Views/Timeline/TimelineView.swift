import SwiftUI
import LoopsCore
import LoopsEngine

/// The main timeline view combining grid, track lanes, and playhead.
/// Scrolling is managed by the parent view (MainContentView).
public struct TimelineView: View {
    @Bindable var viewModel: TimelineViewModel
    @Bindable var projectViewModel: ProjectViewModel
    var selectionState: SelectionState
    var clipboardState: ClipboardState
    let song: Song
    let tracks: [Track]
    let trackHeight: CGFloat
    let minHeight: CGFloat
    var pianoRollState: PianoRollEditorState?
    var ghostDropState: GhostTrackDropState?
    var showRulerAndSections: Bool = true
    var onDropFilesToNewTracks: ((_ urls: [URL], _ startBar: Double) -> Void)?
    var onContainerDoubleClick: (() -> Void)?
    var onPlayheadPosition: ((Double) -> Void)?
    var onNotePreview: ((_ pitch: UInt8, _ isNoteOn: Bool) -> Void)?
    var onOpenPianoRollSheet: (() -> Void)?
    var onSectionSelect: ((ID<SectionRegion>) -> Void)?
    var onRangeSelect: ((ClosedRange<Int>) -> Void)?
    var onRangeDeselect: (() -> Void)?

    @State private var selectedBreakpointID: ID<AutomationBreakpoint>?

    public init(viewModel: TimelineViewModel, projectViewModel: ProjectViewModel, selectionState: SelectionState, clipboardState: ClipboardState? = nil, song: Song, tracks: [Track]? = nil, trackHeight: CGFloat = 80, minHeight: CGFloat = 0, pianoRollState: PianoRollEditorState? = nil, ghostDropState: GhostTrackDropState? = nil, showRulerAndSections: Bool = true, onDropFilesToNewTracks: ((_ urls: [URL], _ startBar: Double) -> Void)? = nil, onContainerDoubleClick: (() -> Void)? = nil, onPlayheadPosition: ((Double) -> Void)? = nil, onNotePreview: ((_ pitch: UInt8, _ isNoteOn: Bool) -> Void)? = nil, onOpenPianoRollSheet: (() -> Void)? = nil, onSectionSelect: ((ID<SectionRegion>) -> Void)? = nil, onRangeSelect: ((ClosedRange<Int>) -> Void)? = nil, onRangeDeselect: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.projectViewModel = projectViewModel
        self.selectionState = selectionState
        self.clipboardState = clipboardState ?? projectViewModel.clipboardState
        self.song = song
        self.tracks = tracks ?? song.tracks
        self.trackHeight = trackHeight
        self.minHeight = minHeight
        self.pianoRollState = pianoRollState
        self.ghostDropState = ghostDropState
        self.showRulerAndSections = showRulerAndSections
        self.onDropFilesToNewTracks = onDropFilesToNewTracks
        self.onContainerDoubleClick = onContainerDoubleClick
        self.onPlayheadPosition = onPlayheadPosition
        self.onNotePreview = onNotePreview
        self.onOpenPianoRollSheet = onOpenPianoRollSheet
        self.onSectionSelect = onSectionSelect
        self.onRangeSelect = onRangeSelect
        self.onRangeDeselect = onRangeDeselect
    }

    public var totalContentHeight: CGFloat {
        tracks.reduce(CGFloat(0)) { total, track in
            let base = viewModel.baseTrackHeight(for: track.id)
            let trackH = viewModel.trackHeight(for: track, baseHeight: base)
            let prExtra = pianoRollState?.extraHeight(forTrackID: track.id) ?? 0
            return total + trackH + prExtra
        }
    }

    /// The height used for the grid and playhead — fills available space.
    /// Includes ruler + section lane + track content (when ruler is shown).
    /// Adds bottom padding so the grid extends below the last track,
    /// giving visual breathing room above the horizontal scrollbar.
    private var displayHeight: CGFloat {
        let headerHeight = showRulerAndSections ? TimelineCanvasView.trackAreaTop : CGFloat(0)
        let contentHeight = headerHeight + totalContentHeight + 200
        return max(contentHeight, minHeight)
    }

    public var body: some View {
        if viewModel.useNSViewTimeline && viewModel.useMetalTimeline {
            metalBody
        } else if viewModel.useNSViewTimeline {
            canvasBody
        } else {
            swiftUIBody
        }
    }

    // MARK: - Metal GPU Rendering Path

    /// Metal-accelerated rendering path. Identical data model to the CG canvas,
    /// but all geometry (grid, containers, waveforms, MIDI, fades) is GPU-rendered.
    /// Text labels are drawn via a CoreGraphics overlay layer.
    private var metalBody: some View {
        TimelineMetalRepresentable(
            tracks: tracks,
            viewModel: viewModel,
            projectViewModel: projectViewModel,
            selectionState: selectionState,
            timeSignature: song.timeSignature,
            minHeight: minHeight,
            sections: song.sections,
            showRulerAndSections: showRulerAndSections,
            onPlayheadPosition: onPlayheadPosition,
            onSectionSelect: onSectionSelect,
            onRangeSelect: onRangeSelect,
            onRangeDeselect: onRangeDeselect
        )
        .frame(
            width: viewModel.quantizedFrameWidth,
            height: displayHeight
        )
        .onDrop(of: [.fileURL], delegate: TimelineEmptyAreaDropDelegate(
            ghostDropState: ghostDropState,
            viewModel: viewModel,
            song: song,
            onPerformDrop: onDropFilesToNewTracks
        ))
        .onKeyPress("+") {
            viewModel.zoomIn()
            return .handled
        }
        .onKeyPress("-") {
            viewModel.zoomOut()
            return .handled
        }
        .onKeyPress(.delete) {
            if let bpID = selectedBreakpointID {
                deleteSelectedBreakpoint(bpID)
                return .handled
            }
            deleteSelectedContainer()
            return .handled
        }
    }

    // MARK: - NSView Canvas Path

    /// High-performance NSView rendering path.
    /// Grid, containers, waveforms, MIDI minimaps, fades, crossfades, range selection,
    /// playhead, and cursor are all rendered in a single draw(_:) call.
    /// Pointer tracking and click-to-position are handled by the NSView itself.
    private var canvasBody: some View {
        TimelineCanvasRepresentable(
            tracks: tracks,
            viewModel: viewModel,
            projectViewModel: projectViewModel,
            selectionState: selectionState,
            timeSignature: song.timeSignature,
            minHeight: minHeight,
            sections: song.sections,
            showRulerAndSections: showRulerAndSections,
            onPlayheadPosition: onPlayheadPosition,
            onSectionSelect: onSectionSelect,
            onRangeSelect: onRangeSelect,
            onRangeDeselect: onRangeDeselect
        )
        .frame(
            width: viewModel.quantizedFrameWidth,
            height: displayHeight
        )
        .onDrop(of: [.fileURL], delegate: TimelineEmptyAreaDropDelegate(
            ghostDropState: ghostDropState,
            viewModel: viewModel,
            song: song,
            onPerformDrop: onDropFilesToNewTracks
        ))
        .onKeyPress("+") {
            viewModel.zoomIn()
            return .handled
        }
        .onKeyPress("-") {
            viewModel.zoomOut()
            return .handled
        }
        .onKeyPress(.delete) {
            if let bpID = selectedBreakpointID {
                deleteSelectedBreakpoint(bpID)
                return .handled
            }
            deleteSelectedContainer()
            return .handled
        }
    }

    // MARK: - SwiftUI Path (original)

    private var swiftUIBody: some View {
        ZStack(alignment: .topLeading) {
            // Grid overlay — fills available space, with click-to-position gesture and cursor tracking
            GridOverlayView(
                totalBars: viewModel.totalBars,
                pixelsPerBar: viewModel.pixelsPerBar,
                timeSignature: song.timeSignature,
                height: displayHeight,
                gridMode: viewModel.gridMode,
                visibleXMin: viewModel.visibleXMin,
                visibleXMax: viewModel.visibleXMax
            )
            .contentShape(Rectangle())
            .onTapGesture { location in
                let bar = viewModel.snappedBar(forXPosition: location.x, timeSignature: song.timeSignature)
                onPlayheadPosition?(bar)
            }

            // Track lanes stacked vertically.
            // Uses VStack (not LazyVStack) because there is no direct ScrollView parent—
            // the outer vertical scroll is in MainContentView, so LazyVStack would render
            // all items anyway but evaluate each body TWICE (measure + layout).
            VStack(spacing: 0) {
                ForEach(tracks) { track in
                    trackLaneSection(track: track, song: song)
                }

                // Ghost track lanes (shown during file drop over empty space)
                if let ghostState = ghostDropState, ghostState.isActive {
                    ForEach(ghostState.ghostTracks) { ghost in
                        ghostTrackLane(ghost: ghost, dropBar: ghostState.dropBar)
                    }
                }
            }

            // Range selection overlay
            if let range = viewModel.selectedRange {
                let startX = CGFloat(range.lowerBound - 1) * viewModel.pixelsPerBar
                let width = CGFloat(range.count) * viewModel.pixelsPerBar
                Rectangle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: width, height: displayHeight)
                    .offset(x: startX)
                    .allowsHitTesting(false)
            }

            // Cursor line — isolated so mouse movement doesn't re-evaluate track lanes
            CursorOverlayView(
                viewModel: viewModel,
                height: displayHeight
            )

            // Playhead — isolated so 60fps updates don't re-evaluate track lanes
            PlayheadOverlayView(
                viewModel: viewModel,
                height: displayHeight
            )

            // Pointer tracking — uses NSTrackingArea so cursor position updates
            // even when hovering over containers or other interactive elements
            PointerTrackingOverlay { x in
                viewModel.cursorX = x
            }
            .allowsHitTesting(false)
        }
        .frame(
            width: viewModel.totalWidth,
            height: displayHeight
        )
        .onDrop(of: [.fileURL], delegate: TimelineEmptyAreaDropDelegate(
            ghostDropState: ghostDropState,
            viewModel: viewModel,
            song: song,
            onPerformDrop: onDropFilesToNewTracks
        ))
        .onKeyPress("+") {
            viewModel.zoomIn()
            return .handled
        }
        .onKeyPress("-") {
            viewModel.zoomOut()
            return .handled
        }
        .onKeyPress(.delete) {
            if let bpID = selectedBreakpointID {
                deleteSelectedBreakpoint(bpID)
                return .handled
            }
            deleteSelectedContainer()
            return .handled
        }
    }

    private func deleteSelectedContainer() {
        guard let containerID = selectionState.selectedContainerID else { return }
        for track in song.tracks {
            if track.containers.contains(where: { $0.id == containerID }) {
                projectViewModel.removeContainer(trackID: track.id, containerID: containerID)
                return
            }
        }
    }

    private func deleteSelectedBreakpoint(_ breakpointID: ID<AutomationBreakpoint>) {
        for track in song.tracks {
            // Check track-level automation lanes
            for lane in track.trackAutomationLanes {
                if lane.breakpoints.contains(where: { $0.id == breakpointID }) {
                    projectViewModel.removeTrackAutomationBreakpoint(trackID: track.id, laneID: lane.id, breakpointID: breakpointID)
                    selectedBreakpointID = nil
                    return
                }
            }
            // Check container-level automation lanes
            for container in track.containers {
                for lane in container.automationLanes {
                    if lane.breakpoints.contains(where: { $0.id == breakpointID }) {
                        projectViewModel.removeAutomationBreakpoint(containerID: container.id, laneID: lane.id, breakpointID: breakpointID)
                        selectedBreakpointID = nil
                        return
                    }
                }
            }
        }
    }

    /// Computes the container-relative playhead beat for the piano roll.
    private func computePlayheadBeat(container: Container) -> Double? {
        let beatsPerBar = Double(song.timeSignature.beatsPerBar)
        let playheadBeat = (viewModel.playheadBar - 1.0) * beatsPerBar
        let containerStartBeat = Double(container.startBar - 1) * beatsPerBar
        let totalContainerBeats = Double(container.lengthBars) * beatsPerBar
        let relative = playheadBeat - containerStartBeat
        guard relative >= 0, relative < totalContainerBeats else { return nil }
        return relative
    }

    // MARK: - Track Lane Section

    @ViewBuilder
    private func trackLaneSection(track: Track, song: Song) -> some View {
        let base = viewModel.baseTrackHeight(for: track.id)
        let perTrackHeight = viewModel.trackHeight(for: track, baseHeight: base)
        let isExpanded = viewModel.automationExpanded.contains(track.id)
        let subLanePaths = uniqueAutomationPaths(for: track)
        trackLaneView(track: track, song: song, height: perTrackHeight, isExpanded: isExpanded, subLanePaths: subLanePaths)
            .equatable()
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
            }
            .onChange(of: selectionState.selectedContainerID) { _, newID in
                if let prState = pianoRollState,
                   prState.isExpanded,
                   prState.trackID == track.id,
                   let newContainerID = newID,
                   track.containers.contains(where: { $0.id == newContainerID }) {
                    prState.switchContainer(containerID: newContainerID)
                }
            }

        // Inline piano roll below this track
        if let prState = pianoRollState,
           prState.isExpanded,
           prState.trackID == track.id {
            let resolvedContainers = track.containers.map { projectViewModel.resolveContainer($0) }
            let activeID = prState.containerID ?? track.containers.first?.id ?? ID<Container>()
            InlinePianoRollView(
                containers: resolvedContainers,
                activeContainerID: activeID,
                totalTimelineBars: viewModel.totalBars,
                timeSignature: song.timeSignature,
                trackHeaderWidth: 0,
                timelinePixelsPerBar: viewModel.pixelsPerBar,
                totalTimelineWidth: viewModel.totalWidth,
                editorState: prState,
                onAddNote: { containerID, note in
                    projectViewModel.addMIDINote(containerID: containerID, note: note)
                },
                onUpdateNote: { containerID, note in
                    projectViewModel.updateMIDINote(containerID: containerID, note: note)
                },
                onRemoveNote: { containerID, noteID in
                    projectViewModel.removeMIDINote(containerID: containerID, noteID: noteID)
                },
                onNotePreview: onNotePreview,
                onOpenSheet: onOpenPianoRollSheet,
                onOverrideMIDI: {
                    if let containerID = prState.containerID,
                       let container = track.containers.first(where: { $0.id == containerID }) {
                        let resolvedSeq = projectViewModel.resolveContainer(container).midiSequence ?? MIDISequence()
                        projectViewModel.setContainerMIDISequence(
                            containerID: containerID,
                            sequence: resolvedSeq
                        )
                    }
                },
                onNavigateToParent: {
                    if let containerID = prState.containerID,
                       let container = track.containers.first(where: { $0.id == containerID }),
                       let parentID = container.parentContainerID {
                        projectViewModel.selectedContainerID = parentID
                        onOpenPianoRollSheet?()
                    }
                },
                onSelectContainer: { containerID in
                    prState.switchContainer(containerID: containerID)
                }
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
            }
        }
    }

    // MARK: - Ghost Track Lane

    @ViewBuilder
    private func ghostTrackLane(ghost: GhostTrackInfo, dropBar: Double) -> some View {
        let laneHeight = TimelineViewModel.defaultTrackHeight
        let trackColor = ghost.trackColor
        let lengthBars = ghost.lengthBars ?? 4.0
        let previewWidth = viewModel.pixelsPerBar * CGFloat(lengthBars)
        let previewX = CGFloat(dropBar - 1.0) * viewModel.pixelsPerBar

        ZStack(alignment: .topLeading) {
            // Semi-transparent background
            Rectangle()
                .fill(trackColor.opacity(0.04))
                .frame(width: viewModel.totalWidth, height: laneHeight)

            // Dashed container preview at drop position
            RoundedRectangle(cornerRadius: 4)
                .fill(trackColor.opacity(0.12))
                .strokeBorder(trackColor.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
                .frame(width: previewWidth, height: laneHeight - 4)
                .offset(x: previewX, y: 2)
        }
        .frame(width: viewModel.totalWidth, height: laneHeight)
        .opacity(0.7)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
    }

    private func trackLaneView(track: Track, song: Song, height: CGFloat, isExpanded: Bool, subLanePaths: [EffectPath]) -> TrackLaneView {
        TrackLaneView(
            track: track,
            pixelsPerBar: viewModel.pixelsPerBar,
            totalBars: viewModel.totalBars,
            height: height,
            selectionState: selectionState,
            waveformPeaksForContainer: { container in
                projectViewModel.waveformPeaks(for: container)
            },
            recordingDurationBarsForContainer: { container in
                projectViewModel.recordingDurationBars(for: container)
            },
            onContainerSelect: { containerID, modifiers in
                if modifiers.contains(.command) {
                    // Cmd+Click: toggle container in multi-selection
                    if selectionState.selectedContainerIDs.isEmpty {
                        // Promote current single selection to multi-set
                        if let existing = selectionState.selectedContainerID {
                            selectionState.selectedContainerIDs = [existing]
                            selectionState.selectedContainerID = nil
                        }
                    }
                    if selectionState.selectedContainerIDs.contains(containerID) {
                        selectionState.selectedContainerIDs.remove(containerID)
                    } else {
                        selectionState.selectedContainerIDs.insert(containerID)
                    }
                    selectionState.lastSelectedContainerID = containerID
                } else if modifiers.contains(.shift) {
                    // Shift+Click: range selection within this track
                    let allContainers = track.containers.sorted { $0.startBar < $1.startBar }
                    let anchorID = selectionState.lastSelectedContainerID ?? selectionState.selectedContainerID
                    guard let anchor = anchorID,
                          let anchorIdx = allContainers.firstIndex(where: { $0.id == anchor }),
                          let clickIdx = allContainers.firstIndex(where: { $0.id == containerID }) else {
                        selectionState.selectedContainerID = containerID
                        return
                    }
                    let range = min(anchorIdx, clickIdx)...max(anchorIdx, clickIdx)
                    selectionState.selectedContainerIDs = Set(allContainers[range].map(\.id))
                    selectionState.selectedContainerID = nil
                    selectionState.lastSelectedContainerID = containerID
                } else {
                    // Plain click: single selection
                    selectionState.selectedContainerID = containerID
                }
            },
            onContainerDelete: { containerID in
                projectViewModel.removeContainer(trackID: track.id, containerID: containerID)
            },
            onContainerMove: { containerID, newStartBar in
                projectViewModel.moveContainer(trackID: track.id, containerID: containerID, newStartBar: newStartBar)
            },
            onContainerResizeLeft: { containerID, newStart, newLength in
                projectViewModel.resizeContainer(trackID: track.id, containerID: containerID, newStartBar: newStart, newLengthBars: newLength)
            },
            onContainerResizeRight: { containerID, newLength in
                projectViewModel.resizeContainer(trackID: track.id, containerID: containerID, newLengthBars: newLength)
            },
            onCreateContainer: { startBar, lengthBars in
                let _ = projectViewModel.addContainer(trackID: track.id, startBar: startBar, lengthBars: lengthBars)
            },
            onDropAudioFile: { url, startBar in
                if let containerID = projectViewModel.importAudioAsync(
                    url: url,
                    trackID: track.id,
                    startBar: startBar,
                    audioDirectory: projectViewModel.audioDirectory
                ) {
                    if let song = projectViewModel.currentSong,
                       let trackObj = song.tracks.first(where: { $0.id == track.id }),
                       let container = trackObj.containers.first(where: { $0.id == containerID }) {
                        viewModel.ensureBarVisible(container.endBar)
                    }
                }
            },
            onDropMIDIFile: { url, startBar in
                projectViewModel.importMIDIFile(url: url, trackID: track.id, startBar: startBar)
            },
            onContainerDoubleClick: { containerID in
                selectionState.selectedContainerID = containerID
                onContainerDoubleClick?()
            },
            onCloneContainer: { containerID, newStartBar in
                projectViewModel.cloneContainer(trackID: track.id, containerID: containerID, newStartBar: newStartBar)
            },
            onCopyContainer: { containerID in
                projectViewModel.copyContainer(trackID: track.id, containerID: containerID)
            },
            onCopyContainerToSong: { containerID, songID in
                projectViewModel.copyContainerToSong(trackID: track.id, containerID: containerID, targetSongID: songID)
            },
            otherSongs: projectViewModel.otherSongs,
            onDuplicateContainer: { containerID in
                projectViewModel.duplicateContainer(trackID: track.id, containerID: containerID)
            },
            onLinkCloneContainer: { containerID in
                guard let container = track.containers.first(where: { $0.id == containerID }) else { return }
                projectViewModel.cloneContainer(trackID: track.id, containerID: containerID, newStartBar: container.endBar)
            },
            onUnlinkContainer: { containerID in
                projectViewModel.consolidateContainer(trackID: track.id, containerID: containerID)
            },
            onContainerArmToggle: { containerID in
                projectViewModel.toggleContainerRecordArm(trackID: track.id, containerID: containerID)
            },
            onPasteAtBar: { bar in
                projectViewModel.pasteContainers(trackID: track.id, atBar: bar)
            },
            hasClipboard: !clipboardState.clipboard.isEmpty,
            resolvedMIDISequenceForContainer: { projectViewModel.resolvedMIDISequence($0) },
            isAutomationExpanded: isExpanded,
            automationSubLanePaths: subLanePaths,
            selectedBreakpointID: selectedBreakpointID,
            onAddBreakpoint: { containerID, laneID, breakpoint in
                projectViewModel.addAutomationBreakpoint(containerID: containerID, laneID: laneID, breakpoint: breakpoint)
            },
            onUpdateBreakpoint: { containerID, laneID, breakpoint in
                projectViewModel.updateAutomationBreakpoint(containerID: containerID, laneID: laneID, breakpoint: breakpoint)
            },
            onDeleteBreakpoint: { containerID, laneID, breakpointID in
                projectViewModel.removeAutomationBreakpoint(containerID: containerID, laneID: laneID, breakpointID: breakpointID)
                if selectedBreakpointID == breakpointID {
                    selectedBreakpointID = nil
                }
            },
            onSelectBreakpoint: { bpID in
                selectedBreakpointID = bpID
            },
            onAddTrackBreakpoint: { laneID, breakpoint in
                projectViewModel.addTrackAutomationBreakpoint(trackID: track.id, laneID: laneID, breakpoint: breakpoint)
            },
            onUpdateTrackBreakpoint: { laneID, breakpoint in
                projectViewModel.updateTrackAutomationBreakpoint(trackID: track.id, laneID: laneID, breakpoint: breakpoint)
            },
            onDeleteTrackBreakpoint: { laneID, breakpointID in
                projectViewModel.removeTrackAutomationBreakpoint(trackID: track.id, laneID: laneID, breakpointID: breakpointID)
                if selectedBreakpointID == breakpointID {
                    selectedBreakpointID = nil
                }
            },
            onReplaceBreakpoints: { containerID, laneID, startPos, endPos, breakpoints in
                projectViewModel.replaceAutomationBreakpoints(
                    containerID: containerID, laneID: laneID,
                    startPosition: startPos, endPosition: endPos,
                    replacements: breakpoints
                )
            },
            onReplaceTrackBreakpoints: { laneID, startPos, endPos, breakpoints in
                projectViewModel.replaceTrackAutomationBreakpoints(
                    trackID: track.id, laneID: laneID,
                    startPosition: startPos, endPosition: endPos,
                    replacements: breakpoints
                )
            },
            selectedAutomationTool: viewModel.selectedAutomationTool,
            onAutomationToolChange: { tool in
                viewModel.selectedAutomationTool = tool
            },
            onSetEnterFade: { containerID, fade in
                projectViewModel.setContainerEnterFade(containerID: containerID, fade: fade)
            },
            onSetExitFade: { containerID, fade in
                projectViewModel.setContainerExitFade(containerID: containerID, fade: fade)
            },
            onContainerTrimLeft: { containerID, offset, startBar, length in
                projectViewModel.trimContainerLeft(trackID: track.id, containerID: containerID, newStartBar: startBar, newLength: length, newAudioStartOffset: offset)
            },
            onContainerTrimRight: { containerID, newLength in
                projectViewModel.trimContainerRight(trackID: track.id, containerID: containerID, newLength: newLength)
            },
            onContainerSplit: { containerID in
                let splitBar = viewModel.playheadBar
                projectViewModel.splitContainer(trackID: track.id, containerID: containerID, atBar: splitBar)
            },
            onGlueContainers: {
                projectViewModel.glueContainers(containerIDs: projectViewModel.selectedContainerIDs)
            },
            onPlayheadTap: { timelineX in
                let bar = viewModel.snappedBar(forXPosition: timelineX, timeSignature: song.timeSignature)
                onPlayheadPosition?(bar)
            },
            onTapBackground: { xPosition in
                let bar = viewModel.snappedBar(forXPosition: xPosition, timeSignature: song.timeSignature)
                onPlayheadPosition?(bar)
            },
            onRangeSelect: { containerID, startBar, endBar in
                selectionState.rangeSelection = SelectionState.RangeSelection(
                    containerID: containerID,
                    startBar: startBar,
                    endBar: endBar
                )
            },
            onResolveAudioFileBars: { url in
                guard let metadata = try? AudioImporter.readMetadata(from: url) else { return nil }
                return AudioImporter.barsForDuration(
                    metadata.durationSeconds,
                    tempo: song.tempo,
                    timeSignature: song.timeSignature
                )
            },
            snapToGrid: { bar in
                viewModel.snapToGrid(bar, timeSignature: song.timeSignature)
            },
            onSetCrossfadeCurveType: { crossfadeID, curveType in
                projectViewModel.setCrossfadeCurveType(trackID: track.id, crossfadeID: crossfadeID, curveType: curveType)
            },
            automationSnapResolution: viewModel.effectiveSnapResolution(timeSignature: song.timeSignature),
            automationTimeSignature: song.timeSignature,
            automationGridMode: viewModel.gridMode,
            multiSelectCount: selectionState.effectiveSelectedContainerIDs.count,
            onDeleteSelected: {
                let trackContainerIDs = Set(track.containers.map(\.id))
                let toDelete = selectionState.effectiveSelectedContainerIDs.intersection(trackContainerIDs)
                for id in toDelete {
                    projectViewModel.removeContainer(trackID: track.id, containerID: id)
                }
                selectionState.deselectAll()
            },
            onDuplicateSelected: {
                let trackContainerIDs = Set(track.containers.map(\.id))
                let toDuplicate = selectionState.effectiveSelectedContainerIDs.intersection(trackContainerIDs)
                for id in toDuplicate {
                    _ = projectViewModel.duplicateContainer(trackID: track.id, containerID: id)
                }
            },
            onCopySelected: {
                if let lastID = selectionState.lastSelectedContainerID {
                    projectViewModel.copyContainer(trackID: track.id, containerID: lastID)
                }
            },
            onSplitSelected: {
                let splitBar = viewModel.playheadBar
                let trackContainerIDs = Set(track.containers.map(\.id))
                let toSplit = selectionState.effectiveSelectedContainerIDs.intersection(trackContainerIDs)
                for id in toSplit {
                    _ = projectViewModel.splitContainer(trackID: track.id, containerID: id, atBar: splitBar)
                }
            },
            visibleXMin: viewModel.visibleXMin,
            visibleXMax: viewModel.visibleXMax
        )
    }

    /// Returns unique automation target paths across track-level and container automation lanes.
    private func uniqueAutomationPaths(for track: Track) -> [EffectPath] {
        var seen = Set<EffectPath>()
        var result: [EffectPath] = []
        // Track-level automation lanes first (volume, pan)
        for lane in track.trackAutomationLanes {
            if seen.insert(lane.targetPath).inserted {
                result.append(lane.targetPath)
            }
        }
        // Then container-level automation lanes
        for container in track.containers {
            for lane in container.automationLanes {
                if seen.insert(lane.targetPath).inserted {
                    result.append(lane.targetPath)
                }
            }
        }
        return result
    }
}

// MARK: - Timeline Empty Area Drop Delegate

/// Handles file drops on the timeline grid area below existing tracks.
/// Activates ghost track previews and handles the actual file import on drop.
private struct TimelineEmptyAreaDropDelegate: DropDelegate {
    let ghostDropState: GhostTrackDropState?
    let viewModel: TimelineViewModel
    let song: Song
    let onPerformDrop: ((_ urls: [URL], _ startBar: Double) -> Void)?

    private static let supportedAudioExtensions: Set<String> = ["wav", "aiff", "aif", "caf", "mp3", "m4a"]
    private static let supportedMIDIExtensions: Set<String> = ["mid", "midi"]

    func dropEntered(info: DropInfo) {
        guard let ghostState = ghostDropState else { return }
        if ghostState.activate() {
            resolveGhostTracks(from: info, into: ghostState)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if let ghostState = ghostDropState {
            let bar = viewModel.snappedBar(forXPosition: info.location.x, timeSignature: song.timeSignature)
            ghostState.dropBar = max(1.0, bar)
        }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        ghostDropState?.deactivate()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let ghostState = ghostDropState, let onPerformDrop else { return false }
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else {
            ghostState.reset()
            return false
        }

        var resolvedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    let ext = url.pathExtension.lowercased()
                    if Self.supportedMIDIExtensions.contains(ext) || Self.supportedAudioExtensions.contains(ext) {
                        resolvedURLs.append(url)
                    }
                }
                group.leave()
            }
        }

        let dropBar = ghostState.dropBar
        group.notify(queue: .main) {
            ghostState.reset()
            if !resolvedURLs.isEmpty {
                onPerformDrop(resolvedURLs, dropBar)
            }
        }

        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    private func resolveGhostTracks(from info: DropInfo, into state: GhostTrackDropState) {
        let beatsPerBar = Double(song.timeSignature.beatsPerBar)
        let tempo = song.tempo
        let timeSignature = song.timeSignature

        let providers = info.itemProviders(for: [.fileURL])
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                let ext = url.pathExtension.lowercased()

                if Self.supportedMIDIExtensions.contains(ext) {
                    let importer = MIDIFileImporter()
                    if let result = try? importer.importFile(at: url) {
                        let baseName = url.deletingPathExtension().lastPathComponent
                        DispatchQueue.main.async {
                            for (index, sequence) in result.sequences.enumerated() {
                                let totalBeats = sequence.durationBeats
                                let lengthBars = max(1.0, ceil(totalBeats / beatsPerBar))
                                let name = result.sequences.count > 1
                                    ? "\(baseName) - Track \(index + 1)"
                                    : baseName
                                state.ghostTracks.append(GhostTrackInfo(
                                    fileName: name,
                                    lengthBars: lengthBars,
                                    trackKind: .midi,
                                    url: url
                                ))
                            }
                        }
                    }
                } else if Self.supportedAudioExtensions.contains(ext) {
                    let baseName = url.deletingPathExtension().lastPathComponent
                    var lengthBars: Double?
                    if let metadata = try? AudioImporter.readMetadata(from: url) {
                        lengthBars = AudioImporter.barsForDuration(
                            metadata.durationSeconds,
                            tempo: tempo,
                            timeSignature: timeSignature
                        )
                    }
                    DispatchQueue.main.async {
                        state.ghostTracks.append(GhostTrackInfo(
                            fileName: baseName,
                            lengthBars: lengthBars,
                            trackKind: .audio,
                            url: url
                        ))
                    }
                }
            }
        }
    }
}
