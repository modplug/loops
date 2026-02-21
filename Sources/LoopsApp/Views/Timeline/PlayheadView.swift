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
