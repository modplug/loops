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
    private var midiOverlayBuffer: MTLBuffer?
    private var midiOverlayCount = 0
    private var automationOverlayLineBuffer: MTLBuffer?
    private var automationOverlayLineCount = 0
    private var automationOverlayRectBuffer: MTLBuffer?
    private var automationOverlayRectCount = 0
    private var automationShapeOverlayLineBuffer: MTLBuffer?
    private var automationShapeOverlayLineCount = 0
    private var automationShapeOverlayRectBuffer: MTLBuffer?
    private var automationShapeOverlayRectCount = 0

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
        focusedPick: GridPickObject = .none,
        suppressedAutomationLanes: Set<PlaybackGridAutomationSuppression> = []
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
        var midiLayoutsByTrack: [ID<Track>: PlaybackGridMIDIResolvedLayout] = [:]

        for layout in scene.trackLayouts where layout.track.kind == .midi {
            let inlineMIDILaneHeight = snapshot.inlineMIDILaneHeights[layout.track.id] ?? 0
            let laneHeight = inlineMIDILaneHeight > 0
                ? inlineMIDILaneHeight
                : (snapshot.trackHeights[layout.track.id] ?? snapshot.defaultTrackHeight)
            midiLayoutsByTrack[layout.track.id] = PlaybackGridMIDIViewResolver.resolveTrackLayout(
                trackLayout: layout,
                laneHeight: laneHeight,
                snapshot: snapshot
            )
        }

        let gridBottom = max(canvasHeight, visibleMaxY)
        let startBar = max(0, Int(floor(visibleMinX / ppb)) - 2)
        let endBar = Int(ceil(visibleMaxX / ppb)) + 2
        let shadingColor = SIMD4<Float>(0.56, 0.64, 0.76, 0.010)

        for bar in startBar..<endBar where bar % 2 == 0 {
            let x = Float(bar) * ppb
            rects.append(PlaybackGridRectInstance(
                origin: SIMD2(x, gridTop),
                size: SIMD2(ppb, gridBottom - gridTop),
                color: shadingColor
            ))
        }

        let barLineColor = SIMD4<Float>(0.78, 0.84, 0.95, 0.060)
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
            let beatLineColor = SIMD4<Float>(0.72, 0.79, 0.90, 0.020)
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

        let bgColor = SIMD4<Float>(0.16, 0.18, 0.22, 0.13)
        let sepColor = SIMD4<Float>(0.76, 0.82, 0.91, 0.10)
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

            if layout.automationToolbarHeight > 0 {
                let toolbarY = Float(layout.yOrigin + layout.clipHeight)
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(visibleMinX, toolbarY),
                    size: SIMD2(visibleMaxX - visibleMinX, Float(layout.automationToolbarHeight)),
                    color: SIMD4(0.14, 0.16, 0.19, 0.42)
                ))
                lines.append(PlaybackGridLineInstance(
                    start: SIMD2(visibleMinX, toolbarY + Float(layout.automationToolbarHeight)),
                    end: SIMD2(visibleMaxX, toolbarY + Float(layout.automationToolbarHeight)),
                    color: SIMD4(0.74, 0.80, 0.90, 0.10),
                    width: 1
                ))
            }

            if !layout.automationLaneLayouts.isEmpty {
                for (laneIndex, laneLayout) in layout.automationLaneLayouts.enumerated() {
                    let laneMinY = Float(laneLayout.rect.minY)
                    let laneHeight = Float(laneLayout.rect.height)
                    let laneTint = automationLaneColor(at: laneIndex)
                    rects.append(PlaybackGridRectInstance(
                        origin: SIMD2(visibleMinX, laneMinY),
                        size: SIMD2(visibleMaxX - visibleMinX, laneHeight),
                        color: SIMD4(laneTint.x, laneTint.y, laneTint.z, 0.055)
                    ))
                    for frac: Float in [0.25, 0.5, 0.75] {
                        let yGuide = laneMinY + ((1.0 - frac) * laneHeight)
                        lines.append(PlaybackGridLineInstance(
                            start: SIMD2(visibleMinX, yGuide),
                            end: SIMD2(visibleMaxX, yGuide),
                            color: SIMD4(0.76, 0.82, 0.91, 0.08),
                            width: 1
                        ))
                    }
                }
            }

            let inlineMIDILaneHeight = snapshot.inlineMIDILaneHeights[layout.track.id] ?? 0
            if layout.track.kind == .midi, inlineMIDILaneHeight > 0 {
                let laneMinY = Float(inlineMIDILaneYOrigin(
                    trackLayout: layout,
                    snapshot: snapshot
                ))
                let laneHeight = Float(inlineMIDILaneHeight)
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(visibleMinX, laneMinY),
                    size: SIMD2(visibleMaxX - visibleMinX, laneHeight),
                    color: SIMD4(0.10, 0.11, 0.14, 0.08)
                ))
                buildMIDIPitchGrid(
                    trackID: layout.track.id,
                    resolved: midiLayoutsByTrack[layout.track.id],
                    yMin: laneMinY,
                    laneHeight: laneHeight,
                    xMin: visibleMinX,
                    xMax: visibleMaxX,
                    pixelsPerBar: ppb,
                    snapshot: snapshot,
                    rects: &rects,
                    lines: &lines
                )
            }
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
                let isFocusedContainer = focusedPick.kind == .containerZone && focusedPick.containerID == cl.container.id
                let fillColor: SIMD4<Float> = isArmed ? trackColors.fillArmed
                    : cl.isSelected ? trackColors.fillSelected
                    : isFocusedContainer ? trackColors.fillFocused : trackColors.fillNormal

                let origin = SIMD2<Float>(Float(rect.minX), Float(rect.minY))
                let size = SIMD2<Float>(Float(rect.width), Float(rect.height))

                let fillOrigin = SIMD2<Float>(origin.x, origin.y + 1)
                let fillSize = SIMD2<Float>(size.x, max(size.y - 2, 1))
                rects.append(PlaybackGridRectInstance(origin: fillOrigin, size: fillSize, color: fillColor))

                let borderColor: SIMD4<Float> = isArmed ? trackColors.borderArmed
                    : cl.isSelected ? trackColors.borderSelected
                    : isFocusedContainer ? trackColors.borderFocused : trackColors.borderNormal
                borders.append(PlaybackGridRectInstance(
                    origin: fillOrigin,
                    size: fillSize,
                    color: borderColor,
                    cornerRadius: 4
                ))

                if cl.isSelected {
                    let shadowExtent: Float = 26
                    let shadowY = max(fillOrigin.y - 1, 0)
                    let shadowH = fillSize.y + 2
                    rects.append(PlaybackGridRectInstance(
                        origin: SIMD2(max(fillOrigin.x - shadowExtent, visibleMinX), shadowY),
                        size: SIMD2(max(0, min(shadowExtent, fillOrigin.x - visibleMinX)), shadowH),
                        color: SIMD4(0.10, 0.16, 0.26, 0.16)
                    ))
                    rects.append(PlaybackGridRectInstance(
                        origin: SIMD2(fillOrigin.x + fillSize.x, shadowY),
                        size: SIMD2(max(0, min(shadowExtent, visibleMaxX - (fillOrigin.x + fillSize.x))), shadowH),
                        color: SIMD4(0.10, 0.16, 0.26, 0.16)
                    ))
                    borders.append(PlaybackGridRectInstance(
                        origin: SIMD2(fillOrigin.x - 1, fillOrigin.y - 1),
                        size: SIMD2(fillSize.x + 2, fillSize.y + 2),
                        color: trackColors.selectionHighlight,
                        cornerRadius: 5
                    ))
                } else if isFocusedContainer {
                    borders.append(PlaybackGridRectInstance(
                        origin: SIMD2(fillOrigin.x - 1.2, fillOrigin.y - 1.2),
                        size: SIMD2(fillSize.x + 2.4, fillSize.y + 2.4),
                        color: trackColors.focusGlow,
                        cornerRadius: 6
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
                            fillColor: isFocusedContainer ? trackColors.waveformFocused : trackColors.waveformFill,
                            peakOffset: offset,
                            peakCount: UInt32(uploadPeaks.count),
                            amplitude: isFocusedContainer ? 0.98 : 0.92
                        ))
                    }
                }

                if let notes = cl.resolvedMIDINotes, !notes.isEmpty {
                    let midiRect = midiEditorRect(
                        trackLayout: trackLayout,
                        containerRect: rect,
                        trackID: trackLayout.track.id,
                        snapshot: snapshot
                    )
                    let resolved = midiLayoutsByTrack[trackLayout.track.id]
                        ?? PlaybackGridMIDIViewResolver.resolveTrackLayout(
                            track: trackLayout.track,
                            laneHeight: midiRect.height,
                            snapshot: snapshot
                        )
                    buildMIDINotes(
                        notes: notes,
                        container: cl.container,
                        rect: midiRect,
                        resolved: resolved,
                        color: trackColors.waveformFill,
                        focusedPick: focusedPick,
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

                if trackLayout.automationLaneLayouts.isEmpty, !cl.container.automationLanes.isEmpty {
                    buildAutomationOverlay(
                        lanes: cl.container.automationLanes,
                        container: cl.container,
                        trackID: trackLayout.track.id,
                        rect: rect,
                        focusedPick: focusedPick,
                        selectedAutomationTool: snapshot.selectedAutomationTool,
                        suppressedAutomationLanes: suppressedAutomationLanes,
                        lines: &lines,
                        rects: &rects
                    )
                }
            }

            if !trackLayout.automationLaneLayouts.isEmpty {
                buildExpandedAutomationOverlays(
                    trackLayout: trackLayout,
                    snapshot: snapshot,
                    visibleMinX: visibleMinX,
                    visibleMaxX: visibleMaxX,
                    focusedPick: focusedPick,
                    suppressedAutomationLanes: suppressedAutomationLanes,
                    lines: &lines,
                    rects: &rects
                )
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
            midiCount: midiCount + midiOverlayCount,
            fadeVertexCount: fadeVertexCount,
            borderCount: borderCount
        )
    }

    public func buildMIDIOverlayBuffer(
        scene: PlaybackGridScene,
        snapshot: PlaybackGridSnapshot,
        midiOverlays: [PlaybackGridMIDINoteOverlay]
    ) {
        guard !midiOverlays.isEmpty else {
            midiOverlayBuffer = nil
            midiOverlayCount = 0
            return
        }

        var byTrack: [ID<Track>: PlaybackGridTrackLayout] = [:]
        var byContainer: [ID<Container>: PlaybackGridContainerLayout] = [:]
        for trackLayout in scene.trackLayouts {
            byTrack[trackLayout.track.id] = trackLayout
            for containerLayout in trackLayout.containers {
                byContainer[containerLayout.container.id] = containerLayout
            }
        }

        var output: [PlaybackGridMIDINoteInstance] = []
        output.reserveCapacity(midiOverlays.count * 4)

        for overlay in midiOverlays {
            guard let trackLayout = byTrack[overlay.trackID],
                  let containerLayout = byContainer[overlay.containerID] else {
                continue
            }
            let midiRect = midiEditorRect(
                trackLayout: trackLayout,
                containerRect: containerLayout.rect,
                trackID: trackLayout.track.id,
                snapshot: snapshot
            )
            let resolved = PlaybackGridMIDIViewResolver.resolveTrackLayout(
                trackLayout: trackLayout,
                laneHeight: midiRect.height,
                snapshot: snapshot
            )
            buildMIDINoteOverlays(
                overlays: [overlay],
                containerID: overlay.containerID,
                trackID: overlay.trackID,
                containerLengthBars: containerLayout.container.lengthBars,
                rect: midiRect,
                resolved: resolved,
                timeSignature: snapshot.timeSignature,
                into: &output
            )
        }

        midiOverlayBuffer = output.isEmpty ? nil : makeBuffer(output)
        midiOverlayCount = output.count
    }

    public func buildAutomationOverlayBuffer(
        scene: PlaybackGridScene,
        snapshot: PlaybackGridSnapshot,
        overlays: [PlaybackGridAutomationBreakpointOverlay]
    ) {
        guard !overlays.isEmpty else {
            automationOverlayLineBuffer = nil
            automationOverlayLineCount = 0
            automationOverlayRectBuffer = nil
            automationOverlayRectCount = 0
            return
        }

        var trackLayoutsByID: [ID<Track>: PlaybackGridTrackLayout] = [:]
        var containerLayoutsByID: [ID<Container>: PlaybackGridContainerLayout] = [:]
        for trackLayout in scene.trackLayouts {
            trackLayoutsByID[trackLayout.track.id] = trackLayout
            for containerLayout in trackLayout.containers {
                containerLayoutsByID[containerLayout.container.id] = containerLayout
            }
        }

        var lines: [PlaybackGridLineInstance] = []
        var rects: [PlaybackGridRectInstance] = []
        lines.reserveCapacity(overlays.count * 12)
        rects.reserveCapacity(overlays.count * 6)
        let ppb = Float(snapshot.pixelsPerBar)

        for overlay in overlays {
            guard overlay.laneRect.width > 0.5, overlay.laneRect.height > 0.5 else { continue }

            let laneColor: SIMD4<Float>
            if let containerID = overlay.containerID,
               let containerLayout = containerLayoutsByID[containerID],
               let laneIndex = containerLayout.container.automationLanes.firstIndex(where: { $0.id == overlay.laneID }) {
                laneColor = automationLaneColor(at: laneIndex)
            } else if let trackLayout = trackLayoutsByID[overlay.trackID],
                      let laneIndex = trackLayout.track.trackAutomationLanes.firstIndex(where: { $0.id == overlay.laneID }) {
                laneColor = automationLaneColor(at: laneIndex)
            } else {
                laneColor = SIMD4(1.0, 0.30, 0.34, 0.92)
            }

            let point: SIMD2<Float>?
            var curvePoints: [SIMD2<Float>] = []
            if let containerID = overlay.containerID {
                guard let containerLayout = containerLayoutsByID[containerID],
                      let lane = containerLayout.container.automationLanes.first(where: { $0.id == overlay.laneID }) else {
                    continue
                }
                let barsToPixels = containerLayout.rect.width / max(CGFloat(containerLayout.container.lengthBars), 0.0001)
                var breakpoints = lane.breakpoints
                if let index = breakpoints.firstIndex(where: { $0.id == overlay.breakpoint.id }) {
                    breakpoints[index] = overlay.breakpoint
                } else {
                    breakpoints.append(overlay.breakpoint)
                }
                breakpoints.sort { $0.position < $1.position }
                curvePoints.reserveCapacity(breakpoints.count)
                for bp in breakpoints {
                    let x = Float(containerLayout.rect.minX + (CGFloat(bp.position) * barsToPixels))
                    let y = Float(overlay.laneRect.maxY - (CGFloat(bp.value) * overlay.laneRect.height))
                    curvePoints.append(SIMD2(x, y))
                }
                let x = Float(containerLayout.rect.minX + (CGFloat(overlay.breakpoint.position) * barsToPixels))
                let y = Float(overlay.laneRect.maxY - (CGFloat(overlay.breakpoint.value) * overlay.laneRect.height))
                point = SIMD2(x, y)
            } else {
                guard let trackLayout = trackLayoutsByID[overlay.trackID],
                      let lane = trackLayout.track.trackAutomationLanes.first(where: { $0.id == overlay.laneID }) else {
                    continue
                }
                var breakpoints = lane.breakpoints
                if let index = breakpoints.firstIndex(where: { $0.id == overlay.breakpoint.id }) {
                    breakpoints[index] = overlay.breakpoint
                } else {
                    breakpoints.append(overlay.breakpoint)
                }
                breakpoints.sort { $0.position < $1.position }
                curvePoints.reserveCapacity(breakpoints.count)
                for bp in breakpoints {
                    let x = Float(bp.position) * ppb
                    let y = Float(overlay.laneRect.maxY - (CGFloat(bp.value) * overlay.laneRect.height))
                    curvePoints.append(SIMD2(x, y))
                }
                let x = Float(overlay.breakpoint.position) * ppb
                let y = Float(overlay.laneRect.maxY - (CGFloat(overlay.breakpoint.value) * overlay.laneRect.height))
                point = SIMD2(x, y)
            }

            guard let handlePoint = point else { continue }

            if curvePoints.count >= 2 {
                let alpha: Float = overlay.isGhost ? 0.28 : min(laneColor.w + 0.06, 1.0)
                appendAutomationCurve(
                    points: curvePoints,
                    color: SIMD4(laneColor.x, laneColor.y, laneColor.z, alpha),
                    lines: &lines
                )
            }

            let size: Float = overlay.isGhost ? 7.0 : 8.8
            let radius = size * 0.5
            if overlay.isGhost {
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(handlePoint.x - radius, handlePoint.y - radius),
                    size: SIMD2(size, size),
                    color: SIMD4(laneColor.x, laneColor.y, laneColor.z, 0.35),
                    cornerRadius: radius
                ))
            } else {
                let glowSize = size + 4.4
                let glowRadius = glowSize * 0.5
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(handlePoint.x - glowRadius, handlePoint.y - glowRadius),
                    size: SIMD2(glowSize, glowSize),
                    color: SIMD4(laneColor.x, laneColor.y, laneColor.z, 0.42),
                    cornerRadius: glowRadius
                ))
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(handlePoint.x - radius, handlePoint.y - radius),
                    size: SIMD2(size, size),
                    color: SIMD4(min(laneColor.x * 0.65 + 0.35, 1.0), min(laneColor.y * 0.65 + 0.35, 1.0), min(laneColor.z * 0.65 + 0.35, 1.0), 0.98),
                    cornerRadius: radius
                ))
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(handlePoint.x - radius + 1.2, handlePoint.y - radius + 1.2),
                    size: SIMD2(max(size - 2.4, 1), max(size - 2.4, 1)),
                    color: SIMD4(0.08, 0.10, 0.13, 0.26),
                    cornerRadius: max(radius - 1.2, 0)
                ))
            }
        }

        automationOverlayLineBuffer = lines.isEmpty ? nil : makeBuffer(lines)
        automationOverlayLineCount = lines.count
        automationOverlayRectBuffer = rects.isEmpty ? nil : makeBuffer(rects)
        automationOverlayRectCount = rects.count
    }

    public func buildAutomationShapeOverlayBuffer(
        scene: PlaybackGridScene,
        snapshot: PlaybackGridSnapshot,
        overlays: [PlaybackGridAutomationShapeOverlay]
    ) {
        guard !overlays.isEmpty else {
            automationShapeOverlayLineBuffer = nil
            automationShapeOverlayLineCount = 0
            automationShapeOverlayRectBuffer = nil
            automationShapeOverlayRectCount = 0
            return
        }

        var trackLayoutsByID: [ID<Track>: PlaybackGridTrackLayout] = [:]
        var containerLayoutsByID: [ID<Container>: PlaybackGridContainerLayout] = [:]
        for trackLayout in scene.trackLayouts {
            trackLayoutsByID[trackLayout.track.id] = trackLayout
            for containerLayout in trackLayout.containers {
                containerLayoutsByID[containerLayout.container.id] = containerLayout
            }
        }

        var lines: [PlaybackGridLineInstance] = []
        var rects: [PlaybackGridRectInstance] = []
        lines.reserveCapacity(overlays.count * 16)
        rects.reserveCapacity(overlays.count * 8)
        let ppb = Float(snapshot.pixelsPerBar)

        for overlay in overlays {
            guard overlay.laneRect.width > 0.5, overlay.laneRect.height > 0.5 else { continue }
            guard !overlay.breakpoints.isEmpty else { continue }

            let laneColor: SIMD4<Float>
            if let containerID = overlay.containerID,
               let containerLayout = containerLayoutsByID[containerID],
               let laneIndex = containerLayout.container.automationLanes.firstIndex(where: { $0.id == overlay.laneID }) {
                laneColor = automationLaneColor(at: laneIndex)
            } else if let trackLayout = trackLayoutsByID[overlay.trackID],
                      let laneIndex = trackLayout.track.trackAutomationLanes.firstIndex(where: { $0.id == overlay.laneID }) {
                laneColor = automationLaneColor(at: laneIndex)
            } else {
                laneColor = SIMD4(1.0, 0.30, 0.34, 0.92)
            }

            let sorted = overlay.breakpoints.sorted { $0.position < $1.position }
            var points: [SIMD2<Float>] = []
            points.reserveCapacity(sorted.count)
            if let containerID = overlay.containerID,
               let containerLayout = containerLayoutsByID[containerID] {
                let barsToPixels = containerLayout.rect.width / max(CGFloat(containerLayout.container.lengthBars), 0.0001)
                for bp in sorted {
                    let x = Float(containerLayout.rect.minX + (CGFloat(bp.position) * barsToPixels))
                    let y = Float(overlay.laneRect.maxY - (CGFloat(bp.value) * overlay.laneRect.height))
                    points.append(SIMD2(x, y))
                }
            } else {
                for bp in sorted {
                    let x = Float(bp.position) * ppb
                    let y = Float(overlay.laneRect.maxY - (CGFloat(bp.value) * overlay.laneRect.height))
                    points.append(SIMD2(x, y))
                }
            }

            let alpha: Float = overlay.isGhost ? 0.30 : 1.0
            appendAutomationCurve(
                points: points,
                color: SIMD4(laneColor.x, laneColor.y, laneColor.z, laneColor.w * alpha),
                lines: &lines
            )

            if let last = points.last {
                let size: Float = overlay.isGhost ? 7.0 : 8.6
                let radius = size * 0.5
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(last.x - radius, last.y - radius),
                    size: SIMD2(size, size),
                    color: SIMD4(laneColor.x, laneColor.y, laneColor.z, overlay.isGhost ? 0.32 : 0.96),
                    cornerRadius: radius
                ))
            }
        }

        automationShapeOverlayLineBuffer = lines.isEmpty ? nil : makeBuffer(lines)
        automationShapeOverlayLineCount = lines.count
        automationShapeOverlayRectBuffer = rects.isEmpty ? nil : makeBuffer(rects)
        automationShapeOverlayRectCount = rects.count
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

        if midiOverlayCount > 0, let buf = midiOverlayBuffer {
            encoder.setRenderPipelineState(midiPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: midiOverlayCount
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

        if automationOverlayLineCount > 0, let buf = automationOverlayLineBuffer {
            encoder.setRenderPipelineState(linePipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: automationOverlayLineCount
            )
        }

        if automationOverlayRectCount > 0, let buf = automationOverlayRectBuffer {
            encoder.setRenderPipelineState(rectPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: automationOverlayRectCount
            )
        }

        if automationShapeOverlayLineCount > 0, let buf = automationShapeOverlayLineBuffer {
            encoder.setRenderPipelineState(linePipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: automationShapeOverlayLineCount
            )
        }

        if automationShapeOverlayRectCount > 0, let buf = automationShapeOverlayRectBuffer {
            encoder.setRenderPipelineState(rectPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: automationShapeOverlayRectCount
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

    private func buildMIDINotes(
        notes: [MIDINoteEvent],
        container: Container,
        rect: CGRect,
        resolved: PlaybackGridMIDIResolvedLayout,
        color: SIMD4<Float>,
        focusedPick: GridPickObject,
        timeSignature: TimeSignature,
        into output: inout [PlaybackGridMIDINoteInstance]
    ) {
        let focusedNoteID: ID<MIDINoteEvent>? =
            focusedPick.kind == .midiNote && focusedPick.containerID == container.id
            ? focusedPick.midiNoteID
            : nil
        let noteBaseColor = SIMD4<Float>(0.84, 0.36, 0.67, 0.98)
        let noteFocusedColor = SIMD4<Float>(0.96, 0.58, 0.83, 1.0)
        let noteBorderColor = SIMD4<Float>(0.22, 0.08, 0.22, 0.88)

        for note in notes {
            guard let noteRect = PlaybackGridMIDIViewResolver.noteRect(
                note: note,
                containerLengthBars: container.lengthBars,
                laneRect: rect,
                timeSignature: timeSignature,
                resolved: resolved
            ) else { continue }
            let noteX = Float(noteRect.minX)
            let noteY = Float(noteRect.minY)
            let noteW = Float(noteRect.width)
            let noteH = Float(noteRect.height)
            let isFocused = focusedNoteID == note.id

            let bodyColor = isFocused
                ? noteFocusedColor
                : SIMD4(
                    (noteBaseColor.x * 0.8) + (color.x * 0.2),
                    (noteBaseColor.y * 0.8) + (color.y * 0.2),
                    (noteBaseColor.z * 0.8) + (color.z * 0.2),
                    noteBaseColor.w
                )

            let shadowOffset: Float = isFocused ? 1.6 : 1.0
            // Keep notes mostly rectangular (Bitwig-style) and avoid diamond/pill
            // silhouettes for short notes.
            let outerRadius = max(0.8, min(noteH * 0.12, noteW * 0.06))
            let innerRadius = max(0.7, min(outerRadius, noteH * 0.10))
            let shineRadius = max(0.6, min(innerRadius, noteH * 0.08))
            output.append(PlaybackGridMIDINoteInstance(
                origin: SIMD2(noteX, noteY + shadowOffset),
                size: SIMD2(noteW, noteH),
                color: SIMD4(0, 0, 0, isFocused ? 0.24 : 0.15),
                cornerRadius: outerRadius
            ))
            output.append(PlaybackGridMIDINoteInstance(
                origin: SIMD2(noteX, noteY),
                size: SIMD2(noteW, noteH),
                color: noteBorderColor,
                cornerRadius: outerRadius
            ))
            output.append(PlaybackGridMIDINoteInstance(
                origin: SIMD2(noteX + 1, noteY + 1),
                size: SIMD2(max(noteW - 2, 3), max(noteH - 2, 2)),
                color: bodyColor,
                cornerRadius: innerRadius
            ))
            output.append(PlaybackGridMIDINoteInstance(
                origin: SIMD2(noteX + 1.5, noteY + 1.5),
                size: SIMD2(max(noteW - 3, 2), max(min(noteH * 0.24, noteH - 2), 1)),
                color: SIMD4(1.0, 0.89, 0.96, isFocused ? 0.46 : 0.25),
                cornerRadius: shineRadius
            ))

            if isFocused, noteW >= 14 {
                let gripHeight = max(2, noteH - 5)
                let gripY = noteY + ((noteH - gripHeight) * 0.5)
                output.append(PlaybackGridMIDINoteInstance(
                    origin: SIMD2(noteX + 2, gripY),
                    size: SIMD2(1.6, gripHeight),
                    color: SIMD4(1, 1, 1, 0.58),
                    cornerRadius: 0.8
                ))
                output.append(PlaybackGridMIDINoteInstance(
                    origin: SIMD2(noteX + noteW - 3.6, gripY),
                    size: SIMD2(1.6, gripHeight),
                    color: SIMD4(1, 1, 1, 0.58),
                    cornerRadius: 0.8
                ))
            }
        }
    }

    private func buildMIDINoteOverlays(
        overlays: [PlaybackGridMIDINoteOverlay],
        containerID: ID<Container>,
        trackID: ID<Track>,
        containerLengthBars: Double,
        rect: CGRect,
        resolved: PlaybackGridMIDIResolvedLayout,
        timeSignature: TimeSignature,
        into output: inout [PlaybackGridMIDINoteInstance]
    ) {
        for overlay in overlays where overlay.containerID == containerID && overlay.trackID == trackID {
            guard let noteRect = PlaybackGridMIDIViewResolver.noteRect(
                note: overlay.note,
                containerLengthBars: containerLengthBars,
                laneRect: rect,
                timeSignature: timeSignature,
                resolved: resolved
            ) else { continue }

            let x = Float(noteRect.minX)
            let y = Float(noteRect.minY)
            let w = Float(noteRect.width)
            let h = Float(noteRect.height)
            let radius = max(0.8, min(h * 0.12, w * 0.06))

            if overlay.isGhost {
                output.append(PlaybackGridMIDINoteInstance(
                    origin: SIMD2(x + 0.6, y + 1.3),
                    size: SIMD2(max(w - 1.2, 2), max(h - 1.3, 2)),
                    color: SIMD4(0.05, 0.07, 0.10, 0.20),
                    cornerRadius: radius
                ))
                output.append(PlaybackGridMIDINoteInstance(
                    origin: SIMD2(x, y),
                    size: SIMD2(w, h),
                    color: SIMD4(0.97, 0.72, 0.90, 0.30),
                    cornerRadius: radius
                ))
                output.append(PlaybackGridMIDINoteInstance(
                    origin: SIMD2(x + 1, y + 1),
                    size: SIMD2(max(w - 2, 1), max(h - 2, 1)),
                    color: SIMD4(0.96, 0.62, 0.85, 0.12),
                    cornerRadius: max(radius - 0.8, 0)
                ))
            } else {
                output.append(PlaybackGridMIDINoteInstance(
                    origin: SIMD2(x + 0.8, y + 1.4),
                    size: SIMD2(max(w - 1.6, 2), max(h - 1.6, 2)),
                    color: SIMD4(0.00, 0.00, 0.00, 0.22),
                    cornerRadius: radius
                ))
                output.append(PlaybackGridMIDINoteInstance(
                    origin: SIMD2(x, y),
                    size: SIMD2(w, h),
                    color: SIMD4(0.99, 0.70, 0.90, 0.85),
                    cornerRadius: radius
                ))
                output.append(PlaybackGridMIDINoteInstance(
                    origin: SIMD2(x + 1, y + 1),
                    size: SIMD2(max(w - 2, 1), max(h - 2, 1)),
                    color: SIMD4(0.96, 0.50, 0.80, 0.92),
                    cornerRadius: max(radius - 0.9, 0)
                ))
            }
        }
    }

    private func midiEditorRect(
        trackLayout: PlaybackGridTrackLayout,
        containerRect rect: CGRect,
        trackID: ID<Track>,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect {
        let inlineHeight = snapshot.inlineMIDILaneHeights[trackID] ?? 0
        guard inlineHeight > 0 else { return rect }
        return CGRect(
            x: rect.minX,
            y: inlineMIDILaneYOrigin(trackLayout: trackLayout, snapshot: snapshot),
            width: rect.width,
            height: inlineHeight
        )
    }

    private func inlineMIDILaneYOrigin(
        trackLayout: PlaybackGridTrackLayout,
        snapshot: PlaybackGridSnapshot
    ) -> CGFloat {
        trackLayout.yOrigin
            + trackLayout.clipHeight
            + trackLayout.automationToolbarHeight
            + (CGFloat(trackLayout.automationLaneLayouts.count) * snapshot.automationSubLaneHeight)
    }

    private func automationLaneColor(at index: Int) -> SIMD4<Float> {
        let palette: [SIMD4<Float>] = [
            SIMD4(1.0, 0.30, 0.34, 0.92),
            SIMD4(0.18, 0.68, 1.0, 0.90),
            SIMD4(0.87, 0.36, 0.92, 0.90),
            SIMD4(1.0, 0.56, 0.18, 0.90),
            SIMD4(0.42, 0.92, 0.66, 0.90)
        ]
        return palette[index % palette.count]
    }

    private func buildMIDIPitchGrid(
        trackID: ID<Track>,
        resolved: PlaybackGridMIDIResolvedLayout?,
        yMin: Float,
        laneHeight: Float,
        xMin: Float,
        xMax: Float,
        pixelsPerBar: Float,
        snapshot: PlaybackGridSnapshot,
        rects: inout [PlaybackGridRectInstance],
        lines: inout [PlaybackGridLineInstance]
    ) {
        guard laneHeight >= 8 else { return }
        let layout = resolved ?? PlaybackGridMIDIViewResolver.resolveLayout(
            notes: [],
            trackID: trackID,
            laneHeight: CGFloat(laneHeight),
            snapshot: snapshot
        )
        let highNote = Int(layout.highPitch)
        let rows = layout.rows
        let rowHeight = Float(layout.rowHeight)
        let horizontalStride = rowHeight < 6 ? 2 : 1

        for i in 0..<rows {
            let midi = highNote - i
            let y = yMin + (Float(i) * rowHeight)
            if y >= (yMin + laneHeight) { break }
            let noteClass = midi % 12
            let isBlackKey = [1, 3, 6, 8, 10].contains(noteClass)
            if isBlackKey, rowHeight >= 4 {
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(xMin, y),
                    size: SIMD2(xMax - xMin, min(rowHeight, (yMin + laneHeight) - y)),
                    color: SIMD4(0, 0, 0, 0.006)
                ))
            }
            if (i % horizontalStride) != 0 { continue }
            let isC = noteClass == 0
            lines.append(PlaybackGridLineInstance(
                start: SIMD2(xMin, y),
                end: SIMD2(xMax, y),
                color: isC ? SIMD4(1, 1, 1, 0.024) : SIMD4(1, 1, 1, 0.0045),
                width: 1
            ))
        }
        let yBottom = yMin + laneHeight
        lines.append(PlaybackGridLineInstance(
            start: SIMD2(xMin, yBottom),
            end: SIMD2(xMax, yBottom),
            color: SIMD4(1, 1, 1, 0.048),
            width: 1
        ))
        lines.append(PlaybackGridLineInstance(
            start: SIMD2(xMin, yBottom - 2),
            end: SIMD2(xMax, yBottom - 2),
            color: SIMD4(1, 1, 1, 0.015),
            width: 1
        ))

        let safePPB = max(pixelsPerBar, 1)
        let beatsPerBar = max(Float(snapshot.timeSignature.beatsPerBar), 1)
        let beatWidth = safePPB / beatsPerBar
        let barStart = floor(xMin / safePPB) - 1
        let barEnd = ceil(xMax / safePPB) + 1
        for bar in Int(barStart)...Int(barEnd) {
            let barX = Float(bar) * safePPB
            lines.append(PlaybackGridLineInstance(
                start: SIMD2(barX, yMin),
                end: SIMD2(barX, yBottom),
                color: SIMD4(1, 1, 1, 0.028),
                width: 1
            ))
            for beat in 1..<Int(beatsPerBar) {
                let beatX = barX + (Float(beat) * beatWidth)
                lines.append(PlaybackGridLineInstance(
                    start: SIMD2(beatX, yMin),
                    end: SIMD2(beatX, yBottom),
                    color: SIMD4(1, 1, 1, 0.0055),
                    width: 1
                ))
            }
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
        trackID: ID<Track>,
        rect: CGRect,
        focusedPick: GridPickObject,
        selectedAutomationTool: AutomationTool,
        suppressedAutomationLanes: Set<PlaybackGridAutomationSuppression>,
        lines: inout [PlaybackGridLineInstance],
        rects: inout [PlaybackGridRectInstance]
    ) {
        guard container.lengthBars > 0 else { return }

        let laneColors: [SIMD4<Float>] = [
            SIMD4(1.0, 0.30, 0.34, 0.92),
            SIMD4(0.18, 0.68, 1.0, 0.90),
            SIMD4(0.87, 0.36, 0.92, 0.90),
            SIMD4(1.0, 0.56, 0.18, 0.90)
        ]
        let handleBaseSize: Float = 7
        let focusedHandleScale: Float = 1.45
        let barsToPixels = rect.width / CGFloat(container.lengthBars)
        let isFocusedContainer = focusedPick.containerID == container.id

        let automationBandHeight: CGFloat
        if selectedAutomationTool == .pointer {
            automationBandHeight = min(rect.height, max(24, rect.height * 0.42))
        } else {
            automationBandHeight = rect.height
        }
        let bandRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: automationBandHeight
        )
        let laneHeight = max(automationBandHeight / CGFloat(max(lanes.count, 1)), 1)

        for laneIndex in 1..<lanes.count {
            let y = Float(bandRect.minY + CGFloat(laneIndex) * laneHeight)
            lines.append(PlaybackGridLineInstance(
                start: SIMD2(Float(bandRect.minX), y),
                end: SIMD2(Float(bandRect.maxX), y),
                color: SIMD4(1, 1, 1, 0.055),
                width: 1
            ))
        }

        for (laneIndex, lane) in lanes.enumerated() {
            let isSuppressed = suppressedAutomationLanes.contains(
                .init(trackID: trackID, containerID: container.id, laneID: lane.id)
            )
            let lineAlphaMul: Float = isSuppressed ? 0.20 : 1.0
            let handleAlphaMul: Float = isSuppressed ? 0.35 : 1.0
            let laneRect = CGRect(
                x: bandRect.minX,
                y: bandRect.minY + CGFloat(laneIndex) * laneHeight,
                width: bandRect.width,
                height: laneHeight
            )
            let color = laneColors[laneIndex % laneColors.count]
            let sorted = lane.breakpoints.sorted { $0.position < $1.position }
            for guide in automationGuides(for: lane) {
                let ratio = guide.normalized
                let y = Float(laneRect.maxY) - (ratio * Float(laneRect.height))
                lines.append(PlaybackGridLineInstance(
                    start: SIMD2(Float(laneRect.minX), y),
                    end: SIMD2(Float(laneRect.maxX), y),
                    color: SIMD4(color.x, color.y, color.z, guide.alpha * lineAlphaMul),
                    width: 1
                ))
            }
            guard !sorted.isEmpty else { continue }

            var points: [SIMD2<Float>] = []
            points.reserveCapacity(sorted.count)

            for bp in sorted {
                let x = Float(rect.minX + (CGFloat(bp.position) * barsToPixels))
                let y = Float(laneRect.maxY - (CGFloat(bp.value) * laneRect.height))
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
                    color: SIMD4(0, 0, 0, (isFocused ? 0.30 : 0.16) * handleAlphaMul),
                    cornerRadius: shadowRadius
                ))
                if isFocused {
                    rects.append(PlaybackGridRectInstance(
                        origin: SIMD2(x - ringRadius, y - ringRadius),
                        size: SIMD2(ringSize, ringSize),
                        color: SIMD4(color.x, color.y, color.z, 0.52 * handleAlphaMul),
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
                        1.0 * handleAlphaMul
                    )
                } else {
                    handleColor = SIMD4(color.x, color.y, color.z, color.w * handleAlphaMul)
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
                    color: SIMD4(0, 0, 0, 0.18 * handleAlphaMul),
                    cornerRadius: max(handleRadius - 1, 0)
                ))
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(x - handleRadius * 0.45, y - handleRadius * 0.45),
                    size: SIMD2(highlightSize, highlightSize),
                    color: SIMD4(1, 1, 1, (isFocused ? 0.80 : 0.48) * handleAlphaMul),
                    cornerRadius: highlightRadius
                ))
            }

            if points.count >= 2 {
                appendAutomationCurve(
                    points: points,
                    color: SIMD4(color.x, color.y, color.z, color.w * lineAlphaMul),
                    lines: &lines
                )
            }
        }
    }

    private func buildExpandedAutomationOverlays(
        trackLayout: PlaybackGridTrackLayout,
        snapshot: PlaybackGridSnapshot,
        visibleMinX: Float,
        visibleMaxX: Float,
        focusedPick: GridPickObject,
        suppressedAutomationLanes: Set<PlaybackGridAutomationSuppression>,
        lines: inout [PlaybackGridLineInstance],
        rects: inout [PlaybackGridRectInstance]
    ) {
        guard !trackLayout.automationLaneLayouts.isEmpty else { return }

        let handleBaseSize: Float = 7
        let focusedHandleScale: Float = 1.45
        let ppb = Float(snapshot.pixelsPerBar)

        for (laneIndex, laneLayout) in trackLayout.automationLaneLayouts.enumerated() {
            if Float(laneLayout.rect.maxX) < visibleMinX || Float(laneLayout.rect.minX) > visibleMaxX {
                continue
            }
            let laneColor = automationLaneColor(at: laneIndex)

            if let trackLane = trackLayout.track.trackAutomationLanes.first(where: { $0.targetPath == laneLayout.targetPath }) {
                let isSuppressed = suppressedAutomationLanes.contains(
                    .init(trackID: trackLayout.track.id, containerID: nil, laneID: trackLane.id)
                )
                let lineAlphaMul: Float = isSuppressed ? 0.20 : 1.0
                let handleAlphaMul: Float = isSuppressed ? 0.35 : 1.0
                let sorted = trackLane.breakpoints.sorted { $0.position < $1.position }
                var points: [SIMD2<Float>] = []
                points.reserveCapacity(sorted.count)
                for guide in automationGuides(for: trackLane) {
                    let y = Float(laneLayout.rect.maxY) - (guide.normalized * Float(laneLayout.rect.height))
                    lines.append(PlaybackGridLineInstance(
                        start: SIMD2(Float(max(visibleMinX, Float(laneLayout.rect.minX))), y),
                        end: SIMD2(Float(min(visibleMaxX, Float(laneLayout.rect.maxX))), y),
                        color: SIMD4(laneColor.x, laneColor.y, laneColor.z, guide.alpha * 0.9 * lineAlphaMul),
                        width: 1
                    ))
                }

                for bp in sorted {
                    let x = Float(bp.position) * ppb
                    let y = Float(laneLayout.rect.maxY - (CGFloat(bp.value) * laneLayout.rect.height))
                    points.append(SIMD2(x, y))

                    let isFocused = focusedPick.kind == .automationBreakpoint
                        && focusedPick.trackID == trackLayout.track.id
                        && focusedPick.containerID == nil
                        && focusedPick.automationLaneID == trackLane.id
                        && focusedPick.automationBreakpointID == bp.id
                    let handleSize = isFocused ? handleBaseSize * focusedHandleScale : handleBaseSize
                    rects.append(PlaybackGridRectInstance(
                        origin: SIMD2(x - (handleSize * 0.5), y - (handleSize * 0.5)),
                        size: SIMD2(handleSize, handleSize),
                        color: SIMD4(laneColor.x, laneColor.y, laneColor.z, (isFocused ? 0.98 : 0.84) * handleAlphaMul),
                        cornerRadius: handleSize * 0.25
                    ))
                }
                appendAutomationCurve(
                    points: points,
                    color: SIMD4(laneColor.x, laneColor.y, laneColor.z, laneColor.w * lineAlphaMul),
                    lines: &lines
                )
            }

            for containerLayout in trackLayout.containers {
                guard let lane = containerLayout.container.automationLanes.first(where: { $0.targetPath == laneLayout.targetPath }) else {
                    continue
                }
                let isSuppressed = suppressedAutomationLanes.contains(
                    .init(trackID: trackLayout.track.id, containerID: containerLayout.container.id, laneID: lane.id)
                )
                let lineAlphaMul: Float = isSuppressed ? 0.20 : 1.0
                let handleAlphaMul: Float = isSuppressed ? 0.35 : 1.0
                if Float(containerLayout.rect.maxX) < visibleMinX || Float(containerLayout.rect.minX) > visibleMaxX {
                    continue
                }
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(Float(containerLayout.rect.minX), Float(laneLayout.rect.minY)),
                    size: SIMD2(Float(containerLayout.rect.width), Float(laneLayout.rect.height)),
                    color: SIMD4(laneColor.x, laneColor.y, laneColor.z, 0.045 * lineAlphaMul)
                ))

                let barsToPixels = containerLayout.rect.width / max(CGFloat(containerLayout.container.lengthBars), 0.0001)
                let sorted = lane.breakpoints.sorted { $0.position < $1.position }
                var points: [SIMD2<Float>] = []
                points.reserveCapacity(sorted.count)
                for guide in automationGuides(for: lane) {
                    let y = Float(laneLayout.rect.maxY) - (guide.normalized * Float(laneLayout.rect.height))
                    lines.append(PlaybackGridLineInstance(
                        start: SIMD2(Float(containerLayout.rect.minX), y),
                        end: SIMD2(Float(containerLayout.rect.maxX), y),
                        color: SIMD4(laneColor.x, laneColor.y, laneColor.z, guide.alpha * 0.86 * lineAlphaMul),
                        width: 1
                    ))
                }
                for bp in sorted {
                    let x = Float(containerLayout.rect.minX + (CGFloat(bp.position) * barsToPixels))
                    let y = Float(laneLayout.rect.maxY - (CGFloat(bp.value) * laneLayout.rect.height))
                    points.append(SIMD2(x, y))

                    let isFocused = focusedPick.kind == .automationBreakpoint
                        && focusedPick.trackID == trackLayout.track.id
                        && focusedPick.containerID == containerLayout.container.id
                        && focusedPick.automationLaneID == lane.id
                        && focusedPick.automationBreakpointID == bp.id
                    let handleSize = isFocused ? handleBaseSize * focusedHandleScale : handleBaseSize
                    rects.append(PlaybackGridRectInstance(
                        origin: SIMD2(x - (handleSize * 0.5), y - (handleSize * 0.5)),
                        size: SIMD2(handleSize, handleSize),
                        color: SIMD4(laneColor.x, laneColor.y, laneColor.z, (isFocused ? 0.98 : 0.84) * handleAlphaMul),
                        cornerRadius: handleSize * 0.25
                    ))
                }
                appendAutomationCurve(
                    points: points,
                    color: SIMD4(laneColor.x, laneColor.y, laneColor.z, laneColor.w * lineAlphaMul),
                    lines: &lines
                )
            }
        }
    }

    private func appendAutomationCurve(
        points: [SIMD2<Float>],
        color: SIMD4<Float>,
        lines: inout [PlaybackGridLineInstance]
    ) {
        guard points.count >= 2 else { return }
        let shadowColor = SIMD4<Float>(0, 0, 0, 0.18 * color.w)
        let glowColor = SIMD4<Float>(color.x, color.y, color.z, 0.16 * color.w)
        let mainColor = SIMD4<Float>(color.x, color.y, color.z, min(color.w + 0.06, 1.0))

        @inline(__always)
        func snapped(_ p: SIMD2<Float>) -> SIMD2<Float> {
            SIMD2(
                (round(p.x * 2) * 0.5),
                (round(p.y * 2) * 0.5)
            )
        }

        for i in 0..<(points.count - 1) {
            let start = snapped(points[i])
            let end = snapped(points[i + 1])
            let dx = end.x - start.x
            let dy = end.y - start.y
            if (dx * dx) + (dy * dy) < 0.25 { continue }
            lines.append(PlaybackGridLineInstance(
                start: SIMD2(start.x, start.y + 1.2),
                end: SIMD2(end.x, end.y + 1.2),
                color: shadowColor,
                width: 2.4
            ))
            lines.append(PlaybackGridLineInstance(
                start: start,
                end: end,
                color: glowColor,
                width: 2.6
            ))
            lines.append(PlaybackGridLineInstance(
                start: start,
                end: end,
                color: mainColor,
                width: 1.55
            ))
        }
    }

    private struct AutomationGuideLine {
        let normalized: Float
        let alpha: Float
    }

    private func automationGuides(for lane: AutomationLane) -> [AutomationGuideLine] {
        let minValue = Double(lane.parameterMin ?? 0)
        let maxValue = Double(lane.parameterMax ?? 1)
        let unit = (lane.parameterUnit ?? "").lowercased()

        // Frequency-like params read far better on logarithmic reference guides.
        if unit.contains("hz"), minValue > 0, maxValue > minValue {
            let anchors: [Double] = [20, 50, 100, 200, 500, 1_000, 2_000, 5_000, 10_000, 20_000]
            let ratio = maxValue / minValue
            var guides: [AutomationGuideLine] = []
            for value in anchors where value >= minValue && value <= maxValue {
                let normalized = Float(log(value / minValue) / log(ratio))
                let isMajor = value == 100 || value == 1_000 || value == 10_000
                guides.append(AutomationGuideLine(
                    normalized: max(0, min(1, normalized)),
                    alpha: isMajor ? 0.14 : 0.08
                ))
            }
            if guides.isEmpty {
                return defaultAutomationGuides()
            }
            return dedupedAutomationGuides(guides)
        }

        if maxValue > minValue {
            let span = maxValue - minValue
            if span >= 16 && span <= 512 {
                let majorStep: Double
                if span <= 64 {
                    majorStep = 8
                } else if span <= 128 {
                    majorStep = 16
                } else {
                    majorStep = 32
                }
                var guides: [AutomationGuideLine] = []
                var value = ceil(minValue / majorStep) * majorStep
                while value <= maxValue + 0.0001 {
                    let normalized = Float((value - minValue) / span)
                    let isBoundary = abs(value - minValue) < 0.0001 || abs(value - maxValue) < 0.0001
                    guides.append(AutomationGuideLine(
                        normalized: max(0, min(1, normalized)),
                        alpha: isBoundary ? 0.14 : 0.09
                    ))
                    value += majorStep
                }
                if guides.count >= 3 {
                    return dedupedAutomationGuides(guides)
                }
            }
        }

        return defaultAutomationGuides()
    }

    private func defaultAutomationGuides() -> [AutomationGuideLine] {
        [
            AutomationGuideLine(normalized: 0.0, alpha: 0.14),
            AutomationGuideLine(normalized: 0.25, alpha: 0.08),
            AutomationGuideLine(normalized: 0.5, alpha: 0.11),
            AutomationGuideLine(normalized: 0.75, alpha: 0.08),
            AutomationGuideLine(normalized: 1.0, alpha: 0.14)
        ]
    }

    private func dedupedAutomationGuides(_ guides: [AutomationGuideLine]) -> [AutomationGuideLine] {
        var buckets: [Int: AutomationGuideLine] = [:]
        for guide in guides {
            let bucket = Int((guide.normalized * 1000).rounded())
            if let existing = buckets[bucket] {
                if guide.alpha > existing.alpha {
                    buckets[bucket] = guide
                }
            } else {
                buckets[bucket] = guide
            }
        }
        return buckets
            .values
            .sorted { $0.normalized < $1.normalized }
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
    let fillFocused: SIMD4<Float>
    let fillArmed: SIMD4<Float>
    let borderNormal: SIMD4<Float>
    let borderSelected: SIMD4<Float>
    let borderFocused: SIMD4<Float>
    let borderArmed: SIMD4<Float>
    let waveformFill: SIMD4<Float>
    let waveformFocused: SIMD4<Float>
    let selectionHighlight: SIMD4<Float>
    let focusGlow: SIMD4<Float>

    init(kind: TrackKind) {
        let base = Self.baseColor(for: kind)
        fillNormal = SIMD4(base.x, base.y, base.z, 0.30)
        fillSelected = SIMD4(base.x, base.y, base.z, 0.46)
        fillFocused = SIMD4(base.x, base.y, base.z, 0.38)
        fillArmed = SIMD4(1, 0.23, 0.19, 0.15)
        borderNormal = SIMD4(base.x, base.y, base.z, 0.50)
        borderSelected = SIMD4(0.33, 0.72, 1.0, 1.0)
        borderFocused = SIMD4(0.78, 0.90, 1.0, 0.90)
        borderArmed = SIMD4(1, 0.23, 0.19, 1.0)
        switch kind {
        case .audio, .backing:
            waveformFill = SIMD4(0.96, 0.99, 1.0, 1.0)
            waveformFocused = SIMD4(1.0, 1.0, 1.0, 1.0)
        case .midi:
            waveformFill = SIMD4(0.90, 0.44, 0.72, 0.96)
            waveformFocused = SIMD4(0.98, 0.58, 0.82, 0.995)
        case .bus:
            waveformFill = SIMD4(0.62, 0.92, 0.72, 0.92)
            waveformFocused = SIMD4(0.76, 0.97, 0.84, 0.99)
        case .master:
            waveformFill = SIMD4(0.86, 0.90, 0.95, 0.90)
            waveformFocused = SIMD4(0.95, 0.97, 1.0, 0.98)
        }
        selectionHighlight = SIMD4(0.25, 0.55, 1.0, 0.24)
        focusGlow = SIMD4(0.76, 0.88, 1.0, 0.18)
    }

    private static func baseColor(for kind: TrackKind) -> SIMD3<Float> {
        switch kind {
        case .audio: return SIMD3(0.09, 0.33, 0.58)
        case .midi: return SIMD3(0.52, 0.23, 0.58)
        case .bus: return SIMD3(0.18, 0.70, 0.38)
        case .backing: return SIMD3(0.90, 0.47, 0.12)
        case .master: return SIMD3(0.43, 0.46, 0.52)
        }
    }
}
