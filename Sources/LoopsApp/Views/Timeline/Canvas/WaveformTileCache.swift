import AppKit
import LoopsCore

/// Caches pre-rendered waveform peak images at discrete zoom levels.
///
/// During scroll, cached tiles are blitted directly (zero path computation).
/// During zoom, the nearest cached zoom level is used and scaled slightly.
/// Cache is invalidated per-container when peaks change (import / recording).
public final class WaveformTileCache {

    /// A rendered waveform tile at a specific zoom level.
    struct Tile {
        let image: CGImage
        let pixelsPerBar: CGFloat
        let containerLengthBars: Double
    }

    /// Per-container cache of rendered tiles at various zoom levels.
    private var cache: [ID<Container>: [CGFloat: Tile]] = [:]

    /// Standard zoom levels to pre-render at.
    static let standardZoomLevels: [CGFloat] = [8, 16, 32, 64, 120, 240, 480, 960]

    /// Returns a cached tile for the given container at (or near) the given zoom level.
    /// Returns nil if no tile is cached — caller should fall back to direct drawing.
    func tile(forContainerID id: ID<Container>, pixelsPerBar: CGFloat) -> Tile? {
        guard let containerTiles = cache[id] else { return nil }

        // Exact match
        if let exact = containerTiles[pixelsPerBar] { return exact }

        // Nearest cached zoom level (prefer slightly larger for downscale quality)
        let nearest = containerTiles.keys.min(by: {
            abs($0 - pixelsPerBar) < abs($1 - pixelsPerBar)
        })
        if let nearest, let tile = containerTiles[nearest] {
            // Only use if within 2x of target (beyond that, quality degrades)
            let ratio = pixelsPerBar / nearest
            if ratio >= 0.5 && ratio <= 2.0 {
                return tile
            }
        }

        return nil
    }

    /// Generates and caches a waveform tile for the given parameters.
    /// Renders into an offscreen CGContext — call from a background thread if needed.
    func generateTile(
        containerID: ID<Container>,
        peaks: [Float],
        containerLengthBars: Double,
        pixelsPerBar: CGFloat,
        height: CGFloat,
        color: NSColor
    ) -> Tile? {
        guard !peaks.isEmpty, containerLengthBars > 0 else { return nil }

        let fullWidth = CGFloat(containerLengthBars) * pixelsPerBar
        guard fullWidth > 0, height > 0 else { return nil }

        // Cap bitmap width to avoid huge allocations for wide containers.
        // The tile gets stretched to fill the container rect during blit,
        // which is fine — waveform fidelity at zoomed-out levels doesn't
        // need pixel-perfect resolution.
        let adaptiveMax = fullWidth > 4096 ? 1024 : 2048
        let intWidth = min(Int(ceil(fullWidth)), adaptiveMax)
        let intHeight = Int(ceil(height))

        guard let context = CGContext(
            data: nil,
            width: intWidth,
            height: intHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip coordinate system to match isFlipped = true
        context.translateBy(x: 0, y: CGFloat(intHeight))
        context.scaleBy(x: 1, y: -1)

        let rect = CGRect(x: 0, y: 0, width: CGFloat(intWidth), height: CGFloat(intHeight))
        drawWaveformIntoContext(
            context: context,
            peaks: peaks,
            rect: rect,
            color: color
        )

        guard let image = context.makeImage() else { return nil }
        let tile = Tile(image: image, pixelsPerBar: pixelsPerBar, containerLengthBars: containerLengthBars)

        // Store in cache
        if cache[containerID] == nil {
            cache[containerID] = [:]
        }
        cache[containerID]![pixelsPerBar] = tile

        return tile
    }

    /// Invalidates all cached tiles for a specific container.
    func invalidate(containerID: ID<Container>) {
        cache.removeValue(forKey: containerID)
    }

    /// Invalidates the entire cache.
    func invalidateAll() {
        cache.removeAll()
    }

    /// Returns the number of cached tiles (for testing).
    var totalTileCount: Int {
        cache.values.reduce(0) { $0 + $1.count }
    }

    /// Returns cached zoom levels for a container (for testing).
    func cachedZoomLevels(forContainerID id: ID<Container>) -> [CGFloat] {
        cache[id].map { Array($0.keys).sorted() } ?? []
    }

    // MARK: - Private

    private func drawWaveformIntoContext(
        context: CGContext,
        peaks: [Float],
        rect: CGRect,
        color: NSColor
    ) {
        let midY = rect.midY
        let halfHeight = rect.height / 2 * 0.9
        let peakWidth = rect.width / CGFloat(peaks.count)

        // Downsample when multiple peaks map to the same pixel column.
        // Use 2px minimum spacing to match the direct draw path.
        let minPointSpacing: CGFloat = 2.0
        let step: Int = max(1, Int(ceil(minPointSpacing / peakWidth)))
        let lastIndex = peaks.count - 1

        let path = CGMutablePath()
        let startX = peakWidth / 2
        path.move(to: CGPoint(x: startX, y: midY))

        // Top half (left to right) — max amplitude per bucket
        var lastStepIndex = 0
        for i in stride(from: 0, through: lastIndex, by: step) {
            let bucketEnd = min(i + step - 1, lastIndex)
            var maxAmp: Float = 0
            for j in i...bucketEnd {
                let a = abs(peaks[j])
                if a > maxAmp { maxAmp = a }
            }
            let x = CGFloat(i) * peakWidth + peakWidth / 2
            path.addLine(to: CGPoint(x: x, y: midY - CGFloat(maxAmp) * halfHeight))
            lastStepIndex = i
        }

        // Bridge
        let endX = CGFloat(lastStepIndex) * peakWidth + peakWidth / 2
        path.addLine(to: CGPoint(x: endX, y: midY))

        // Bottom half (right to left) — mirrored
        for i in stride(from: lastStepIndex, through: 0, by: -step) {
            let bucketEnd = min(i + step - 1, lastIndex)
            var maxAmp: Float = 0
            for j in i...bucketEnd {
                let a = abs(peaks[j])
                if a > maxAmp { maxAmp = a }
            }
            let x = CGFloat(i) * peakWidth + peakWidth / 2
            path.addLine(to: CGPoint(x: x, y: midY + CGFloat(maxAmp) * halfHeight))
        }
        path.closeSubpath()

        context.addPath(path)
        context.setFillColor(color.withAlphaComponent(0.4).cgColor)
        context.fillPath()
    }
}
