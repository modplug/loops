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
    private let proceduralGridPipeline: MTLRenderPipelineState

    private let quadIndexBuffer: MTLBuffer
    private let waveformResidencyCache = PlaybackGridWaveformResidencyCache()

    public let frameSemaphore = DispatchSemaphore(value: 2)

    private let rectBufferStorage = PlaybackGridReusableBuffer()
    private var rectBuffer: MTLBuffer?
    private var rectCount = 0

    private let lineBufferStorage = PlaybackGridReusableBuffer()
    private var lineBuffer: MTLBuffer?
    private var lineCount = 0

    private var waveformDrawCalls: [PlaybackGridWaveformDrawCall] = []
    private var waveformCoreDrawCalls: [PlaybackGridWaveformDrawCall] = []

    private let midiBufferStorage = PlaybackGridReusableBuffer()
    private var midiBuffer: MTLBuffer?
    private var midiCount = 0
    private let midiOverlayBufferStorage = PlaybackGridReusableBuffer()
    private var midiOverlayBuffer: MTLBuffer?
    private var midiOverlayCount = 0
    private let containerOverlayRectBufferStorage = PlaybackGridReusableBuffer()
    private var containerOverlayRectBuffer: MTLBuffer?
    private var containerOverlayRectCount = 0
    private let containerOverlayLineBufferStorage = PlaybackGridReusableBuffer()
    private var containerOverlayLineBuffer: MTLBuffer?
    private var containerOverlayLineCount = 0
    private var containerOverlayWaveformDrawCalls: [PlaybackGridWaveformDrawCall] = []
    private var containerOverlayWaveformCoreDrawCalls: [PlaybackGridWaveformDrawCall] = []
    private let containerOverlayMIDIBufferStorage = PlaybackGridReusableBuffer()
    private var containerOverlayMIDIBuffer: MTLBuffer?
    private var containerOverlayMIDICount = 0
    private let containerOverlayFadeVertexBufferStorage = PlaybackGridReusableBuffer()
    private var containerOverlayFadeVertexBuffer: MTLBuffer?
    private var containerOverlayFadeVertexCount = 0
    private var containerOverlayFadeDrawCalls: [(offset: Int, count: Int)] = []
    private let containerOverlayBorderBufferStorage = PlaybackGridReusableBuffer()
    private var containerOverlayBorderBuffer: MTLBuffer?
    private var containerOverlayBorderCount = 0
    private let focusRectBufferStorage = PlaybackGridReusableBuffer()
    private var focusRectBuffer: MTLBuffer?
    private var focusRectCount = 0
    private let focusLineBufferStorage = PlaybackGridReusableBuffer()
    private var focusLineBuffer: MTLBuffer?
    private var focusLineCount = 0
    private let focusMIDIBufferStorage = PlaybackGridReusableBuffer()
    private var focusMIDIBuffer: MTLBuffer?
    private var focusMIDICount = 0
    private let automationOverlayLineBufferStorage = PlaybackGridReusableBuffer()
    private var automationOverlayLineBuffer: MTLBuffer?
    private var automationOverlayLineCount = 0
    private let automationOverlayRectBufferStorage = PlaybackGridReusableBuffer()
    private var automationOverlayRectBuffer: MTLBuffer?
    private var automationOverlayRectCount = 0
    private let automationShapeOverlayLineBufferStorage = PlaybackGridReusableBuffer()
    private var automationShapeOverlayLineBuffer: MTLBuffer?
    private var automationShapeOverlayLineCount = 0
    private let automationShapeOverlayRectBufferStorage = PlaybackGridReusableBuffer()
    private var automationShapeOverlayRectBuffer: MTLBuffer?
    private var automationShapeOverlayRectCount = 0

    private let fadeVertexBufferStorage = PlaybackGridReusableBuffer()
    private var fadeVertexBuffer: MTLBuffer?
    private var fadeVertexCount = 0
    private var fadeDrawCalls: [(offset: Int, count: Int)] = []

    private let borderBufferStorage = PlaybackGridReusableBuffer()
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
        proceduralGridPipeline = try Self.makePipeline(
            device: device,
            library: library,
            pixelFormat: pixelFormat,
            vertexFunction: "pg_procedural_vertex",
            fragmentFunction: "pg_grid_fragment"
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
        midiOverlays: [PlaybackGridMIDINoteOverlay] = [],
        focusedPick: GridPickObject = .none,
        suppressedAutomationLanes: Set<PlaybackGridAutomationSuppression> = []
    ) {
        let ppb = Float(snapshot.pixelsPerBar)
        let visibleMinX = Float(visibleRect.minX)
        let visibleMaxX = Float(visibleRect.maxX)
        let visibleMinY = Float(visibleRect.minY)
        let canvasHeight = Float(canvasSize.height)
        let rulerHeight = Float(PlaybackGridLayout.rulerHeight)
        let sectionLaneHeight = Float(PlaybackGridLayout.sectionLaneHeight)

        var rects: [PlaybackGridRectInstance] = []
        var lines: [PlaybackGridLineInstance] = []
        var wfDrawCalls: [PlaybackGridWaveformDrawCall] = []
        var wfCoreDrawCalls: [PlaybackGridWaveformDrawCall] = []
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

        let bgColor = SIMD4<Float>(0.16, 0.18, 0.22, 0.13)
        let sepColor = SIMD4<Float>(0.76, 0.82, 0.91, 0.10)
        for layout in scene.trackLayouts {
            let y = Float(layout.yOrigin)
            let h = Float(layout.height)
            rects.append(PlaybackGridRectInstance(
                origin: SIMD2(visibleMinX, y),
                size: SIMD2(visibleMaxX - visibleMinX, h),
                color: layout.isPreviewed ? SIMD4<Float>(0.25, 0.55, 1.0, 0.08) : bgColor
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
                        color: laneLayout.isPreviewed
                            ? SIMD4(laneTint.x, laneTint.y, laneTint.z, 0.14)
                            : SIMD4(laneTint.x, laneTint.y, laneTint.z, 0.055)
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
                let config = snapshot.inlineMIDIConfigs[layout.track.id]
                let noteAreaHeight = config?.noteAreaHeight(totalInlineHeight: inlineMIDILaneHeight) ?? inlineMIDILaneHeight
                let laneHeight = Float(noteAreaHeight)
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(visibleMinX, laneMinY),
                    size: SIMD2(visibleMaxX - visibleMinX, laneHeight),
                    color: SIMD4(0.08, 0.09, 0.11, 0.24)
                ))
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(visibleMinX, laneMinY),
                    size: SIMD2(visibleMaxX - visibleMinX, max(1, laneHeight * 0.08)),
                    color: SIMD4(1, 1, 1, 0.028)
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
                if let config, !config.detailLanes.isEmpty {
                    var detailLaneY = CGFloat(laneMinY) + noteAreaHeight
                    for detailLane in config.detailLanes {
                        let laneRect = CGRect(
                            x: CGFloat(visibleMinX),
                            y: detailLaneY,
                            width: CGFloat(visibleMaxX - visibleMinX),
                            height: detailLane.height
                        )
                        appendMIDIDetailLaneBackground(
                            lane: detailLane,
                            laneRect: laneRect,
                            rects: &rects,
                            lines: &lines
                        )
                        detailLaneY += detailLane.height
                    }
                }
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
                let fillColor: SIMD4<Float> = cl.isPreviewed ? SIMD4<Float>(0.22, 0.48, 0.96, 0.30)
                    : isArmed ? trackColors.fillArmed
                    : cl.isSelected ? trackColors.fillSelected
                    : isFocusedContainer ? trackColors.fillFocused : trackColors.fillNormal

                let origin = SIMD2<Float>(Float(rect.minX), Float(rect.minY))
                let size = SIMD2<Float>(Float(rect.width), Float(rect.height))

                let fillOrigin = SIMD2<Float>(origin.x, origin.y + 1)
                let fillSize = SIMD2<Float>(size.x, max(size.y - 2, 1))
                rects.append(PlaybackGridRectInstance(origin: fillOrigin, size: fillSize, color: fillColor))

                let borderColor: SIMD4<Float> = cl.isPreviewed ? SIMD4<Float>(0.42, 0.70, 1.0, 0.90)
                    : isArmed ? trackColors.borderArmed
                    : cl.isSelected ? trackColors.borderSelected
                    : isFocusedContainer ? trackColors.borderFocused : trackColors.borderNormal
                let borderW: Float = cl.isPreviewed ? 2.0 : cl.isSelected ? 1.5 : 1.0
                borders.append(PlaybackGridRectInstance(
                    origin: fillOrigin,
                    size: fillSize,
                    color: borderColor,
                    cornerRadius: 4,
                    borderWidth: borderW
                ))

                if cl.isSelected || cl.isPreviewed {
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
                        color: cl.isPreviewed ? SIMD4<Float>(0.42, 0.70, 1.0, 0.62) : trackColors.selectionHighlight,
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

                let waveformExtrema = cl.waveformExtrema
                    ?? cl.waveformPeaks.map { symmetricExtrema(from: $0) }
                let waveformRMS = cl.waveformRMS
                if let extrema = waveformExtrema, !extrema.isEmpty, fillSize.x >= 4 {
                    let visibleAudioBars = max(0.0001, min(
                        cl.container.lengthBars,
                        (cl.audioDurationBars ?? cl.container.lengthBars) - cl.container.audioStartOffset
                    ))
                    let waveformWidth = Float(visibleAudioBars) * ppb
                    let maxPeaks = targetWaveformPeakCount(
                        containerWidthPx: max(waveformWidth, 1),
                        detailed: true
                    )
                    let envelopeParamsBase = PlaybackGridWaveformParams(
                        containerOrigin: SIMD2(Float(cl.container.startBar - 1.0), fillOrigin.y),
                        containerSize: SIMD2(Float(cl.container.lengthBars), fillSize.y),
                        fillColor: isFocusedContainer ? trackColors.waveformFocused : trackColors.waveformFill,
                        peakOffset: 0,
                        peakCount: 0,
                        amplitude: isFocusedContainer ? 0.98 : 0.92,
                        visibleBars: Float(visibleAudioBars),
                        audioStartOffsetBars: Float(cl.container.audioStartOffset),
                        clipLengthBars: Float(cl.container.lengthBars),
                        enterFadeBars: Float(cl.enterFade?.duration ?? 0),
                        exitFadeBars: Float(cl.exitFade?.duration ?? 0),
                        reserved: .zero
                    )

                    if let recordingID = cl.container.sourceRecordingID,
                       cl.waveformExtrema != nil,
                       let residency = waveformResidencyCache.residency(
                            for: recordingID,
                            extrema: extrema,
                            rms: waveformRMS ?? [],
                            device: device
                       ),
                       let envelopeLevel = selectWaveformResidencyLevel(
                            levels: residency.levels,
                            mode: .envelope,
                            targetPeakCount: maxPeaks
                       ) {
                        var params = envelopeParamsBase
                        params.peakOffset = UInt32(envelopeLevel.offset)
                        params.peakCount = UInt32(envelopeLevel.count)
                        wfDrawCalls.append(PlaybackGridWaveformDrawCall(
                            buffer: residency.buffer,
                            params: params
                        ))

                        if let rmsLevel = selectWaveformResidencyLevel(
                            levels: residency.levels,
                            mode: .rms,
                            targetPeakCount: maxPeaks
                        ) {
                            var coreParams = envelopeParamsBase
                            coreParams.fillColor = isFocusedContainer
                                ? withAlpha(trackColors.waveformFocused, 0.26)
                                : withAlpha(trackColors.waveformFill, 0.18)
                            coreParams.peakOffset = UInt32(rmsLevel.offset)
                            coreParams.peakCount = UInt32(rmsLevel.count)
                            coreParams.amplitude = 0.78
                            wfCoreDrawCalls.append(PlaybackGridWaveformDrawCall(
                                buffer: residency.buffer,
                                params: coreParams
                            ))
                        }
                    } else {
                        let fallbackExtrema = downsampleWaveformExtrema(extrema, to: maxPeaks)
                        if let buffer = makeBuffer(fallbackExtrema.map { SIMD2<Float>($0.minimum, $0.maximum) }) {
                            var params = envelopeParamsBase
                            params.peakCount = UInt32(fallbackExtrema.count)
                            wfDrawCalls.append(PlaybackGridWaveformDrawCall(
                                buffer: buffer,
                                params: params
                            ))
                        }
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
                        selectedNoteIDs: snapshot.selectedMIDINoteIDs,
                        focusedPick: focusedPick,
                        timeSignature: snapshot.timeSignature,
                        into: &midiNotes
                    )
                    if let config = snapshot.inlineMIDIConfigs[trackLayout.track.id], !config.detailLanes.isEmpty {
                        let detailLaneNotes = mergedMIDIDetailLaneNotes(
                            baseNotes: notes,
                            containerID: cl.container.id,
                            trackID: trackLayout.track.id,
                            overlays: midiOverlays
                        )
                        appendMIDIDetailLaneData(
                            notes: detailLaneNotes,
                            container: cl.container,
                            noteRect: midiRect,
                            detailLanes: config.detailLanes,
                            resolved: resolved,
                            timeSignature: snapshot.timeSignature,
                            selectedNoteIDs: snapshot.selectedMIDINoteIDs,
                            focusedPick: focusedPick,
                            rects: &rects,
                            lines: &lines
                        )
                    }
                }

                if cl.enterFade != nil || cl.exitFade != nil {
                    buildFadeOverlay(
                        enterFade: cl.enterFade,
                        exitFade: cl.exitFade,
                        rect: rect,
                        pixelsPerBar: ppb,
                        into: &fadeVerts,
                        calls: &fadeCalls,
                        lines: &lines
                    )
                }

                let showFadeHandles = (cl.enterFade != nil || cl.exitFade != nil) || isFocusedContainer || cl.isSelected
                if showFadeHandles {
                    let handleSize: Float = 7
                    let handleRadius: Float = handleSize / 2
                    let handleColor = SIMD4<Float>(1, 1, 1, 0.85)
                    let handleY = fillOrigin.y - handleRadius

                    let isFocusedFadeLeft = isFocusedContainer && focusedPick.zone == .fadeLeft
                    let isFocusedFadeRight = isFocusedContainer && focusedPick.zone == .fadeRight

                    let enterW = cl.enterFade.map { Float($0.duration) * ppb } ?? 0
                    let enterHandleOrigin = SIMD2(fillOrigin.x + enterW - handleRadius, handleY)
                    if isFocusedFadeLeft {
                        let glowSize: Float = handleSize + 4
                        let glowRadius = glowSize / 2
                        borders.append(PlaybackGridRectInstance(
                            origin: SIMD2(enterHandleOrigin.x - 2, enterHandleOrigin.y - 2),
                            size: SIMD2(glowSize, glowSize),
                            color: SIMD4(1, 1, 1, 0.3),
                            cornerRadius: glowRadius
                        ))
                    }
                    borders.append(PlaybackGridRectInstance(
                        origin: enterHandleOrigin,
                        size: SIMD2(handleSize, handleSize),
                        color: isFocusedFadeLeft ? SIMD4<Float>(1, 1, 1, 1) : handleColor,
                        cornerRadius: handleRadius
                    ))

                    let exitW = cl.exitFade.map { Float($0.duration) * ppb } ?? 0
                    let exitHandleOrigin = SIMD2(fillOrigin.x + fillSize.x - exitW - handleRadius, handleY)
                    if isFocusedFadeRight {
                        let glowSize: Float = handleSize + 4
                        let glowRadius = glowSize / 2
                        borders.append(PlaybackGridRectInstance(
                            origin: SIMD2(exitHandleOrigin.x - 2, exitHandleOrigin.y - 2),
                            size: SIMD2(glowSize, glowSize),
                            color: SIMD4(1, 1, 1, 0.3),
                            cornerRadius: glowRadius
                        ))
                    }
                    borders.append(PlaybackGridRectInstance(
                        origin: exitHandleOrigin,
                        size: SIMD2(handleSize, handleSize),
                        color: isFocusedFadeRight ? SIMD4<Float>(1, 1, 1, 1) : handleColor,
                        cornerRadius: handleRadius
                    ))
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
            let startX = Float(range.lowerBound - 1) * ppb
            let endX = Float(range.upperBound) * ppb
            let accentColor = SIMD4<Float>(0.25, 0.55, 1.0, 0.15)
            let edgeColor = SIMD4<Float>(0.25, 0.55, 1.0, 0.5)

            var scopedBands: [(y: Float, height: Float)] = []
            for trackLayout in scene.trackLayouts {
                if trackLayout.containers.contains(where: { snapshot.selectedContainerIDs.contains($0.container.id) }) {
                    scopedBands.append((y: Float(trackLayout.yOrigin), height: Float(trackLayout.clipHeight)))
                }
            }

            if scopedBands.isEmpty {
                let totalHeight = scene.trackLayouts.last.map { Float($0.yOrigin + $0.height) } ?? canvasHeight
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(startX, 0),
                    size: SIMD2(endX - startX, totalHeight),
                    color: accentColor
                ))
                lines.append(PlaybackGridLineInstance(
                    start: SIMD2(startX, 0), end: SIMD2(startX, totalHeight),
                    color: edgeColor, width: 1
                ))
                lines.append(PlaybackGridLineInstance(
                    start: SIMD2(endX, 0), end: SIMD2(endX, totalHeight),
                    color: edgeColor, width: 1
                ))
            } else {
                for band in scopedBands {
                    rects.append(PlaybackGridRectInstance(
                        origin: SIMD2(startX, band.y),
                        size: SIMD2(endX - startX, band.height),
                        color: accentColor
                    ))
                    lines.append(PlaybackGridLineInstance(
                        start: SIMD2(startX, band.y), end: SIMD2(startX, band.y + band.height),
                        color: edgeColor, width: 1
                    ))
                    lines.append(PlaybackGridLineInstance(
                        start: SIMD2(endX, band.y), end: SIMD2(endX, band.y + band.height),
                        color: edgeColor, width: 1
                    ))
                }
            }
        }

        // Container-scoped range selection (from selector zone drag)
        if let rangeSelection = snapshot.rangeSelection {
            let startX = Float(rangeSelection.startBar - 1.0) * ppb
            let endX = Float(rangeSelection.endBar - 1.0) * ppb
            let rangeWidth = endX - startX
            if rangeWidth > 0 {
                let accentColor = SIMD4<Float>(0.25, 0.55, 1.0, 0.15)
                let edgeColor = SIMD4<Float>(0.25, 0.55, 1.0, 0.5)
                for trackLayout in scene.trackLayouts {
                    if trackLayout.containers.contains(where: { $0.container.id == rangeSelection.containerID }) {
                        let y = Float(trackLayout.yOrigin)
                        let h = Float(trackLayout.clipHeight)
                        rects.append(PlaybackGridRectInstance(
                            origin: SIMD2(startX, y),
                            size: SIMD2(rangeWidth, h),
                            color: accentColor
                        ))
                        lines.append(PlaybackGridLineInstance(
                            start: SIMD2(startX, y), end: SIMD2(startX, y + h),
                            color: edgeColor, width: 1
                        ))
                        lines.append(PlaybackGridLineInstance(
                            start: SIMD2(endX, y), end: SIMD2(endX, y + h),
                            color: edgeColor, width: 1
                        ))
                    }
                }
            }
        }

        rectBuffer = rectBufferStorage.write(rects, device: device)
        rectCount = rects.count

        lineBuffer = lineBufferStorage.write(lines, device: device)
        lineCount = lines.count

        waveformDrawCalls = wfDrawCalls
        waveformCoreDrawCalls = wfCoreDrawCalls

        midiBuffer = midiBufferStorage.write(midiNotes, device: device)
        midiCount = midiNotes.count

        fadeVertexBuffer = fadeVertexBufferStorage.write(fadeVerts, device: device)
        fadeVertexCount = fadeVerts.count
        fadeDrawCalls = fadeCalls

        borderBuffer = borderBufferStorage.write(borders, device: device)
        borderCount = borders.count

        debugStats = PlaybackGridDebugStats(
            rectCount: rectCount,
            lineCount: lineCount,
            waveformCount: waveformDrawCalls.count,
            midiCount: midiCount + midiOverlayCount,
            fadeVertexCount: fadeVertexCount,
            borderCount: borderCount
        )
    }

    public func buildFocusOverlayBuffer(
        scene: PlaybackGridScene,
        snapshot: PlaybackGridSnapshot,
        focusedPick: GridPickObject
    ) {
        guard focusedPick.kind != .none else {
            focusRectBuffer = nil
            focusRectCount = 0
            focusLineBuffer = nil
            focusLineCount = 0
            focusMIDIBuffer = nil
            focusMIDICount = 0
            return
        }

        var rects: [PlaybackGridRectInstance] = []
        var lines: [PlaybackGridLineInstance] = []
        var midiNotes: [PlaybackGridMIDINoteInstance] = []

        let trackLayoutsByID = Dictionary(uniqueKeysWithValues: scene.trackLayouts.map { ($0.track.id, $0) })
        let containerLayoutsByID = Dictionary(uniqueKeysWithValues: scene.trackLayouts.flatMap { layout in
            layout.containers.map { ($0.container.id, (layout, $0)) }
        })

        switch focusedPick.kind {
        case .containerZone:
            guard let containerID = focusedPick.containerID,
                  let (_, containerLayout) = containerLayoutsByID[containerID] else { break }
            appendContainerFocusOverlay(
                containerLayout: containerLayout,
                focusedPick: focusedPick,
                pixelsPerBar: Float(snapshot.pixelsPerBar),
                rects: &rects
            )

        case .midiNote:
            guard let containerID = focusedPick.containerID,
                  let noteID = focusedPick.midiNoteID,
                  let (trackLayout, containerLayout) = containerLayoutsByID[containerID],
                  let notes = containerLayout.resolvedMIDINotes,
                  let note = notes.first(where: { $0.id == noteID }) else { break }

            let midiRect = midiEditorRect(
                trackLayout: trackLayout,
                containerRect: containerLayout.rect,
                trackID: trackLayout.track.id,
                snapshot: snapshot
            )
            let resolved = PlaybackGridMIDIViewResolver.resolveTrackLayout(
                track: trackLayout.track,
                laneHeight: midiRect.height,
                snapshot: snapshot
            )
            appendFocusedMIDINoteOverlay(
                note: note,
                container: containerLayout.container,
                rect: midiRect,
                resolved: resolved,
                timeSignature: snapshot.timeSignature,
                into: &midiNotes
            )
            if let velocityLaneRect = midiVelocityLaneRect(
                trackLayout: trackLayout,
                containerLayout: containerLayout,
                snapshot: snapshot
            ) {
                appendFocusedMIDIVelocityOverlay(
                    note: note,
                    container: containerLayout.container,
                    noteRect: midiRect,
                    velocityLaneRect: velocityLaneRect,
                    resolved: resolved,
                    timeSignature: snapshot.timeSignature,
                    rects: &rects,
                    lines: &lines
                )
            }

        case .automationBreakpoint:
            guard let trackID = focusedPick.trackID,
                  let laneID = focusedPick.automationLaneID,
                  let breakpointID = focusedPick.automationBreakpointID,
                  let trackLayout = trackLayoutsByID[trackID] else { break }

            if let containerID = focusedPick.containerID,
               let (_, containerLayout) = containerLayoutsByID[containerID],
               let lane = containerLayout.container.automationLanes.first(where: { $0.id == laneID }),
               let breakpoint = lane.breakpoints.first(where: { $0.id == breakpointID }),
               let laneRect = automationLaneRect(
                    trackLayout: trackLayout,
                    containerLayout: containerLayout,
                    lane: lane,
                    snapshot: snapshot
               ) {
                appendFocusedAutomationBreakpoint(
                    breakpoint: breakpoint,
                    laneRect: laneRect,
                    containerRect: containerLayout.rect,
                    containerLengthBars: containerLayout.container.lengthBars,
                    trackID: trackID,
                    laneID: laneID,
                    laneColor: automationLaneColor(at: laneColorIndex(trackLayout: trackLayout, containerID: containerID, laneID: laneID)),
                    rects: &rects
                )
            } else if let laneIndex = trackLayout.track.trackAutomationLanes.firstIndex(where: { $0.id == laneID }),
                      laneIndex < trackLayout.automationLaneLayouts.count {
                let lane = trackLayout.track.trackAutomationLanes[laneIndex]
                guard let breakpoint = lane.breakpoints.first(where: { $0.id == breakpointID }) else { break }
                let laneRect = trackLayout.automationLaneLayouts[laneIndex].rect
                appendFocusedTrackAutomationBreakpoint(
                    breakpoint: breakpoint,
                    laneRect: laneRect,
                    pixelsPerBar: snapshot.pixelsPerBar,
                    laneColor: automationLaneColor(at: laneIndex),
                    rects: &rects
                )
            }

        default:
            break
        }

        focusRectBuffer = focusRectBufferStorage.write(rects, device: device)
        focusRectCount = rects.count
        focusLineBuffer = focusLineBufferStorage.write(lines, device: device)
        focusLineCount = lines.count
        focusMIDIBuffer = focusMIDIBufferStorage.write(midiNotes, device: device)
        focusMIDICount = midiNotes.count
    }

    private func selectWaveformLevel(
        levels: [PlaybackGridWaveformCache.Level],
        targetPeakCount: Int
    ) -> PlaybackGridWaveformCache.Level? {
        guard !levels.isEmpty else { return nil }
        guard targetPeakCount > 0 else { return levels[0] }
        return levels.first(where: { $0.extrema.count <= targetPeakCount })
    }

    private func selectWaveformResidencyLevel(
        levels: [PlaybackGridWaveformResidencyCache.Level],
        mode: PlaybackGridWaveformResidencyCache.Mode,
        targetPeakCount: Int
    ) -> PlaybackGridWaveformResidencyCache.Level? {
        let matching = levels.filter { $0.mode == mode }
        guard !matching.isEmpty else { return nil }
        guard targetPeakCount > 0 else { return matching[0] }
        return matching.first(where: { $0.count <= targetPeakCount }) ?? matching.last
    }

    private func selectWaveformExtrema(
        levels: [PlaybackGridWaveformCache.Level],
        targetPeakCount: Int
    ) -> [WaveformExtrema] {
        guard !levels.isEmpty else { return [] }
        guard targetPeakCount > 0 else { return levels[0].extrema }

        // Prefer a cached LOD close to the visible density to avoid rebuilding
        // downsampled arrays during every draw.
        if let match = selectWaveformLevel(levels: levels, targetPeakCount: targetPeakCount) {
            return match.extrema
        }

        let source = levels.last?.extrema ?? levels[0].extrema
        guard source.count > targetPeakCount else { return source }
        return downsampleWaveformExtrema(source, to: targetPeakCount)
    }

    private func selectWaveformRMS(
        levels: [PlaybackGridWaveformCache.Level],
        targetPeakCount: Int
    ) -> [Float] {
        guard !levels.isEmpty else { return [] }
        guard targetPeakCount > 0 else { return levels[0].rms }

        if let match = selectWaveformLevel(levels: levels, targetPeakCount: targetPeakCount) {
            return match.rms
        }

        let source = levels.last?.rms ?? levels[0].rms
        guard source.count > targetPeakCount else { return source }
        return downsampleWaveformRMS(source, to: targetPeakCount)
    }

    private func targetWaveformPeakCount(containerWidthPx: Float, detailed: Bool) -> Int {
        guard containerWidthPx > 0 else { return 4 }
        if detailed {
            // Signed extrema only make sense once the source density approaches
            // the visible pixel density. Cap aggressively to keep zooming smooth.
            return max(4, min(Int(ceil(containerWidthPx * 0.72)), 2048))
        }

        // Overview/edit zoom should still read as a continuous silhouette.
        return max(8, min(Int(ceil(containerWidthPx * 0.9)), 1536))
    }

    private func waveformRenderMode(sourceExtremaCount: Int, waveformWidth: Float) -> PlaybackGridWaveformRenderMode {
        guard sourceExtremaCount > 0, waveformWidth > 0 else { return .envelope }
        let extremaPerPixel = Float(sourceExtremaCount) / max(waveformWidth, 1)
        // Stay in mirrored-envelope mode until the user is very close to
        // true detail zoom.
        return extremaPerPixel <= 0.12 ? .detailedExtrema : .envelope
    }

    private func hasVisibleWaveformCore(rms: [Float]) -> Bool {
        rms.contains { $0 > 0.01 }
    }

    private func downsampleWaveformExtrema(_ extrema: [WaveformExtrema], to targetCount: Int) -> [WaveformExtrema] {
        guard !extrema.isEmpty, targetCount > 0, extrema.count > targetCount else { return extrema }

        var downsampled = [WaveformExtrema]()
        downsampled.reserveCapacity(targetCount)
        for i in 0..<targetCount {
            let start = i * extrema.count / targetCount
            let end = max(start + 1, ((i + 1) * extrema.count) / targetCount)
            var minimum: Float = .greatestFiniteMagnitude
            var maximum: Float = -.greatestFiniteMagnitude
            for j in start..<min(end, extrema.count) {
                minimum = min(minimum, extrema[j].minimum)
                maximum = max(maximum, extrema[j].maximum)
            }
            downsampled.append(WaveformExtrema(minimum: minimum, maximum: maximum))
        }
        return downsampled
    }

    private func downsampleWaveformRMS(_ rms: [Float], to targetCount: Int) -> [Float] {
        guard !rms.isEmpty, targetCount > 0, rms.count > targetCount else { return rms }

        var downsampled: [Float] = []
        downsampled.reserveCapacity(targetCount)
        for i in 0..<targetCount {
            let start = i * rms.count / targetCount
            let end = max(start + 1, ((i + 1) * rms.count) / targetCount)
            var sumSquares: Float = 0
            var count: Float = 0
            for j in start..<min(end, rms.count) {
                sumSquares += rms[j] * rms[j]
                count += 1
            }
            downsampled.append(count > 0 ? sqrt(sumSquares / count) : 0)
        }
        return downsampled
    }

    private func symmetricExtrema(from peaks: [Float]) -> [WaveformExtrema] {
        peaks.map { peak in
            let amplitude = abs(peak)
            return WaveformExtrema(minimum: -amplitude, maximum: amplitude)
        }
    }

    private func symmetricEnvelope(from extrema: [WaveformExtrema]) -> [WaveformExtrema] {
        extrema.map { sample in
            let amplitude = max(abs(sample.minimum), abs(sample.maximum))
            return WaveformExtrema(minimum: -amplitude, maximum: amplitude)
        }
    }

    private func smoothEnvelope(_ extrema: [WaveformExtrema]) -> [WaveformExtrema] {
        guard extrema.count > 2 else { return extrema }
        let amplitudes = extrema.map { max(abs($0.minimum), abs($0.maximum)) }
        let smoothed = smoothRMS(amplitudes)
        return smoothed.map { WaveformExtrema(minimum: -$0, maximum: $0) }
    }

    private func smoothRMS(_ values: [Float]) -> [Float] {
        guard values.count > 2 else { return values }
        var output = values
        for index in values.indices {
            let left = values[max(index - 1, values.startIndex)]
            let center = values[index]
            let right = values[min(index + 1, values.index(before: values.endIndex))]
            output[index] = (left * 0.22) + (center * 0.56) + (right * 0.22)
        }
        return output
    }

    private func applyWaveformFades(
        extrema: [WaveformExtrema],
        waveformWidth: Float,
        containerWidth: Float,
        enterFade: FadeSettings?,
        exitFade: FadeSettings?,
        enterFadeWidth: Float,
        exitFadeWidth: Float
    ) -> [WaveformExtrema] {
        guard !extrema.isEmpty else { return extrema }
        guard enterFadeWidth > 0 || exitFadeWidth > 0 else { return extrema }

        var adjusted = extrema
        let peakCount = adjusted.count
        for i in 0..<peakCount {
            let peakX = (Float(i) + 0.5) / Float(peakCount) * waveformWidth
            var gain: Float = 1.0
            if enterFadeWidth > 0, let enterFade, peakX < enterFadeWidth {
                let t = Double(peakX / enterFadeWidth)
                gain *= Float(enterFade.curve.gain(at: t))
            }
            if exitFadeWidth > 0, let exitFade, containerWidth - peakX < exitFadeWidth {
                let t = Double((containerWidth - peakX) / exitFadeWidth)
                gain *= Float(exitFade.curve.gain(at: t))
            }
            if gain < 1.0 {
                adjusted[i].minimum *= gain
                adjusted[i].maximum *= gain
            }
        }
        return adjusted
    }

    private func applyWaveformFadesToRMS(
        _ rms: [Float],
        waveformWidth: Float,
        containerWidth: Float,
        enterFade: FadeSettings?,
        exitFade: FadeSettings?,
        enterFadeWidth: Float,
        exitFadeWidth: Float
    ) -> [Float] {
        guard !rms.isEmpty else { return rms }
        let faded = applyWaveformFades(
            extrema: rms.map { WaveformExtrema(minimum: -$0, maximum: $0) },
            waveformWidth: waveformWidth,
            containerWidth: containerWidth,
            enterFade: enterFade,
            exitFade: exitFade,
            enterFadeWidth: enterFadeWidth,
            exitFadeWidth: exitFadeWidth
        )
        return faded.map { max(abs($0.minimum), abs($0.maximum)) }
    }

    private func appendWaveformEnvelopeRects(
        extrema: [WaveformExtrema],
        color: SIMD4<Float>,
        origin: SIMD2<Float>,
        waveformWidth: Float,
        containerHeight: Float,
        widthScale: Float,
        into rects: inout [PlaybackGridRectInstance]
    ) {
        guard !extrema.isEmpty, waveformWidth > 0, containerHeight > 0 else { return }

        let midY = origin.y + (containerHeight * 0.5)
        let halfHeight = containerHeight * 0.5
        let bucketWidth = waveformWidth / Float(extrema.count)
        let rectWidth = max(1.0, bucketWidth * widthScale)

        for (index, sample) in extrema.enumerated() {
            let minValue = min(max(sample.minimum, -1.0), 1.0)
            let maxValue = min(max(sample.maximum, -1.0), 1.0)
            if max(abs(minValue), abs(maxValue)) <= 0.0008 {
                continue
            }

            let x = origin.x + ((Float(index) + 0.5) / Float(extrema.count)) * waveformWidth
            let topY = midY - (maxValue * halfHeight)
            let bottomY = midY - (minValue * halfHeight)
            rects.append(PlaybackGridRectInstance(
                origin: SIMD2<Float>(x - (rectWidth * 0.5), topY),
                size: SIMD2<Float>(rectWidth, max(bottomY - topY, 1.0)),
                color: color
            ))
        }
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

        midiOverlayBuffer = midiOverlayBufferStorage.write(output, device: device)
        midiOverlayCount = output.count
    }

    public func buildContainerOverlayBuffer(
        scene: PlaybackGridScene,
        snapshot: PlaybackGridSnapshot,
        overlays: [PlaybackGridContainerOverlay]
    ) {
        guard !overlays.isEmpty else {
            containerOverlayRectBuffer = nil
            containerOverlayRectCount = 0
            containerOverlayLineBuffer = nil
            containerOverlayLineCount = 0
            containerOverlayWaveformDrawCalls = []
            containerOverlayWaveformCoreDrawCalls = []
            containerOverlayMIDIBuffer = nil
            containerOverlayMIDICount = 0
            containerOverlayFadeVertexBuffer = nil
            containerOverlayFadeVertexCount = 0
            containerOverlayFadeDrawCalls = []
            containerOverlayBorderBuffer = nil
            containerOverlayBorderCount = 0
            return
        }

        var trackLayoutsByID: [ID<Track>: PlaybackGridTrackLayout] = [:]
        var containerLayoutsByID: [ID<Container>: PlaybackGridContainerLayout] = [:]
        var midiLayoutsByTrack: [ID<Track>: PlaybackGridMIDIResolvedLayout] = [:]
        for trackLayout in scene.trackLayouts {
            trackLayoutsByID[trackLayout.track.id] = trackLayout
            for containerLayout in trackLayout.containers {
                containerLayoutsByID[containerLayout.container.id] = containerLayout
            }
            if trackLayout.track.kind == .midi {
                let inlineMIDILaneHeight = snapshot.inlineMIDILaneHeights[trackLayout.track.id] ?? 0
                let laneHeight = inlineMIDILaneHeight > 0
                    ? inlineMIDILaneHeight
                    : (snapshot.trackHeights[trackLayout.track.id] ?? snapshot.defaultTrackHeight)
                midiLayoutsByTrack[trackLayout.track.id] = PlaybackGridMIDIViewResolver.resolveTrackLayout(
                    trackLayout: trackLayout,
                    laneHeight: laneHeight,
                    snapshot: snapshot
                )
            }
        }

        let ppb = Float(snapshot.pixelsPerBar)
        var rects: [PlaybackGridRectInstance] = []
        var lines: [PlaybackGridLineInstance] = []
        var wfDrawCalls: [PlaybackGridWaveformDrawCall] = []
        var wfCoreDrawCalls: [PlaybackGridWaveformDrawCall] = []
        var midiNotes: [PlaybackGridMIDINoteInstance] = []
        var fadeVerts: [PlaybackGridFadeVertex] = []
        var fadeCalls: [(offset: Int, count: Int)] = []
        var borders: [PlaybackGridRectInstance] = []

        rects.reserveCapacity(overlays.count * 5)
        lines.reserveCapacity(overlays.count * 8)
        midiNotes.reserveCapacity(overlays.count * 16)
        borders.reserveCapacity(overlays.count * 4)

        for overlay in overlays {
            guard let trackLayout = trackLayoutsByID[overlay.trackID] else { continue }
            let baseLayout = containerLayoutsByID[overlay.containerID]
            let rect = CGRect(
                x: CGFloat(overlay.container.startBar - 1.0) * snapshot.pixelsPerBar,
                y: trackLayout.yOrigin,
                width: CGFloat(overlay.container.lengthBars) * snapshot.pixelsPerBar,
                height: trackLayout.clipHeight
            )
            guard rect.width > 0.5, rect.height > 0.5 else { continue }

            let trackColors = PlaybackGridTrackMetalColors(kind: trackLayout.track.kind)
            let fillColor = overlay.isGhost
                ? withAlpha(trackColors.fillSelected, 0.18)
                : withAlpha(trackColors.fillFocused, 0.52)
            let borderColor = overlay.isGhost
                ? withAlpha(trackColors.borderSelected, 0.42)
                : withAlpha(trackColors.borderFocused, 0.98)
            let waveformColor = overlay.isGhost
                ? withAlpha(trackColors.waveformFill, 0.48)
                : withAlpha(trackColors.waveformFocused, 0.98)

            let origin = SIMD2<Float>(Float(rect.minX), Float(rect.minY))
            let size = SIMD2<Float>(Float(rect.width), Float(rect.height))
            let fillOrigin = SIMD2<Float>(origin.x, origin.y + 1)
            let fillSize = SIMD2<Float>(size.x, max(size.y - 2, 1))

            rects.append(PlaybackGridRectInstance(
                origin: SIMD2(fillOrigin.x - 1.5, max(fillOrigin.y - 1.5, 0)),
                size: SIMD2(fillSize.x + 3, fillSize.y + 3),
                color: overlay.isGhost ? withAlpha(trackColors.focusGlow, 0.10) : withAlpha(trackColors.focusGlow, 0.24),
                cornerRadius: 6
            ))
            rects.append(PlaybackGridRectInstance(origin: fillOrigin, size: fillSize, color: fillColor))
            borders.append(PlaybackGridRectInstance(
                origin: fillOrigin,
                size: fillSize,
                color: borderColor,
                cornerRadius: 4,
                borderWidth: overlay.isGhost ? 1.0 : 1.6
            ))

            let waveformExtrema = overlay.waveformExtrema
                ?? baseLayout?.waveformExtrema
                ?? overlay.waveformPeaks.map { symmetricExtrema(from: $0) }
                ?? baseLayout?.waveformPeaks.map { symmetricExtrema(from: $0) }
            let waveformRMS = overlay.waveformRMS
                ?? baseLayout?.waveformRMS
            if let extrema = waveformExtrema, !extrema.isEmpty, fillSize.x >= 4 {
                let maxPeaks = targetWaveformPeakCount(
                    containerWidthPx: fillSize.x,
                    detailed: true
                )
                let visibleAudioBars = max(0.0001, min(
                    overlay.container.lengthBars,
                    ((overlay.audioDurationBars ?? baseLayout?.audioDurationBars) ?? overlay.container.lengthBars)
                        - overlay.container.audioStartOffset
                ))
                let paramsBase = PlaybackGridWaveformParams(
                    containerOrigin: SIMD2(Float(overlay.container.startBar - 1.0), fillOrigin.y),
                    containerSize: SIMD2(Float(overlay.container.lengthBars), fillSize.y),
                    fillColor: waveformColor,
                    peakOffset: 0,
                    peakCount: 0,
                    amplitude: overlay.isGhost ? 0.82 : 0.98,
                    visibleBars: Float(visibleAudioBars),
                    audioStartOffsetBars: Float(overlay.container.audioStartOffset),
                    clipLengthBars: Float(overlay.container.lengthBars),
                    enterFadeBars: Float(overlay.container.enterFade?.duration ?? 0),
                    exitFadeBars: Float(overlay.container.exitFade?.duration ?? 0),
                    reserved: .zero
                )
                if let recordingID = overlay.container.sourceRecordingID,
                   (overlay.waveformExtrema != nil || baseLayout?.waveformExtrema != nil),
                   let residency = waveformResidencyCache.residency(
                        for: recordingID,
                        extrema: extrema,
                        rms: waveformRMS ?? [],
                        device: device
                   ),
                   let envelopeLevel = selectWaveformResidencyLevel(
                        levels: residency.levels,
                        mode: .envelope,
                        targetPeakCount: maxPeaks
                   ) {
                    var params = paramsBase
                    params.peakOffset = UInt32(envelopeLevel.offset)
                    params.peakCount = UInt32(envelopeLevel.count)
                    wfDrawCalls.append(PlaybackGridWaveformDrawCall(buffer: residency.buffer, params: params))

                    if let rmsLevel = selectWaveformResidencyLevel(
                        levels: residency.levels,
                        mode: .rms,
                        targetPeakCount: maxPeaks
                    ) {
                        var coreParams = paramsBase
                        coreParams.fillColor = overlay.isGhost
                            ? withAlpha(trackColors.waveformFill, 0.12)
                            : withAlpha(trackColors.waveformFocused, 0.20)
                        coreParams.peakOffset = UInt32(rmsLevel.offset)
                        coreParams.peakCount = UInt32(rmsLevel.count)
                        coreParams.amplitude = overlay.isGhost ? 0.64 : 0.78
                        wfCoreDrawCalls.append(PlaybackGridWaveformDrawCall(buffer: residency.buffer, params: coreParams))
                    }
                } else {
                    let fallbackExtrema = downsampleWaveformExtrema(extrema, to: maxPeaks)
                    if let buffer = makeBuffer(fallbackExtrema.map { SIMD2<Float>($0.minimum, $0.maximum) }) {
                        var params = paramsBase
                        params.peakCount = UInt32(fallbackExtrema.count)
                        wfDrawCalls.append(PlaybackGridWaveformDrawCall(buffer: buffer, params: params))
                    }
                }
            }

            let resolvedNotes = overlay.resolvedMIDINotes ?? baseLayout?.resolvedMIDINotes
            if let resolvedNotes, !resolvedNotes.isEmpty {
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
                    notes: resolvedNotes,
                    container: overlay.container,
                    rect: midiRect,
                    resolved: resolved,
                    color: waveformColor,
                    selectedNoteIDs: snapshot.selectedMIDINoteIDs,
                    focusedPick: .none,
                    timeSignature: snapshot.timeSignature,
                    into: &midiNotes
                )
            }

            if overlay.container.enterFade != nil || overlay.container.exitFade != nil {
                buildFadeOverlay(
                    enterFade: overlay.container.enterFade,
                    exitFade: overlay.container.exitFade,
                    rect: rect,
                    pixelsPerBar: ppb,
                    into: &fadeVerts,
                    calls: &fadeCalls,
                    lines: &lines
                )
            }
        }

        containerOverlayRectBuffer = containerOverlayRectBufferStorage.write(rects, device: device)
        containerOverlayRectCount = rects.count
        containerOverlayLineBuffer = containerOverlayLineBufferStorage.write(lines, device: device)
        containerOverlayLineCount = lines.count
        containerOverlayWaveformDrawCalls = wfDrawCalls
        containerOverlayWaveformCoreDrawCalls = wfCoreDrawCalls
        containerOverlayMIDIBuffer = containerOverlayMIDIBufferStorage.write(midiNotes, device: device)
        containerOverlayMIDICount = midiNotes.count
        containerOverlayFadeVertexBuffer = containerOverlayFadeVertexBufferStorage.write(fadeVerts, device: device)
        containerOverlayFadeVertexCount = fadeVerts.count
        containerOverlayFadeDrawCalls = fadeCalls
        containerOverlayBorderBuffer = containerOverlayBorderBufferStorage.write(borders, device: device)
        containerOverlayBorderCount = borders.count
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

        automationOverlayLineBuffer = automationOverlayLineBufferStorage.write(lines, device: device)
        automationOverlayLineCount = lines.count
        automationOverlayRectBuffer = automationOverlayRectBufferStorage.write(rects, device: device)
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

        automationShapeOverlayLineBuffer = automationShapeOverlayLineBufferStorage.write(lines, device: device)
        automationShapeOverlayLineCount = lines.count
        automationShapeOverlayRectBuffer = automationShapeOverlayRectBufferStorage.write(rects, device: device)
        automationShapeOverlayRectCount = rects.count
    }

    public func encode(
        into encoder: MTLRenderCommandEncoder,
        visibleRect: CGRect,
        canvasHeight: CGFloat,
        viewportSize: MTLSize,
        pixelsPerBar: CGFloat,
        timeSignature: TimeSignature,
        showRulerAndSections: Bool,
        selectedRange: ClosedRange<Int>?
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

        var gridUniforms = PlaybackGridProceduralGridUniforms(
            visibleMinX: Float(visibleRect.minX),
            visibleMaxX: Float(visibleRect.maxX),
            visibleMinY: Float(visibleRect.minY),
            visibleMaxY: Float(visibleRect.maxY),
            pixelsPerBar: Float(pixelsPerBar),
            beatsPerBar: UInt32(timeSignature.beatsPerBar),
            rulerHeight: Float(PlaybackGridLayout.rulerHeight),
            sectionLaneHeight: Float(PlaybackGridLayout.sectionLaneHeight),
            trackAreaTop: Float(PlaybackGridLayout.trackAreaTop),
            showRulerAndSections: showRulerAndSections ? 1 : 0,
            selectedRangeStartBar: Int32(selectedRange?.lowerBound ?? 0),
            selectedRangeLength: Int32(selectedRange?.count ?? 0)
        )
        encoder.setRenderPipelineState(proceduralGridPipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&gridUniforms, length: MemoryLayout<PlaybackGridProceduralGridUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

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

        if !waveformDrawCalls.isEmpty {
            encoder.setRenderPipelineState(waveformPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            var currentPeakBuffer: MTLBuffer?

            for drawCall in waveformDrawCalls {
                if currentPeakBuffer !== drawCall.buffer {
                    encoder.setVertexBuffer(drawCall.buffer, offset: 0, index: 2)
                    currentPeakBuffer = drawCall.buffer
                }
                var params = drawCall.params
                encoder.setVertexBytes(&params, length: MemoryLayout<PlaybackGridWaveformParams>.stride, index: 1)
                let vertexCount = Int(params.peakCount) * 2
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCount)
            }
        }

        if !waveformCoreDrawCalls.isEmpty {
            encoder.setRenderPipelineState(waveformPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            var currentPeakBuffer: MTLBuffer?

            for drawCall in waveformCoreDrawCalls {
                if currentPeakBuffer !== drawCall.buffer {
                    encoder.setVertexBuffer(drawCall.buffer, offset: 0, index: 2)
                    currentPeakBuffer = drawCall.buffer
                }
                var params = drawCall.params
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

        if focusMIDICount > 0, let buf = focusMIDIBuffer {
            encoder.setRenderPipelineState(midiPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: focusMIDICount
            )
        }

        if focusLineCount > 0, let buf = focusLineBuffer {
            encoder.setRenderPipelineState(linePipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: focusLineCount
            )
        }

        if focusRectCount > 0, let buf = focusRectBuffer {
            encoder.setRenderPipelineState(rectPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: focusRectCount
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

        if containerOverlayRectCount > 0, let buf = containerOverlayRectBuffer {
            encoder.setRenderPipelineState(rectPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: containerOverlayRectCount
            )
        }

        if !containerOverlayWaveformDrawCalls.isEmpty {
            encoder.setRenderPipelineState(waveformPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            var currentPeakBuffer: MTLBuffer?

            for drawCall in containerOverlayWaveformDrawCalls {
                if currentPeakBuffer !== drawCall.buffer {
                    encoder.setVertexBuffer(drawCall.buffer, offset: 0, index: 2)
                    currentPeakBuffer = drawCall.buffer
                }
                var params = drawCall.params
                encoder.setVertexBytes(&params, length: MemoryLayout<PlaybackGridWaveformParams>.stride, index: 1)
                let vertexCount = Int(params.peakCount) * 2
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCount)
            }
        }

        if !containerOverlayWaveformCoreDrawCalls.isEmpty {
            encoder.setRenderPipelineState(waveformPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            var currentPeakBuffer: MTLBuffer?

            for drawCall in containerOverlayWaveformCoreDrawCalls {
                if currentPeakBuffer !== drawCall.buffer {
                    encoder.setVertexBuffer(drawCall.buffer, offset: 0, index: 2)
                    currentPeakBuffer = drawCall.buffer
                }
                var params = drawCall.params
                encoder.setVertexBytes(&params, length: MemoryLayout<PlaybackGridWaveformParams>.stride, index: 1)
                let vertexCount = Int(params.peakCount) * 2
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCount)
            }
        }

        if containerOverlayMIDICount > 0, let buf = containerOverlayMIDIBuffer {
            encoder.setRenderPipelineState(midiPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: containerOverlayMIDICount
            )
        }

        if containerOverlayLineCount > 0, let buf = containerOverlayLineBuffer {
            encoder.setRenderPipelineState(linePipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: containerOverlayLineCount
            )
        }

        if containerOverlayFadeVertexCount > 0, let buf = containerOverlayFadeVertexBuffer {
            encoder.setRenderPipelineState(fadePipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            for call in containerOverlayFadeDrawCalls {
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: call.offset, vertexCount: call.count)
            }
        }

        if containerOverlayBorderCount > 0, let buf = containerOverlayBorderBuffer {
            encoder.setRenderPipelineState(rectPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PlaybackGridUniforms>.stride, index: 0)
            encoder.setVertexBuffer(buf, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: quadIndexBuffer,
                indexBufferOffset: 0,
                instanceCount: containerOverlayBorderCount
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
        selectedNoteIDs: Set<ID<MIDINoteEvent>>,
        focusedPick: GridPickObject,
        timeSignature: TimeSignature,
        into output: inout [PlaybackGridMIDINoteInstance]
    ) {
        let focusedNoteID: ID<MIDINoteEvent>? =
            focusedPick.kind == .midiNote && focusedPick.containerID == container.id
            ? focusedPick.midiNoteID
            : nil
        let noteBaseColor = SIMD4<Float>(0.88, 0.38, 0.70, 0.98)
        let noteFocusedColor = SIMD4<Float>(0.98, 0.63, 0.87, 1.0)
        let noteBorderColor = SIMD4<Float>(0.11, 0.06, 0.12, 0.94)

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
            let isSelected = selectedNoteIDs.contains(note.id)
            let isFocused = focusedNoteID == note.id || isSelected
            let velocityTint = max(Float(note.velocity) / 127.0, 0.18)

            let bodyColor = isFocused
                ? noteFocusedColor
                : SIMD4(
                    ((noteBaseColor.x * 0.68) + (color.x * 0.32)) * (0.80 + velocityTint * 0.20),
                    ((noteBaseColor.y * 0.68) + (color.y * 0.32)) * (0.76 + velocityTint * 0.24),
                    ((noteBaseColor.z * 0.68) + (color.z * 0.32)) * (0.78 + velocityTint * 0.22),
                    0.68 + (velocityTint * 0.30)
                )

            let shadowOffset: Float = isFocused ? 1.8 : 1.1
            // Keep notes mostly rectangular (Bitwig-style) and avoid diamond/pill
            // silhouettes for short notes.
            let outerRadius = max(0.8, min(noteH * 0.12, noteW * 0.06))
            let innerRadius = max(0.7, min(outerRadius, noteH * 0.10))
            let shineRadius = max(0.6, min(innerRadius, noteH * 0.08))
            output.append(PlaybackGridMIDINoteInstance(
                origin: SIMD2(noteX, noteY + shadowOffset),
                size: SIMD2(noteW, noteH),
                color: SIMD4(0, 0, 0, isFocused ? 0.28 : 0.18),
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
                size: SIMD2(max(noteW - 3, 2), max(min(noteH * 0.22, noteH - 2), 1)),
                color: SIMD4(1.0, 0.90, 0.97, isFocused ? 0.54 : 0.24),
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

    private func appendMIDIDetailLaneBackground(
        lane: PlaybackGridMIDIConfig.DetailLane,
        laneRect: CGRect,
        rects: inout [PlaybackGridRectInstance],
        lines: inout [PlaybackGridLineInstance]
    ) {
        let tint: SIMD4<Float>
        switch lane.lane {
        case .velocity:
            tint = SIMD4(0.16, 0.26, 0.18, 0.36)
        case .channel:
            tint = SIMD4(0.18, 0.18, 0.22, 0.32)
        case .sustain:
            tint = SIMD4(0.16, 0.20, 0.24, 0.34)
        case .expression:
            tint = SIMD4(0.22, 0.18, 0.16, 0.34)
        }

        rects.append(PlaybackGridRectInstance(
            origin: SIMD2(Float(laneRect.minX), Float(laneRect.minY)),
            size: SIMD2(Float(laneRect.width), Float(laneRect.height)),
            color: tint
        ))
        lines.append(PlaybackGridLineInstance(
            start: SIMD2(Float(laneRect.minX), Float(laneRect.minY)),
            end: SIMD2(Float(laneRect.maxX), Float(laneRect.minY)),
            color: SIMD4(1, 1, 1, 0.06),
            width: 1
        ))
        let midY = Float(laneRect.midY)
        lines.append(PlaybackGridLineInstance(
            start: SIMD2(Float(laneRect.minX), midY),
            end: SIMD2(Float(laneRect.maxX), midY),
            color: SIMD4(1, 1, 1, 0.035),
            width: 1
        ))

        if lane.lane == .velocity {
            let guideFractions: [CGFloat] = [1.0, 0.75, 0.5, 0.25, 0.0]
            for fraction in guideFractions {
                let y = laneRect.maxY - (laneRect.height * fraction)
                let emphasis = abs(fraction - 0.5) < 0.001
                lines.append(PlaybackGridLineInstance(
                    start: SIMD2(Float(laneRect.minX), Float(y)),
                    end: SIMD2(Float(laneRect.maxX), Float(y)),
                    color: emphasis
                        ? SIMD4(0.62, 0.98, 0.74, 0.14)
                        : SIMD4(1, 1, 1, 0.05),
                    width: emphasis ? 1.2 : 1
                ))
            }
        }
    }

    private func mergedMIDIDetailLaneNotes(
        baseNotes: [MIDINoteEvent],
        containerID: ID<Container>,
        trackID: ID<Track>,
        overlays: [PlaybackGridMIDINoteOverlay]
    ) -> [MIDINoteEvent] {
        guard !overlays.isEmpty else { return baseNotes }

        var mergedByID: [ID<MIDINoteEvent>: MIDINoteEvent] = [:]
        mergedByID.reserveCapacity(baseNotes.count + overlays.count)
        for note in baseNotes {
            mergedByID[note.id] = note
        }
        for overlay in overlays where overlay.containerID == containerID && overlay.trackID == trackID && !overlay.isGhost {
            mergedByID[overlay.note.id] = overlay.note
        }

        var merged: [MIDINoteEvent] = []
        merged.reserveCapacity(mergedByID.count)
        for note in baseNotes {
            if let updated = mergedByID.removeValue(forKey: note.id) {
                merged.append(updated)
            }
        }
        if !mergedByID.isEmpty {
            merged.append(contentsOf: mergedByID.values.sorted { lhs, rhs in
                if lhs.startBeat == rhs.startBeat {
                    return lhs.pitch < rhs.pitch
                }
                return lhs.startBeat < rhs.startBeat
            })
        }
        return merged
    }

    private func appendMIDIDetailLaneData(
        notes: [MIDINoteEvent],
        container: Container,
        noteRect: CGRect,
        detailLanes: [PlaybackGridMIDIConfig.DetailLane],
        resolved: PlaybackGridMIDIResolvedLayout,
        timeSignature: TimeSignature,
        selectedNoteIDs: Set<ID<MIDINoteEvent>>,
        focusedPick: GridPickObject,
        rects: inout [PlaybackGridRectInstance],
        lines: inout [PlaybackGridLineInstance]
    ) {
        var laneY = noteRect.maxY
        for detailLane in detailLanes {
            let laneRect = CGRect(
                x: noteRect.minX,
                y: laneY,
                width: noteRect.width,
                height: detailLane.height
            )
            if detailLane.lane == .velocity {
                appendMIDIVelocityLane(
                    notes: notes,
                    container: container,
                    noteRect: noteRect,
                    laneRect: laneRect,
                    resolved: resolved,
                    timeSignature: timeSignature,
                    selectedNoteIDs: selectedNoteIDs,
                    focusedPick: focusedPick,
                    rects: &rects,
                    lines: &lines
                )
            }
            laneY += detailLane.height
        }
    }

    private func appendMIDIVelocityLane(
        notes: [MIDINoteEvent],
        container: Container,
        noteRect: CGRect,
        laneRect: CGRect,
        resolved: PlaybackGridMIDIResolvedLayout,
        timeSignature: TimeSignature,
        selectedNoteIDs: Set<ID<MIDINoteEvent>>,
        focusedPick: GridPickObject,
        rects: inout [PlaybackGridRectInstance],
        lines: inout [PlaybackGridLineInstance]
    ) {
        let focusedNoteID: ID<MIDINoteEvent>? =
            focusedPick.kind == .midiNote && focusedPick.containerID == container.id
            ? focusedPick.midiNoteID
            : nil

        for note in notes {
            guard let renderedNoteRect = PlaybackGridMIDIViewResolver.noteRect(
                note: note,
                containerLengthBars: container.lengthBars,
                laneRect: noteRect,
                timeSignature: timeSignature,
                resolved: resolved
            ) else { continue }
            let x = min(max(renderedNoteRect.minX + min(renderedNoteRect.width * 0.25, 10), laneRect.minX + 3), laneRect.maxX - 3)
            let normalized = max(0.0, min(1.0, CGFloat(note.velocity) / 127.0))
            let topY = laneRect.maxY - max(5, normalized * max(laneRect.height - 8, 1))
            let isSelected = selectedNoteIDs.contains(note.id)
            let isFocused = focusedNoteID == note.id
            let isEmphasized = isFocused || isSelected
            let lineColor = isSelected
                ? SIMD4<Float>(1.0, 0.75, 0.90, 0.95)
                : (isFocused
                    ? SIMD4<Float>(1.0, 0.82, 0.94, 0.96)
                    : SIMD4<Float>(0.36, 0.90, 0.54, 0.82))
            let handleColor = isSelected
                ? SIMD4<Float>(1.0, 0.82, 0.94, 0.98)
                : (isFocused
                    ? SIMD4<Float>(1.0, 0.88, 0.96, 1.0)
                    : SIMD4<Float>(0.46, 0.96, 0.62, 0.95))

            if isEmphasized {
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(Float(x - (isFocused ? 7 : 6)), Float(laneRect.minY + 1)),
                    size: SIMD2(isFocused ? 14 : 12, Float(max(laneRect.height - 2, 4))),
                    color: isFocused
                        ? SIMD4<Float>(1.0, 0.72, 0.88, 0.16)
                        : SIMD4<Float>(1.0, 0.80, 0.92, 0.09),
                    cornerRadius: isFocused ? 5 : 4
                ))
            }

            lines.append(PlaybackGridLineInstance(
                start: SIMD2(Float(x), Float(laneRect.maxY - 2)),
                end: SIMD2(Float(x), Float(topY)),
                color: lineColor,
                width: isFocused ? 2.8 : (isSelected ? 2.2 : 1.4)
            ))
            if isEmphasized {
                let glowSize: Float = isFocused ? 14 : 12
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(Float(x) - (glowSize * 0.5), Float(topY) - (glowSize * 0.5)),
                    size: SIMD2(glowSize, glowSize),
                    color: isFocused
                        ? SIMD4<Float>(1.0, 0.78, 0.92, 0.22)
                        : SIMD4<Float>(1.0, 0.82, 0.94, 0.12),
                    cornerRadius: glowSize * 0.5
                ))
            }
            rects.append(PlaybackGridRectInstance(
                origin: SIMD2(Float(x - (isFocused ? 5 : (isSelected ? 4 : 3))), Float(topY - (isFocused ? 5 : (isSelected ? 4 : 3)))),
                size: SIMD2(isFocused ? 10 : (isSelected ? 8 : 6), isFocused ? 10 : (isSelected ? 8 : 6)),
                color: handleColor,
                cornerRadius: isFocused ? 5 : (isSelected ? 4 : 3)
            ))
        }
    }

    private func midiVelocityLaneRect(
        trackLayout: PlaybackGridTrackLayout,
        containerLayout: PlaybackGridContainerLayout,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect? {
        guard let config = snapshot.inlineMIDIConfigs[trackLayout.track.id],
              let velocityLane = config.detailLanes.first(where: { $0.lane == .velocity }) else {
            return nil
        }
        let noteAreaRect = midiEditorRect(
            trackLayout: trackLayout,
            containerRect: containerLayout.rect,
            trackID: trackLayout.track.id,
            snapshot: snapshot
        )
        return CGRect(
            x: noteAreaRect.minX,
            y: noteAreaRect.maxY,
            width: noteAreaRect.width,
            height: velocityLane.height
        )
    }

    private func appendFocusedMIDIVelocityOverlay(
        note: MIDINoteEvent,
        container: Container,
        noteRect: CGRect,
        velocityLaneRect: CGRect,
        resolved: PlaybackGridMIDIResolvedLayout,
        timeSignature: TimeSignature,
        rects: inout [PlaybackGridRectInstance],
        lines: inout [PlaybackGridLineInstance]
    ) {
        guard let renderedNoteRect = PlaybackGridMIDIViewResolver.noteRect(
            note: note,
            containerLengthBars: container.lengthBars,
            laneRect: noteRect,
            timeSignature: timeSignature,
            resolved: resolved
        ) else { return }

        let x = min(max(renderedNoteRect.minX + min(renderedNoteRect.width * 0.25, 10), velocityLaneRect.minX + 3), velocityLaneRect.maxX - 3)
        let normalized = max(0.0, min(1.0, CGFloat(note.velocity) / 127.0))
        let topY = velocityLaneRect.maxY - max(5, normalized * max(velocityLaneRect.height - 8, 1))

        rects.append(PlaybackGridRectInstance(
            origin: SIMD2(Float(x - 8), Float(velocityLaneRect.minY + 1)),
            size: SIMD2(16, Float(max(velocityLaneRect.height - 2, 4))),
            color: SIMD4<Float>(1.0, 0.72, 0.88, 0.12),
            cornerRadius: 5
        ))
        rects.append(PlaybackGridRectInstance(
            origin: SIMD2(Float(x - 7), Float(topY - 7)),
            size: SIMD2(14, 14),
            color: SIMD4<Float>(1.0, 0.78, 0.92, 0.20),
            cornerRadius: 7
        ))
        lines.append(PlaybackGridLineInstance(
            start: SIMD2(Float(x), Float(velocityLaneRect.maxY - 2)),
            end: SIMD2(Float(x), Float(topY)),
            color: SIMD4<Float>(1.0, 0.85, 0.95, 0.96),
            width: 2.8
        ))
        rects.append(PlaybackGridRectInstance(
            origin: SIMD2(Float(x - 5), Float(topY - 5)),
            size: SIMD2(10, 10),
            color: SIMD4<Float>(1.0, 0.92, 0.98, 0.98),
            cornerRadius: 5
        ))
    }

    private func appendFocusedMIDINoteOverlay(
        note: MIDINoteEvent,
        container: Container,
        rect: CGRect,
        resolved: PlaybackGridMIDIResolvedLayout,
        timeSignature: TimeSignature,
        into output: inout [PlaybackGridMIDINoteInstance]
    ) {
        guard let noteRect = PlaybackGridMIDIViewResolver.noteRect(
            note: note,
            containerLengthBars: container.lengthBars,
            laneRect: rect,
            timeSignature: timeSignature,
            resolved: resolved
        ) else { return }

        let noteX = Float(noteRect.minX)
        let noteY = Float(noteRect.minY)
        let noteW = Float(noteRect.width)
        let noteH = Float(noteRect.height)
        let outerRadius = max(0.8, min(noteH * 0.12, noteW * 0.06))
        let glowInset: Float = 3.0

        output.append(PlaybackGridMIDINoteInstance(
            origin: SIMD2(noteX - glowInset, noteY - glowInset),
            size: SIMD2(noteW + (glowInset * 2), noteH + (glowInset * 2)),
            color: SIMD4(1.0, 0.78, 0.90, 0.24),
            cornerRadius: outerRadius + glowInset
        ))
        output.append(PlaybackGridMIDINoteInstance(
            origin: SIMD2(noteX - 1.5, noteY - 1.5),
            size: SIMD2(noteW + 3, noteH + 3),
            color: SIMD4(1.0, 0.86, 0.94, 0.96),
            cornerRadius: outerRadius + 1.5
        ))
    }

    private func appendContainerFocusOverlay(
        containerLayout: PlaybackGridContainerLayout,
        focusedPick: GridPickObject,
        pixelsPerBar: Float,
        rects: inout [PlaybackGridRectInstance]
    ) {
        let rect = containerLayout.rect
        let fillOrigin = SIMD2<Float>(Float(rect.minX), Float(rect.minY) + 1)
        let fillSize = SIMD2<Float>(Float(rect.width), max(Float(rect.height) - 2, 1))

        rects.append(PlaybackGridRectInstance(
            origin: SIMD2(fillOrigin.x - 1.5, fillOrigin.y - 1.5),
            size: SIMD2(fillSize.x + 3, fillSize.y + 3),
            color: SIMD4(1.0, 1.0, 1.0, 0.16),
            cornerRadius: 6
        ))
        rects.append(PlaybackGridRectInstance(
            origin: SIMD2(fillOrigin.x - 0.8, fillOrigin.y - 0.8),
            size: SIMD2(fillSize.x + 1.6, fillSize.y + 1.6),
            color: SIMD4(0.90, 0.96, 1.0, 0.92),
            cornerRadius: 5,
            borderWidth: 1.4
        ))

        let handleSize: Float = 7
        let handleRadius = handleSize / 2
        let handleY = fillOrigin.y - handleRadius
        let enterW = containerLayout.enterFade.map { Float($0.duration) * pixelsPerBar } ?? 0
        let exitW = containerLayout.exitFade.map { Float($0.duration) * pixelsPerBar } ?? 0
        let enterHandleOrigin = SIMD2(fillOrigin.x + enterW - handleRadius, handleY)
        let exitHandleOrigin = SIMD2(fillOrigin.x + fillSize.x - exitW - handleRadius, handleY)
        let focusedLeft = focusedPick.zone == .fadeLeft
        let focusedRight = focusedPick.zone == .fadeRight

        appendFadeHandleOverlay(
            origin: enterHandleOrigin,
            focused: focusedLeft,
            rects: &rects
        )
        appendFadeHandleOverlay(
            origin: exitHandleOrigin,
            focused: focusedRight,
            rects: &rects
        )
    }

    private func appendFadeHandleOverlay(
        origin: SIMD2<Float>,
        focused: Bool,
        rects: inout [PlaybackGridRectInstance]
    ) {
        let handleSize: Float = 7
        let handleRadius = handleSize / 2
        if focused {
            rects.append(PlaybackGridRectInstance(
                origin: SIMD2(origin.x - 2, origin.y - 2),
                size: SIMD2(handleSize + 4, handleSize + 4),
                color: SIMD4(1, 1, 1, 0.28),
                cornerRadius: handleRadius + 2
            ))
        }
        rects.append(PlaybackGridRectInstance(
            origin: origin,
            size: SIMD2(handleSize, handleSize),
            color: focused ? SIMD4(1, 1, 1, 1) : SIMD4(1, 1, 1, 0.88),
            cornerRadius: handleRadius
        ))
    }

    private func laneColorIndex(
        trackLayout: PlaybackGridTrackLayout,
        containerID: ID<Container>?,
        laneID: ID<AutomationLane>
    ) -> Int {
        if let containerID,
           let containerLayout = trackLayout.containers.first(where: { $0.container.id == containerID }),
           let lane = containerLayout.container.automationLanes.first(where: { $0.id == laneID }) {
            let paths = orderedAutomationPaths(for: trackLayout.track)
            return max(0, paths.firstIndex(of: lane.targetPath) ?? 0)
        }

        if let lane = trackLayout.track.trackAutomationLanes.first(where: { $0.id == laneID }) {
            let paths = orderedAutomationPaths(for: trackLayout.track)
            return max(0, paths.firstIndex(of: lane.targetPath) ?? 0)
        }

        return 0
    }

    private func orderedAutomationPaths(for track: Track) -> [EffectPath] {
        var seen = Set<EffectPath>()
        var ordered: [EffectPath] = []
        for lane in track.trackAutomationLanes {
            if seen.insert(lane.targetPath).inserted {
                ordered.append(lane.targetPath)
            }
        }
        for container in track.containers {
            for lane in container.automationLanes {
                if seen.insert(lane.targetPath).inserted {
                    ordered.append(lane.targetPath)
                }
            }
        }
        return ordered
    }

    private func automationLaneRect(
        trackLayout: PlaybackGridTrackLayout,
        containerLayout: PlaybackGridContainerLayout,
        lane: AutomationLane,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect? {
        if trackLayout.automationLaneLayouts.isEmpty {
            let lanes = containerLayout.container.automationLanes
            guard let laneIndex = lanes.firstIndex(where: { $0.id == lane.id }) else { return nil }
            let rect = containerLayout.rect
            let automationBandHeight: CGFloat
            if snapshot.selectedAutomationTool == .pointer {
                automationBandHeight = min(rect.height, max(24, rect.height * 0.42))
            } else {
                automationBandHeight = rect.height
            }
            let laneHeight = max(automationBandHeight / CGFloat(max(lanes.count, 1)), 1)
            return CGRect(
                x: rect.minX,
                y: rect.minY + (CGFloat(laneIndex) * laneHeight),
                width: rect.width,
                height: laneHeight
            )
        }

        guard let laneLayout = trackLayout.automationLaneLayouts.first(where: { $0.targetPath == lane.targetPath }) else {
            return nil
        }
        return CGRect(
            x: containerLayout.rect.minX,
            y: laneLayout.rect.minY,
            width: containerLayout.rect.width,
            height: laneLayout.rect.height
        )
    }

    private func appendFocusedAutomationBreakpoint(
        breakpoint: AutomationBreakpoint,
        laneRect: CGRect,
        containerRect: CGRect,
        containerLengthBars: Double,
        trackID: ID<Track>,
        laneID: ID<AutomationLane>,
        laneColor: SIMD4<Float>,
        rects: inout [PlaybackGridRectInstance]
    ) {
        let barsToPixels = containerRect.width / max(CGFloat(containerLengthBars), 0.0001)
        let x = Float(containerRect.minX + (CGFloat(breakpoint.position) * barsToPixels))
        let y = Float(laneRect.maxY - (CGFloat(breakpoint.value) * laneRect.height))
        appendAutomationBreakpointFocus(at: SIMD2(x, y), laneColor: laneColor, rects: &rects)
    }

    private func appendFocusedTrackAutomationBreakpoint(
        breakpoint: AutomationBreakpoint,
        laneRect: CGRect,
        pixelsPerBar: CGFloat,
        laneColor: SIMD4<Float>,
        rects: inout [PlaybackGridRectInstance]
    ) {
        let x = Float(CGFloat(breakpoint.position) * pixelsPerBar)
        let y = Float(laneRect.maxY - (CGFloat(breakpoint.value) * laneRect.height))
        appendAutomationBreakpointFocus(at: SIMD2(x, y), laneColor: laneColor, rects: &rects)
    }

    private func appendAutomationBreakpointFocus(
        at point: SIMD2<Float>,
        laneColor: SIMD4<Float>,
        rects: inout [PlaybackGridRectInstance]
    ) {
        rects.append(PlaybackGridRectInstance(
            origin: SIMD2(point.x - 7, point.y - 7),
            size: SIMD2(14, 14),
            color: SIMD4(laneColor.x, laneColor.y, laneColor.z, 0.38),
            cornerRadius: 7
        ))
        rects.append(PlaybackGridRectInstance(
            origin: SIMD2(point.x - 5.2, point.y - 5.2),
            size: SIMD2(10.4, 10.4),
            color: SIMD4(0.10, 0.11, 0.13, 0.92),
            cornerRadius: 5.2
        ))
        rects.append(PlaybackGridRectInstance(
            origin: SIMD2(point.x - 3.8, point.y - 3.8),
            size: SIMD2(7.6, 7.6),
            color: SIMD4(1.0, 1.0, 1.0, 0.98),
            cornerRadius: 3.8
        ))
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
        let noteAreaHeight = snapshot.inlineMIDIConfigs[trackID]?.noteAreaHeight(totalInlineHeight: inlineHeight) ?? inlineHeight
        return CGRect(
            x: rect.minX,
            y: inlineMIDILaneYOrigin(trackLayout: trackLayout, snapshot: snapshot),
            width: rect.width,
            height: noteAreaHeight
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
                    color: SIMD4(0, 0, 0, 0.085)
                ))
            } else {
                rects.append(PlaybackGridRectInstance(
                    origin: SIMD2(xMin, y),
                    size: SIMD2(xMax - xMin, min(rowHeight, (yMin + laneHeight) - y)),
                    color: SIMD4(1, 1, 1, (i % 2 == 0) ? 0.010 : 0.005)
                ))
            }
            if (i % horizontalStride) != 0 { continue }
            let isC = noteClass == 0
            lines.append(PlaybackGridLineInstance(
                start: SIMD2(xMin, y),
                end: SIMD2(xMax, y),
                color: isC ? SIMD4(0.34, 0.62, 0.95, 0.22) : SIMD4(1, 1, 1, 0.040),
                width: isC ? 1.2 : 1
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
                color: SIMD4(1, 1, 1, 0.15),
                width: 1
            ))
            for beat in 1..<Int(beatsPerBar) {
                let beatX = barX + (Float(beat) * beatWidth)
                lines.append(PlaybackGridLineInstance(
                    start: SIMD2(beatX, yMin),
                    end: SIMD2(beatX, yBottom),
                    color: SIMD4(1, 1, 1, 0.042),
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
        calls: inout [(offset: Int, count: Int)],
        lines: inout [PlaybackGridLineInstance]
    ) {
        let fadeColor = SIMD4<Float>(0, 0, 0, 0.55)
        let outlineColor = SIMD4<Float>(1, 1, 1, 0.45)

        if let fade = enterFade, fade.duration > 0 {
            let fadeWidth = Float(fade.duration) * pixelsPerBar
            let steps = max(Int(fadeWidth / 2), 20)
            let offset = vertices.count

            var prevCurvePoint = SIMD2<Float>(0, 0)
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let gain = fade.curve.gain(at: t)
                let x = Float(rect.minX) + Float(t) * fadeWidth
                let yTop = Float(rect.minY)
                let yCurve = Float(rect.maxY) - Float(gain) * Float(rect.height)

                vertices.append(PlaybackGridFadeVertex(position: SIMD2(x, yTop), color: fadeColor))
                vertices.append(PlaybackGridFadeVertex(position: SIMD2(x, yCurve), color: SIMD4(0, 0, 0, 0)))

                let curvePoint = SIMD2<Float>(x, yCurve)
                if i > 0 {
                    lines.append(PlaybackGridLineInstance(
                        start: prevCurvePoint, end: curvePoint,
                        color: outlineColor, width: 1.5
                    ))
                }
                prevCurvePoint = curvePoint
            }
            calls.append((offset: offset, count: (steps + 1) * 2))
        }

        if let fade = exitFade, fade.duration > 0 {
            let fadeWidth = Float(fade.duration) * pixelsPerBar
            let steps = max(Int(fadeWidth / 2), 20)
            let startX = Float(rect.maxX) - fadeWidth
            let offset = vertices.count

            var prevCurvePoint = SIMD2<Float>(0, 0)
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let gain = fade.curve.gain(at: 1.0 - t)
                let x = startX + Float(t) * fadeWidth
                let yTop = Float(rect.minY)
                let yCurve = Float(rect.maxY) - Float(gain) * Float(rect.height)

                vertices.append(PlaybackGridFadeVertex(position: SIMD2(x, yTop), color: fadeColor))
                vertices.append(PlaybackGridFadeVertex(position: SIMD2(x, yCurve), color: SIMD4(0, 0, 0, 0)))

                let curvePoint = SIMD2<Float>(x, yCurve)
                if i > 0 {
                    lines.append(PlaybackGridLineInstance(
                        start: prevCurvePoint, end: curvePoint,
                        color: outlineColor, width: 1.5
                    ))
                }
                prevCurvePoint = curvePoint
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

                points.append(SIMD2(x, y))
                appendAutomationBreakpointHandle(
                    at: SIMD2(x, y),
                    laneColor: color,
                    isFocused: isFocused,
                    baseSize: handleBaseSize,
                    focusedScale: focusedHandleScale,
                    alphaMultiplier: handleAlphaMul,
                    rects: &rects
                )
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
                    appendAutomationBreakpointHandle(
                        at: SIMD2(x, y),
                        laneColor: laneColor,
                        isFocused: isFocused,
                        baseSize: handleBaseSize,
                        focusedScale: focusedHandleScale,
                        alphaMultiplier: handleAlphaMul,
                        rects: &rects
                    )
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
                    appendAutomationBreakpointHandle(
                        at: SIMD2(x, y),
                        laneColor: laneColor,
                        isFocused: isFocused,
                        baseSize: handleBaseSize,
                        focusedScale: focusedHandleScale,
                        alphaMultiplier: handleAlphaMul,
                        rects: &rects
                    )
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

    private func appendAutomationBreakpointHandle(
        at point: SIMD2<Float>,
        laneColor: SIMD4<Float>,
        isFocused: Bool,
        baseSize: Float,
        focusedScale: Float,
        alphaMultiplier: Float,
        rects: inout [PlaybackGridRectInstance]
    ) {
        let handleSize = isFocused ? baseSize * focusedScale : baseSize
        let handleRadius = handleSize * 0.5
        let shadowSize = handleSize + (isFocused ? 7.5 : 4.5)
        let shadowRadius = shadowSize * 0.5
        let ringSize = handleSize + (isFocused ? 4.5 : 2.5)
        let ringRadius = ringSize * 0.5
        let highlightSize = max(2, handleSize * 0.34)
        let highlightRadius = highlightSize * 0.5

        rects.append(PlaybackGridRectInstance(
            origin: SIMD2(point.x - shadowRadius, point.y - shadowRadius + 1.4),
            size: SIMD2(shadowSize, shadowSize),
            color: SIMD4(0, 0, 0, (isFocused ? 0.32 : 0.18) * alphaMultiplier),
            cornerRadius: shadowRadius
        ))
        rects.append(PlaybackGridRectInstance(
            origin: SIMD2(point.x - ringRadius, point.y - ringRadius),
            size: SIMD2(ringSize, ringSize),
            color: SIMD4(laneColor.x, laneColor.y, laneColor.z, (isFocused ? 0.54 : 0.24) * alphaMultiplier),
            cornerRadius: ringRadius
        ))

        let handleColor: SIMD4<Float>
        if isFocused {
            handleColor = SIMD4(
                min(laneColor.x * 0.60 + 0.40, 1.0),
                min(laneColor.y * 0.60 + 0.40, 1.0),
                min(laneColor.z * 0.60 + 0.40, 1.0),
                1.0 * alphaMultiplier
            )
        } else {
            handleColor = SIMD4(
                min(laneColor.x * 0.90 + 0.08, 1.0),
                min(laneColor.y * 0.90 + 0.08, 1.0),
                min(laneColor.z * 0.90 + 0.08, 1.0),
                min(laneColor.w + 0.04, 1.0) * alphaMultiplier
            )
        }

        rects.append(PlaybackGridRectInstance(
            origin: SIMD2(point.x - handleRadius, point.y - handleRadius),
            size: SIMD2(handleSize, handleSize),
            color: handleColor,
            cornerRadius: handleRadius
        ))
        rects.append(PlaybackGridRectInstance(
            origin: SIMD2(point.x - handleRadius + 1, point.y - handleRadius + 1),
            size: SIMD2(max(handleSize - 2, 1), max(handleSize - 2, 1)),
            color: SIMD4(0.08, 0.09, 0.11, (isFocused ? 0.20 : 0.14) * alphaMultiplier),
            cornerRadius: max(handleRadius - 1, 0)
        ))
        rects.append(PlaybackGridRectInstance(
            origin: SIMD2(point.x - handleRadius * 0.42, point.y - handleRadius * 0.48),
            size: SIMD2(highlightSize, highlightSize),
            color: SIMD4(1, 1, 1, (isFocused ? 0.82 : 0.46) * alphaMultiplier),
            cornerRadius: highlightRadius
        ))
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

private struct PlaybackGridWaveformDrawCall {
    let buffer: MTLBuffer
    let params: PlaybackGridWaveformParams
}

private enum PlaybackGridWaveformRenderMode {
    case envelope
    case detailedExtrema
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
        let accent = Self.simd4(from: NSColor.controlAccentColor)

        fillNormal = SIMD4(base.x, base.y, base.z, 0.30)
        fillSelected = SIMD4(base.x, base.y, base.z, 0.35)
        fillFocused = SIMD4(base.x, base.y, base.z, 0.33)
        fillArmed = SIMD4(1, 0.23, 0.19, 0.15)
        borderNormal = SIMD4(base.x, base.y, base.z, 0.65)
        borderSelected = SIMD4(accent.x, accent.y, accent.z, 0.85)
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
        selectionHighlight = SIMD4(accent.x, accent.y, accent.z, 0.30)
        focusGlow = SIMD4(accent.x, accent.y, accent.z, 0.15)
    }

    private static func simd4(from nsColor: NSColor) -> SIMD4<Float> {
        let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
        return SIMD4(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), Float(c.alphaComponent))
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

private func withAlpha(_ color: SIMD4<Float>, _ alpha: Float) -> SIMD4<Float> {
    SIMD4(color.x, color.y, color.z, alpha)
}
