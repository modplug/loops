import SwiftUI
import LoopsCore

/// Draws vertical grid lines at bar and beat boundaries across the timeline.
public struct GridOverlayView: View {
    let totalBars: Int
    let pixelsPerBar: CGFloat
    let timeSignature: TimeSignature
    let height: CGFloat

    public init(
        totalBars: Int,
        pixelsPerBar: CGFloat,
        timeSignature: TimeSignature,
        height: CGFloat
    ) {
        self.totalBars = totalBars
        self.pixelsPerBar = pixelsPerBar
        self.timeSignature = timeSignature
        self.height = height
    }

    public var body: some View {
        Canvas { context, size in
            let totalHeight = size.height

            // Alternating bar shading (Bitwig-style)
            for bar in 0..<totalBars {
                if bar % 2 == 1 {
                    let x = CGFloat(bar) * pixelsPerBar
                    let rect = CGRect(x: x, y: 0, width: pixelsPerBar, height: totalHeight)
                    context.fill(Path(rect), with: .color(.primary.opacity(0.03)))
                }
            }

            for bar in 0...totalBars {
                let x = CGFloat(bar) * pixelsPerBar

                // Bar line
                var barPath = Path()
                barPath.move(to: CGPoint(x: x, y: 0))
                barPath.addLine(to: CGPoint(x: x, y: totalHeight))
                context.stroke(barPath, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)

                // Beat lines (lighter)
                if pixelsPerBar > 50 && bar < totalBars {
                    let pixelsPerBeat = pixelsPerBar / CGFloat(timeSignature.beatsPerBar)
                    for beat in 1..<timeSignature.beatsPerBar {
                        let beatX = x + CGFloat(beat) * pixelsPerBeat
                        var beatPath = Path()
                        beatPath.move(to: CGPoint(x: beatX, y: 0))
                        beatPath.addLine(to: CGPoint(x: beatX, y: totalHeight))
                        context.stroke(beatPath, with: .color(.secondary.opacity(0.08)), lineWidth: 0.5)
                    }
                }
            }
        }
        .frame(
            width: CGFloat(totalBars) * pixelsPerBar,
            height: height
        )
    }
}
