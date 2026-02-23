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
    var onContainerDoubleClick: (() -> Void)?
    var onPlayheadPosition: ((Double) -> Void)?
    var onNotePreview: ((_ pitch: UInt8, _ isNoteOn: Bool) -> Void)?
    var onOpenPianoRollSheet: (() -> Void)?

    @State private var selectedBreakpointID: ID<AutomationBreakpoint>?

    public init(viewModel: TimelineViewModel, projectViewModel: ProjectViewModel, selectionState: SelectionState, clipboardState: ClipboardState? = nil, song: Song, tracks: [Track]? = nil, trackHeight: CGFloat = 80, minHeight: CGFloat = 0, pianoRollState: PianoRollEditorState? = nil, onContainerDoubleClick: (() -> Void)? = nil, onPlayheadPosition: ((Double) -> Void)? = nil, onNotePreview: ((_ pitch: UInt8, _ isNoteOn: Bool) -> Void)? = nil, onOpenPianoRollSheet: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.projectViewModel = projectViewModel
        self.selectionState = selectionState
        self.clipboardState = clipboardState ?? projectViewModel.clipboardState
        self.song = song
        self.tracks = tracks ?? song.tracks
        self.trackHeight = trackHeight
        self.minHeight = minHeight
        self.pianoRollState = pianoRollState
        self.onContainerDoubleClick = onContainerDoubleClick
        self.onPlayheadPosition = onPlayheadPosition
        self.onNotePreview = onNotePreview
        self.onOpenPianoRollSheet = onOpenPianoRollSheet
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
    private var displayHeight: CGFloat {
        max(totalContentHeight, minHeight)
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Grid overlay — fills available space, with click-to-position gesture and cursor tracking
            GridOverlayView(
                totalBars: viewModel.totalBars,
                pixelsPerBar: viewModel.pixelsPerBar,
                timeSignature: song.timeSignature,
                height: displayHeight,
                gridMode: viewModel.gridMode
            )
            .contentShape(Rectangle())
            .onTapGesture { location in
                let bar = viewModel.snappedBar(forXPosition: location.x, timeSignature: song.timeSignature)
                onPlayheadPosition?(bar)
            }

            // Track lanes stacked vertically (lazy — off-screen tracks are not rendered)
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(tracks) { track in
                    trackLaneSection(track: track, song: song)
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
            onContainerSelect: { containerID in
                selectionState.selectedContainerID = containerID
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
            }
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
