import SwiftUI
import LoopsCore

/// Draws vertical grid lines at bar and beat boundaries across the timeline.
public struct GridOverlayView: View {
    let totalBars: Int
    let pixelsPerBar: CGFloat
    let timeSignature: TimeSignature
    let height: CGFloat
    let gridMode: GridMode
    let visibleXMin: CGFloat
    let visibleXMax: CGFloat

    public init(
        totalBars: Int,
        pixelsPerBar: CGFloat,
        timeSignature: TimeSignature,
        height: CGFloat,
        gridMode: GridMode = .adaptive,
        visibleXMin: CGFloat = 0,
        visibleXMax: CGFloat = .greatestFiniteMagnitude
    ) {
        self.totalBars = totalBars
        self.pixelsPerBar = pixelsPerBar
        self.timeSignature = timeSignature
        self.height = height
        self.gridMode = gridMode
        self.visibleXMin = visibleXMin
        self.visibleXMax = visibleXMax
    }

    public var body: some View {
        Canvas { context, size in
            let totalHeight = size.height
            let pixelsPerBeat = pixelsPerBar / CGFloat(timeSignature.beatsPerBar)

            // Compute visible bar range (clamp to valid bounds).
            // startBar can exceed totalBars when visibleXMin is stale (set at a higher ppb)
            // and zoom-out reduces ppb before the visible range updates.
            let endBar: Int
            if visibleXMax >= CGFloat(totalBars) * pixelsPerBar {
                endBar = totalBars
            } else {
                endBar = min(totalBars, Int(ceil(visibleXMax / pixelsPerBar)) + 1)
            }
            let startBar = min(max(0, Int(floor(visibleXMin / pixelsPerBar))), endBar)

            // Alternating bar shading (Bitwig-style)
            for bar in startBar..<endBar {
                if bar % 2 == 1 {
                    let x = CGFloat(bar) * pixelsPerBar
                    let rect = CGRect(x: x, y: 0, width: pixelsPerBar, height: totalHeight)
                    context.fill(Path(rect), with: .color(.primary.opacity(0.03)))
                }
            }

            for bar in startBar...endBar {
                guard bar <= totalBars else { break }
                let x = CGFloat(bar) * pixelsPerBar

                // Bar line
                var barPath = Path()
                barPath.move(to: CGPoint(x: x, y: 0))
                barPath.addLine(to: CGPoint(x: x, y: totalHeight))
                context.stroke(barPath, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)

                // Beat lines — always drawn when space permits (structural)
                if pixelsPerBar > 50 && bar < totalBars {
                    for beat in 1..<timeSignature.beatsPerBar {
                        let beatX = x + CGFloat(beat) * pixelsPerBeat
                        var beatPath = Path()
                        beatPath.move(to: CGPoint(x: beatX, y: 0))
                        beatPath.addLine(to: CGPoint(x: beatX, y: totalHeight))
                        context.stroke(beatPath, with: .color(.secondary.opacity(0.08)), lineWidth: 0.5)
                    }
                }

                guard bar < totalBars else { continue }

                // Subdivision lines based on grid mode
                switch gridMode {
                case .adaptive:
                    drawAdaptiveSubdivisions(context: &context, barX: x, totalHeight: totalHeight, pixelsPerBeat: pixelsPerBeat)
                case .fixed(let resolution):
                    drawFixedSubdivisions(context: &context, barX: x, totalHeight: totalHeight, resolution: resolution)
                }
            }
        }
        .frame(
            width: CGFloat(totalBars) * pixelsPerBar,
            height: height
        )
    }

    private func drawAdaptiveSubdivisions(context: inout GraphicsContext, barX: CGFloat, totalHeight: CGFloat, pixelsPerBeat: CGFloat) {
        // 1/16 subdivision lines
        if pixelsPerBeat >= 80 {
            let subdivisions = timeSignature.beatsPerBar * 4
            let pixelsPerSub = pixelsPerBar / CGFloat(subdivisions)
            for sub in 1..<subdivisions {
                if sub % 4 == 0 { continue }
                let subX = barX + CGFloat(sub) * pixelsPerSub
                var subPath = Path()
                subPath.move(to: CGPoint(x: subX, y: 0))
                subPath.addLine(to: CGPoint(x: subX, y: totalHeight))
                context.stroke(subPath, with: .color(.secondary.opacity(0.04)), lineWidth: 0.5)
            }
        }

        // 1/32 subdivision lines
        if pixelsPerBeat >= 150 {
            let subdivisions = timeSignature.beatsPerBar * 8
            let pixelsPerSub = pixelsPerBar / CGFloat(subdivisions)
            for sub in 1..<subdivisions {
                if sub % 2 == 0 { continue }
                let subX = barX + CGFloat(sub) * pixelsPerSub
                var subPath = Path()
                subPath.move(to: CGPoint(x: subX, y: 0))
                subPath.addLine(to: CGPoint(x: subX, y: totalHeight))
                context.stroke(subPath, with: .color(.secondary.opacity(0.02)), lineWidth: 0.5)
            }
        }
    }

}

// MARK: - Equatable

extension GridOverlayView: Equatable {
    public static func == (lhs: GridOverlayView, rhs: GridOverlayView) -> Bool {
        lhs.totalBars == rhs.totalBars &&
        lhs.pixelsPerBar == rhs.pixelsPerBar &&
        lhs.timeSignature == rhs.timeSignature &&
        lhs.height == rhs.height &&
        lhs.gridMode == rhs.gridMode &&
        lhs.visibleXMin == rhs.visibleXMin &&
        lhs.visibleXMax == rhs.visibleXMax
    }
}

extension GridOverlayView {
    private func drawFixedSubdivisions(context: inout GraphicsContext, barX: CGFloat, totalHeight: CGFloat, resolution: SnapResolution) {
        let beatsPerBar = Double(timeSignature.beatsPerBar)
        let subsPerBeat = resolution.subdivisionsPerBeat
        let totalSubs = Int(ceil(beatsPerBar * subsPerBeat))
        let pixelsPerSub = pixelsPerBar / CGFloat(beatsPerBar * subsPerBeat)

        // Skip if lines would be too dense
        guard pixelsPerSub >= 4 else { return }

        let beatsPerBarInt = timeSignature.beatsPerBar
        let opacity: Double = resolution.isTriplet ? 0.06 : 0.04

        for sub in 1..<totalSubs {
            // Skip positions that coincide with beat lines
            let beatPosition = Double(sub) / subsPerBeat
            let isOnBeat = abs(beatPosition - beatPosition.rounded()) < 0.001
                && Int(beatPosition.rounded()) > 0
                && Int(beatPosition.rounded()) < beatsPerBarInt
            if isOnBeat { continue }

            let subX = barX + CGFloat(Double(sub)) * pixelsPerSub
            var subPath = Path()
            subPath.move(to: CGPoint(x: subX, y: 0))
            subPath.addLine(to: CGPoint(x: subX, y: totalHeight))
            context.stroke(subPath, with: .color(.secondary.opacity(opacity)), lineWidth: 0.5)
        }
    }
}
