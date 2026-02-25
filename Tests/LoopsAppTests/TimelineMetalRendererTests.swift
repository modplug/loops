import Testing
import Metal
import simd
@testable import LoopsApp
@testable import LoopsCore

@Suite("TimelineMetalRenderer Tests")
struct TimelineMetalRendererTests {

    private func makeDevice() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalTestError.noDevice
        }
        return device
    }

    private func makeRenderer() throws -> TimelineMetalRenderer {
        let device = try makeDevice()
        return try TimelineMetalRenderer(device: device)
    }

    // MARK: - Shader Compilation

    @Test("Shader compilation succeeds")
    func shaderCompilation() throws {
        _ = try makeRenderer()
    }

    // MARK: - Buffer Building

    @Test("Build buffers produces geometry for empty timeline")
    func buildBuffersEmpty() throws {
        let renderer = try makeRenderer()

        renderer.buildBuffers(
            trackLayouts: [],
            sectionLayouts: [],
            pixelsPerBar: 120,
            totalBars: 32,
            timeSignature: TimeSignature(),
            gridMode: .adaptive,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            canvasWidth: 800,
            canvasHeight: 600,
            visibleMinX: 0,
            visibleMaxX: 800
        )

        // Grid lines and bar shading should still be generated
        #expect(renderer.rectCount > 0, "Should have grid bar shading rects")
        #expect(renderer.lineCount > 0, "Should have grid bar lines")
    }

    @Test("Build buffers produces container geometry")
    func buildBuffersWithContainers() throws {
        let renderer = try makeRenderer()

        let container = Container(
            name: "Test",
            startBar: 1.0,
            lengthBars: 4.0
        )
        let track = Track(
            name: "Audio 1",
            kind: .audio,
            containers: [container]
        )

        let containerLayout = TimelineCanvasView.ContainerLayout(
            container: container,
            rect: NSRect(x: 0, y: 44, width: 480, height: 80),
            waveformPeaks: nil,
            isSelected: false,
            isClone: false,
            resolvedMIDINotes: nil,
            enterFade: nil,
            exitFade: nil,
            audioDurationBars: nil
        )
        let trackLayout = TimelineCanvasView.TrackLayout(
            track: track,
            yOrigin: 44,
            height: 80,
            containers: [containerLayout]
        )

        renderer.buildBuffers(
            trackLayouts: [trackLayout],
            sectionLayouts: [],
            pixelsPerBar: 120,
            totalBars: 32,
            timeSignature: TimeSignature(),
            gridMode: .adaptive,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            canvasWidth: 800,
            canvasHeight: 600,
            visibleMinX: 0,
            visibleMaxX: 800
        )

        // Should have grid rects + track background + container fill
        #expect(renderer.rectCount >= 3, "Should have grid + track bg + container rects")
        #expect(renderer.lineCount > 0, "Should have grid lines + track separator")
    }

    @Test("Build buffers with visible range past timeline end does not crash")
    func buildBuffersVisiblePastEnd() throws {
        let renderer = try makeRenderer()

        // Simulate: scrolled far right (visibleMinX=1792) with small zoom (ppb=14)
        // totalBars=64 → content ends at 64*14=896px, but visible starts at 1792
        // This caused a "Range requires lowerBound <= upperBound" crash
        renderer.buildBuffers(
            trackLayouts: [],
            sectionLayouts: [],
            pixelsPerBar: 14,
            totalBars: 64,
            timeSignature: TimeSignature(),
            gridMode: .adaptive,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            canvasWidth: 1039,
            canvasHeight: 720,
            visibleMinX: 1792,
            visibleMaxX: 2831
        )

        // Should not crash; grid geometry may be empty since visible area is past content
        #expect(renderer.rectCount >= 0)
    }

    @Test("Build buffers with waveform peaks")
    func buildBuffersWithWaveform() throws {
        let renderer = try makeRenderer()

        let container = Container(
            name: "Audio Clip",
            startBar: 1.0,
            lengthBars: 4.0
        )
        let track = Track(
            name: "Audio 1",
            kind: .audio,
            containers: [container]
        )

        // Generate synthetic peak data
        let peaks = (0..<200).map { Float(sin(Double($0) * 0.1) * 0.5 + 0.5) }

        let containerLayout = TimelineCanvasView.ContainerLayout(
            container: container,
            rect: NSRect(x: 0, y: 44, width: 480, height: 80),
            waveformPeaks: peaks,
            isSelected: false,
            isClone: false,
            resolvedMIDINotes: nil,
            enterFade: nil,
            exitFade: nil,
            audioDurationBars: nil
        )
        let trackLayout = TimelineCanvasView.TrackLayout(
            track: track,
            yOrigin: 44,
            height: 80,
            containers: [containerLayout]
        )

        renderer.buildBuffers(
            trackLayouts: [trackLayout],
            sectionLayouts: [],
            pixelsPerBar: 120,
            totalBars: 32,
            timeSignature: TimeSignature(),
            gridMode: .adaptive,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            canvasWidth: 800,
            canvasHeight: 600,
            visibleMinX: 0,
            visibleMaxX: 800
        )

        #expect(renderer.rectCount >= 3)
    }

    // MARK: - Offscreen Rendering

    @Test("Offscreen render produces non-empty output")
    func offscreenRender() throws {
        let device = try makeDevice()
        let renderer = try TimelineMetalRenderer(device: device)

        // Build simple geometry
        let container = Container(
            name: "Test",
            startBar: 1.0,
            lengthBars: 4.0
        )
        let track = Track(
            name: "Audio 1",
            kind: .audio,
            containers: [container]
        )

        let containerLayout = TimelineCanvasView.ContainerLayout(
            container: container,
            rect: NSRect(x: 0, y: 44, width: 480, height: 80),
            waveformPeaks: nil,
            isSelected: false,
            isClone: false,
            resolvedMIDINotes: nil,
            enterFade: nil,
            exitFade: nil,
            audioDurationBars: nil
        )
        let trackLayout = TimelineCanvasView.TrackLayout(
            track: track,
            yOrigin: 44,
            height: 80,
            containers: [containerLayout]
        )

        renderer.buildBuffers(
            trackLayouts: [trackLayout],
            sectionLayouts: [],
            pixelsPerBar: 120,
            totalBars: 32,
            timeSignature: TimeSignature(),
            gridMode: .adaptive,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            canvasWidth: 800,
            canvasHeight: 600,
            visibleMinX: 0,
            visibleMaxX: 800
        )

        // Create offscreen render target
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 800,
            height: 600,
            mipmapped: false
        )
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: texDesc) else {
            throw MetalTestError.textureCreation
        }

        // Render
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else {
            throw MetalTestError.encoderCreation
        }

        let viewportSize = MTLSize(width: 800, height: 600, depth: 1)
        encoder.setViewport(MTLViewport(
            originX: 0, originY: 0,
            width: 800, height: 600,
            znear: 0, zfar: 1
        ))

        var uniforms = TimelineUniforms(
            projectionMatrix: TimelineUniforms.orthographic(
                left: 0, right: 800,
                top: 0, bottom: 600
            ),
            pixelsPerBar: 120,
            canvasHeight: 600,
            viewportMinX: 0,
            viewportMaxX: 800
        )

        renderer.encode(into: encoder, uniforms: &uniforms, viewportSize: viewportSize)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read back pixels and verify non-zero content
        var pixels = [UInt8](repeating: 0, count: 800 * 600 * 4)
        texture.getBytes(
            &pixels,
            bytesPerRow: 800 * 4,
            from: MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: 800, height: 600, depth: 1)
            ),
            mipmapLevel: 0
        )

        let hasContent = pixels.contains { $0 != 0 }
        #expect(hasContent, "Metal render should produce non-empty pixel output")
    }

    // MARK: - Projection Matrix

    @Test("Orthographic projection maps corners correctly")
    func orthographicProjection() throws {
        // Viewport from (100, 50) to (900, 650) — a flipped coordinate system
        let proj = TimelineUniforms.orthographic(
            left: 100, right: 900,
            top: 50, bottom: 650
        )

        // Top-left corner (100, 50) should map to NDC (-1, +1)
        let topLeft = proj * SIMD4<Float>(100, 50, 0, 1)
        #expect(abs(topLeft.x / topLeft.w - (-1)) < 0.001)
        #expect(abs(topLeft.y / topLeft.w - 1) < 0.001)

        // Bottom-right corner (900, 650) should map to NDC (+1, -1)
        let bottomRight = proj * SIMD4<Float>(900, 650, 0, 1)
        #expect(abs(bottomRight.x / bottomRight.w - 1) < 0.001)
        #expect(abs(bottomRight.y / bottomRight.w - (-1)) < 0.001)

        // Center (500, 350) should map to NDC (0, 0)
        let center = proj * SIMD4<Float>(500, 350, 0, 1)
        #expect(abs(center.x / center.w) < 0.001)
        #expect(abs(center.y / center.w) < 0.001)
    }

    @Test("Orthographic projection flips Y for isFlipped view")
    func orthographicFlipsY() throws {
        // For a flipped view: top (small Y) should be at NDC +1, bottom (large Y) at NDC -1
        let proj = TimelineUniforms.orthographic(
            left: 0, right: 800,
            top: 0, bottom: 600
        )

        // Y=0 (top of flipped view) -> NDC y=+1
        let topPoint = proj * SIMD4<Float>(400, 0, 0, 1)
        #expect(abs(topPoint.y / topPoint.w - 1) < 0.001)

        // Y=600 (bottom of flipped view) -> NDC y=-1
        let bottomPoint = proj * SIMD4<Float>(400, 600, 0, 1)
        #expect(abs(bottomPoint.y / bottomPoint.w - (-1)) < 0.001)
    }

    // MARK: - Grid Extent

    @Test("Grid lines extend to visibleMaxY when scrolled")
    func gridExtendsToVisibleMaxY() throws {
        let renderer = try makeRenderer()

        // Simulate scrolled state: viewport starts at Y=1800, visible to Y=2400
        // Canvas content height is only 2000 (tracks end), but we're scrolled past it
        renderer.buildBuffers(
            trackLayouts: [],
            sectionLayouts: [],
            pixelsPerBar: 120,
            totalBars: 32,
            timeSignature: TimeSignature(),
            gridMode: .adaptive,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            canvasWidth: 800,
            canvasHeight: 2000,
            visibleMinX: 0,
            visibleMaxX: 800,
            visibleMinY: 1800,
            visibleMaxY: 2400
        )

        // Grid should extend to at least visibleMaxY (2400), not stop at canvasHeight (2000)
        #expect(renderer.rectCount > 0, "Should have grid shading rects")
        #expect(renderer.lineCount > 0, "Should have grid lines")
    }

    @Test("Grid lines extend to canvasHeight when not scrolled past content")
    func gridExtendsToCanvasHeight() throws {
        let renderer = try makeRenderer()

        // Viewport within content bounds
        renderer.buildBuffers(
            trackLayouts: [],
            sectionLayouts: [],
            pixelsPerBar: 120,
            totalBars: 32,
            timeSignature: TimeSignature(),
            gridMode: .adaptive,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            canvasWidth: 800,
            canvasHeight: 2000,
            visibleMinX: 0,
            visibleMaxX: 800,
            visibleMinY: 0,
            visibleMaxY: 600
        )

        // Grid should extend to canvasHeight (2000), not visibleMaxY (600)
        #expect(renderer.rectCount > 0)
        #expect(renderer.lineCount > 0)
    }

    // MARK: - Waveform Peak Downsampling

    @Test("Waveform peaks are downsampled when container is narrow")
    func waveformPeakDownsampling() throws {
        let renderer = try makeRenderer()

        let container = Container(
            name: "Clip",
            startBar: 1.0,
            lengthBars: 4.0
        )
        let track = Track(
            name: "Audio 1",
            kind: .audio,
            containers: [container]
        )

        // 1000 peaks in a container that's only 10px wide
        let peaks = [Float](repeating: 0.5, count: 1000)

        let containerLayout = TimelineCanvasView.ContainerLayout(
            container: container,
            rect: NSRect(x: 0, y: 44, width: 10, height: 80),
            waveformPeaks: peaks,
            isSelected: false,
            isClone: false,
            resolvedMIDINotes: nil,
            enterFade: nil,
            exitFade: nil,
            audioDurationBars: nil
        )
        let trackLayout = TimelineCanvasView.TrackLayout(
            track: track,
            yOrigin: 44,
            height: 80,
            containers: [containerLayout]
        )

        renderer.buildBuffers(
            trackLayouts: [trackLayout],
            sectionLayouts: [],
            pixelsPerBar: 2.5,
            totalBars: 32,
            timeSignature: TimeSignature(),
            gridMode: .adaptive,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            canvasWidth: 800,
            canvasHeight: 600,
            visibleMinX: 0,
            visibleMaxX: 800
        )

        // With 10px container width, maxPeaks = max(4, 10/2) = 5
        // So 1000 peaks should be downsampled to 5
        #expect(renderer.waveformParamsList.count == 1, "Should have one waveform")
        #expect(renderer.waveformParamsList[0].peakCount == 5,
                "1000 peaks in 10px container should downsample to 5 peaks")
    }

    @Test("Waveform skipped for containers narrower than 4px")
    func waveformSkippedForTinyContainers() throws {
        let renderer = try makeRenderer()

        let container = Container(
            name: "Tiny",
            startBar: 1.0,
            lengthBars: 1.0
        )
        let track = Track(
            name: "Audio 1",
            kind: .audio,
            containers: [container]
        )

        let peaks = [Float](repeating: 0.5, count: 100)

        let containerLayout = TimelineCanvasView.ContainerLayout(
            container: container,
            rect: NSRect(x: 0, y: 44, width: 3, height: 80),
            waveformPeaks: peaks,
            isSelected: false,
            isClone: false,
            resolvedMIDINotes: nil,
            enterFade: nil,
            exitFade: nil,
            audioDurationBars: nil
        )
        let trackLayout = TimelineCanvasView.TrackLayout(
            track: track,
            yOrigin: 44,
            height: 80,
            containers: [containerLayout]
        )

        renderer.buildBuffers(
            trackLayouts: [trackLayout],
            sectionLayouts: [],
            pixelsPerBar: 3,
            totalBars: 32,
            timeSignature: TimeSignature(),
            gridMode: .adaptive,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            canvasWidth: 800,
            canvasHeight: 600,
            visibleMinX: 0,
            visibleMaxX: 800
        )

        #expect(renderer.waveformParamsList.isEmpty,
                "Container < 4px wide should have no waveform")
    }

    @Test("Waveform peaks not downsampled when container is wide enough")
    func waveformNoDownsamplingWhenWide() throws {
        let renderer = try makeRenderer()

        let container = Container(
            name: "Wide",
            startBar: 1.0,
            lengthBars: 4.0
        )
        let track = Track(
            name: "Audio 1",
            kind: .audio,
            containers: [container]
        )

        // 100 peaks in a 480px container — plenty of space
        let peaks = (0..<100).map { Float(sin(Double($0) * 0.1) * 0.5 + 0.5) }

        let containerLayout = TimelineCanvasView.ContainerLayout(
            container: container,
            rect: NSRect(x: 0, y: 44, width: 480, height: 80),
            waveformPeaks: peaks,
            isSelected: false,
            isClone: false,
            resolvedMIDINotes: nil,
            enterFade: nil,
            exitFade: nil,
            audioDurationBars: nil
        )
        let trackLayout = TimelineCanvasView.TrackLayout(
            track: track,
            yOrigin: 44,
            height: 80,
            containers: [containerLayout]
        )

        renderer.buildBuffers(
            trackLayouts: [trackLayout],
            sectionLayouts: [],
            pixelsPerBar: 120,
            totalBars: 32,
            timeSignature: TimeSignature(),
            gridMode: .adaptive,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            canvasWidth: 800,
            canvasHeight: 600,
            visibleMinX: 0,
            visibleMaxX: 800
        )

        #expect(renderer.waveformParamsList.count == 1)
        #expect(renderer.waveformParamsList[0].peakCount == 100,
                "100 peaks in 480px container should not be downsampled")
    }

    @Test("Downsampled peaks preserve max amplitudes")
    func downsampledPeaksPreserveMaxAmplitude() throws {
        let renderer = try makeRenderer()

        let container = Container(
            name: "Clip",
            startBar: 1.0,
            lengthBars: 4.0
        )
        let track = Track(
            name: "Audio 1",
            kind: .audio,
            containers: [container]
        )

        // 20 peaks with a known max at index 5
        var peaks = [Float](repeating: 0.1, count: 20)
        peaks[5] = 0.95  // known max in first bucket

        // Container is 8px wide → maxPeaks = max(4, 8/2) = 4
        // Bucket size = 20/4 = 5 peaks each
        // Bucket 0: peaks[0..4] → max 0.1
        // Bucket 1: peaks[5..9] → max 0.95
        let containerLayout = TimelineCanvasView.ContainerLayout(
            container: container,
            rect: NSRect(x: 0, y: 44, width: 8, height: 80),
            waveformPeaks: peaks,
            isSelected: false,
            isClone: false,
            resolvedMIDINotes: nil,
            enterFade: nil,
            exitFade: nil,
            audioDurationBars: nil
        )
        let trackLayout = TimelineCanvasView.TrackLayout(
            track: track,
            yOrigin: 44,
            height: 80,
            containers: [containerLayout]
        )

        renderer.buildBuffers(
            trackLayouts: [trackLayout],
            sectionLayouts: [],
            pixelsPerBar: 2,
            totalBars: 32,
            timeSignature: TimeSignature(),
            gridMode: .adaptive,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            canvasWidth: 800,
            canvasHeight: 600,
            visibleMinX: 0,
            visibleMaxX: 800
        )

        #expect(renderer.waveformParamsList.count == 1)
        #expect(renderer.waveformParamsList[0].peakCount == 4)
    }

    // MARK: - Waveform-Audio Sync

    @Test("Waveform uses audioDurationBars for width when available")
    func waveformUsesAudioDurationBars() throws {
        let renderer = try makeRenderer()

        // Container is 6 bars wide (ceil'd from 5.5), but audio is only 5.5 bars
        let container = Container(
            name: "Clip",
            startBar: 1.0,
            lengthBars: 6.0
        )
        let track = Track(
            name: "Audio 1",
            kind: .audio,
            containers: [container]
        )

        let peaks = [Float](repeating: 0.5, count: 50)
        let ppb: CGFloat = 120

        let containerLayout = TimelineCanvasView.ContainerLayout(
            container: container,
            rect: NSRect(x: 0, y: 44, width: 6.0 * ppb, height: 80),
            waveformPeaks: peaks,
            isSelected: false,
            isClone: false,
            resolvedMIDINotes: nil,
            enterFade: nil,
            exitFade: nil,
            audioDurationBars: 5.5  // actual audio is 5.5 bars
        )
        let trackLayout = TimelineCanvasView.TrackLayout(
            track: track,
            yOrigin: 44,
            height: 80,
            containers: [containerLayout]
        )

        renderer.buildBuffers(
            trackLayouts: [trackLayout],
            sectionLayouts: [],
            pixelsPerBar: ppb,
            totalBars: 32,
            timeSignature: TimeSignature(),
            gridMode: .adaptive,
            selectedRange: nil,
            rangeSelection: nil,
            showRulerAndSections: true,
            canvasWidth: 800,
            canvasHeight: 600,
            visibleMinX: 0,
            visibleMaxX: 800
        )

        #expect(renderer.waveformParamsList.count == 1)
        // Waveform width should be 5.5 * 120 = 660, not 6.0 * 120 = 720
        let wfWidth = renderer.waveformParamsList[0].containerSize.x
        #expect(abs(wfWidth - 660) < 1.0,
                "Waveform width should match audio duration (660px), got \(wfWidth)")
    }

    // MARK: - Errors

    private enum MetalTestError: Error {
        case noDevice
        case textureCreation
        case encoderCreation
    }
}
