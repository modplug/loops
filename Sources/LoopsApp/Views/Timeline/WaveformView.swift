import SwiftUI
import LoopsCore

/// Renders waveform peak data as a visual waveform inside a container.
/// Uses pixel-aware downsampling: for each pixel column, computes the max peak
/// in that column's range, so drawing cost is O(pixels) not O(peaks).
/// A 3-minute file (18,000 peaks) in a 300px container draws only ~300 segments.
public struct WaveformView: View {
    let peaks: [Float]
    let color: Color
    /// Fraction of the total recording where the visible portion starts (0.0 = from start).
    let startFraction: CGFloat
    /// Fraction of the total recording that is visible (1.0 = full recording).
    let lengthFraction: CGFloat

    public init(peaks: [Float], color: Color = .white,
                startFraction: CGFloat = 0.0, lengthFraction: CGFloat = 1.0) {
        self.peaks = peaks
        self.color = color
        self.startFraction = startFraction
        self.lengthFraction = lengthFraction
    }

    public var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard !peaks.isEmpty, size.width > 0, size.height > 0 else { return }

                // Compute visible slice bounds (avoid Array copy — use indices directly)
                let totalPeaks = peaks.count
                let startIndex = max(0, min(Int(startFraction * CGFloat(totalPeaks)), totalPeaks))
                let visibleCount = max(1, min(Int(lengthFraction * CGFloat(totalPeaks)), totalPeaks - startIndex))
                let endIndex = startIndex + visibleCount

                guard visibleCount > 0 else { return }

                let midY = size.height / 2
                let pixelWidth = Int(ceil(size.width))

                // When fewer peaks than pixels, draw one segment per peak (high zoom)
                // When more peaks than pixels, downsample to one column per pixel
                if visibleCount <= pixelWidth * 2 {
                    // High zoom: draw individual peaks as a smooth path
                    drawDetailedPath(
                        context: &context, size: size, midY: midY,
                        startIndex: startIndex, endIndex: endIndex, visibleCount: visibleCount
                    )
                } else {
                    // Low zoom: pixel-column downsampling
                    drawDownsampledPath(
                        context: &context, size: size, midY: midY,
                        startIndex: startIndex, endIndex: endIndex,
                        visibleCount: visibleCount, pixelWidth: pixelWidth
                    )
                }
            }
        }
    }

    /// High-zoom rendering: one path segment per peak (smooth waveform shape).
    private func drawDetailedPath(
        context: inout GraphicsContext, size: CGSize, midY: CGFloat,
        startIndex: Int, endIndex: Int, visibleCount: Int
    ) {
        let peakWidth = size.width / CGFloat(visibleCount)
        var path = Path()

        // Top half
        path.move(to: CGPoint(x: 0, y: midY))
        for i in startIndex..<endIndex {
            let localIndex = i - startIndex
            let x = CGFloat(localIndex) * peakWidth + peakWidth / 2
            let amplitude = CGFloat(peaks[i]) * midY * 0.9
            path.addLine(to: CGPoint(x: x, y: midY - amplitude))
        }
        path.addLine(to: CGPoint(x: size.width, y: midY))

        // Bottom half (mirror)
        for i in stride(from: endIndex - 1, through: startIndex, by: -1) {
            let localIndex = i - startIndex
            let x = CGFloat(localIndex) * peakWidth + peakWidth / 2
            let amplitude = CGFloat(peaks[i]) * midY * 0.9
            path.addLine(to: CGPoint(x: x, y: midY + amplitude))
        }
        path.closeSubpath()

        context.fill(path, with: .color(color.opacity(0.4)))
        context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 0.5)
    }

    /// Low-zoom rendering: one vertical column per pixel.
    /// For each pixel column, finds the max peak in that column's range.
    private func drawDownsampledPath(
        context: inout GraphicsContext, size: CGSize, midY: CGFloat,
        startIndex: Int, endIndex: Int,
        visibleCount: Int, pixelWidth: Int
    ) {
        let columns = min(pixelWidth, visibleCount)
        guard columns > 0 else { return }

        var path = Path()

        // Top half: left to right
        path.move(to: CGPoint(x: 0, y: midY))
        for col in 0..<columns {
            let peakStart = startIndex + (col * visibleCount) / columns
            let peakEnd = startIndex + ((col + 1) * visibleCount) / columns
            let maxPeak = maxInRange(from: peakStart, to: peakEnd)
            let x = (CGFloat(col) + 0.5) * size.width / CGFloat(columns)
            let amplitude = CGFloat(maxPeak) * midY * 0.9
            path.addLine(to: CGPoint(x: x, y: midY - amplitude))
        }
        path.addLine(to: CGPoint(x: size.width, y: midY))

        // Bottom half: right to left (mirror)
        for col in stride(from: columns - 1, through: 0, by: -1) {
            let peakStart = startIndex + (col * visibleCount) / columns
            let peakEnd = startIndex + ((col + 1) * visibleCount) / columns
            let maxPeak = maxInRange(from: peakStart, to: peakEnd)
            let x = (CGFloat(col) + 0.5) * size.width / CGFloat(columns)
            let amplitude = CGFloat(maxPeak) * midY * 0.9
            path.addLine(to: CGPoint(x: x, y: midY + amplitude))
        }
        path.closeSubpath()

        context.fill(path, with: .color(color.opacity(0.4)))
    }

    /// Finds the maximum peak value in a range of the peaks array.
    @inline(__always)
    private func maxInRange(from start: Int, to end: Int) -> Float {
        guard start < end else { return 0 }
        var maxVal: Float = 0
        for i in start..<end {
            let v = peaks[i]
            if v > maxVal { maxVal = v }
        }
        return maxVal
    }
}
