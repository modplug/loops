import Metal
import QuartzCore
import simd
import LoopsCore
import AppKit

/// Manages all Metal pipeline state, buffer allocation, and render encoding
/// for the timeline. Constructed once and reused across frames.
final class TimelineMetalRenderer {

    // MARK: - Metal State

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let library: MTLLibrary

    // Pipeline states
    private let rectPipeline: MTLRenderPipelineState
    private let linePipeline: MTLRenderPipelineState
    private let waveformPipeline: MTLRenderPipelineState
    private let midiPipeline: MTLRenderPipelineState
    private let fadePipeline: MTLRenderPipelineState

    // Shared index buffer for unit quad (2 triangles: 0,1,2 + 2,1,3)
    private let quadIndexBuffer: MTLBuffer

    // MARK: - Frame Synchronization

    /// Double-buffered semaphore — allows CPU to prepare frame N+1 while GPU renders frame N.
    let frameSemaphore = DispatchSemaphore(value: 2)

    // MARK: - Built Buffers (rebuilt per-frame when data changes)

    private var rectBuffer: MTLBuffer?
    private(set) var rectCount: Int = 0

    private var lineBuffer: MTLBuffer?
    private(set) var lineCount: Int = 0

    private var peakBuffer: MTLBuffer?
    private(set) var waveformParamsList: [WaveformParams] = []

    private var midiBuffer: MTLBuffer?
    private var midiCount: Int = 0

    private var fadeVertexBuffer: MTLBuffer?
    private var fadeVertexCount: Int = 0
    private var fadeDrawCalls: [(offset: Int, count: Int)] = []

    // Border rects drawn after containers (thicker, SDF rounded)
    private var borderBuffer: MTLBuffer?
    private var borderCount: Int = 0

    // MARK: - Init

    init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw MetalError.noCommandQueue
        }
        self.commandQueue = queue

        // Compile shaders from source string
        let compileOptions = MTLCompileOptions()
        self.library = try device.makeLibrary(source: timelineShaderSource, options: compileOptions)

        // Pixel format for CAMetalLayer
        let pixelFormat: MTLPixelFormat = .bgra8Unorm

        // Rect pipeline
        self.rectPipeline = try Self.makePipeline(
            device: device, library: library, pixelFormat: pixelFormat,
            vertexFunction: "rect_vertex", fragmentFunction: "rect_fragment"
        )

        // Line pipeline
        self.linePipeline = try Self.makePipeline(
            device: device, library: library, pixelFormat: pixelFormat,
            vertexFunction: "line_vertex", fragmentFunction: "line_fragment"
        )

        // Waveform pipeline
        self.waveformPipeline = try Self.makePipeline(
            device: device, library: library, pixelFormat: pixelFormat,
            vertexFunction: "waveform_vertex", fragmentFunction: "waveform_fragment"
        )

        // MIDI pipeline
        self.midiPipeline = try Self.makePipeline(
            device: device, library: library, pixelFormat: pixelFormat,
            vertexFunction: "midi_vertex", fragmentFunction: "midi_fragment"
        )

        // Fade pipeline
        self.fadePipeline = try Self.makePipeline(
            device: device, library: library, pixelFormat: pixelFormat,
            vertexFunction: "fade_vertex", fragmentFunction: "fade_fragment"
        )

        // Shared unit quad index buffer
        let indices: [UInt16] = [0, 1, 2, 2, 1, 3]
        guard let ib = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride, options: .storageModeShared) else {
            throw MetalError.bufferAllocation
        }
        self.quadIndexBuffer = ib
    }

    // MARK: - Pipeline Construction

    private static func makePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat,
        vertexFunction: String,
        fragmentFunction: String
    ) throws -> MTLRenderPipelineState {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: vertexFunction)
        desc.fragmentFunction = library.makeFunction(name: fragmentFunction)
        desc.colorAttachments[0].pixelFormat = pixelFormat

        // Alpha blending for transparency
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].alphaBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try device.makeRenderPipelineState(descriptor: desc)
    }

    // MARK: - Buffer Building

    /// Rebuilds all GPU buffers from the current timeline layout data.
    /// Called from `TimelineMetalView.draw(_:)` when data has changed.
    func buildBuffers(
        trackLayouts: [TimelineCanvasView.TrackLayout],
        sectionLayouts: [TimelineCanvasView.SectionLayout],
        pixelsPerBar: CGFloat,
        totalBars: Int,
        timeSignature: TimeSignature,
        gridMode: GridMode,
        selectedRange: ClosedRange<Int>?,
        rangeSelection: SelectionState.RangeSelection?,
        showRulerAndSections: Bool,
        canvasWidth: Float,
        canvasHeight: Float,
        visibleMinX: Float,
        visibleMaxX: Float,
        visibleMinY: Float = 0,
        visibleMaxY: Float = 0
    ) {
        let ppb = Float(pixelsPerBar)
        // When ruler is shown, pin grid top to viewport so ruler area stays above
        let rulerHeight = Float(TimelineCanvasView.rulerHeight)
        let sectionLaneHeight = Float(TimelineCanvasView.sectionLaneHeight)
        let trackAreaTop = rulerHeight + sectionLaneHeight
        let gridTop = showRulerAndSections ? (visibleMinY + trackAreaTop) : Float(0)

        var rects: [RectInstance] = []
        var lines: [LineInstance] = []
        var allPeaks: [Float] = []
        var wfParams: [WaveformParams] = []
        var midiNotes: [MIDINoteInstance] = []
        var fadeVerts: [FadeVertex] = []
        var fadeCalls: [(offset: Int, count: Int)] = []
        var borders: [RectInstance] = []

        // ── Grid: alternating bar shading ──
        // Extend grid across full visible area (not clamped to totalBars)
        // so gridlines appear even past the last bar of content.
        // Use max(canvasHeight, visibleMaxY) so grid fills the visible viewport
        // even when scrolled below the total content height.
        let gridBottom = max(canvasHeight, visibleMaxY)
        let startBar = max(0, Int(floor(visibleMinX / ppb)) - 2)
        let endBar = Int(ceil(visibleMaxX / ppb)) + 2
        let shadingColor = SIMD4<Float>(1, 1, 1, 0.03)

        for bar in startBar..<endBar where bar % 2 == 0 {
            let x = Float(bar) * ppb
            rects.append(RectInstance(
                origin: SIMD2(x, gridTop),
                size: SIMD2(ppb, gridBottom - gridTop),
                color: shadingColor
            ))
        }

        // ── Grid: bar lines ──
        // Use 1.0px width for consistent rendering at retina (0.5px causes
        // sub-pixel aliasing where some lines appear thicker than others)
        let barLineColor = SIMD4<Float>(1, 1, 1, 0.15)
        for bar in startBar...endBar {
            let x = Float(bar) * ppb
            lines.append(LineInstance(
                start: SIMD2(x, gridTop),
                end: SIMD2(x, gridBottom),
                color: barLineColor,
                width: 1
            ))
        }

        // ── Grid: beat lines ──
        let pixelsPerBeat = ppb / Float(timeSignature.beatsPerBar)
        if pixelsPerBeat >= 20 {
            let beatLineColor = SIMD4<Float>(1, 1, 1, 0.06)
            for bar in startBar...endBar {
                let barX = Float(bar) * ppb
                for beat in 1..<timeSignature.beatsPerBar {
                    let beatX = barX + Float(beat) * pixelsPerBeat
                    lines.append(LineInstance(
                        start: SIMD2(beatX, gridTop),
                        end: SIMD2(beatX, gridBottom),
                        color: beatLineColor,
                        width: 1
                    ))
                }
            }
        }

        // ── Track backgrounds + separators ──
        let bgColor = SIMD4<Float>(0.5, 0.5, 0.5, 0.15)
        // High-contrast separator: white at alpha 0.5 stands out against both
        // container fills and empty track backgrounds
        let sepColor = SIMD4<Float>(1, 1, 1, 0.15)

        for layout in trackLayouts {
            let y = Float(layout.yOrigin)
            let h = Float(layout.height)

            rects.append(RectInstance(
                origin: SIMD2(visibleMinX, y),
                size: SIMD2(visibleMaxX - visibleMinX, h),
                color: bgColor
            ))

            // Separator line at bottom of each track
            let sepY = y + h
            lines.append(LineInstance(
                start: SIMD2(visibleMinX, sepY),
                end: SIMD2(visibleMaxX, sepY),
                color: sepColor,
                width: 1
            ))
        }

        // ── Containers ──
        for trackLayout in trackLayouts {
            let trackColors = TrackMetalColors(kind: trackLayout.track.kind)

            for cl in trackLayout.containers {
                let rect = cl.rect
                // Visibility cull
                guard Float(rect.maxX) >= visibleMinX && Float(rect.minX) <= visibleMaxX else { continue }

                let isArmed = cl.container.isRecordArmed
                let fillColor: SIMD4<Float> = isArmed ? trackColors.fillArmed
                    : cl.isSelected ? trackColors.fillSelected : trackColors.fillNormal

                let origin = SIMD2<Float>(Float(rect.minX), Float(rect.minY))
                let size = SIMD2<Float>(Float(rect.width), Float(rect.height))

                // Container fill — inset 1px top/bottom for visual track separation
                let fillOrigin = SIMD2<Float>(origin.x, origin.y + 1)
                let fillSize = SIMD2<Float>(size.x, max(size.y - 2, 1))
                rects.append(RectInstance(
                    origin: fillOrigin, size: fillSize, color: fillColor
                ))

                // Container border (drawn later on top, also inset to match fill)
                let borderColor: SIMD4<Float> = isArmed ? trackColors.borderArmed
                    : cl.isSelected ? trackColors.borderSelected : trackColors.borderNormal
                borders.append(RectInstance(
                    origin: fillOrigin, size: fillSize, color: borderColor, cornerRadius: 4
                ))

                // Selection highlight (thicker outer glow)
                if cl.isSelected {
                    borders.append(RectInstance(
                        origin: SIMD2(fillOrigin.x - 1, fillOrigin.y - 1),
                        size: SIMD2(fillSize.x + 2, fillSize.y + 2),
                        color: trackColors.selectionHighlight,
                        cornerRadius: 5
                    ))
                }

                // ── Waveform ──
                if let peaks = cl.waveformPeaks, !peaks.isEmpty {
                    let containerWidthPx = fillSize.x

                    // Skip waveform for containers too narrow to render meaningfully
                    if containerWidthPx >= 4 {
                        // Downsample peaks on the CPU when zoomed out so the GPU
                        // receives at most 1 peak per 2 pixels (matches CG path).
                        let maxPeaks = max(4, Int(containerWidthPx / 2))
                        let uploadPeaks: [Float]
                        if peaks.count > maxPeaks {
                            let step = peaks.count / maxPeaks
                            var downsampled = [Float](repeating: 0, count: maxPeaks)
                            for i in 0..<maxPeaks {
                                let start = i * step
                                let end = min(start + step, peaks.count)
                                var maxAmp: Float = 0
                                for j in start..<end {
                                    let a = abs(peaks[j])
                                    if a > maxAmp { maxAmp = a }
                                }
                                downsampled[i] = maxAmp
                            }
                            uploadPeaks = downsampled
                        } else {
                            uploadPeaks = peaks
                        }

                        // Scale waveform width to actual audio content if available,
                        // preventing drift when container.lengthBars was ceil'd.
                        let waveformWidth: Float
                        if let audioDuration = cl.audioDurationBars {
                            let visibleAudioBars = min(
                                cl.container.lengthBars,
                                audioDuration - cl.container.audioStartOffset
                            )
                            waveformWidth = Float(visibleAudioBars) * ppb
                        } else {
                            waveformWidth = fillSize.x
                        }

                        let offset = UInt32(allPeaks.count)
                        allPeaks.append(contentsOf: uploadPeaks)
                        wfParams.append(WaveformParams(
                            containerOrigin: fillOrigin,
                            containerSize: SIMD2(waveformWidth, fillSize.y),
                            fillColor: trackColors.waveformFill,
                            peakOffset: offset,
                            peakCount: UInt32(uploadPeaks.count),
                            amplitude: 0.9
                        ))
                    }
                }

                // ── MIDI diamonds ──
                if let notes = cl.resolvedMIDINotes, !notes.isEmpty {
                    buildMIDIDiamonds(
                        notes: notes,
                        container: cl.container,
                        rect: rect,
                        color: trackColors.waveformFill,
                        timeSignature: timeSignature,
                        into: &midiNotes
                    )
                }

                // ── Fade overlays ──
                if cl.enterFade != nil || cl.exitFade != nil {
                    buildFadeOverlay(
                        enterFade: cl.enterFade,
                        exitFade: cl.exitFade,
                        rect: rect,
                        pixelsPerBar: ppb,
                        into: &fadeVerts,
                        calls: &fadeCalls
                    )
                }
            }

            // ── Crossfades ──
            for xfade in trackLayout.track.crossfades {
                buildCrossfade(
                    xfade, track: trackLayout.track, trackLayout: trackLayout,
                    pixelsPerBar: ppb,
                    visibleMinX: visibleMinX, visibleMaxX: visibleMaxX,
                    rects: &rects, lines: &lines
                )
            }
        }

        // ── Range selection overlay ──
        if let range = selectedRange {
            let startX = Float(range.lowerBound) * ppb
            let endX = Float(range.upperBound + 1) * ppb
            let totalHeight = trackLayouts.last.map { Float($0.yOrigin + $0.height) } ?? canvasHeight
            let accentColor = SIMD4<Float>(0.25, 0.55, 1.0, 0.15)
            rects.append(RectInstance(
                origin: SIMD2(startX, 0),
                size: SIMD2(endX - startX, totalHeight),
                color: accentColor
            ))
            // Selection edges
            let edgeColor = SIMD4<Float>(0.25, 0.55, 1.0, 0.5)
            lines.append(LineInstance(start: SIMD2(startX, 0), end: SIMD2(startX, totalHeight), color: edgeColor, width: 1))
            lines.append(LineInstance(start: SIMD2(endX, 0), end: SIMD2(endX, totalHeight), color: edgeColor, width: 1))
        }

        // ── Ruler + section lane backgrounds (pinned to viewport top, drawn on top) ──
        if showRulerAndSections {
            let rulerBg = SIMD4<Float>(0.11, 0.11, 0.12, 0.95)
            rects.append(RectInstance(
                origin: SIMD2(visibleMinX, visibleMinY),
                size: SIMD2(visibleMaxX - visibleMinX, rulerHeight),
                color: rulerBg
            ))
            let sectionBg = SIMD4<Float>(0.11, 0.11, 0.12, 0.85)
            rects.append(RectInstance(
                origin: SIMD2(visibleMinX, visibleMinY + rulerHeight),
                size: SIMD2(visibleMaxX - visibleMinX, sectionLaneHeight),
                color: sectionBg
            ))
            // Ruler bottom border
            lines.append(LineInstance(
                start: SIMD2(visibleMinX, visibleMinY + rulerHeight),
                end: SIMD2(visibleMaxX, visibleMinY + rulerHeight),
                color: SIMD4(1, 1, 1, 0.15),
                width: 1
            ))
            // Section lane bottom border
            lines.append(LineInstance(
                start: SIMD2(visibleMinX, visibleMinY + trackAreaTop),
                end: SIMD2(visibleMaxX, visibleMinY + trackAreaTop),
                color: SIMD4(1, 1, 1, 0.15),
                width: 1
            ))

            // Range selection highlight in ruler
            if let range = selectedRange {
                let rangeStartX = Float(range.lowerBound - 1) * ppb
                let rangeWidth = Float(range.count) * ppb
                rects.append(RectInstance(
                    origin: SIMD2(rangeStartX, visibleMinY),
                    size: SIMD2(rangeWidth, rulerHeight),
                    color: SIMD4(0.25, 0.55, 1.0, 0.25)
                ))
            }
        }

        // ── Upload to GPU ──
        rectBuffer = makeBuffer(rects)
        rectCount = rects.count

        lineBuffer = makeBuffer(lines)
        lineCount = lines.count

        peakBuffer = allPeaks.isEmpty ? nil : makeBuffer(allPeaks)
        waveformParamsList = wfParams

        midiBuffer = makeBuffer(midiNotes)
        midiCount = midiNotes.count

        fadeVertexBuffer = fadeVerts.isEmpty ? nil : makeBuffer(fadeVerts)
        fadeVertexCount = fadeVerts.count
        fadeDrawCalls = fadeCalls

        borderBuffer = makeBuffer(borders)
        borderCount = borders.count
    }

    // MARK: - Render Encoding

    /// Encodes all draw calls into the given render command encoder.
    func encode(
        into encoder: MTLRenderCommandEncoder,
        uniforms: inout TimelineUniforms,
        viewportSize: MTLSize
    ) {
        // Scissor rect = full viewport (could be refined for partial redraws)
        encoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: viewportSize.width, height: viewportSize.height))

        // 1. Rects (grid fills, track bg, container fills, range selection)
        if rectCount > 0, let buf = rectBuffer {
            encoder.setRenderPipelineState(rectPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<TimelineUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: rectCount
            )
        }

        // 2. Lines (grid lines, beat lines, separators, crossfade X)
        if lineCount > 0, let buf = lineBuffer {
            encoder.setRenderPipelineState(linePipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<TimelineUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: lineCount
            )
        }

        // 3. Waveforms (one draw per container)
        if !waveformParamsList.isEmpty, let peakBuf = peakBuffer {
            encoder.setRenderPipelineState(waveformPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<TimelineUniforms>.stride, index: 0)
            encoder.setVertexBuffer(peakBuf, offset: 0, index: 2)

            for var params in waveformParamsList {
                encoder.setVertexBytes(&params, length: MemoryLayout<WaveformParams>.stride, index: 1)
                // Triangle strip: 2 vertices per peak (top + bottom)
                let vertexCount = Int(params.peakCount) * 2
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCount)
            }
        }

        // 4. MIDI diamonds
        if midiCount > 0, let buf = midiBuffer {
            encoder.setRenderPipelineState(midiPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<TimelineUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            // Diamond: 4 vertices, 6 indices (2 triangles)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: midiCount
            )
        }

        // 5. Fade overlays
        if fadeVertexCount > 0, let buf = fadeVertexBuffer {
            encoder.setRenderPipelineState(fadePipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<TimelineUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            for call in fadeDrawCalls {
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: call.offset, vertexCount: call.count)
            }
        }

        // 6. Container borders (rounded rect SDF, drawn on top)
        if borderCount > 0, let buf = borderBuffer {
            encoder.setRenderPipelineState(rectPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<TimelineUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: borderCount
            )
        }
    }

    // MARK: - MIDI Diamond Builder

    private func buildMIDIDiamonds(
        notes: [MIDINoteEvent],
        container: Container,
        rect: NSRect,
        color: SIMD4<Float>,
        timeSignature: TimeSignature,
        into output: inout [MIDINoteInstance]
    ) {
        var minPitch: UInt8 = 127
        var maxPitch: UInt8 = 0
        for note in notes {
            if note.pitch < minPitch { minPitch = note.pitch }
            if note.pitch > maxPitch { maxPitch = note.pitch }
        }
        let pitchRange = max(Float(maxPitch - minPitch), 12)

        let beatsPerBar = Double(timeSignature.beatsPerBar)
        let totalBeats = container.lengthBars * beatsPerBar
        let invTotalBeats = 1.0 / totalBeats
        let heightMinusPad = Float(rect.height) - 4
        let invPitchRange = 1.0 / pitchRange
        let noteH = max(2, heightMinusPad * invPitchRange)

        for note in notes {
            let xFraction = Float(note.startBeat * invTotalBeats)
            let widthFraction = Float(note.duration * invTotalBeats)

            let noteX = Float(rect.minX) + xFraction * Float(rect.width)
            let noteW = max(2, widthFraction * Float(rect.width))
            let yFraction = 1.0 - (Float(note.pitch - minPitch) * invPitchRange)
            let noteY = Float(rect.minY) + yFraction * heightMinusPad + 2

            let centerX = noteX + noteW / 2
            let centerY = noteY + noteH / 2
            let halfSize = min(noteW, noteH, 8) / 2

            output.append(MIDINoteInstance(
                center: SIMD2(centerX, centerY),
                halfSize: halfSize,
                color: color
            ))
        }
    }

    // MARK: - Fade Overlay Builder

    private func buildFadeOverlay(
        enterFade: FadeSettings?,
        exitFade: FadeSettings?,
        rect: NSRect,
        pixelsPerBar: Float,
        into vertices: inout [FadeVertex],
        calls: inout [(offset: Int, count: Int)]
    ) {
        let fadeColor = SIMD4<Float>(0, 0, 0, 0.25)

        // Enter fade (left side)
        if let fade = enterFade, fade.duration > 0 {
            let fadeWidth = Float(fade.duration) * pixelsPerBar
            let steps = max(Int(fadeWidth / 2), 20)
            let offset = vertices.count

            // Triangle strip: alternating between bottom edge and curve
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let gain = fade.curve.gain(at: t)
                let x = Float(rect.minX) + Float(t) * fadeWidth
                let yBottom = Float(rect.minY)
                let yCurve = Float(rect.minY) + Float(gain) * Float(rect.height)

                vertices.append(FadeVertex(position: SIMD2(x, yBottom), color: fadeColor))
                vertices.append(FadeVertex(position: SIMD2(x, yCurve), color: SIMD4(0, 0, 0, 0)))
            }
            calls.append((offset: offset, count: (steps + 1) * 2))
        }

        // Exit fade (right side)
        if let fade = exitFade, fade.duration > 0 {
            let fadeWidth = Float(fade.duration) * pixelsPerBar
            let steps = max(Int(fadeWidth / 2), 20)
            let startX = Float(rect.maxX) - fadeWidth
            let offset = vertices.count

            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let gain = fade.curve.gain(at: 1.0 - t)
                let x = startX + Float(t) * fadeWidth
                let yBottom = Float(rect.minY)
                let yCurve = Float(rect.minY) + Float(gain) * Float(rect.height)

                vertices.append(FadeVertex(position: SIMD2(x, yBottom), color: fadeColor))
                vertices.append(FadeVertex(position: SIMD2(x, yCurve), color: SIMD4(0, 0, 0, 0)))
            }
            calls.append((offset: offset, count: (steps + 1) * 2))
        }
    }

    // MARK: - Crossfade Builder

    private func buildCrossfade(
        _ xfade: Crossfade,
        track: Track,
        trackLayout: TimelineCanvasView.TrackLayout,
        pixelsPerBar: Float,
        visibleMinX: Float,
        visibleMaxX: Float,
        rects: inout [RectInstance],
        lines: inout [LineInstance]
    ) {
        guard let containerA = track.containers.first(where: { $0.id == xfade.containerAID }),
              let containerB = track.containers.first(where: { $0.id == xfade.containerBID }) else { return }

        let overlap = xfade.duration(containerA: containerA, containerB: containerB)
        guard overlap > 0 else { return }

        let xStart = Float(containerB.startBar - 1.0) * pixelsPerBar
        let width = Float(overlap) * pixelsPerBar
        guard xStart + width >= visibleMinX && xStart <= visibleMaxX else { return }

        let y = Float(trackLayout.yOrigin) + 2
        let h = Float(trackLayout.height) - 4

        // Background
        rects.append(RectInstance(
            origin: SIMD2(xStart, y),
            size: SIMD2(width, h),
            color: SIMD4(1, 1, 1, 0.08)
        ))

        // X-pattern
        let xColor = SIMD4<Float>(1, 1, 1, 0.7)
        lines.append(LineInstance(start: SIMD2(xStart, y), end: SIMD2(xStart + width, y + h), color: xColor, width: 1.5))
        lines.append(LineInstance(start: SIMD2(xStart, y + h), end: SIMD2(xStart + width, y), color: xColor, width: 1.5))
    }

    // MARK: - Buffer Helpers

    private func makeBuffer<T>(_ data: [T]) -> MTLBuffer? {
        guard !data.isEmpty else { return nil }
        return data.withUnsafeBytes { ptr in
            device.makeBuffer(bytes: ptr.baseAddress!, length: ptr.count, options: .storageModeShared)
        }
    }

    // MARK: - Errors

    enum MetalError: Error {
        case noCommandQueue
        case bufferAllocation
        case pipelineCreation
    }
}

// MARK: - Track Colors for Metal

/// Pre-computed SIMD4 colors for each track kind, matching the CG path.
struct TrackMetalColors {
    let fillNormal: SIMD4<Float>
    let fillSelected: SIMD4<Float>
    let fillArmed: SIMD4<Float>
    let borderNormal: SIMD4<Float>
    let borderSelected: SIMD4<Float>
    let borderArmed: SIMD4<Float>
    let waveformFill: SIMD4<Float>
    let selectionHighlight: SIMD4<Float>

    init(kind: TrackKind) {
        let base = Self.baseColor(for: kind)
        fillNormal = SIMD4(base.x, base.y, base.z, 0.3)
        fillSelected = SIMD4(base.x, base.y, base.z, 0.5)
        fillArmed = SIMD4(1, 0.23, 0.19, 0.15) // systemRed alpha 0.15
        borderNormal = SIMD4(base.x, base.y, base.z, 0.6)
        borderSelected = SIMD4(0.25, 0.55, 1.0, 1.0) // controlAccentColor approximation
        borderArmed = SIMD4(1, 0.23, 0.19, 1.0) // systemRed
        waveformFill = SIMD4(base.x, base.y, base.z, 0.4)
        selectionHighlight = SIMD4(0.25, 0.55, 1.0, 0.3)
    }

    private static func baseColor(for kind: TrackKind) -> SIMD3<Float> {
        switch kind {
        case .audio: return SIMD3(0.0, 0.48, 1.0)      // systemBlue
        case .midi: return SIMD3(0.69, 0.32, 0.87)      // systemPurple
        case .bus: return SIMD3(0.20, 0.78, 0.35)       // systemGreen
        case .backing: return SIMD3(1.0, 0.58, 0.0)     // systemOrange
        case .master: return SIMD3(0.56, 0.56, 0.58)    // systemGray
        }
    }
}
