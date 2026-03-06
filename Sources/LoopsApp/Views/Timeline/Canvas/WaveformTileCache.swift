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

        // Prefer reusing a slightly larger tile to avoid blurring from upscaling.
        let largerOrEqual = containerTiles.keys
            .filter { $0 >= pixelsPerBar }
            .min()
        if let largerOrEqual, let tile = containerTiles[largerOrEqual] {
            let ratio = largerOrEqual / pixelsPerBar
            if ratio <= 1.5 {
                return tile
            }
        }

        // Fall back to a smaller tile only at low zoom levels where slight
        // upscale is less noticeable than rebuilding constantly.
        let nearestSmaller = containerTiles.keys
            .filter { $0 < pixelsPerBar }
            .max()
        if let nearestSmaller, let tile = containerTiles[nearestSmaller] {
            let ratio = pixelsPerBar / nearestSmaller
            if ratio <= 1.15 {
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
        color: NSColor,
        contentsScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
    ) -> Tile? {
        guard !peaks.isEmpty, containerLengthBars > 0 else { return nil }

        let fullWidth = CGFloat(containerLengthBars) * pixelsPerBar
        guard fullWidth > 0, height > 0 else { return nil }

        // Keep enough horizontal resolution that overview/edit waveforms do not
        // turn muddy when stretched across longer clips, while still capping
        // pathological zoom levels.
        let adaptiveMax = fullWidth > 8192 ? 8192 : 4096
        let scale = max(1, contentsScale)
        let intWidth = min(Int(ceil(fullWidth * scale)), Int(CGFloat(adaptiveMax) * scale))
        let intHeight = Int(ceil(height * scale))

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
        context.interpolationQuality = .none
        context.translateBy(x: 0, y: CGFloat(intHeight))
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: scale, y: scale)

        let rect = CGRect(x: 0, y: 0, width: CGFloat(intWidth) / scale, height: CGFloat(intHeight) / scale)
        drawWaveformIntoContext(
            context: context,
            extrema: peaks.map { WaveformExtrema(minimum: -$0, maximum: $0) },
            rms: peaks,
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
        extrema: [WaveformExtrema],
        rms: [Float],
        rect: CGRect,
        color: NSColor
    ) {
        guard !extrema.isEmpty else { return }

        context.setShouldAntialias(false)
        let midY = rect.midY
        let halfHeight = rect.height / 2 * 0.9
        let width = max(1, Int(rect.width.rounded(.up)))
        let count = extrema.count
        let envelopeMode = Double(count) / Double(width) > 1.2
        let outerColor = color.withAlphaComponent(0.86).cgColor
        let innerColor = color.withAlphaComponent(0.98).cgColor

        var outerAmplitudes = Array(repeating: Float(0), count: width)
        var rmsAmplitudes = Array(repeating: Float(0), count: width)
        var signedMinima = Array(repeating: Float(0), count: width)
        var signedMaxima = Array(repeating: Float(0), count: width)

        for x in 0..<width {
            let start = min(count - 1, Int((Double(x) / Double(width)) * Double(count)))
            let end = max(start + 1, min(count, Int((Double(x + 1) / Double(width)) * Double(count))))
            guard start < end else { continue }

            var minimum = extrema[start].minimum
            var maximum = extrema[start].maximum
            var rmsValue = rms.isEmpty ? max(abs(minimum), abs(maximum)) * 0.65 : rms[min(start, rms.count - 1)]

            if end - start > 1 {
                for index in start + 1..<end {
                    let value = extrema[index]
                    minimum = min(minimum, value.minimum)
                    maximum = max(maximum, value.maximum)
                    if !rms.isEmpty {
                        rmsValue = max(rmsValue, rms[min(index, rms.count - 1)])
                    }
                }
            }

            outerAmplitudes[x] = max(abs(minimum), abs(maximum))
            rmsAmplitudes[x] = min(max(rmsValue, 0), 1)
            signedMinima[x] = minimum
            signedMaxima[x] = maximum
        }

        if envelopeMode && width >= 3 {
            for x in 1..<(width - 1) {
                outerAmplitudes[x] = max(
                    outerAmplitudes[x],
                    (outerAmplitudes[x - 1] + outerAmplitudes[x] + outerAmplitudes[x + 1]) / 3
                )
                rmsAmplitudes[x] = max(
                    rmsAmplitudes[x],
                    (rmsAmplitudes[x - 1] + rmsAmplitudes[x] + rmsAmplitudes[x + 1]) / 3
                )
            }
        }

        for x in 0..<width {
            let top: CGFloat
            let bottom: CGFloat
            if envelopeMode {
                let amplitude = CGFloat(outerAmplitudes[x]) * halfHeight
                top = midY - amplitude
                bottom = midY + amplitude
            } else {
                top = midY - CGFloat(signedMaxima[x]) * halfHeight
                bottom = midY - CGFloat(signedMinima[x]) * halfHeight
            }

            let outerRect = CGRect(
                x: rect.minX + CGFloat(x),
                y: floor(min(top, bottom)),
                width: 1,
                height: max(1, ceil(abs(bottom - top)))
            )
            context.setFillColor(outerColor)
            context.fill(outerRect)

            let clampedRMS = rmsAmplitudes[x]
            let rmsTop = midY - CGFloat(clampedRMS) * halfHeight
            let rmsBottom = midY + CGFloat(clampedRMS) * halfHeight
            let innerRect = CGRect(
                x: rect.minX + CGFloat(x),
                y: floor(rmsTop),
                width: 1,
                height: max(1, ceil(rmsBottom - rmsTop))
            )
            context.setFillColor(innerColor)
            context.fill(innerRect)
        }
    }

    func generateTile(
        containerID: ID<Container>,
        extrema: [WaveformExtrema],
        rms: [Float],
        containerLengthBars: Double,
        pixelsPerBar: CGFloat,
        height: CGFloat,
        color: NSColor,
        contentsScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
    ) -> Tile? {
        guard !extrema.isEmpty, containerLengthBars > 0 else { return nil }

        let fullWidth = CGFloat(containerLengthBars) * pixelsPerBar
        guard fullWidth > 0, height > 0 else { return nil }

        let adaptiveMax = fullWidth > 8192 ? 8192 : 4096
        let scale = max(1, contentsScale)
        let intWidth = min(Int(ceil(fullWidth * scale)), Int(CGFloat(adaptiveMax) * scale))
        let intHeight = Int(ceil(height * scale))

        guard let context = CGContext(
            data: nil,
            width: intWidth,
            height: intHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .none
        context.translateBy(x: 0, y: CGFloat(intHeight))
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: scale, y: scale)

        let rect = CGRect(x: 0, y: 0, width: CGFloat(intWidth) / scale, height: CGFloat(intHeight) / scale)
        drawWaveformIntoContext(
            context: context,
            extrema: extrema,
            rms: rms,
            rect: rect,
            color: color
        )

        guard let image = context.makeImage() else { return nil }
        let tile = Tile(image: image, pixelsPerBar: pixelsPerBar, containerLengthBars: containerLengthBars)

        if cache[containerID] == nil {
            cache[containerID] = [:]
        }
        cache[containerID]![pixelsPerBar] = tile

        return tile
    }
}
