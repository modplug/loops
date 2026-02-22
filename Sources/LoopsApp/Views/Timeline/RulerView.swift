import SwiftUI
import LoopsCore

/// Displays bar numbers along the top of the timeline.
public struct RulerView: View {
    let totalBars: Int
    let pixelsPerBar: CGFloat
    let timeSignature: TimeSignature

    public init(totalBars: Int, pixelsPerBar: CGFloat, timeSignature: TimeSignature) {
        self.totalBars = totalBars
        self.pixelsPerBar = pixelsPerBar
        self.timeSignature = timeSignature
    }

    public var body: some View {
        Canvas { context, size in
            let height = size.height

            // Bottom border
            var bottomLine = Path()
            bottomLine.move(to: CGPoint(x: 0, y: height - 0.5))
            bottomLine.addLine(to: CGPoint(x: size.width, y: height - 0.5))
            context.stroke(bottomLine, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)

            for bar in 1...totalBars {
                let x = CGFloat(bar - 1) * pixelsPerBar

                // Tick mark at bottom
                var path = Path()
                path.move(to: CGPoint(x: x, y: height - 6))
                path.addLine(to: CGPoint(x: x, y: height))
                context.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)

                // Bar number — small, near top
                let text = Text("\(bar)").font(.system(size: 9, weight: .regular)).foregroundColor(.secondary)
                context.draw(text, at: CGPoint(x: x + 3, y: 5), anchor: .topLeading)

                // Beat ticks within bar
                if pixelsPerBar > 50 {
                    let pixelsPerBeat = pixelsPerBar / CGFloat(timeSignature.beatsPerBar)
                    for beat in 1..<timeSignature.beatsPerBar {
                        let beatX = x + CGFloat(beat) * pixelsPerBeat
                        var beatPath = Path()
                        beatPath.move(to: CGPoint(x: beatX, y: height - 3))
                        beatPath.addLine(to: CGPoint(x: beatX, y: height))
                        context.stroke(beatPath, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)
                    }
                }
            }
        }
        .frame(width: CGFloat(totalBars) * pixelsPerBar, height: 20)
    }
}
