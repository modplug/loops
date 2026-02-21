import SwiftUI
import LoopsCore

/// The main timeline view combining ruler, grid, track lanes, and playhead.
public struct TimelineView: View {
    @Bindable var viewModel: TimelineViewModel
    let song: Song
    let trackHeight: CGFloat

    public init(viewModel: TimelineViewModel, song: Song, trackHeight: CGFloat = 80) {
        self.viewModel = viewModel
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
                                height: trackHeight
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
    }
}
