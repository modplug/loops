import SwiftUI

/// Displays the playhead as a vertical line at the current position.
public struct PlayheadView: View {
    let xPosition: CGFloat
    let height: CGFloat

    public init(xPosition: CGFloat, height: CGFloat) {
        self.xPosition = xPosition
        self.height = height
    }

    public var body: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 1.5, height: height)
            .offset(x: xPosition)
    }
}

/// Isolates playhead observation from the parent view tree.
/// By reading `viewModel.playheadX` in this child view's body (not the parent's),
/// 60fps playhead updates only re-evaluate this view — not the entire TimelineView.
struct PlayheadOverlayView: View {
    let viewModel: TimelineViewModel
    let height: CGFloat

    var body: some View {
        PlayheadView(
            xPosition: viewModel.playheadX,
            height: height
        )
    }
}
