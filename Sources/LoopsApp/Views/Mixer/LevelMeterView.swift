import SwiftUI

/// A vertical level meter showing audio peak level.
public struct LevelMeterView: View {
    let level: Float
    let width: CGFloat

    public init(level: Float, width: CGFloat = 6) {
        self.level = level
        self.width = width
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: .separatorColor))

                // Level fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(levelColor)
                    .frame(height: geometry.size.height * CGFloat(min(level, 1.0)))
            }
        }
        .frame(width: width)
    }

    private var levelColor: Color {
        if level > 0.9 { return .red }
        if level > 0.7 { return .yellow }
        return .green
    }
}
