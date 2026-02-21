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

            for bar in 1...totalBars {
                let x = CGFloat(bar - 1) * pixelsPerBar

                // Bar line
                var path = Path()
                path.move(to: CGPoint(x: x, y: height * 0.5))
                path.addLine(to: CGPoint(x: x, y: height))
                context.stroke(path, with: .color(.secondary), lineWidth: 1)

                // Bar number
                let text = Text("\(bar)").font(.caption2).foregroundColor(.secondary)
                context.draw(text, at: CGPoint(x: x + 4, y: height * 0.3), anchor: .leading)

                // Beat ticks within bar
                if pixelsPerBar > 50 {
                    let pixelsPerBeat = pixelsPerBar / CGFloat(timeSignature.beatsPerBar)
                    for beat in 1..<timeSignature.beatsPerBar {
                        let beatX = x + CGFloat(beat) * pixelsPerBeat
                        var beatPath = Path()
                        beatPath.move(to: CGPoint(x: beatX, y: height * 0.7))
                        beatPath.addLine(to: CGPoint(x: beatX, y: height))
                        context.stroke(beatPath, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)
                    }
                }
            }
        }
        .frame(width: CGFloat(totalBars) * pixelsPerBar, height: 28)
    }
}
