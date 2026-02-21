import SwiftUI
import LoopsCore

/// The main timeline view combining ruler, grid, track lanes, and playhead.
public struct TimelineView: View {
    @Bindable var viewModel: TimelineViewModel
    @Bindable var projectViewModel: ProjectViewModel
    let song: Song
    let trackHeight: CGFloat

    public init(viewModel: TimelineViewModel, projectViewModel: ProjectViewModel, song: Song, trackHeight: CGFloat = 80) {
        self.viewModel = viewModel
        self.projectViewModel = projectViewModel
        self.song = song
        self.trackHeight = trackHeight
    }

    private var totalContentHeight: CGFloat {
        CGFloat(max(song.tracks.count, 1)) * trackHeight
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Ruler at the top
            ScrollView(.horizontal, showsIndicators: false) {
                RulerView(
                    totalBars: viewModel.totalBars,
                    pixelsPerBar: viewModel.pixelsPerBar,
                    timeSignature: song.timeSignature
                )
            }
            .frame(height: 28)

            Divider()

            // Main timeline area with tracks
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Grid overlay
                    GridOverlayView(
                        totalBars: viewModel.totalBars,
                        pixelsPerBar: viewModel.pixelsPerBar,
                        timeSignature: song.timeSignature,
                        trackCount: song.tracks.count,
                        trackHeight: trackHeight
                    )

                    // Track lanes stacked vertically
                    VStack(spacing: 0) {
                        ForEach(song.tracks) { track in
                            TrackLaneView(
                                track: track,
                                pixelsPerBar: viewModel.pixelsPerBar,
                                totalBars: viewModel.totalBars,
                                height: trackHeight,
                                selectedContainerID: projectViewModel.selectedContainerID,
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
                                }
                            )
                        }
                    }

                    // Playhead
                    PlayheadView(
                        xPosition: viewModel.playheadX,
                        height: totalContentHeight
                    )
                }
                .frame(
                    width: viewModel.totalWidth,
                    height: totalContentHeight
                )
            }
        }
        .onKeyPress("+") {
            viewModel.zoomIn()
            return .handled
        }
        .onKeyPress("-") {
            viewModel.zoomOut()
            return .handled
        }
        .onKeyPress(.delete) {
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
}
