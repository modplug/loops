import SwiftUI
import LoopsCore

/// The main timeline view combining grid, track lanes, and playhead.
/// Scrolling is managed by the parent view (MainContentView).
public struct TimelineView: View {
    @Bindable var viewModel: TimelineViewModel
    @Bindable var projectViewModel: ProjectViewModel
    let song: Song
    let trackHeight: CGFloat
    let minHeight: CGFloat
    var onContainerDoubleClick: (() -> Void)?

    public init(viewModel: TimelineViewModel, projectViewModel: ProjectViewModel, song: Song, trackHeight: CGFloat = 80, minHeight: CGFloat = 0, onContainerDoubleClick: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.projectViewModel = projectViewModel
        self.song = song
        self.trackHeight = trackHeight
        self.minHeight = minHeight
        self.onContainerDoubleClick = onContainerDoubleClick
    }

    public var totalContentHeight: CGFloat {
        CGFloat(max(song.tracks.count, 1)) * trackHeight
    }

    /// The height used for the grid and playhead — fills available space.
    private var displayHeight: CGFloat {
        max(totalContentHeight, minHeight)
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Grid overlay — fills available space
            GridOverlayView(
                totalBars: viewModel.totalBars,
                pixelsPerBar: viewModel.pixelsPerBar,
                timeSignature: song.timeSignature,
                height: displayHeight
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
                            let _ = try? projectViewModel.importAudio(
                                url: url,
                                trackID: track.id,
                                startBar: startBar,
                                audioDirectory: projectViewModel.audioDirectory
                            )
                        },
                        onContainerDoubleClick: { containerID in
                            projectViewModel.selectedContainerID = containerID
                            onContainerDoubleClick?()
                        }
                    )
                }
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
