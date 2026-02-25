import SwiftUI
import QuartzCore
import LoopsCore

/// Renders waveform peak data as a visual waveform inside a container.
///
/// Viewport-aware: only draws peaks within the visible range (`visibleMinX`...`visibleMaxX`),
/// so even a 107,000pt-wide container at extreme zoom builds a path with ~100 segments
/// instead of 4096+. Falls back to drawing everything when no visible range is specified.
///
/// No GeometryReader — Canvas gets its size directly from parent layout.
public struct WaveformView: View {
    let peaks: [Float]
    let color: Color
    let startFraction: CGFloat
    let lengthFraction: CGFloat
    /// Visible horizontal range in the WaveformView's local coordinate space.
    /// Used for viewport-aware rendering — only peaks in this range are drawn.
    let visibleMinX: CGFloat
    let visibleMaxX: CGFloat

    public init(peaks: [Float], color: Color = .white,
                startFraction: CGFloat = 0.0, lengthFraction: CGFloat = 1.0,
                visibleMinX: CGFloat = 0, visibleMaxX: CGFloat = .greatestFiniteMagnitude) {
        self.peaks = peaks
        self.color = color
        self.startFraction = startFraction
        self.lengthFraction = lengthFraction
        self.visibleMinX = visibleMinX
        self.visibleMaxX = visibleMaxX
    }

    /// Maximum path segments when no viewport culling is active.
    private static let maxSegments = 4096

    public var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty, size.width > 0, size.height > 0 else { return }

            let totalPeaks = peaks.count
            let startIndex = max(0, min(Int(startFraction * CGFloat(totalPeaks)), totalPeaks))
            let visibleCount = max(1, min(Int(lengthFraction * CGFloat(totalPeaks)), totalPeaks - startIndex))
            let endIndex = startIndex + visibleCount

            guard visibleCount > 0 else { return }

            // Clamp visible range to canvas bounds
            let clampedMinX = max(0, visibleMinX)
            let clampedMaxX = min(size.width, visibleMaxX)

            // Skip drawing entirely if visible range doesn't intersect the canvas
            guard clampedMinX < size.width, clampedMaxX > 0 else { return }

            let midY = size.height / 2

            if visibleCount <= Self.maxSegments {
                drawDetailedPath(
                    context: &context, size: size, midY: midY,
                    startIndex: startIndex, endIndex: endIndex, visibleCount: visibleCount,
                    visibleMinX: clampedMinX, visibleMaxX: clampedMaxX
                )
            } else {
                drawDownsampledPath(
                    context: &context, size: size, midY: midY,
                    startIndex: startIndex, endIndex: endIndex,
                    visibleCount: visibleCount, columns: Self.maxSegments,
                    visibleMinX: clampedMinX, visibleMaxX: clampedMaxX
                )
            }
        }
    }

    /// High-zoom rendering: one path segment per peak, clipped to visible range.
    private func drawDetailedPath(
        context: inout GraphicsContext, size: CGSize, midY: CGFloat,
        startIndex: Int, endIndex: Int, visibleCount: Int,
        visibleMinX: CGFloat, visibleMaxX: CGFloat
    ) {
        let peakWidth = size.width / CGFloat(visibleCount)

        // Compute which local indices fall within the visible range (+1 margin for path continuity)
        let firstLocal = max(0, Int(floor(visibleMinX / peakWidth)) - 1)
        let lastLocal = min(visibleCount - 1, Int(ceil(visibleMaxX / peakWidth)) + 1)
        guard firstLocal <= lastLocal else { return }

        var path = Path()
        let firstX = CGFloat(firstLocal) * peakWidth + peakWidth / 2

        // Top half (left to right)
        path.move(to: CGPoint(x: firstX, y: midY))
        for localIndex in firstLocal...lastLocal {
            let i = startIndex + localIndex
            guard i < endIndex else { break }
            let x = CGFloat(localIndex) * peakWidth + peakWidth / 2
            let amplitude = CGFloat(peaks[i]) * midY * 0.9
            path.addLine(to: CGPoint(x: x, y: midY - amplitude))
        }

        // Bridge to bottom half
        let lastX = CGFloat(lastLocal) * peakWidth + peakWidth / 2
        path.addLine(to: CGPoint(x: lastX, y: midY))

        // Bottom half (right to left)
        for localIndex in stride(from: lastLocal, through: firstLocal, by: -1) {
            let i = startIndex + localIndex
            guard i < endIndex else { continue }
            let x = CGFloat(localIndex) * peakWidth + peakWidth / 2
            let amplitude = CGFloat(peaks[i]) * midY * 0.9
            path.addLine(to: CGPoint(x: x, y: midY + amplitude))
        }
        path.closeSubpath()

        context.fill(path, with: .color(color.opacity(0.4)))
        context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 0.5)
    }

    /// Downsampled rendering: fixed number of columns, clipped to visible range.
    private func drawDownsampledPath(
        context: inout GraphicsContext, size: CGSize, midY: CGFloat,
        startIndex: Int, endIndex: Int,
        visibleCount: Int, columns: Int,
        visibleMinX: CGFloat, visibleMaxX: CGFloat
    ) {
        guard columns > 0 else { return }

        let columnWidth = size.width / CGFloat(columns)

        // Compute which columns fall within the visible range (+1 margin for path continuity)
        let firstCol = max(0, Int(floor(visibleMinX / columnWidth)) - 1)
        let lastCol = min(columns - 1, Int(ceil(visibleMaxX / columnWidth)) + 1)
        guard firstCol <= lastCol else { return }

        var path = Path()
        let firstX = (CGFloat(firstCol) + 0.5) * columnWidth

        // Top half (left to right)
        path.move(to: CGPoint(x: firstX, y: midY))
        for col in firstCol...lastCol {
            let peakStart = startIndex + (col * visibleCount) / columns
            let peakEnd = startIndex + ((col + 1) * visibleCount) / columns
            let maxPeak = maxInRange(from: peakStart, to: peakEnd)
            let x = (CGFloat(col) + 0.5) * columnWidth
            let amplitude = CGFloat(maxPeak) * midY * 0.9
            path.addLine(to: CGPoint(x: x, y: midY - amplitude))
        }

        // Bridge to bottom half
        let lastX = (CGFloat(lastCol) + 0.5) * columnWidth
        path.addLine(to: CGPoint(x: lastX, y: midY))

        // Bottom half (right to left)
        for col in stride(from: lastCol, through: firstCol, by: -1) {
            let peakStart = startIndex + (col * visibleCount) / columns
            let peakEnd = startIndex + ((col + 1) * visibleCount) / columns
            let maxPeak = maxInRange(from: peakStart, to: peakEnd)
            let x = (CGFloat(col) + 0.5) * columnWidth
            let amplitude = CGFloat(maxPeak) * midY * 0.9
            path.addLine(to: CGPoint(x: x, y: midY + amplitude))
        }
        path.closeSubpath()

        context.fill(path, with: .color(color.opacity(0.4)))
    }

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

// MARK: - Equatable

extension WaveformView: Equatable {
    public static func == (lhs: WaveformView, rhs: WaveformView) -> Bool {
        lhs.color == rhs.color &&
        lhs.startFraction == rhs.startFraction &&
        lhs.lengthFraction == rhs.lengthFraction &&
        lhs.visibleMinX == rhs.visibleMinX &&
        lhs.visibleMaxX == rhs.visibleMaxX &&
        peaksEqual(lhs.peaks, rhs.peaks)
    }

    /// O(1) peaks identity check — count + sentinel samples.
    /// Peaks change rarely (only on import/recording).
    private static func peaksEqual(_ a: [Float], _ b: [Float]) -> Bool {
        guard a.count == b.count else { return false }
        guard !a.isEmpty else { return true }
        return a[0] == b[0] &&
               a[a.count / 2] == b[a.count / 2] &&
               a[a.count - 1] == b[a.count - 1]
    }
}
