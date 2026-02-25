import Metal
import QuartzCore
import AppKit
import LoopsCore

public final class PlaybackGridRenderer {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    private let library: MTLLibrary

    private let rectPipeline: MTLRenderPipelineState
    private let linePipeline: MTLRenderPipelineState
    private let waveformPipeline: MTLRenderPipelineState
    private let midiPipeline: MTLRenderPipelineState
    private let fadePipeline: MTLRenderPipelineState

    private let quadIndexBuffer: MTLBuffer

    public let frameSemaphore = DispatchSemaphore(value: 2)

    private var rectBuffer: MTLBuffer?
    private var rectCount = 0

    private var lineBuffer: MTLBuffer?
    private var lineCount = 0

    private var peakBuffer: MTLBuffer?
    private var waveformParamsList: [PlaybackGridWaveformParams] = []

    private var midiBuffer: MTLBuffer?
    private var midiCount = 0

    private var fadeVertexBuffer: MTLBuffer?
    private var fadeVertexCount = 0
    private var fadeDrawCalls: [(offset: Int, count: Int)] = []

    private var borderBuffer: MTLBuffer?
    private var borderCount = 0
    public private(set) var debugStats = PlaybackGridDebugStats()

    public init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw PlaybackGridMetalError.noCommandQueue
        }
        commandQueue = queue

        library = try device.makeLibrary(source: playbackGridShaderSource, options: MTLCompileOptions())

        let pixelFormat: MTLPixelFormat = .bgra8Unorm
        rectPipeline = try Self.makePipeline(
            device: device,
            library: library,
            pixelFormat: pixelFormat,
            vertexFunction: "pg_rect_vertex",
            fragmentFunction: "pg_rect_fragment"
        )
        linePipeline = try Self.makePipeline(
            device: device,
            library: library,
            pixelFormat: pixelFormat,
            vertexFunction: "pg_line_vertex",
            fragmentFunction: "pg_line_fragment"
        )
        waveformPipeline = try Self.makePipeline(
            device: device,
            library: library,
            pixelFormat: pixelFormat,
            vertexFunction: "pg_waveform_vertex",
            fragmentFunction: "pg_waveform_fragment"
        )
        midiPipeline = try Self.makePipeline(
            device: device,
            library: library,
            pixelFormat: pixelFormat,
            vertexFunction: "pg_midi_vertex",
            fragmentFunction: "pg_midi_fragment"
        )
        fadePipeline = try Self.makePipeline(
            device: device,
            library: library,
            pixelFormat: pixelFormat,
            vertexFunction: "pg_fade_vertex",
            fragmentFunction: "pg_fade_fragment"
        )

        let indices: [UInt16] = [0, 1, 2, 2, 1, 3]
        guard let ib = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt16>.stride,
            options: .storageModeShared
        ) else {
            throw PlaybackGridMetalError.bufferAllocation
        }
        quadIndexBuffer = ib
    }

    public func buildBuffers(
        scene: PlaybackGridScene,
        snapshot: PlaybackGridSnapshot,
        canvasSize: CGSize,
        visibleRect: CGRect,
        focusedPick: GridPickObject = .none
    ) {
        let ppb = Float(snapshot.pixelsPerBar)
        let visibleMinX = Float(visibleRect.minX)
        let visibleMaxX = Float(visibleRect.maxX)
        let visibleMinY = Float(visibleRect.minY)
        let visibleMaxY = Float(visibleRect.maxY)
        let canvasHeight = Float(canvasSize.height)

        let rulerHeight = Float(PlaybackGridLayout.rulerHeight)
        let sectionLaneHeight = Float(PlaybackGridLayout.sectionLaneHeight)
        let trackAreaTop = rulerHeight + sectionLaneHeight
        let gridTop = snapshot.showRulerAndSections ? (visibleMinY + trackAreaTop) : Float(0)

        var rects: [PlaybackGridRectInstance] = []
        var lines: [PlaybackGridLineInstance] = []
        var allPeaks: [Float] = []
        var wfParams: [PlaybackGridWaveformParams] = []
        var midiNotes: [PlaybackGridMIDINoteInstance] = []
        var fadeVerts: [PlaybackGridFadeVertex] = []
        var fadeCalls: [(offset: Int, count: Int)] = []
        var borders: [PlaybackGridRectInstance] = []

        let gridBottom = max(canvasHeight, visibleMaxY)
        let startBar = max(0, Int(floor(visibleMinX / ppb)) - 2)
        let endBar = Int(ceil(visibleMaxX / ppb)) + 2
        let shadingColor = SIMD4<Float>(1, 1, 1, 0.05)

        for bar in startBar..<endBar where bar % 2 == 0 {
            let x = Float(bar) * ppb
            rects.append(PlaybackGridRectInstance(
                origin: SIMD2(x, gridTop),
                size: SIMD2(ppb, gridBottom - gridTop),
                color: shadingColor
            ))
        }

        let barLineColor = SIMD4<Float>(1, 1, 1, 0.24)
        for bar in startBar...endBar {
            let x = Float(bar) * ppb
            lines.append(PlaybackGridLineInstance(
                start: SIMD2(x, gridTop),
                end: SIMD2(x, gridBottom),
                color: barLineColor,
                width: 1
            ))
        }

        let pixelsPerBeat = ppb / Float(snapshot.timeSignature.beatsPerBar)
        if pixelsPerBeat >= 20 {
            let beatLineColor = SIMD4<Float>(1, 1, 1, 0.11)
            for bar in startBar...endBar {
                let barX = Float(bar) * ppb
                for beat in 1..<snapshot.timeSignature.beatsPerBar {
                    let beatX = barX + Float(beat) * pixelsPerBeat
                    lines.append(PlaybackGridLineInstance(
                        start: SIMD2(beatX, gridTop),
                        end: SIMD2(beatX, gridBottom),
                        color: beatLineColor,
                        width: 1
                    ))
                }
            }
        }

        let bgColor = SIMD4<Float>(0.56, 0.56, 0.58, 0.18)
        let sepColor = SIMD4<Float>(1, 1, 1, 0.22)
        for layout in scene.trackLayouts {
            let y = Float(layout.yOrigin)
            let h = Float(layout.height)
            rects.append(PlaybackGridRectInstance(
                origin: SIMD2(visibleMinX, y),
                size: SIMD2(visibleMaxX - visibleMinX, h),
                color: bgColor
            ))

            let sepY = y + h
            lines.append(PlaybackGridLineInstance(
                start: SIMD2(visibleMinX, sepY),
                end: SIMD2(visibleMaxX, sepY),
                color: sepColor,
                width: 1
            ))
        }

        for section in scene.sectionLayouts {
            guard snapshot.showRulerAndSections else { break }
            guard Float(section.rect.maxX) >= visibleMinX && Float(section.rect.minX) <= visibleMaxX else { continue }

            let color: SIMD4<Float> = section.isSelected
                ? SIMD4(0.25, 0.55, 1.0, 0.35)
                : SIMD4(1, 1, 1, 0.05)
            rects.append(PlaybackGridRectInstance(
                origin: SIMD2(Float(section.rect.minX), visibleMinY + rulerHeight + 1),
                size: SIMD2(Float(section.rect.width), max(1, sectionLaneHeight - 2)),
                color: color,
                cornerRadius: 4
            ))
        }

        for trackLayout in scene.trackLayouts {
            let trackColors = PlaybackGridTrackMetalColors(kind: trackLayout.track.kind)

            for cl in trackLayout.containers {
                let rect = cl.rect
                guard Float(rect.maxX) >= visibleMinX && Float(rect.minX) <= visibleMaxX else { continue }

                let isArmed = cl.container.isRecordArmed
                let fillColor: SIMD4<Float> = isArmed ? trackColors.fillArmed
                    : cl.isSelected ? trackColors.fillSelected : trackColors.fillNormal

                let origin = SIMD2<Float>(Float(rect.minX), Float(rect.minY))
                let size = SIMD2<Float>(Float(rect.width), Float(rect.height))

                let fillOrigin = SIMD2<Float>(origin.x, origin.y + 1)
                let fillSize = SIMD2<Float>(size.x, max(size.y - 2, 1))
                rects.append(PlaybackGridRectInstance(origin: fillOrigin, size: fillSize, color: fillColor))

                let borderColor: SIMD4<Float> = isArmed ? trackColors.borderArmed
                    : cl.isSelected ? trackColors.borderSelected : trackColors.borderNormal
                borders.append(PlaybackGridRectInstance(
                    origin: fillOrigin,
                    size: fillSize,
                    color: borderColor,
                    cornerRadius: 4
                ))

                if cl.isSelected {
                    borders.append(PlaybackGridRectInstance(
                        origin: SIMD2(fillOrigin.x - 1, fillOrigin.y - 1),
                        size: SIMD2(fillSize.x + 2, fillSize.y + 2),
                        color: trackColors.selectionHighlight,
                        cornerRadius: 5
                    ))
                }

                if let peaks = cl.waveformPeaks, !peaks.isEmpty {
                    let containerWidthPx = fillSize.x
                    if containerWidthPx >= 4 {
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
                        wfParams.append(PlaybackGridWaveformParams(
                            containerOrigin: fillOrigin,
                            containerSize: SIMD2(waveformWidth, fillSize.y),
                            fillColor: trackColors.waveformFill,
                            peakOffset: offset,
                            peakCount: UInt32(uploadPeaks.count),
                            amplitude: 0.9
                        ))
                    }
                }

                if let notes = cl.resolvedMIDINotes, !notes.isEmpty {
                    buildMIDIDiamonds(
                        notes: notes,
                        container: cl.container,
                        rect: rect,
                        color: trackColors.waveformFill,
                        timeSignature: snapshot.timeSignature,
                        into: &midiNotes
                    )
                }

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

                if !cl.container.automationLanes.isEmpty {
                    buildAutomationOverlay(
                        lanes: cl.container.automationLanes,
                        container: cl.container,
                        rect: rect,
                        focusedPick: focusedPick,
                        lines: &lines,
                        rects: &rects
                    )
                }
            }

            for xfade in trackLayout.track.crossfades {
                buildCrossfade(
                    xfade,
                    track: trackLayout.track,
                    trackLayout: trackLayout,
                    pixelsPerBar: ppb,
                    visibleMinX: visibleMinX,
                    visibleMaxX: visibleMaxX,
                    rects: &rects,
                    lines: &lines
                )
            }
        }

        if let range = snapshot.selectedRange {
            let startX = Float(range.lowerBound) * ppb
            let endX = Float(range.upperBound + 1) * ppb
            let totalHeight = scene.trackLayouts.last.map { Float($0.yOrigin + $0.height) } ?? canvasHeight
            let accentColor = SIMD4<Float>(0.25, 0.55, 1.0, 0.15)
            rects.append(PlaybackGridRectInstance(
                origin: SIMD2(startX, 0),
                size: SIMD2(endX - startX, totalHeight),
                color: accentColor
            ))

            let edgeColor = SIMD4<Float>(0.25, 0.55, 1.0, 0.5)
            lines.append(PlaybackGridLineInstance(
                start: SIMD2(startX, 0),
                end: SIMD2(startX, totalHeight),
                color: edgeColor,
                width: 1
            ))
            lines.append(PlaybackGridLineInstance(
                start: SIMD2(endX, 0),
                end: SIMD2(endX, totalHeight),
                color: edgeColor,
                width: 1
            ))
        }

        if snapshot.showRulerAndSections {
            let rulerBg = SIMD4<Float>(0.13, 0.14, 0.16, 0.95)
            rects.append(PlaybackGridRectInstance(
                origin: SIMD2(visibleMinX, visibleMinY),
                size: SIMD2(visibleMaxX - visibleMinX, rulerHeight),
                color: rulerBg
            ))
            let sectionBg = SIMD4<Float>(0.15, 0.16, 0.18, 0.95)
            rects.append(PlaybackGridRectInstance(
                origin: SIMD2(visibleMinX, visibleMinY + rulerHeight),
                size: SIMD2(visibleMaxX - visibleMinX, sectionLaneHeight),
                color: sectionBg
            ))

            lines.append(PlaybackGridLineInstance(
                start: SIMD2(visibleMinX, visibleMinY + rulerHeight),
                end: SIMD2(visibleMaxX, visibleMinY + rulerHeight),
                color: SIMD4(1, 1, 1, 0.24),
                width: 1
            ))
            lines.append(PlaybackGridLineInstance(
                start: SIMD2(visibleMinX, visibleMinY + trackAreaTop),
                end: SIMD2(visibleMaxX, visibleMinY + trackAreaTop),
                color: SIMD4(1, 1, 1, 0.24),
                width: 1
            ))

            if let range = snapshot.selectedRange {
                let rangeStartX = Float(range.lowerBound - 1) * ppb
                let rangeWidth = Float(range.count) * ppb
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(rangeStartX, visibleMinY),
                    size: SIMD2(rangeWidth, rulerHeight),
                    color: SIMD4(0.25, 0.55, 1.0, 0.25)
                ))
            }
        }

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

        debugStats = PlaybackGridDebugStats(
            rectCount: rectCount,
            lineCount: lineCount,
            waveformCount: waveformParamsList.count,
            midiCount: midiCount,
            fadeVertexCount: fadeVertexCount,
            borderCount: borderCount
        )
    }

    public func encode(
        into encoder: MTLRenderCommandEncoder,
        visibleRect: CGRect,
        canvasHeight: CGFloat,
        viewportSize: MTLSize,
        pixelsPerBar: CGFloat
    ) {
        var uniforms = PlaybackGridUniforms(
            projectionMatrix: PlaybackGridUniforms.orthographic(
                left: Float(visibleRect.minX),
                right: Float(visibleRect.maxX),
                top: Float(visibleRect.minY),
                bottom: Float(visibleRect.maxY)
            ),
            pixelsPerBar: Float(pixelsPerBar),
            canvasHeight: Float(canvasHeight),
            viewportMinX: Float(visibleRect.minX),
            viewportMaxX: Float(visibleRect.maxX)
        )

        encoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: viewportSize.width, height: viewportSize.height))

        if rectCount > 0, let buf = rectBuffer {
            encoder.setRenderPipelineState(rectPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
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

        if lineCount > 0, let buf = lineBuffer {
            encoder.setRenderPipelineState(linePipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
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

        if !waveformParamsList.isEmpty, let peakBuf = peakBuffer {
            encoder.setRenderPipelineState(waveformPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(peakBuf, offset: 0, index: 2)

            for var params in waveformParamsList {
                encoder.setVertexBytes(&params, length: MemoryLayout<PlaybackGridWaveformParams>.stride, index: 1)
                let vertexCount = Int(params.peakCount) * 2
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCount)
            }
        }

        if midiCount > 0, let buf = midiBuffer {
            encoder.setRenderPipelineState(midiPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: midiCount
            )
        }

        if fadeVertexCount > 0, let buf = fadeVertexBuffer {
            encoder.setRenderPipelineState(fadePipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            for call in fadeDrawCalls {
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: call.offset, vertexCount: call.count)
            }
        }

        if borderCount > 0, let buf = borderBuffer {
            encoder.setRenderPipelineState(rectPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
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

        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].alphaBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try device.makeRenderPipelineState(descriptor: desc)
    }

    private func buildMIDIDiamonds(
        notes: [MIDINoteEvent],
        container: Container,
        rect: CGRect,
        color: SIMD4<Float>,
        timeSignature: TimeSignature,
        into output: inout [PlaybackGridMIDINoteInstance]
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

            output.append(PlaybackGridMIDINoteInstance(
                center: SIMD2(centerX, centerY),
                halfSize: halfSize,
                color: color
            ))
        }
    }

    private func buildFadeOverlay(
        enterFade: FadeSettings?,
        exitFade: FadeSettings?,
        rect: CGRect,
        pixelsPerBar: Float,
        into vertices: inout [PlaybackGridFadeVertex],
        calls: inout [(offset: Int, count: Int)]
    ) {
        let fadeColor = SIMD4<Float>(0, 0, 0, 0.25)

        if let fade = enterFade, fade.duration > 0 {
            let fadeWidth = Float(fade.duration) * pixelsPerBar
            let steps = max(Int(fadeWidth / 2), 20)
            let offset = vertices.count

            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let gain = fade.curve.gain(at: t)
                let x = Float(rect.minX) + Float(t) * fadeWidth
                let yBottom = Float(rect.minY)
                let yCurve = Float(rect.minY) + Float(gain) * Float(rect.height)

                vertices.append(PlaybackGridFadeVertex(position: SIMD2(x, yBottom), color: fadeColor))
                vertices.append(PlaybackGridFadeVertex(position: SIMD2(x, yCurve), color: SIMD4(0, 0, 0, 0)))
            }
            calls.append((offset: offset, count: (steps + 1) * 2))
        }

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

                vertices.append(PlaybackGridFadeVertex(position: SIMD2(x, yBottom), color: fadeColor))
                vertices.append(PlaybackGridFadeVertex(position: SIMD2(x, yCurve), color: SIMD4(0, 0, 0, 0)))
            }
            calls.append((offset: offset, count: (steps + 1) * 2))
        }
    }

    private func buildAutomationOverlay(
        lanes: [AutomationLane],
        container: Container,
        rect: CGRect,
        focusedPick: GridPickObject,
        lines: inout [PlaybackGridLineInstance],
        rects: inout [PlaybackGridRectInstance]
    ) {
        guard container.lengthBars > 0 else { return }

        let laneColors: [SIMD4<Float>] = [
            SIMD4(1.0, 0.55, 0.15, 0.9),
            SIMD4(0.33, 0.75, 1.0, 0.9),
            SIMD4(0.65, 0.95, 0.45, 0.9),
            SIMD4(0.95, 0.45, 0.85, 0.9)
        ]
        let handleBaseSize: Float = 7
        let focusedHandleScale: Float = 1.45
        let barsToPixels = rect.width / CGFloat(container.lengthBars)
        let isFocusedContainer = focusedPick.containerID == container.id
        let yMin = Float(rect.minY) + 2
        let yMax = Float(rect.maxY) - 2

        for (laneIndex, lane) in lanes.enumerated() {
            let color = laneColors[laneIndex % laneColors.count]
            let sorted = lane.breakpoints.sorted { $0.position < $1.position }
            guard !sorted.isEmpty else { continue }

            var points: [SIMD2<Float>] = []
            points.reserveCapacity(sorted.count)

            for bp in sorted {
                let x = Float(rect.minX + (CGFloat(bp.position) * barsToPixels))
                let y = Float(rect.maxY - (CGFloat(bp.value) * rect.height))
                let isFocused = isFocusedContainer
                    && focusedPick.kind == .automationBreakpoint
                    && focusedPick.automationLaneID == lane.id
                    && focusedPick.automationBreakpointID == bp.id

                let handleSize = isFocused ? handleBaseSize * focusedHandleScale : handleBaseSize
                let handleRadius = handleSize * 0.5
                let shadowSize = handleSize + (isFocused ? 7 : 4)
                let shadowRadius = shadowSize * 0.5
                let ringSize = handleSize + 4
                let ringRadius = ringSize * 0.5
                let highlightSize = max(2, handleSize * 0.34)
                let highlightRadius = highlightSize * 0.5

                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(x - shadowRadius, y - shadowRadius + 1.3),
                    size: SIMD2(shadowSize, shadowSize),
                    color: SIMD4(0, 0, 0, isFocused ? 0.30 : 0.16),
                    cornerRadius: shadowRadius
                ))
                if isFocused {
                    rects.append(PlaybackGridRectInstance(
                        origin: SIMD2(x - ringRadius, y - ringRadius),
                        size: SIMD2(ringSize, ringSize),
                        color: SIMD4(color.x, color.y, color.z, 0.52),
                        cornerRadius: ringRadius
                    ))
                    rects.append(PlaybackGridRectInstance(
                        origin: SIMD2(x - ringRadius + 1.6, y - ringRadius + 1.6),
                        size: SIMD2(max(ringSize - 3.2, 1), max(ringSize - 3.2, 1)),
                        color: SIMD4(0.10, 0.11, 0.13, 0.90),
                        cornerRadius: max(ringRadius - 1.6, 0)
                    ))
                }

                let handleColor: SIMD4<Float>
                if isFocused {
                    handleColor = SIMD4(
                        min(color.x * 0.62 + 0.38, 1.0),
                        min(color.y * 0.62 + 0.38, 1.0),
                        min(color.z * 0.62 + 0.38, 1.0),
                        1.0
                    )
                } else {
                    handleColor = color
                }

                points.append(SIMD2(x, y))
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(x - handleRadius, y - handleRadius),
                    size: SIMD2(handleSize, handleSize),
                    color: handleColor,
                    cornerRadius: handleRadius
                ))
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(x - handleRadius + 1, y - handleRadius + 1),
                    size: SIMD2(max(handleSize - 2, 1), max(handleSize - 2, 1)),
                    color: SIMD4(0, 0, 0, 0.18),
                    cornerRadius: max(handleRadius - 1, 0)
                ))
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(x - handleRadius * 0.45, y - handleRadius * 0.45),
                    size: SIMD2(highlightSize, highlightSize),
                    color: SIMD4(1, 1, 1, isFocused ? 0.80 : 0.48),
                    cornerRadius: highlightRadius
                ))
            }

            if points.count >= 2 {
                let smoothed = smoothedAutomationPoints(points: points, yMin: yMin, yMax: yMax)
                appendAutomationCurve(points: smoothed, color: color, lines: &lines)
            }
        }
    }

    private func appendAutomationCurve(
        points: [SIMD2<Float>],
        color: SIMD4<Float>,
        lines: inout [PlaybackGridLineInstance]
    ) {
        guard points.count >= 2 else { return }
        let shadowColor = SIMD4<Float>(0, 0, 0, 0.22)
        let glowColor = SIMD4<Float>(color.x, color.y, color.z, 0.24)
        let mainColor = SIMD4<Float>(color.x, color.y, color.z, min(color.w + 0.08, 1.0))

        for i in 0..<(points.count - 1) {
            let start = points[i]
            let end = points[i + 1]
            lines.append(PlaybackGridLineInstance(
                start: SIMD2(start.x, start.y + 1.2),
                end: SIMD2(end.x, end.y + 1.2),
                color: shadowColor,
                width: 3.0
            ))
            lines.append(PlaybackGridLineInstance(
                start: start,
                end: end,
                color: glowColor,
                width: 3.2
            ))
            lines.append(PlaybackGridLineInstance(
                start: start,
                end: end,
                color: mainColor,
                width: 1.8
            ))
        }
    }

    private func smoothedAutomationPoints(
        points: [SIMD2<Float>],
        yMin: Float,
        yMax: Float
    ) -> [SIMD2<Float>] {
        guard points.count >= 3 else { return points }
        var smoothed: [SIMD2<Float>] = [points[0]]
        smoothed.reserveCapacity(points.count * 10)

        for i in 0..<(points.count - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = (i + 2) < points.count ? points[i + 2] : points[i + 1]
            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let distance = sqrt((dx * dx) + (dy * dy))
            let samples = min(max(Int(distance / 18), 6), 28)

            for sample in 1...samples {
                let t = Float(sample) / Float(samples)
                var point = catmullRomPoint(p0: p0, p1: p1, p2: p2, p3: p3, t: t)
                point.x = min(max(point.x, p1.x), p2.x)
                point.y = min(max(point.y, yMin), yMax)
                smoothed.append(point)
            }
        }

        return smoothed
    }

    private func catmullRomPoint(
        p0: SIMD2<Float>,
        p1: SIMD2<Float>,
        p2: SIMD2<Float>,
        p3: SIMD2<Float>,
        t: Float
    ) -> SIMD2<Float> {
        let t2 = t * t
        let t3 = t2 * t
        let a = 2 * p1
        let b = -p0 + p2
        let c = (2 * p0) - (5 * p1) + (4 * p2) - p3
        let d = -p0 + (3 * p1) - (3 * p2) + p3
        return 0.5 * (a + (b * t) + (c * t2) + (d * t3))
    }

    private func buildCrossfade(
        _ xfade: Crossfade,
        track: Track,
        trackLayout: PlaybackGridTrackLayout,
        pixelsPerBar: Float,
        visibleMinX: Float,
        visibleMaxX: Float,
        rects: inout [PlaybackGridRectInstance],
        lines: inout [PlaybackGridLineInstance]
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

        rects.append(PlaybackGridRectInstance(
            origin: SIMD2(xStart, y),
            size: SIMD2(width, h),
            color: SIMD4(1, 1, 1, 0.08)
        ))

        let xColor = SIMD4<Float>(1, 1, 1, 0.7)
        lines.append(PlaybackGridLineInstance(
            start: SIMD2(xStart, y),
            end: SIMD2(xStart + width, y + h),
            color: xColor,
            width: 1.5
        ))
        lines.append(PlaybackGridLineInstance(
            start: SIMD2(xStart, y + h),
            end: SIMD2(xStart + width, y),
            color: xColor,
            width: 1.5
        ))
    }

    private func makeBuffer<T>(_ data: [T]) -> MTLBuffer? {
        guard !data.isEmpty else { return nil }
        return data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return nil }
            return device.makeBuffer(bytes: baseAddress, length: ptr.count, options: .storageModeShared)
        }
    }
}

private enum PlaybackGridMetalError: Error {
    case noCommandQueue
    case bufferAllocation
}

private struct PlaybackGridTrackMetalColors {
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
        fillNormal = SIMD4(base.x, base.y, base.z, 0.25)
        fillSelected = SIMD4(base.x, base.y, base.z, 0.42)
        fillArmed = SIMD4(1, 0.23, 0.19, 0.15)
        borderNormal = SIMD4(base.x, base.y, base.z, 0.45)
        borderSelected = SIMD4(0.25, 0.55, 1.0, 1.0)
        borderArmed = SIMD4(1, 0.23, 0.19, 1.0)
        let waveformRGB = (base * 0.38) + SIMD3<Float>(repeating: 1.0) * 0.62
        waveformFill = SIMD4(waveformRGB.x, waveformRGB.y, waveformRGB.z, 0.85)
        selectionHighlight = SIMD4(0.25, 0.55, 1.0, 0.3)
    }

    private static func baseColor(for kind: TrackKind) -> SIMD3<Float> {
        switch kind {
        case .audio: return SIMD3(0.0, 0.48, 1.0)
        case .midi: return SIMD3(0.69, 0.32, 0.87)
        case .bus: return SIMD3(0.20, 0.78, 0.35)
        case .backing: return SIMD3(1.0, 0.58, 0.0)
        case .master: return SIMD3(0.56, 0.56, 0.58)
        }
    }
}
