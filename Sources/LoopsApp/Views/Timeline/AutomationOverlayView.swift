import SwiftUI
import LoopsCore

/// Palette of distinct colors for automation lanes.
enum AutomationColors {
    static let palette: [Color] = [
        .red, .green, .cyan, .yellow, .pink, .mint, .teal, .indigo
    ]

    static func color(at index: Int) -> Color {
        palette[index % palette.count]
    }
}

/// Draws automation curves as semi-transparent overlays on a container body.
/// Each lane is rendered as a colored path with breakpoint dots.
struct AutomationOverlayView: View {
    let automationLanes: [AutomationLane]
    let containerLengthBars: Int
    let pixelsPerBar: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            for (index, lane) in automationLanes.enumerated() {
                let color = AutomationColors.color(at: index)
                drawLane(lane, index: index, color: color, in: context, size: size)
            }
        }
        .allowsHitTesting(false)

        // Parameter name labels
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(automationLanes.enumerated()), id: \.element.id) { index, lane in
                Text("P\(lane.targetPath.effectIndex):\(lane.targetPath.parameterAddress)")
                    .font(.system(size: 7))
                    .foregroundStyle(AutomationColors.color(at: index).opacity(0.8))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .padding(.leading, 2)
        .allowsHitTesting(false)
    }

    private func drawLane(_ lane: AutomationLane, index: Int, color: Color, in context: GraphicsContext, size: CGSize) {
        let sorted = lane.breakpoints.sorted { $0.position < $1.position }
        guard !sorted.isEmpty else { return }

        let containerWidth = CGFloat(containerLengthBars) * pixelsPerBar

        // Draw curve path
        var path = Path()
        let resolution = max(Int(containerWidth / 2), 2)
        for step in 0...resolution {
            let barPosition = Double(step) / Double(resolution) * Double(containerLengthBars)
            guard let value = lane.interpolatedValue(atBar: barPosition) else { continue }
            let x = CGFloat(barPosition) / CGFloat(containerLengthBars) * size.width
            let y = CGFloat(1.0 - value) * size.height
            if step == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        context.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 1.5)

        // Draw breakpoint dots
        for bp in sorted {
            let x = CGFloat(bp.position) / CGFloat(containerLengthBars) * size.width
            let y = CGFloat(1.0 - bp.value) * size.height
            let dotRect = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: dotRect), with: .color(color))
        }
    }
}

// MARK: - Coordinate Mapping Helpers

/// Pure functions for mapping between automation breakpoint coordinates and pixel positions.
/// These are used by both overlay and sub-lane views.
enum AutomationCoordinateMapping {
    /// Converts a breakpoint position (bar offset) to an x-pixel coordinate within a container.
    static func xForPosition(_ position: Double, containerLengthBars: Int, pixelsPerBar: CGFloat) -> CGFloat {
        CGFloat(position) * pixelsPerBar
    }

    /// Converts a breakpoint value (0-1) to a y-pixel coordinate within a given height.
    /// Value 1.0 maps to y=0 (top), value 0.0 maps to y=height (bottom).
    static func yForValue(_ value: Float, height: CGFloat) -> CGFloat {
        CGFloat(1.0 - value) * height
    }

    /// Converts an x-pixel coordinate within a container to a breakpoint position (bar offset).
    static func positionForX(_ x: CGFloat, containerLengthBars: Int, pixelsPerBar: CGFloat) -> Double {
        let position = Double(x) / Double(pixelsPerBar)
        return max(0, min(position, Double(containerLengthBars)))
    }

    /// Converts a y-pixel coordinate within a given height to a breakpoint value (0-1).
    static func valueForY(_ y: CGFloat, height: CGFloat) -> Float {
        let value = Float(1.0 - y / height)
        return max(0, min(value, 1))
    }
}
