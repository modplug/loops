import SwiftUI
import LoopsCore

/// Draws vertical grid lines at bar and beat boundaries across the timeline.
public struct GridOverlayView: View {
    let totalBars: Int
    let pixelsPerBar: CGFloat
    let timeSignature: TimeSignature
    let trackCount: Int
    let trackHeight: CGFloat

    public init(
        totalBars: Int,
        pixelsPerBar: CGFloat,
        timeSignature: TimeSignature,
        trackCount: Int,
        trackHeight: CGFloat = 80
    ) {
        self.totalBars = totalBars
        self.pixelsPerBar = pixelsPerBar
        self.timeSignature = timeSignature
        self.trackCount = trackCount
        self.trackHeight = trackHeight
    }

    public var body: some View {
        Canvas { context, size in
            let totalHeight = size.height

            for bar in 0...totalBars {
                let x = CGFloat(bar) * pixelsPerBar

                // Bar line (stronger)
                var barPath = Path()
                barPath.move(to: CGPoint(x: x, y: 0))
                barPath.addLine(to: CGPoint(x: x, y: totalHeight))
                context.stroke(barPath, with: .color(.secondary.opacity(0.4)), lineWidth: 1)

                // Beat lines (lighter)
                if pixelsPerBar > 50 && bar < totalBars {
                    let pixelsPerBeat = pixelsPerBar / CGFloat(timeSignature.beatsPerBar)
                    for beat in 1..<timeSignature.beatsPerBar {
                        let beatX = x + CGFloat(beat) * pixelsPerBeat
                        var beatPath = Path()
                        beatPath.move(to: CGPoint(x: beatX, y: 0))
                        beatPath.addLine(to: CGPoint(x: beatX, y: totalHeight))
                        context.stroke(beatPath, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
                    }
                }
            }

            // Horizontal track separator lines
            for i in 0...trackCount {
                let y = CGFloat(i) * trackHeight
                var trackLine = Path()
                trackLine.move(to: CGPoint(x: 0, y: y))
                trackLine.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(trackLine, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)
            }
        }
        .frame(
            width: CGFloat(totalBars) * pixelsPerBar,
            height: CGFloat(trackCount) * trackHeight
        )
    }
}
