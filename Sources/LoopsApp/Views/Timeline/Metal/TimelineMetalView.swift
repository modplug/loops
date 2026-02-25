import AppKit
import Metal
import QuartzCore
import LoopsCore

/// High-performance Metal-backed NSView for timeline rendering.
/// Uses CAMetalLayer as a sublayer (not the backing layer), sized to the
/// visible viewport only. This keeps drawable dimensions within GPU limits
/// and uses standard AppKit display cycle (updateLayer).
public final class TimelineMetalView: NSView {

    // MARK: - Metal State

    private var renderer: TimelineMetalRenderer?
    private let metalLayer: CAMetalLayer
    private let textOverlayLayer = TimelineTextOverlayLayer()

    // MARK: - Layout Constants (matching TimelineCanvasView)

    static let rulerHeight: CGFloat = TimelineCanvasView.rulerHeight
    static let sectionLaneHeight: CGFloat = TimelineCanvasView.sectionLaneHeight
    static let trackAreaTop: CGFloat = TimelineCanvasView.trackAreaTop

    // MARK: - Data (set via configure())

    private(set) var trackLayouts: [TimelineCanvasView.TrackLayout] = []
    private(set) var sectionLayouts: [TimelineCanvasView.SectionLayout] = []

    private(set) var tracks: [Track] = []
    private(set) var pixelsPerBar: CGFloat = 120
    private(set) var totalBars: Int = 32
    private(set) var timeSignature: TimeSignature = TimeSignature()
    private(set) var selectedContainerIDs: Set<ID<Container>> = []
    private(set) var trackHeights: [ID<Track>: CGFloat] = [:]
    private(set) var defaultTrackHeight: CGFloat = 80
    private(set) var gridMode: GridMode = .adaptive
    private(set) var sections: [SectionRegion] = []
    private(set) var selectedSectionID: ID<SectionRegion>?
    var showRulerAndSections: Bool = true
    private(set) var selectedRange: ClosedRange<Int>?
    private(set) var rangeSelection: SelectionState.RangeSelection?

    // MARK: - Providers

    var waveformPeaksProvider: ((_ container: Container) -> [Float]?)?
    var audioDurationBarsProvider: ((_ container: Container) -> Double?)?
    var resolvedMIDISequenceProvider: ((_ container: Container) -> MIDISequence?)?

    // MARK: - Callbacks

    var onPlayheadPosition: ((Double) -> Void)?
    var onCursorPosition: ((CGFloat?) -> Void)?
    var onSectionSelect: ((ID<SectionRegion>) -> Void)?
    var onRangeSelect: ((ClosedRange<Int>) -> Void)?
    var onRangeDeselect: (() -> Void)?

    // MARK: - Overlay Layers (playhead + cursor, same as CG path)

    private let playheadLayer = CALayer()
    private let cursorLayer = CALayer()

    // MARK: - Performance Counters

    private(set) var configureSkipCount: Int = 0
    private(set) var configureHitCount: Int = 0
    private(set) var lastDrawDuration: CFTimeInterval = 0

    private var configureWillRedraw = false
    private var needsBufferRebuild = true

    // MARK: - Scroll Observation

    private var scrollObserver: NSObjectProtocol?

    // MARK: - Init

    private static func makeMetalLayer() -> CAMetalLayer {
        let ml = CAMetalLayer()
        ml.device = MTLCreateSystemDefaultDevice()
        ml.pixelFormat = .bgra8Unorm
        ml.isOpaque = false
        ml.framebufferOnly = true
        return ml
    }

    public override init(frame frameRect: NSRect) {
        metalLayer = Self.makeMetalLayer()
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        metalLayer = Self.makeMetalLayer()
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        guard let backingLayer = layer else { return }

        // Create renderer
        if let device = metalLayer.device {
            do {
                renderer = try TimelineMetalRenderer(device: device)
            } catch {
            }
        }

        // Metal rendering sublayer (positioned at visible viewport in updateLayer)
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        backingLayer.addSublayer(metalLayer)

        // Text overlay layer (ruler labels + section names)
        textOverlayLayer.zPosition = 1
        textOverlayLayer.contentsScale = metalLayer.contentsScale
        backingLayer.addSublayer(textOverlayLayer)

        // Playhead layer
        playheadLayer.backgroundColor = NSColor.systemRed.cgColor
        playheadLayer.zPosition = 100
        playheadLayer.isHidden = true
        backingLayer.addSublayer(playheadLayer)

        // Cursor layer
        cursorLayer.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
        cursorLayer.zPosition = 99
        cursorLayer.isHidden = true
        backingLayer.addSublayer(cursorLayer)

        // Appearance change observation
        NotificationCenter.default.addObserver(
            self, selector: #selector(invalidateAndRedraw),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    deinit {
        scrollObserver.map { NotificationCenter.default.removeObserver($0) }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layer Backing

    public override var wantsUpdateLayer: Bool { true }

    // MARK: - View Lifecycle

    public override var isFlipped: Bool { true }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        setupScrollObservation()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Retry scroll observation — enclosingScrollView may not be available
        // in viewDidMoveToSuperview because the SwiftUI hierarchy isn't fully assembled yet
        if scrollObserver == nil {
            setupScrollObservation()
        }
        if let window {
            let scale = window.backingScaleFactor
            metalLayer.contentsScale = scale
            textOverlayLayer.contentsScale = scale
        }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2.0
        metalLayer.contentsScale = scale
        textOverlayLayer.contentsScale = scale
        needsDisplay = true
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        invalidateAndRedraw()
    }

    @objc private func invalidateAndRedraw() {
        needsBufferRebuild = true
        needsDisplay = true
    }

    // MARK: - Scroll Observation

    private func setupScrollObservation() {
        scrollObserver.map { NotificationCenter.default.removeObserver($0) }
        scrollObserver = nil

        guard let clipView = enclosingScrollView?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            self?.handleScrollChange()
        }
    }

    private func handleScrollChange() {
        needsBufferRebuild = true
        needsDisplay = true
    }

    // MARK: - Frame Change

    public override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)

        if oldSize != newSize && !configureWillRedraw {
            needsBufferRebuild = true
            needsDisplay = true
        }
    }

    // MARK: - Mouse Tracking

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    public override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        onCursorPosition?(local.x)
    }

    public override func mouseExited(with event: NSEvent) {
        onCursorPosition?(nil)
    }

    private var rulerDragStartX: CGFloat?
    private var rulerIsScrubbing = false

    public override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let hit = hitTest(at: local)

        switch hit {
        case .ruler:
            let isShift = event.modifierFlags.contains(.shift)
            if isShift {
                rulerDragStartX = local.x
                rulerIsScrubbing = false
            } else {
                rulerIsScrubbing = true
                rulerDragStartX = local.x
                let bar = snappedBarForX(local.x)
                onPlayheadPosition?(bar)
                onRangeDeselect?()
            }

        case .section(let sectionID):
            onSectionSelect?(sectionID)

        case .sectionBackground:
            break

        case .trackBackground, .emptyArea:
            let bar = (Double(local.x) / Double(pixelsPerBar)) + 1.0
            onPlayheadPosition?(max(bar, 1.0))

        case .container:
            break
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard rulerDragStartX != nil else { return }
        if rulerIsScrubbing {
            let bar = snappedBarForX(local.x)
            onPlayheadPosition?(bar)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        defer {
            rulerDragStartX = nil
            rulerIsScrubbing = false
        }

        guard let startX = rulerDragStartX else { return }

        if rulerIsScrubbing {
            let bar = snappedBarForX(local.x)
            onPlayheadPosition?(bar)
        } else {
            let distance = abs(local.x - startX)
            if distance < 3 {
                onRangeDeselect?()
                let bar = snappedBarForX(local.x)
                onPlayheadPosition?(bar)
            } else {
                let startBar = barForX(startX)
                let endBar = barForX(local.x)
                if startBar != endBar {
                    let lower = min(startBar, endBar)
                    let upper = max(startBar, endBar)
                    onRangeSelect?(lower...upper)
                }
            }
        }
    }

    // MARK: - Hit Testing

    func hitTest(at point: NSPoint) -> TimelineHitResult {
        if showRulerAndSections {
            // Ruler and section lane are pinned to viewport top (not at fixed world y=0).
            // Click point is in world coordinates — compare against viewport-relative positions.
            let vpTop = visibleRect.origin.y
            if point.y < vpTop + Self.rulerHeight {
                return .ruler
            }
            if point.y < vpTop + Self.trackAreaTop {
                // Check section bands at their pinned viewport positions
                for sl in sectionLayouts.reversed() {
                    let pinnedRect = NSRect(
                        x: sl.rect.minX, y: vpTop + Self.rulerHeight + 1,
                        width: sl.rect.width, height: Self.sectionLaneHeight - 2
                    )
                    if pinnedRect.contains(point) {
                        return .section(sectionID: sl.section.id)
                    }
                }
                return .sectionBackground
            }
        }

        for trackLayout in trackLayouts.reversed() {
            for cl in trackLayout.containers.reversed() {
                if cl.rect.contains(point) {
                    let zone = detectZone(point: point, containerRect: cl.rect)
                    return .container(
                        containerID: cl.container.id,
                        trackID: trackLayout.track.id,
                        zone: zone
                    )
                }
            }
            let trackRect = NSRect(x: 0, y: trackLayout.yOrigin, width: bounds.width, height: trackLayout.height)
            if trackRect.contains(point) {
                return .trackBackground(trackID: trackLayout.track.id)
            }
        }

        return .emptyArea
    }

    private static let edgeThreshold: CGFloat = 12

    private func detectZone(point: NSPoint, containerRect: NSRect) -> TimelineHitResult.ContainerZone {
        let localX = point.x - containerRect.minX
        let localY = point.y - containerRect.minY
        let width = containerRect.width
        let height = containerRect.height
        let edge = Self.edgeThreshold

        let isLeftEdge = localX < edge
        let isRightEdge = localX > width - edge
        let relativeY = localY / height

        if relativeY < 1.0 / 3.0 {
            if isLeftEdge { return .fadeLeft }
            if isRightEdge { return .fadeRight }
            return .selector
        } else if relativeY < 2.0 / 3.0 {
            if isLeftEdge { return .resizeLeft }
            if isRightEdge { return .resizeRight }
            return .move
        } else {
            if isLeftEdge { return .trimLeft }
            if isRightEdge { return .trimRight }
            return .move
        }
    }

    // MARK: - Bar Helpers

    private func barForX(_ x: CGFloat) -> Int {
        max(1, min(Int(x / pixelsPerBar) + 1, totalBars))
    }

    private func snappedBarForX(_ x: CGFloat) -> Double {
        let clampedX = max(x, 0)
        let rawBar = (Double(clampedX) / Double(pixelsPerBar)) + 1.0
        let ppBeat = pixelsPerBar / CGFloat(timeSignature.beatsPerBar)
        if ppBeat >= 40.0 {
            let beatsPerBar = Double(timeSignature.beatsPerBar)
            let totalBeats = (rawBar - 1.0) * beatsPerBar
            let snappedBeats = totalBeats.rounded()
            return max((snappedBeats / beatsPerBar) + 1.0, 1.0)
        } else {
            return max(rawBar.rounded(), 1.0)
        }
    }

    // MARK: - Configuration

    func configure(
        tracks: [Track],
        pixelsPerBar: CGFloat,
        totalBars: Int,
        timeSignature: TimeSignature,
        selectedContainerIDs: Set<ID<Container>>,
        trackHeights: [ID<Track>: CGFloat],
        defaultTrackHeight: CGFloat,
        gridMode: GridMode,
        selectedRange: ClosedRange<Int>? = nil,
        rangeSelection: SelectionState.RangeSelection? = nil,
        sections: [SectionRegion] = [],
        selectedSectionID: ID<SectionRegion>? = nil
    ) {
        let tracksChanged = self.tracks != tracks
        let zoomChanged = self.pixelsPerBar != pixelsPerBar
        let barsChanged = self.totalBars != totalBars
        let timeSigChanged = self.timeSignature != timeSignature
        let selectionChanged = self.selectedContainerIDs != selectedContainerIDs
        let heightsChanged = self.trackHeights != trackHeights || self.defaultTrackHeight != defaultTrackHeight
        let gridChanged = self.gridMode != gridMode
        let rangeChanged = self.selectedRange != selectedRange
        let rangeSelChanged = self.rangeSelection != rangeSelection
        let sectionsChanged = self.sections != sections
        let sectionSelChanged = self.selectedSectionID != selectedSectionID

        let anythingChanged = tracksChanged || zoomChanged || barsChanged || timeSigChanged
            || selectionChanged || heightsChanged || gridChanged || rangeChanged || rangeSelChanged
            || sectionsChanged || sectionSelChanged

        if !anythingChanged {
            configureSkipCount += 1
            return
        }
        configureHitCount += 1

        self.tracks = tracks
        self.pixelsPerBar = pixelsPerBar
        self.totalBars = totalBars
        self.timeSignature = timeSignature
        self.selectedContainerIDs = selectedContainerIDs
        self.trackHeights = trackHeights
        self.defaultTrackHeight = defaultTrackHeight
        self.gridMode = gridMode
        self.selectedRange = selectedRange
        self.rangeSelection = rangeSelection
        self.sections = sections
        self.selectedSectionID = selectedSectionID

        recomputeLayout()
        needsBufferRebuild = true

        let geometryChanged = zoomChanged || barsChanged || timeSigChanged || tracksChanged
            || heightsChanged || gridChanged || sectionsChanged
        if geometryChanged {
            configureWillRedraw = true
        }
        needsDisplay = true
    }

    // MARK: - Layout Computation (identical to TimelineCanvasView)

    func recomputeLayout() {
        var layouts: [TimelineCanvasView.TrackLayout] = []
        var yOffset: CGFloat = showRulerAndSections ? Self.trackAreaTop : 0

        for track in tracks {
            let height = trackHeights[track.id] ?? defaultTrackHeight

            var containerLayouts: [TimelineCanvasView.ContainerLayout] = []
            for container in track.containers {
                let x = CGFloat(container.startBar - 1.0) * pixelsPerBar
                let width = CGFloat(container.lengthBars) * pixelsPerBar
                let rect = NSRect(x: x, y: yOffset, width: width, height: height)
                let isSelected = selectedContainerIDs.contains(container.id)
                let peaks = waveformPeaksProvider?(container)
                let midiNotes = resolvedMIDISequenceProvider?(container)?.notes
                let audioDuration = audioDurationBarsProvider?(container)

                containerLayouts.append(TimelineCanvasView.ContainerLayout(
                    container: container,
                    rect: rect,
                    waveformPeaks: peaks,
                    isSelected: isSelected,
                    isClone: container.isClone,
                    resolvedMIDINotes: midiNotes,
                    enterFade: container.enterFade,
                    exitFade: container.exitFade,
                    audioDurationBars: audioDuration
                ))
            }

            layouts.append(TimelineCanvasView.TrackLayout(
                track: track,
                yOrigin: yOffset,
                height: height,
                containers: containerLayouts
            ))
            yOffset += height
        }

        trackLayouts = layouts

        var sLayouts: [TimelineCanvasView.SectionLayout] = []
        for section in sections {
            let x = CGFloat(section.startBar - 1) * pixelsPerBar
            let width = CGFloat(section.lengthBars) * pixelsPerBar
            let rect = NSRect(x: x, y: Self.rulerHeight, width: width, height: Self.sectionLaneHeight)
            sLayouts.append(TimelineCanvasView.SectionLayout(
                section: section,
                rect: rect,
                isSelected: selectedSectionID == section.id
            ))
        }
        sectionLayouts = sLayouts
    }

    // MARK: - Playhead & Cursor Overlays

    func updatePlayhead(bar: Double, height: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let x = CGFloat(bar - 1.0) * pixelsPerBar
        playheadLayer.frame = CGRect(x: x - 0.5, y: 0, width: 1, height: height)
        playheadLayer.isHidden = false
        CATransaction.commit()
    }

    func updateCursor(x: CGFloat?, height: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let x {
            cursorLayer.frame = CGRect(x: x - 0.5, y: 0, width: 1, height: height)
            cursorLayer.isHidden = false
        } else {
            cursorLayer.isHidden = true
        }
        CATransaction.commit()
    }

    // MARK: - Drawing

    public override func updateLayer() {
        configureWillRedraw = false
        let drawStart = CACurrentMediaTime()

        // Lazy scroll observer setup — lifecycle methods may fire before
        // the SwiftUI scroll view is in the hierarchy
        if scrollObserver == nil {
            setupScrollObservation()
        }

        guard let renderer else {
            return
        }

        // Get visible rect in view coordinates (scroll viewport)
        let visible = visibleRect
        guard visible.width > 0 && visible.height > 0 else {
            return
        }

        // Position metalLayer and textOverlayLayer at the visible viewport
        let scale = metalLayer.contentsScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = visible
        metalLayer.drawableSize = CGSize(
            width: visible.width * scale,
            height: visible.height * scale
        )
        textOverlayLayer.frame = visible
        CATransaction.commit()

        guard let drawable = metalLayer.nextDrawable() else {
            return
        }

        // Never block the main thread waiting for GPU work; drop this frame instead.
        guard renderer.frameSemaphore.wait(timeout: .now()) == .success else {
            return
        }

        let visibleMinX = Float(visible.minX)
        let visibleMaxX = Float(visible.maxX)
        let visibleMinY = Float(visible.minY)
        let visibleMaxY = Float(visible.maxY)

        // Rebuild GPU buffers if data changed or viewport moved
        if needsBufferRebuild {
            renderer.buildBuffers(
                trackLayouts: trackLayouts,
                sectionLayouts: sectionLayouts,
                pixelsPerBar: pixelsPerBar,
                totalBars: totalBars,
                timeSignature: timeSignature,
                gridMode: gridMode,
                selectedRange: selectedRange,
                rangeSelection: rangeSelection,
                showRulerAndSections: showRulerAndSections,
                canvasWidth: Float(bounds.width),
                canvasHeight: Float(bounds.height),
                visibleMinX: visibleMinX,
                visibleMaxX: visibleMaxX,
                visibleMinY: visibleMinY,
                visibleMaxY: visibleMaxY
            )
            needsBufferRebuild = false
        }

        // Update text overlay — must draw synchronously so ruler matches
        // the Metal content in the same frame (setNeedsDisplay would defer
        // the draw to the next cycle, causing zoom/scroll mismatch)
        textOverlayLayer.pixelsPerBar = pixelsPerBar
        textOverlayLayer.totalBars = totalBars
        textOverlayLayer.timeSignature = timeSignature
        textOverlayLayer.sections = sectionLayouts
        textOverlayLayer.selectedRange = selectedRange
        textOverlayLayer.showRulerAndSections = showRulerAndSections
        textOverlayLayer.viewportOrigin = visible.origin
        if textOverlayLayer.updateIfNeeded() {
            textOverlayLayer.displayIfNeeded()
        }

        // Orthographic projection: maps visible world rect to NDC
        // For flipped NSView: top=minY (small Y at screen top), bottom=maxY
        var uniforms = TimelineUniforms(
            projectionMatrix: TimelineUniforms.orthographic(
                left: visibleMinX,
                right: visibleMaxX,
                top: visibleMinY,
                bottom: visibleMaxY
            ),
            pixelsPerBar: Float(pixelsPerBar),
            canvasHeight: Float(bounds.height),
            viewportMinX: visibleMinX,
            viewportMaxX: visibleMaxX
        )

        // Render pass
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)

        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else {
            renderer.frameSemaphore.signal()
            return
        }

        let texW = drawable.texture.width
        let texH = drawable.texture.height
        encoder.setViewport(MTLViewport(
            originX: 0, originY: 0,
            width: Double(texW), height: Double(texH),
            znear: 0, zfar: 1
        ))

        renderer.encode(
            into: encoder,
            uniforms: &uniforms,
            viewportSize: MTLSize(width: texW, height: texH, depth: 1)
        )

        encoder.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.renderer?.frameSemaphore.signal()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()

        lastDrawDuration = CACurrentMediaTime() - drawStart
    }

    // MARK: - Intrinsic Size

    public override var intrinsicContentSize: NSSize {
        let fallback = showRulerAndSections ? Self.trackAreaTop + 400 : CGFloat(400)
        let totalHeight = trackLayouts.last.map { $0.yOrigin + $0.height } ?? fallback
        return NSSize(width: CGFloat(totalBars) * pixelsPerBar, height: totalHeight)
    }
}
