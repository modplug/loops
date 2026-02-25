import AppKit
import LoopsCore

// MARK: - Track Color Mapping

extension TrackKind {
    /// NSColor equivalent of the SwiftUI track colors used in TrackLaneView.
    var nsColor: NSColor {
        switch self {
        case .audio: return .systemBlue
        case .midi: return .systemPurple
        case .bus: return .systemGreen
        case .backing: return .systemOrange
        case .master: return .systemGray
        }
    }
}

// MARK: - Timeline Canvas View

/// High-performance NSView that renders the entire timeline grid, containers,
/// waveforms, MIDI minimaps, and overlays in a single `draw(_:)` pass.
///
/// Architecture:
///   - One draw call renders grid lines, track backgrounds, containers, waveforms
///   - Playhead and cursor are separate CALayers (repositioned at 60fps, no redraw)
///   - Dirty-rect invalidation: scroll only redraws newly-exposed strip
///   - Waveform peaks are cached as CGImages at discrete zoom levels
public final class TimelineCanvasView: NSView {

    // MARK: - Layout Constants

    /// Height of the ruler area at the top of the canvas.
    static let rulerHeight: CGFloat = 20
    /// Height of the section lane below the ruler.
    static let sectionLaneHeight: CGFloat = 24
    /// Y offset where track lanes begin (below ruler + section lane).
    static let trackAreaTop: CGFloat = rulerHeight + sectionLaneHeight

    // MARK: - Data (set by the representable bridge or tests)

    struct TrackLayout {
        let track: Track
        let yOrigin: CGFloat
        let height: CGFloat
        let containers: [ContainerLayout]
    }

    struct ContainerLayout {
        let container: Container
        let rect: NSRect
        let waveformPeaks: [Float]?
        let isSelected: Bool
        let isClone: Bool
        let resolvedMIDINotes: [MIDINoteEvent]?
        let enterFade: FadeSettings?
        let exitFade: FadeSettings?
        /// Total duration of the source recording in bars (unrounded).
        /// Used by the Metal renderer to map waveform peaks to actual audio
        /// content width, preventing drift when container.lengthBars was ceil'd.
        let audioDurationBars: Double?
    }

    struct SectionLayout {
        let section: SectionRegion
        let rect: NSRect
        let isSelected: Bool
    }

    /// Computed layout for all tracks — recalculated when data or zoom changes.
    private(set) var trackLayouts: [TrackLayout] = []

    /// Computed layout for section regions.
    private(set) var sectionLayouts: [SectionLayout] = []

    /// Snapshot of rendering inputs. Set via `configure(...)`.
    private(set) var tracks: [Track] = []
    private(set) var pixelsPerBar: CGFloat = 120
    private(set) var totalBars: Int = 32
    private(set) var timeSignature: TimeSignature = TimeSignature()
    private(set) var selectedContainerIDs: Set<ID<Container>> = []
    private(set) var trackHeights: [ID<Track>: CGFloat] = [:]
    private(set) var defaultTrackHeight: CGFloat = 80
    private(set) var gridMode: GridMode = .adaptive

    /// Section regions drawn in the section lane.
    private(set) var sections: [SectionRegion] = []
    private(set) var selectedSectionID: ID<SectionRegion>?

    /// When false, ruler and section lane are not drawn and tracks start at y=0.
    /// Used for the docked master track which shares the main timeline's ruler.
    var showRulerAndSections: Bool = true

    /// Bar range selection from ruler (for looping/export).
    private(set) var selectedRange: ClosedRange<Int>?

    /// Container-level range selection (time selection within a container).
    private(set) var rangeSelection: SelectionState.RangeSelection?

    /// Waveform peak data lookup, keyed by container ID.
    var waveformPeaksProvider: ((_ container: Container) -> [Float]?)?

    /// Total source recording duration in bars (unrounded), for waveform-audio sync.
    var audioDurationBarsProvider: ((_ container: Container) -> Double?)?

    /// Resolved MIDI sequence for containers (follows clone chain).
    var resolvedMIDISequenceProvider: ((_ container: Container) -> MIDISequence?)?

    // MARK: - Callbacks

    /// Called when the user clicks empty space to position the playhead.
    var onPlayheadPosition: ((Double) -> Void)?

    /// Called when the cursor moves over the canvas (x in canvas coordinates) or exits (nil).
    var onCursorPosition: ((CGFloat?) -> Void)?

    // MARK: - Overlay Layers

    private let playheadLayer = CALayer()
    private let cursorLayer = CALayer()

    // MARK: - Waveform Tile Cache

    let waveformTileCache = WaveformTileCache()

    // MARK: - Cached CGColors

    /// Pre-computed CGColors for each track kind. Avoids expensive NSColor→CGColor
    /// conversions (via ColorSync) during draw — up to 0.1ms per conversion.
    struct TrackDrawColors {
        let fillNormal: CGColor
        let fillSelected: CGColor
        let fillArmed: CGColor
        let borderNormal: CGColor
        let borderSelected: CGColor
        let borderArmed: CGColor
        let waveformFill: CGColor
        let waveformStroke: CGColor
        let selectionHighlight: CGColor

        init(kind: TrackKind) {
            let base = kind.nsColor
            fillNormal = base.withAlphaComponent(0.3).cgColor
            fillSelected = base.withAlphaComponent(0.5).cgColor
            fillArmed = NSColor.systemRed.withAlphaComponent(0.15).cgColor
            borderNormal = base.withAlphaComponent(0.6).cgColor
            borderSelected = NSColor.controlAccentColor.cgColor
            borderArmed = NSColor.systemRed.cgColor
            waveformFill = base.withAlphaComponent(0.4).cgColor
            waveformStroke = base.withAlphaComponent(0.7).cgColor
            selectionHighlight = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
        }
    }

    /// Lazily populated color cache, keyed by TrackKind.
    /// Invalidated on appearance/screen changes via notification observer.
    private var drawColors: [TrackKind: TrackDrawColors] = [:]

    /// Cached attribute dictionaries for ruler text drawing.
    /// Avoids re-creating font+color attribute dicts on every draw.
    private static let rulerLabelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 9),
        .foregroundColor: NSColor.secondaryLabelColor
    ]

    private func colors(for kind: TrackKind) -> TrackDrawColors {
        if let cached = drawColors[kind] { return cached }
        let c = TrackDrawColors(kind: kind)
        drawColors[kind] = c
        return c
    }

    // MARK: - Performance Counters (for testing and diagnostics)

    /// Number of configure() calls that were skipped (no data changed).
    private(set) var configureSkipCount: Int = 0
    /// Number of configure() calls that triggered a layout recompute + redraw.
    private(set) var configureHitCount: Int = 0
    /// Duration of the most recent draw() call in seconds.
    private(set) var lastDrawDuration: CFTimeInterval = 0

    /// When true, configure() has already set needsDisplay — setFrameSize() should skip its own.
    /// Prevents double draws during zoom when both configure() and setFrameSize() fire in the same frame.
    private var configureWillRedraw = false

    // MARK: - Init

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    // MARK: - Frame Change → Redraw

    /// With `.onSetNeedsDisplay`, frame changes do NOT trigger redraws.
    /// SwiftUI resizes this view when totalWidth changes (zoom), so we must
    /// explicitly mark for redraw to avoid stale/stretched layer content.
    public override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)
        if oldSize != newSize && !configureWillRedraw {
            needsDisplay = true
        }
    }

    private func commonInit() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.drawsAsynchronously = true

        // Playhead layer — thin red line
        playheadLayer.backgroundColor = NSColor.systemRed.cgColor
        playheadLayer.zPosition = 100
        playheadLayer.isHidden = true
        layer?.addSublayer(playheadLayer)

        // Cursor layer — thin gray line
        cursorLayer.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
        cursorLayer.zPosition = 99
        cursorLayer.isHidden = true
        layer?.addSublayer(cursorLayer)

        // Invalidate CGColor cache on appearance/screen changes
        NotificationCenter.default.addObserver(
            self, selector: #selector(invalidateColorCache),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        invalidateColorCache()
    }

    @objc private func invalidateColorCache() {
        drawColors.removeAll(keepingCapacity: true)
        invalidateVisibleRect()
    }

    /// Marks only the visible scroll area as needing redraw, rather than the entire frame.
    /// During zoom, the full frame can be 9600+ px wide, but only ~1400px is visible.
    private func invalidateVisibleRect() {
        if let clipBounds = enclosingScrollView?.contentView.bounds {
            setNeedsDisplay(clipBounds)
        } else {
            needsDisplay = true
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

    /// Called when the user clicks a section band.
    var onSectionSelect: ((ID<SectionRegion>) -> Void)?

    /// Called when the user Shift+drags on the ruler to select a range.
    var onRangeSelect: ((ClosedRange<Int>) -> Void)?

    /// Called when a range selection is deselected (click without shift).
    var onRangeDeselect: (() -> Void)?

    /// Ruler drag state for scrubbing / range selection.
    private var rulerDragStartX: CGFloat?
    private var rulerIsScrubbing = false

    public override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let hit = hitTest(at: local)

        switch hit {
        case .ruler:
            let isShift = event.modifierFlags.contains(.shift)
            if isShift {
                // Start range selection drag
                rulerDragStartX = local.x
                rulerIsScrubbing = false
            } else {
                // Click to position playhead (+ start scrub drag)
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

        // Handle ruler drag (scrub or range selection)
        guard rulerDragStartX != nil else { return }

        if rulerIsScrubbing {
            let bar = snappedBarForX(local.x)
            onPlayheadPosition?(bar)
        }
        // Range selection visual feedback would need needsDisplay on the ruler area
        // For now, range selection is committed on mouseUp
    }

    public override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)

        defer {
            rulerDragStartX = nil
            rulerIsScrubbing = false
        }

        guard let startX = rulerDragStartX else { return }

        if rulerIsScrubbing {
            // Final scrub position
            let bar = snappedBarForX(local.x)
            onPlayheadPosition?(bar)
        } else {
            // Range selection ended
            let distance = abs(local.x - startX)
            if distance < 3 {
                // Too short — deselect and position playhead
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

    /// Converts x position to integer bar number (1-based).
    private func barForX(_ x: CGFloat) -> Int {
        max(1, min(Int(x / pixelsPerBar) + 1, totalBars))
    }

    /// Converts x position to a snapped bar value (Double, 1-based).
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

    /// Updates all rendering data. Only triggers a redraw if something rendering-relevant changed.
    /// Called from the NSViewRepresentable bridge when SwiftUI state changes.
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
        // Check if anything rendering-relevant changed before triggering a redraw.
        // This is critical: SwiftUI calls updateNSView on every observation cycle
        // (including scroll position changes), and we must NOT redraw on every scroll frame.
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

        // Geometry changes (zoom, bars, tracks, heights) invalidate the full backing store
        // because ALL positions shift. Selection-only changes can use visible-rect invalidation.
        let geometryChanged = zoomChanged || barsChanged || timeSigChanged || tracksChanged
            || heightsChanged || gridChanged || sectionsChanged
        if geometryChanged {
            configureWillRedraw = true
            needsDisplay = true
        } else {
            invalidateVisibleRect()
        }
    }

    /// Repositions the playhead CALayer without triggering draw.
    func updatePlayhead(bar: Double, height: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let x = CGFloat(bar - 1.0) * pixelsPerBar
        playheadLayer.frame = CGRect(x: x - 0.5, y: 0, width: 1, height: height)
        playheadLayer.isHidden = false
        CATransaction.commit()
    }

    /// Repositions the cursor CALayer without triggering draw.
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

    // MARK: - Layout Computation

    /// Recomputes container rects and track Y origins from current data.
    /// Pure geometry — no drawing, no side effects.
    func recomputeLayout() {
        var layouts: [TrackLayout] = []
        var yOffset: CGFloat = showRulerAndSections ? Self.trackAreaTop : 0

        for track in tracks {
            let height = trackHeights[track.id] ?? defaultTrackHeight

            var containerLayouts: [ContainerLayout] = []
            for container in track.containers {
                let x = CGFloat(container.startBar - 1.0) * pixelsPerBar
                let width = CGFloat(container.lengthBars) * pixelsPerBar
                let rect = NSRect(x: x, y: yOffset, width: width, height: height)
                let isSelected = selectedContainerIDs.contains(container.id)
                let peaks = waveformPeaksProvider?(container)
                let midiNotes = resolvedMIDISequenceProvider?(container)?.notes
                let audioDuration = audioDurationBarsProvider?(container)

                containerLayouts.append(ContainerLayout(
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

            layouts.append(TrackLayout(
                track: track,
                yOrigin: yOffset,
                height: height,
                containers: containerLayouts
            ))
            yOffset += height
        }

        trackLayouts = layouts

        // Section layouts
        var sLayouts: [SectionLayout] = []
        for section in sections {
            let x = CGFloat(section.startBar - 1) * pixelsPerBar
            let width = CGFloat(section.lengthBars) * pixelsPerBar
            let rect = NSRect(x: x, y: Self.rulerHeight, width: width, height: Self.sectionLaneHeight)
            sLayouts.append(SectionLayout(
                section: section,
                rect: rect,
                isSelected: selectedSectionID == section.id
            ))
        }
        sectionLayouts = sLayouts
    }

    /// Returns computed rects for all containers, keyed by container ID.
    /// Used by tests to validate layout geometry.
    func containerRects() -> [ID<Container>: NSRect] {
        var result: [ID<Container>: NSRect] = [:]
        for trackLayout in trackLayouts {
            for cl in trackLayout.containers {
                result[cl.container.id] = cl.rect
            }
        }
        return result
    }

    // MARK: - Drawing

    public override var isFlipped: Bool { true }

    public override func draw(_ dirtyRect: NSRect) {
        configureWillRedraw = false
        let drawStart = CACurrentMediaTime()

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Color cache is persisted across draws for performance (~4.5ms saved).
        // Invalidated on appearance/screen changes via notification observer.

        if showRulerAndSections {
            drawRuler(in: dirtyRect, context: context)
            drawSectionLane(in: dirtyRect, context: context)
        }
        drawGrid(in: dirtyRect, context: context)
        drawTrackBackgrounds(in: dirtyRect, context: context)
        _ = drawContainers(in: dirtyRect, context: context)

        lastDrawDuration = CACurrentMediaTime() - drawStart
    }

    // MARK: - Ruler Drawing

    /// Step between labeled bar numbers based on zoom level.
    private var rulerLabelStep: Int {
        let minLabelWidth: CGFloat = 30
        let niceSteps = [1, 2, 4, 5, 8, 10, 16, 20, 25, 32, 50, 64, 100, 200, 500, 1000]
        for step in niceSteps {
            if CGFloat(step) * pixelsPerBar >= minLabelWidth {
                return step
            }
        }
        return 1000
    }

    private func drawRuler(in dirtyRect: NSRect, context: CGContext) {
        let rulerRect = NSRect(x: dirtyRect.minX, y: 0, width: dirtyRect.width, height: Self.rulerHeight)
        guard rulerRect.intersects(dirtyRect) else { return }

        let height = Self.rulerHeight
        let step = rulerLabelStep

        // Ruler background
        context.saveGState()
        context.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor)
        context.fill(rulerRect)

        // Visible bar range from dirty rect — extends beyond totalBars
        // to fill the full canvas frame (which may be quantized wider).
        let startBar = max(1, Int(floor(dirtyRect.minX / pixelsPerBar)) + 1)
        let endBar = Int(ceil(dirtyRect.maxX / pixelsPerBar)) + 1
        guard startBar <= endBar else {
            context.restoreGState()
            return
        }

        // Bottom border
        context.setStrokeColor(NSColor.secondaryLabelColor.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: dirtyRect.minX, y: height - 0.5))
        context.addLine(to: CGPoint(x: dirtyRect.maxX, y: height - 0.5))
        context.strokePath()

        // Selected range highlight in ruler
        if let range = selectedRange {
            let rangeStartX = CGFloat(range.lowerBound - 1) * pixelsPerBar
            let rangeWidth = CGFloat(range.count) * pixelsPerBar
            let rangeRect = NSRect(x: rangeStartX, y: 0, width: rangeWidth, height: height)
            if rangeRect.intersects(dirtyRect) {
                context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor)
                context.fill(rangeRect.intersection(dirtyRect))
            }
        }

        // Tick marks and bar numbers
        let tickPath = CGMutablePath()
        for bar in startBar...endBar {
            let x = CGFloat(bar - 1) * pixelsPerBar

            // Tick mark at bottom
            if pixelsPerBar >= 4 {
                tickPath.move(to: CGPoint(x: x, y: height - 6))
                tickPath.addLine(to: CGPoint(x: x, y: height))
            }

            // Bar number label
            if bar % step == 0 {
                let label = "\(bar)" as NSString
                label.draw(at: NSPoint(x: x + 3, y: 2), withAttributes: Self.rulerLabelAttributes)
            }

            // Beat ticks within bar
            if pixelsPerBar > 50 {
                let pixelsPerBeat = pixelsPerBar / CGFloat(timeSignature.beatsPerBar)
                for beat in 1..<timeSignature.beatsPerBar {
                    let beatX = x + CGFloat(beat) * pixelsPerBeat
                    if beatX >= dirtyRect.minX && beatX <= dirtyRect.maxX {
                        tickPath.move(to: CGPoint(x: beatX, y: height - 3))
                        tickPath.addLine(to: CGPoint(x: beatX, y: height))
                    }
                }
            }
        }

        context.setStrokeColor(NSColor.secondaryLabelColor.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(0.5)
        context.addPath(tickPath)
        context.strokePath()

        context.restoreGState()
    }

    // MARK: - Section Lane Drawing

    private func drawSectionLane(in dirtyRect: NSRect, context: CGContext) {
        let laneRect = NSRect(x: dirtyRect.minX, y: Self.rulerHeight, width: dirtyRect.width, height: Self.sectionLaneHeight)
        guard laneRect.intersects(dirtyRect) else { return }

        context.saveGState()

        // Section lane background
        context.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.7).cgColor)
        context.fill(laneRect)

        // Bottom border
        context.setStrokeColor(NSColor.secondaryLabelColor.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(0.5)
        let borderY = Self.rulerHeight + Self.sectionLaneHeight - 0.5
        context.move(to: CGPoint(x: dirtyRect.minX, y: borderY))
        context.addLine(to: CGPoint(x: dirtyRect.maxX, y: borderY))
        context.strokePath()

        // Section bands
        for sl in sectionLayouts {
            guard sl.rect.intersects(dirtyRect) else { continue }

            let sectionColor = nsColorFromHex(sl.section.color)

            // Band fill
            let bandRect = NSRect(x: sl.rect.minX, y: sl.rect.minY + 1, width: sl.rect.width, height: sl.rect.height - 2)
            let bandPath = CGPath(roundedRect: bandRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
            context.addPath(bandPath)
            context.setFillColor(sectionColor.withAlphaComponent(0.4).cgColor)
            context.fillPath()

            // Band border
            context.addPath(bandPath)
            if sl.isSelected {
                context.setStrokeColor(NSColor.controlAccentColor.cgColor)
                context.setLineWidth(1.5)
            } else {
                context.setStrokeColor(sectionColor.withAlphaComponent(0.7).cgColor)
                context.setLineWidth(0.5)
            }
            context.strokePath()

            // Section name label
            let label = sl.section.name as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: sectionColor
            ]
            let labelSize = label.size(withAttributes: attrs)
            let labelX = bandRect.minX + 6
            let labelY = bandRect.midY - labelSize.height / 2
            // Clip to band bounds
            if labelX + labelSize.width <= bandRect.maxX - 4 {
                label.draw(at: NSPoint(x: labelX, y: labelY), withAttributes: attrs)
            } else if bandRect.width > 20 {
                // Truncate with clipping
                context.saveGState()
                context.clip(to: NSRect(x: bandRect.minX + 4, y: bandRect.minY, width: bandRect.width - 8, height: bandRect.height))
                label.draw(at: NSPoint(x: labelX, y: labelY), withAttributes: attrs)
                context.restoreGState()
            }
        }

        context.restoreGState()
    }

    /// Converts a hex color string (e.g. "#E74C3C") to NSColor.
    private func nsColorFromHex(_ hex: String) -> NSColor {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let rgb = Int(trimmed, radix: 16) else { return .gray }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    // MARK: - Grid Drawing

    private func drawGrid(in dirtyRect: NSRect, context: CGContext) {
        guard pixelsPerBar > 0 else { return }

        // Grid only draws in the track area (below ruler + section lane when shown)
        let gridTop = showRulerAndSections ? Self.trackAreaTop : CGFloat(0)
        let gridDirty = dirtyRect.intersection(NSRect(x: dirtyRect.minX, y: gridTop, width: dirtyRect.width, height: max(0, dirtyRect.maxY - gridTop)))
        guard !gridDirty.isEmpty else { return }

        let pixelsPerBeat = pixelsPerBar / CGFloat(timeSignature.beatsPerBar)

        // Visible bar range from dirty rect — extends beyond totalBars
        // to fill the full canvas frame (which may be quantized wider).
        let startBar = max(0, Int(floor(gridDirty.minX / pixelsPerBar)))
        let endBar = max(startBar, Int(ceil(gridDirty.maxX / pixelsPerBar)) + 1)

        // Alternating bar shading
        let shadingColor = NSColor.white.withAlphaComponent(0.03).cgColor
        context.setFillColor(shadingColor)
        for bar in startBar..<endBar where bar % 2 == 0 {
            let x = CGFloat(bar) * pixelsPerBar
            let rect = CGRect(x: x, y: gridDirty.minY, width: pixelsPerBar, height: gridDirty.height)
            context.fill(rect)
        }

        // Batch bar lines into a single path
        let barLinePath = CGMutablePath()
        for bar in startBar...endBar {
            let barX = CGFloat(bar) * pixelsPerBar
            barLinePath.move(to: CGPoint(x: barX, y: gridDirty.minY))
            barLinePath.addLine(to: CGPoint(x: barX, y: gridDirty.maxY))
        }
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.2).cgColor)
        context.setLineWidth(0.5)
        context.addPath(barLinePath)
        context.strokePath()

        // Batch beat subdivision lines into a single path (only if zoomed in enough)
        if pixelsPerBeat >= 20 {
            let beatLinePath = CGMutablePath()
            for bar in startBar...endBar {
                let barX = CGFloat(bar) * pixelsPerBar
                for beat in 1..<timeSignature.beatsPerBar {
                    let beatX = barX + CGFloat(beat) * pixelsPerBeat
                    if beatX >= gridDirty.minX && beatX <= gridDirty.maxX {
                        beatLinePath.move(to: CGPoint(x: beatX, y: gridDirty.minY))
                        beatLinePath.addLine(to: CGPoint(x: beatX, y: gridDirty.maxY))
                    }
                }
            }
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
            context.setLineWidth(0.5)
            context.addPath(beatLinePath)
            context.strokePath()
        }
    }

    // MARK: - Track Background Drawing

    private func drawTrackBackgrounds(in dirtyRect: NSRect, context: CGContext) {
        let bgColor = NSColor(named: "textBackgroundColor") ?? NSColor.controlBackgroundColor

        // Base background fills the entire grid area so it looks consistent
        // even below the last track. Track-specific fills add their tint on top.
        let gridTop = showRulerAndSections ? Self.trackAreaTop : CGFloat(0)
        let baseRect = NSRect(x: dirtyRect.minX, y: max(dirtyRect.minY, gridTop),
                              width: dirtyRect.width, height: dirtyRect.maxY - max(dirtyRect.minY, gridTop))
        if !baseRect.isEmpty {
            context.setFillColor(bgColor.withAlphaComponent(0.15).cgColor)
            context.fill(baseRect)
        }

        for (index, layout) in trackLayouts.enumerated() {
            let trackRect = NSRect(x: dirtyRect.minX, y: layout.yOrigin, width: dirtyRect.width, height: layout.height)
            guard trackRect.intersects(dirtyRect) else { continue }

            // Track background — additional tint on top of the base fill
            context.setFillColor(bgColor.withAlphaComponent(0.15).cgColor)
            context.fill(trackRect.intersection(dirtyRect))

            // Track separator line at bottom
            let separatorY = layout.yOrigin + layout.height - 0.5
            if separatorY >= dirtyRect.minY && separatorY <= dirtyRect.maxY {
                context.setStrokeColor(NSColor.secondaryLabelColor.withAlphaComponent(0.3).cgColor)
                context.setLineWidth(1)
                context.move(to: CGPoint(x: dirtyRect.minX, y: separatorY))
                context.addLine(to: CGPoint(x: dirtyRect.maxX, y: separatorY))
                context.strokePath()
            }

            _ = index // suppress unused warning
        }
    }

    // MARK: - Container Drawing

    @discardableResult
    private func drawContainers(in dirtyRect: NSRect, context: CGContext) -> Int {
        var drawnCount = 0
        for trackLayout in trackLayouts {
            // Early exit: skip entire track if its Y band doesn't intersect dirty rect
            let trackYRange = NSRect(x: dirtyRect.minX, y: trackLayout.yOrigin, width: 1, height: trackLayout.height)
            guard trackYRange.intersects(dirtyRect) else { continue }

            let colors = colors(for: trackLayout.track.kind)

            for cl in trackLayout.containers {
                // Skip containers outside dirty rect
                guard cl.rect.intersects(dirtyRect) else { continue }
                drawnCount += 1

                let isArmed = cl.container.isRecordArmed

                // Container fill — clipped to dirty rect intersection for efficiency.
                // A container can be 7000+ px wide; filling only the visible slice avoids
                // processing the offscreen majority.
                let fillColor = isArmed ? colors.fillArmed
                    : cl.isSelected ? colors.fillSelected : colors.fillNormal
                let visibleFill = cl.rect.intersection(dirtyRect)
                context.setFillColor(fillColor)
                context.fill(visibleFill)

                // Container border — rounded rect path (CG clips to dirty rect automatically)
                let borderColor = isArmed ? colors.borderArmed
                    : cl.isSelected ? colors.borderSelected : colors.borderNormal
                let borderWidth: CGFloat = (isArmed || cl.isSelected) ? 2 : 1
                let path = CGPath(roundedRect: cl.rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
                context.addPath(path)
                context.setStrokeColor(borderColor)
                context.setLineWidth(borderWidth)
                context.strokePath()

                // Waveform — check tile cache first, fall back to path drawing.
                // Tile bitmaps are capped at 2048px wide so even large containers
                // get cached tiles (stretched during blit — acceptable quality).
                if let peaks = cl.waveformPeaks, !peaks.isEmpty {
                    if let tile = waveformTileCache.tile(forContainerID: cl.container.id, pixelsPerBar: pixelsPerBar) {
                        // Cache hit — blit the pre-rendered CGImage (near-zero cost)
                        context.saveGState()
                        context.clip(to: visibleFill)
                        context.draw(tile.image, in: cl.rect)
                        context.restoreGState()
                    } else if let tile = waveformTileCache.generateTile(
                        containerID: cl.container.id,
                        peaks: peaks,
                        containerLengthBars: cl.container.lengthBars,
                        pixelsPerBar: pixelsPerBar,
                        height: cl.rect.height,
                        color: trackLayout.track.kind.nsColor
                    ) {
                        // Cache miss — generate tile and blit immediately
                        context.saveGState()
                        context.clip(to: visibleFill)
                        context.draw(tile.image, in: cl.rect)
                        context.restoreGState()
                    } else {
                        // Tile generation failed — direct path drawing fallback
                        drawWaveform(peaks: peaks, in: cl.rect, fillColor: colors.waveformFill, strokeColor: colors.waveformStroke, context: context, dirtyRect: dirtyRect)
                    }
                }

                // MIDI minimap
                if let notes = cl.resolvedMIDINotes, !notes.isEmpty {
                    drawMIDIMinimap(notes: notes, container: cl.container, in: cl.rect, color: colors.waveformFill, context: context)
                }

                // Fade overlays
                if cl.enterFade != nil || cl.exitFade != nil {
                    drawFadeOverlay(enterFade: cl.enterFade, exitFade: cl.exitFade, in: cl.rect, context: context)
                }

                // Selection highlight shadow
                if cl.isSelected {
                    context.addPath(path)
                    context.setStrokeColor(colors.selectionHighlight)
                    context.setLineWidth(4)
                    context.strokePath()
                }
            }

            // Crossfade overlays for this track
            for xfade in trackLayout.track.crossfades {
                drawCrossfade(xfade, track: trackLayout.track, trackLayout: trackLayout, in: dirtyRect, context: context)
            }
        }

        // Range selection overlay (bar range from ruler)
        if let range = selectedRange {
            drawRangeSelection(range: range, in: dirtyRect, context: context)
        }
        return drawnCount
    }

    // MARK: - Waveform Drawing

    private func drawWaveform(peaks: [Float], in rect: NSRect, fillColor: CGColor, strokeColor: CGColor, context: CGContext, dirtyRect: NSRect) {
        // Skip waveform for tiny containers — the fill color is enough
        guard rect.width >= 4 else { return }

        let midY = rect.midY
        let halfHeight = rect.height / 2 * 0.9

        // Viewport culling: only draw peaks within dirty rect intersection
        let visibleMinX = max(rect.minX, dirtyRect.minX)
        let visibleMaxX = min(rect.maxX, dirtyRect.maxX)
        guard visibleMinX < visibleMaxX else { return }

        let peakWidth = rect.width / CGFloat(peaks.count)
        let firstIndex = max(0, Int(floor((visibleMinX - rect.minX) / peakWidth)) - 1)
        let lastIndex = min(peaks.count - 1, Int(ceil((visibleMaxX - rect.minX) / peakWidth)) + 1)
        guard firstIndex <= lastIndex else { return }

        // Downsample to at most 1 path point per 2 pixels.
        // At zoomed-out levels peaks are sub-pixel; without this, thousands of
        // path points map to the same few pixels, wasting rasterization time.
        // Using 2px spacing halves path complexity vs 1px with no visible difference.
        let minPointSpacing: CGFloat = 2.0
        let step = max(1, Int(ceil(minPointSpacing / peakWidth)))

        // Build waveform path (top half + bottom half mirror)
        let waveformPath = CGMutablePath()
        let startX = rect.minX + CGFloat(firstIndex) * peakWidth + peakWidth / 2
        waveformPath.move(to: CGPoint(x: startX, y: midY))

        // Top half (left to right) — max amplitude per bucket
        var lastStepIndex = firstIndex
        for i in stride(from: firstIndex, through: lastIndex, by: step) {
            let bucketEnd = min(i + step - 1, lastIndex)
            var maxAmp: Float = 0
            for j in i...bucketEnd {
                let a = abs(peaks[j])
                if a > maxAmp { maxAmp = a }
            }
            let x = rect.minX + CGFloat(i) * peakWidth + peakWidth / 2
            waveformPath.addLine(to: CGPoint(x: x, y: midY - CGFloat(maxAmp) * halfHeight))
            lastStepIndex = i
        }

        // Bridge to bottom
        let endX = rect.minX + CGFloat(lastStepIndex) * peakWidth + peakWidth / 2
        waveformPath.addLine(to: CGPoint(x: endX, y: midY))

        // Bottom half (right to left) — same buckets, mirrored
        for i in stride(from: lastStepIndex, through: firstIndex, by: -step) {
            let bucketEnd = min(i + step - 1, lastIndex)
            var maxAmp: Float = 0
            for j in i...bucketEnd {
                let a = abs(peaks[j])
                if a > maxAmp { maxAmp = a }
            }
            let x = rect.minX + CGFloat(i) * peakWidth + peakWidth / 2
            waveformPath.addLine(to: CGPoint(x: x, y: midY + CGFloat(maxAmp) * halfHeight))
        }
        waveformPath.closeSubpath()

        // Fill waveform — path is already constrained to container rect by construction.
        // Stroke adds the waveform outline. Skip it when peaks are dense (< 4px apart)
        // — the outline is invisible at that density and fillStroke doubles rasterization cost.
        let effectivePointSpacing = peakWidth * CGFloat(step)
        context.addPath(waveformPath)
        context.setFillColor(fillColor)
        if effectivePointSpacing >= 4.0 {
            context.setStrokeColor(strokeColor)
            context.setLineWidth(0.5)
            context.drawPath(using: .fillStroke)
        } else {
            context.fillPath()
        }
    }

    // MARK: - MIDI Minimap Drawing

    private func drawMIDIMinimap(notes: [MIDINoteEvent], container: Container, in rect: NSRect, color: CGColor, context: CGContext) {
        guard !notes.isEmpty else { return }

        // Find pitch range
        var minPitch: UInt8 = 127
        var maxPitch: UInt8 = 0
        for note in notes {
            if note.pitch < minPitch { minPitch = note.pitch }
            if note.pitch > maxPitch { maxPitch = note.pitch }
        }
        let pitchRange = max(CGFloat(maxPitch - minPitch), 12)

        let beatsPerBar = Double(timeSignature.beatsPerBar)
        let totalBeats = container.lengthBars * beatsPerBar
        let invTotalBeats = 1.0 / totalBeats
        let heightMinusPad = rect.height - 4
        let invPitchRange = 1.0 / pitchRange
        let noteH = max(2, heightMinusPad * invPitchRange)

        context.saveGState()
        context.clip(to: rect)

        // Batch all note diamonds into a single path — one fillPath() call total
        let batchedPath = CGMutablePath()
        for note in notes {
            let xFraction = note.startBeat * invTotalBeats
            let widthFraction = note.duration * invTotalBeats

            let noteX = rect.minX + CGFloat(xFraction) * rect.width
            let noteW = max(2, CGFloat(widthFraction) * rect.width)
            let yFraction = 1.0 - (CGFloat(note.pitch - minPitch) * invPitchRange)
            let noteY = rect.minY + yFraction * heightMinusPad + 2

            let centerX = noteX + noteW / 2
            let centerY = noteY + noteH / 2
            let halfSize = min(noteW, noteH, 8) / 2

            batchedPath.move(to: CGPoint(x: centerX, y: centerY - halfSize))
            batchedPath.addLine(to: CGPoint(x: centerX + halfSize, y: centerY))
            batchedPath.addLine(to: CGPoint(x: centerX, y: centerY + halfSize))
            batchedPath.addLine(to: CGPoint(x: centerX - halfSize, y: centerY))
            batchedPath.closeSubpath()
        }

        context.setFillColor(color)
        context.addPath(batchedPath)
        context.fillPath()

        context.restoreGState()
    }

    // MARK: - Fade Overlay Drawing

    private func drawFadeOverlay(enterFade: FadeSettings?, exitFade: FadeSettings?, in rect: NSRect, context: CGContext) {
        context.saveGState()
        context.clip(to: rect)

        // Enter fade (left side) — darkened area showing gain ramp 0→1
        if let fade = enterFade, fade.duration > 0 {
            let fadeWidth = CGFloat(fade.duration) * pixelsPerBar
            let steps = max(Int(fadeWidth / 2), 20)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let gain = fade.curve.gain(at: t)
                let x = rect.minX + CGFloat(t) * fadeWidth
                let y = rect.minY + CGFloat(gain) * rect.height
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: rect.minX + fadeWidth, y: rect.minY))
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
            context.fillPath()
        }

        // Exit fade (right side) — darkened area showing gain ramp 1→0
        if let fade = exitFade, fade.duration > 0 {
            let fadeWidth = CGFloat(fade.duration) * pixelsPerBar
            let steps = max(Int(fadeWidth / 2), 20)
            let startX = rect.maxX - fadeWidth
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let gain = fade.curve.gain(at: 1.0 - t)
                let x = startX + CGFloat(t) * fadeWidth
                let y = rect.minY + CGFloat(gain) * rect.height
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: startX, y: rect.minY))
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
            context.fillPath()
        }

        context.restoreGState()
    }

    // MARK: - Crossfade Drawing

    private func drawCrossfade(_ xfade: Crossfade, track: Track, trackLayout: TrackLayout, in dirtyRect: NSRect, context: CGContext) {
        guard let containerA = track.containers.first(where: { $0.id == xfade.containerAID }),
              let containerB = track.containers.first(where: { $0.id == xfade.containerBID }) else { return }

        let overlap = xfade.duration(containerA: containerA, containerB: containerB)
        guard overlap > 0 else { return }

        let xStart = CGFloat(containerB.startBar - 1.0) * pixelsPerBar
        let width = CGFloat(overlap) * pixelsPerBar
        let xfadeRect = NSRect(x: xStart, y: trackLayout.yOrigin + 2, width: width, height: trackLayout.height - 4)

        guard xfadeRect.intersects(dirtyRect) else { return }

        context.saveGState()

        // Semi-transparent background
        context.setFillColor(NSColor.white.withAlphaComponent(0.08).cgColor)
        context.fill(xfadeRect)

        // X-pattern (crossfade indicator)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(1.5)

        // Top-left to bottom-right
        context.move(to: CGPoint(x: xfadeRect.minX, y: xfadeRect.minY))
        context.addLine(to: CGPoint(x: xfadeRect.maxX, y: xfadeRect.maxY))
        context.strokePath()

        // Bottom-left to top-right
        context.move(to: CGPoint(x: xfadeRect.minX, y: xfadeRect.maxY))
        context.addLine(to: CGPoint(x: xfadeRect.maxX, y: xfadeRect.minY))
        context.strokePath()

        context.restoreGState()
    }

    // MARK: - Range Selection Drawing

    private func drawRangeSelection(range: ClosedRange<Int>, in dirtyRect: NSRect, context: CGContext) {
        let startX = CGFloat(range.lowerBound) * pixelsPerBar
        let endX = CGFloat(range.upperBound + 1) * pixelsPerBar
        let totalHeight = trackLayouts.last.map { $0.yOrigin + $0.height } ?? bounds.height
        let selRect = NSRect(x: startX, y: 0, width: endX - startX, height: totalHeight)

        guard selRect.intersects(dirtyRect) else { return }

        context.saveGState()
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor)
        context.fill(selRect.intersection(dirtyRect))

        // Selection edges
        context.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1)
        if startX >= dirtyRect.minX && startX <= dirtyRect.maxX {
            context.move(to: CGPoint(x: startX, y: dirtyRect.minY))
            context.addLine(to: CGPoint(x: startX, y: dirtyRect.maxY))
            context.strokePath()
        }
        if endX >= dirtyRect.minX && endX <= dirtyRect.maxX {
            context.move(to: CGPoint(x: endX, y: dirtyRect.minY))
            context.addLine(to: CGPoint(x: endX, y: dirtyRect.maxY))
            context.strokePath()
        }
        context.restoreGState()
    }

    // MARK: - Intrinsic Size

    public override var intrinsicContentSize: NSSize {
        let fallback = showRulerAndSections ? Self.trackAreaTop + 400 : CGFloat(400)
        let totalHeight = trackLayouts.last.map { $0.yOrigin + $0.height } ?? fallback
        return NSSize(width: CGFloat(totalBars) * pixelsPerBar, height: totalHeight)
    }
}
