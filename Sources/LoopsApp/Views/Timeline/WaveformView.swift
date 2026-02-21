import SwiftUI
import LoopsCore

/// Renders waveform peak data as a visual waveform inside a container.
public struct WaveformView: View {
    let peaks: [Float]
    let color: Color

    public init(peaks: [Float], color: Color = .white) {
        self.peaks = peaks
        self.color = color
    }

    public var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard !peaks.isEmpty else { return }

                let midY = size.height / 2
                let peakWidth = size.width / CGFloat(peaks.count)

                var path = Path()

                // Draw top half
                path.move(to: CGPoint(x: 0, y: midY))
                for (i, peak) in peaks.enumerated() {
                    let x = CGFloat(i) * peakWidth + peakWidth / 2
                    let amplitude = CGFloat(peak) * midY * 0.9
                    path.addLine(to: CGPoint(x: x, y: midY - amplitude))
                }
                path.addLine(to: CGPoint(x: size.width, y: midY))

                // Draw bottom half (mirror)
                for i in stride(from: peaks.count - 1, through: 0, by: -1) {
                    let x = CGFloat(i) * peakWidth + peakWidth / 2
                    let amplitude = CGFloat(peaks[i]) * midY * 0.9
                    path.addLine(to: CGPoint(x: x, y: midY + amplitude))
                }
                path.closeSubpath()

                context.fill(path, with: .color(color.opacity(0.4)))
                context.stroke(
                    path,
                    with: .color(color.opacity(0.7)),
                    lineWidth: 0.5
                )
            }
        }
    }
}
