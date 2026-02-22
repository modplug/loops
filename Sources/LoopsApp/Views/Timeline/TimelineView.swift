import SwiftUI
import LoopsCore

/// The main timeline view combining grid, track lanes, and playhead.
/// Scrolling is managed by the parent view (MainContentView).
public struct TimelineView: View {
    @Bindable var viewModel: TimelineViewModel
    @Bindable var projectViewModel: ProjectViewModel
    let song: Song
    let tracks: [Track]
    let trackHeight: CGFloat
    let minHeight: CGFloat
    var onContainerDoubleClick: (() -> Void)?
    var onPlayheadPosition: ((Double) -> Void)?

    @State private var selectedBreakpointID: ID<AutomationBreakpoint>?

    public init(viewModel: TimelineViewModel, projectViewModel: ProjectViewModel, song: Song, tracks: [Track]? = nil, trackHeight: CGFloat = 80, minHeight: CGFloat = 0, onContainerDoubleClick: (() -> Void)? = nil, onPlayheadPosition: ((Double) -> Void)? = nil) {
        self.viewModel = viewModel
        self.projectViewModel = projectViewModel
        self.song = song
        self.tracks = tracks ?? song.tracks
        self.trackHeight = trackHeight
        self.minHeight = minHeight
        self.onContainerDoubleClick = onContainerDoubleClick
        self.onPlayheadPosition = onPlayheadPosition
    }

    public var totalContentHeight: CGFloat {
        tracks.reduce(CGFloat(0)) { total, track in
            total + viewModel.trackHeight(for: track, baseHeight: trackHeight)
        }
    }

    /// The height used for the grid and playhead — fills available space.
    private var displayHeight: CGFloat {
        max(totalContentHeight, minHeight)
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Grid overlay — fills available space, with click-to-position gesture
            GridOverlayView(
                totalBars: viewModel.totalBars,
                pixelsPerBar: viewModel.pixelsPerBar,
                timeSignature: song.timeSignature,
                height: displayHeight
            )
            .contentShape(Rectangle())
            .onTapGesture { location in
                let bar = viewModel.snappedBar(forXPosition: location.x, timeSignature: song.timeSignature)
                onPlayheadPosition?(bar)
            }

            // Track lanes stacked vertically
            VStack(spacing: 0) {
                ForEach(tracks) { track in
                    let perTrackHeight = viewModel.trackHeight(for: track, baseHeight: trackHeight)
                    let isExpanded = viewModel.automationExpanded.contains(track.id)
                    let subLanePaths = uniqueAutomationPaths(for: track)
                    TrackLaneView(
                        track: track,
                        pixelsPerBar: viewModel.pixelsPerBar,
                        totalBars: viewModel.totalBars,
                        height: perTrackHeight,
                        selectedContainerID: projectViewModel.selectedContainerID,
                        waveformPeaksForContainer: { container in
                            projectViewModel.waveformPeaks(for: container)
                        },
                        onContainerSelect: { containerID in
                            projectViewModel.selectedContainerID = containerID
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
                                // Auto-scroll if imported container extends beyond visible area
                                if let song = projectViewModel.currentSong,
                                   let trackObj = song.tracks.first(where: { $0.id == track.id }),
                                   let container = trackObj.containers.first(where: { $0.id == containerID }) {
                                    viewModel.ensureBarVisible(container.endBar)
                                }
                            }
                        },
                        onContainerDoubleClick: { containerID in
                            projectViewModel.selectedContainerID = containerID
                            onContainerDoubleClick?()
                        },
                        onCloneContainer: { containerID, newStartBar in
                            projectViewModel.cloneContainer(trackID: track.id, containerID: containerID, newStartBar: newStartBar)
                        },
                        onCopyContainer: { containerID in
                            projectViewModel.copyContainer(trackID: track.id, containerID: containerID)
                        },
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
                        onArmToggle: {
                            projectViewModel.setTrackRecordArmed(trackID: track.id, armed: !track.isRecordArmed)
                        },
                        onPasteAtBar: { bar in
                            projectViewModel.pasteContainers(trackID: track.id, atBar: bar)
                        },
                        hasClipboard: !projectViewModel.clipboard.isEmpty,
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
                        }
                    )
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

            // Playhead — extends full height
            PlayheadView(
                xPosition: viewModel.playheadX,
                height: displayHeight
            )
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
        guard let containerID = projectViewModel.selectedContainerID else { return }
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
