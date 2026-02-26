import AppKit
import Metal
import QuartzCore
import LoopsCore

public final class PlaybackGridNSView: NSView {
    public var debugLabel: String = "grid"

    private var renderer: PlaybackGridRenderer?
    private let metalLayer: CAMetalLayer
    private let textOverlayLayer = TimelineTextOverlayLayer()

    private let sceneBuilder = PlaybackGridSceneBuilder()
    private let pickingRenderer = PlaybackGridPickingRenderer()
    private var interactionController = PlaybackGridInteractionController(sink: nil)
    private var commandSink: (any PlaybackGridCommandSink)?
    private var contextMenuTargetContainerID: ID<Container>?
    private var contextMenuTargetTrackID: ID<Track>?

    private var snapshot: PlaybackGridSnapshot?
    private var scene = PlaybackGridScene(trackLayouts: [], sectionLayouts: [], contentHeight: PlaybackGridLayout.bottomPadding)

    private var needsBufferRebuild = true
    private var configureWillRedraw = false

    private var scrollObservers: [NSObjectProtocol] = []
    private var lastObservedVisibleRect: CGRect = .null
    private var lastCursorXSent: CGFloat?
    private var lastCursorPoint: CGPoint?
    private var liveCursorX: CGFloat?
    private var midiRangeScrollAccumulator: CGFloat = 0
    private var hoveredPick: GridPickObject = .none
    private var cachedMIDINoteLabels: [TimelineTextOverlayLayer.MIDINoteLabelLayout] = []

    public var waveformPeaksProvider: ((_ container: Container) -> [Float]?)? {
        didSet { sceneBuilder.waveformPeaksProvider = waveformPeaksProvider }
    }

    public var audioDurationBarsProvider: ((_ container: Container) -> Double?)? {
        didSet { sceneBuilder.audioDurationBarsProvider = audioDurationBarsProvider }
    }

    public var resolvedMIDISequenceProvider: ((_ container: Container) -> MIDISequence?)? {
        didSet { sceneBuilder.resolvedMIDISequenceProvider = resolvedMIDISequenceProvider }
    }

    public var onCursorPosition: ((CGFloat?) -> Void)?

    private let playheadLayer = CALayer()
    private let cursorLayer = CALayer()

    public private(set) var configureSkipCount = 0
    public private(set) var configureHitCount = 0
    public private(set) var lastDrawDuration: CFTimeInterval = 0
    private var lastDebugLogTime: CFTimeInterval = 0
    private static let debugLogsEnabled: Bool = {
        ProcessInfo.processInfo.environment["LOOPS_GRID_DEBUG"] == "1"
        || UserDefaults.standard.bool(forKey: "PlaybackGridDebugLogs")
    }()
    private static let publishCursorToViewModel: Bool = {
        ProcessInfo.processInfo.environment["LOOPS_GRID_CURSOR_PUBLISH"] == "1"
        || UserDefaults.standard.bool(forKey: "PlaybackGridPublishCursorModel")
    }()
    private static let cursorPublishInterval: CFTimeInterval = 1.0 / 12.0
    private var lastCursorPublishTime: CFTimeInterval = 0

    private static func makeMetalLayer() -> CAMetalLayer {
        let layer = CAMetalLayer()
        layer.device = MTLCreateSystemDefaultDevice()
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = false
        return layer
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

    deinit {
        teardownScrollObservation()
        NotificationCenter.default.removeObserver(self)
    }

    private func commonInit() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        guard let backingLayer = layer else { return }

        if let device = metalLayer.device {
            renderer = try? PlaybackGridRenderer(device: device)
        }

        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        backingLayer.addSublayer(metalLayer)

        textOverlayLayer.zPosition = 1
        textOverlayLayer.contentsScale = metalLayer.contentsScale
        backingLayer.addSublayer(textOverlayLayer)

        playheadLayer.backgroundColor = NSColor.systemRed.cgColor
        playheadLayer.zPosition = 100
        playheadLayer.isHidden = true
        playheadLayer.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "frame": NSNull(),
            "hidden": NSNull()
        ]
        backingLayer.addSublayer(playheadLayer)

        cursorLayer.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
        cursorLayer.zPosition = 99
        cursorLayer.isHidden = true
        cursorLayer.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "frame": NSNull(),
            "hidden": NSNull()
        ]
        backingLayer.addSublayer(cursorLayer)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invalidateAndRedraw),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        sceneBuilder.waveformPeaksProvider = waveformPeaksProvider
        sceneBuilder.audioDurationBarsProvider = audioDurationBarsProvider
        sceneBuilder.resolvedMIDISequenceProvider = resolvedMIDISequenceProvider
    }

    public override var isFlipped: Bool { true }
    public override var wantsUpdateLayer: Bool { true }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        setupScrollObservation()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupScrollObservation()

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

    public func setCommandSink(_ sink: PlaybackGridCommandSink?) {
        commandSink = sink
        interactionController.setCommandSink(sink)
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        guard let snapshot else { return super.menu(for: event) }
        let local = convert(event.locationInWindow, from: nil)
        let pick = pickingRenderer.pick(
            at: local,
            scene: scene,
            snapshot: snapshot,
            visibleRect: visibleRect,
            canvasWidth: bounds.width
        )

        guard pick.kind == .containerZone,
              let containerID = pick.containerID,
              let trackID = pick.trackID else {
            return super.menu(for: event)
        }

        contextMenuTargetContainerID = containerID
        contextMenuTargetTrackID = trackID
        commandSink?.selectContainer(containerID, trackID: trackID, modifiers: event.modifierFlags)

        let menu = NSMenu(title: "Container")
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(contextCopyContainer(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Duplicate", action: #selector(contextDuplicateContainer(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Split at Playhead", action: #selector(contextSplitContainer(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Delete", action: #selector(contextDeleteContainer(_:)), keyEquivalent: ""))
        for item in menu.items {
            item.target = self
        }
        return menu
    }

    @objc private func contextCopyContainer(_ sender: NSMenuItem) {
        withContextTarget { containerID, trackID in
            commandSink?.copyContainer(containerID, trackID: trackID)
        }
    }

    @objc private func contextDuplicateContainer(_ sender: NSMenuItem) {
        withContextTarget { containerID, trackID in
            commandSink?.duplicateContainer(containerID, trackID: trackID)
        }
    }

    @objc private func contextSplitContainer(_ sender: NSMenuItem) {
        withContextTarget { containerID, trackID in
            commandSink?.splitContainerAtPlayhead(containerID, trackID: trackID)
        }
    }

    @objc private func contextDeleteContainer(_ sender: NSMenuItem) {
        withContextTarget { containerID, trackID in
            commandSink?.deleteContainer(containerID, trackID: trackID)
        }
    }

    private func withContextTarget(_ action: (_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void) {
        guard let containerID = contextMenuTargetContainerID,
              let trackID = contextMenuTargetTrackID else { return }
        action(containerID, trackID)
    }

    public func configure(snapshot newSnapshot: PlaybackGridSnapshot) {
        PlaybackGridPerfLogger.bump("grid.configure.calls")
        if let oldSnapshot = snapshot {
            let compareStart = PlaybackGridPerfLogger.begin()
            let isEqual = staticSnapshotEqual(oldSnapshot, newSnapshot)
            PlaybackGridPerfLogger.end("grid.configure.staticEqual.ms", compareStart)
            if isEqual {
                PlaybackGridPerfLogger.bump("grid.configure.skip")
                configureSkipCount += 1
                snapshot = newSnapshot
                updateOverlayLayers(using: newSnapshot)
                return
            }
        }

        PlaybackGridPerfLogger.bump("grid.configure.hit")
        configureHitCount += 1
        snapshot = newSnapshot
        let buildStart = PlaybackGridPerfLogger.begin()
        scene = sceneBuilder.build(snapshot: newSnapshot)
        PlaybackGridPerfLogger.end("grid.configure.sceneBuild.ms", buildStart)
        needsBufferRebuild = true
        configureWillRedraw = true
        needsDisplay = true

        if Self.debugLogsEnabled {
            print("[GRIDDBG][\(debugLabel)] configure tracks=\(newSnapshot.tracks.count) showRuler=\(newSnapshot.showRulerAndSections) ppb=\(String(format: "%.2f", newSnapshot.pixelsPerBar)) bars=\(newSnapshot.totalBars) minH=\(String(format: "%.1f", newSnapshot.minimumContentHeight)) sceneH=\(String(format: "%.1f", scene.contentHeight)) sceneTracks=\(scene.trackLayouts.count) bounds=\(NSStringFromRect(bounds))")
        }

        updateOverlayLayers(using: newSnapshot)
        invalidateIntrinsicContentSize()
    }

    private func updateOverlayLayers(using snapshot: PlaybackGridSnapshot) {
        let overlayStart = PlaybackGridPerfLogger.begin()
        defer { PlaybackGridPerfLogger.end("grid.configure.overlayLayers.ms", overlayStart) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let playheadX = CGFloat(snapshot.playheadBar - 1.0) * snapshot.pixelsPerBar
        playheadLayer.frame = CGRect(x: playheadX - 0.5, y: 0, width: 1, height: scene.contentHeight)
        playheadLayer.isHidden = false

        if let cursorX = liveCursorX ?? snapshot.cursorX {
            cursorLayer.frame = CGRect(x: cursorX - 0.5, y: 0, width: 1, height: scene.contentHeight)
            cursorLayer.isHidden = false
        } else {
            cursorLayer.isHidden = true
        }

        CATransaction.commit()
    }

    private func setupScrollObservation() {
        teardownScrollObservation()

        var clipViews: [NSClipView] = []
        var cursor: NSView? = superview
        while let view = cursor {
            if let clip = view as? NSClipView, !clipViews.contains(where: { $0 === clip }) {
                clipViews.append(clip)
            }
            cursor = view.superview
        }

        if clipViews.isEmpty, let clip = enclosingScrollView?.contentView {
            clipViews.append(clip)
        }

        for clip in clipViews {
            clip.postsBoundsChangedNotifications = true
            let observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clip,
                queue: .main
            ) { [weak self] _ in
                self?.handleScrollChange()
            }
            scrollObservers.append(observer)
        }
    }

    private func teardownScrollObservation() {
        guard !scrollObservers.isEmpty else { return }
        for observer in scrollObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        scrollObservers.removeAll()
    }

    private func handleScrollChange() {
        PlaybackGridPerfLogger.bump("grid.scroll.boundsDidChange")
        let currentVisible = visibleRect.intersection(bounds)
        guard !currentVisible.isNull else { return }
        if !lastObservedVisibleRect.isNull,
           currentVisible.equalTo(lastObservedVisibleRect) {
            return
        }
        lastObservedVisibleRect = currentVisible
        needsBufferRebuild = true
        needsDisplay = true
    }

    public override func setFrameSize(_ newSize: NSSize) {
        let old = frame.size
        super.setFrameSize(newSize)

        if old != newSize && !configureWillRedraw {
            PlaybackGridPerfLogger.bump("grid.frameSize.changed")
            needsBufferRebuild = true
            needsDisplay = true
        }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }

        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    public override func mouseMoved(with event: NSEvent) {
        PlaybackGridPerfLogger.bump("input.mouseMoved")
        let local = convert(event.locationInWindow, from: nil)
        if let last = lastCursorPoint,
           abs(last.x - local.x) < 0.5,
           abs(last.y - local.y) < 0.5 {
            return
        }
        lastCursorPoint = local
        updateLiveCursor(at: local.x)

        // During active drags/edits we do not need hover picking. Skipping it
        // avoids CPU-heavy hit-tests while pointer events are already saturated.
        if interactionController.isInteractionActive {
            PlaybackGridPerfLogger.bump("grid.pick.skippedWhileInteracting")
            return
        }

        guard let snapshot else { return }
        let pickStart = PlaybackGridPerfLogger.begin()
        let pick = pickingRenderer.pick(
            at: local,
            scene: scene,
            snapshot: snapshot,
            visibleRect: visibleRect,
            canvasWidth: bounds.width
        )
        PlaybackGridPerfLogger.end("grid.pick.mouseMoved.ms", pickStart)

        if isPointNearInlineMIDILaneResizeHandle(local, snapshot: snapshot) {
            NSCursor.resizeUpDown.set()
        } else {
            switch pick.kind {
            case .midiNote:
                if pick.zone == .resizeLeft || pick.zone == .resizeRight {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.openHand.set()
                }
            case .containerZone:
                if pick.zone == .resizeLeft || pick.zone == .resizeRight {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            default:
                NSCursor.arrow.set()
            }
        }

        let newHoveredPick: GridPickObject
        switch pick.kind {
        case .containerZone, .midiNote, .automationBreakpoint:
            newHoveredPick = pick
        default:
            newHoveredPick = .none
        }
        if newHoveredPick != hoveredPick {
            hoveredPick = newHoveredPick
            needsBufferRebuild = true
            needsDisplay = true
        }
    }

    public override func mouseExited(with event: NSEvent) {
        PlaybackGridPerfLogger.bump("input.mouseExited")
        lastCursorXSent = nil
        lastCursorPoint = nil
        liveCursorX = nil
        cursorLayer.isHidden = true
        if Self.publishCursorToViewModel {
            onCursorPosition?(nil)
        }
        if hoveredPick != .none {
            hoveredPick = .none
            needsBufferRebuild = true
            needsDisplay = true
        }
        NSCursor.arrow.set()
    }

    public override func mouseDown(with event: NSEvent) {
        PlaybackGridPerfLogger.bump("input.mouseDown")
        guard let snapshot else { return }
        let local = convert(event.locationInWindow, from: nil)
        let pickStart = PlaybackGridPerfLogger.begin()
        let pick = pickingRenderer.pick(
            at: local,
            scene: scene,
            snapshot: snapshot,
            visibleRect: visibleRect,
            canvasWidth: bounds.width
        )
        PlaybackGridPerfLogger.end("grid.pick.mouseDown.ms", pickStart)

        if event.clickCount >= 2,
           pick.kind == .automationBreakpoint,
           presentAutomationValueEditor(pick: pick, event: event, snapshot: snapshot) {
            return
        }

        interactionController.handleMouseDown(
            event: event,
            point: local,
            pick: pick,
            snapshot: snapshot
        )
    }

    public override func mouseDragged(with event: NSEvent) {
        PlaybackGridPerfLogger.bump("input.mouseDragged")
        guard let snapshot else { return }
        let local = convert(event.locationInWindow, from: nil)
        updateLiveCursor(at: local.x)
        let visualChanged = interactionController.handleMouseDragged(
            point: local,
            snapshot: snapshot,
            modifiers: event.modifierFlags
        )
        if visualChanged {
            needsDisplay = true
        }
    }

    public override func mouseUp(with event: NSEvent) {
        PlaybackGridPerfLogger.bump("input.mouseUp")
        guard let snapshot else { return }
        let local = convert(event.locationInWindow, from: nil)
        interactionController.handleMouseUp(
            point: local,
            snapshot: snapshot,
            modifiers: event.modifierFlags
        )
    }

    public override func scrollWheel(with event: NSEvent) {
        PlaybackGridPerfLogger.bump("input.scrollWheel")
        guard let snapshot else {
            super.scrollWheel(with: event)
            return
        }
        let local = convert(event.locationInWindow, from: nil)
        guard let trackID = inlineMIDITrackID(at: local, snapshot: snapshot) else {
            super.scrollWheel(with: event)
            return
        }

        let mods = event.modifierFlags
        let signedStep: CGFloat = event.scrollingDeltaY > 0 ? 1 : -1
        if mods.contains(.command) {
            commandSink?.adjustInlineMIDIRowHeight(trackID: trackID, delta: signedStep)
            return
        }
        if mods.contains(.option) {
            commandSink?.shiftInlineMIDIPitchRange(trackID: trackID, semitoneDelta: Int(signedStep))
            return
        }
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            // Default inline MIDI wheel behavior: pan pitch range up/down.
            midiRangeScrollAccumulator += event.scrollingDeltaY
            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 14 : 1
            while abs(midiRangeScrollAccumulator) >= threshold {
                let semitoneStep = midiRangeScrollAccumulator > 0 ? 1 : -1
                commandSink?.shiftInlineMIDIPitchRange(trackID: trackID, semitoneDelta: semitoneStep)
                midiRangeScrollAccumulator -= CGFloat(semitoneStep) * threshold
            }
            return
        }
        midiRangeScrollAccumulator = 0
        super.scrollWheel(with: event)
    }

    public override func magnify(with event: NSEvent) {
        PlaybackGridPerfLogger.bump("input.magnify")
        guard let snapshot else {
            super.magnify(with: event)
            return
        }
        let local = convert(event.locationInWindow, from: nil)
        guard let trackID = inlineMIDITrackID(at: local, snapshot: snapshot) else {
            super.magnify(with: event)
            return
        }
        // Positive magnification zooms in (larger rows), negative zooms out.
        let delta = max(-8.0, min(8.0, CGFloat(event.magnification * 24.0)))
        guard abs(delta) > 0.01 else { return }
        commandSink?.adjustInlineMIDIRowHeight(trackID: trackID, delta: delta)
    }

    public override func updateLayer() {
        let updateStart = PlaybackGridPerfLogger.begin()
        defer { PlaybackGridPerfLogger.end("grid.updateLayer.total.ms", updateStart) }
        PlaybackGridPerfLogger.bump("grid.updateLayer.calls")

        configureWillRedraw = false
        let drawStart = CACurrentMediaTime()

        guard let renderer, let snapshot else { return }

        if scrollObservers.isEmpty {
            setupScrollObservation()
        }

        let rawVisible = visibleRect
        let visible = rawVisible.intersection(bounds)
        guard visible.width > 0, visible.height > 0 else { return }

        let scale = metalLayer.contentsScale

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = visible
        metalLayer.drawableSize = CGSize(width: visible.width * scale, height: visible.height * scale)
        textOverlayLayer.frame = visible
        CATransaction.commit()

        let drawableStart = PlaybackGridPerfLogger.begin()
        guard let drawable = metalLayer.nextDrawable() else {
            PlaybackGridPerfLogger.bump("grid.updateLayer.noDrawable")
            return
        }
        PlaybackGridPerfLogger.end("grid.updateLayer.nextDrawable.ms", drawableStart)
        let drawableWaitMs = (CACurrentMediaTime() - drawableStart) * 1000.0
        if drawableWaitMs > 4.0 {
            PlaybackGridPerfLogger.bump("grid.updateLayer.nextDrawable.stall")
        }

        let waitStart = PlaybackGridPerfLogger.begin()
        guard renderer.frameSemaphore.wait(timeout: .now()) == .success else {
            PlaybackGridPerfLogger.bump("grid.updateLayer.semaphoreTimeout")
            return
        }
        PlaybackGridPerfLogger.end("grid.updateLayer.semaphoreWait.ms", waitStart)
        let midiOverlays = interactionController.activeMIDINoteOverlays

        if needsBufferRebuild {
            PlaybackGridPerfLogger.bump("grid.updateLayer.bufferRebuild")
            let rebuildStart = PlaybackGridPerfLogger.begin()
            renderer.buildBuffers(
                scene: scene,
                snapshot: snapshot,
                canvasSize: bounds.size,
                visibleRect: visible,
                focusedPick: hoveredPick
            )
            PlaybackGridPerfLogger.end("grid.updateLayer.buildBuffers.ms", rebuildStart)
            needsBufferRebuild = false
        }
        let overlayBufferStart = PlaybackGridPerfLogger.begin()
        renderer.buildMIDIOverlayBuffer(
            scene: scene,
            snapshot: snapshot,
            midiOverlays: midiOverlays
        )
        PlaybackGridPerfLogger.end("grid.updateLayer.midiOverlayBuffer.ms", overlayBufferStart)

        if Self.debugLogsEnabled {
            let now = CACurrentMediaTime()
            if now - lastDebugLogTime > 0.5 {
                lastDebugLogTime = now
                let stats = renderer.debugStats
                print("[GRIDDBG][\(debugLabel)] draw visible=\(NSStringFromRect(visible)) rawVisible=\(NSStringFromRect(rawVisible)) bounds=\(NSStringFromRect(bounds)) canvasH=\(String(format: "%.1f", bounds.height)) stats rect=\(stats.rectCount) line=\(stats.lineCount) wave=\(stats.waveformCount) midi=\(stats.midiCount) border=\(stats.borderCount)")
            }
        }

        let textStart = PlaybackGridPerfLogger.begin()
        textOverlayLayer.pixelsPerBar = snapshot.pixelsPerBar
        textOverlayLayer.totalBars = snapshot.totalBars
        textOverlayLayer.timeSignature = snapshot.timeSignature
        textOverlayLayer.sections = scene.asLegacySectionLayouts()
        textOverlayLayer.selectedRange = snapshot.selectedRange
        textOverlayLayer.showRulerAndSections = snapshot.showRulerAndSections
        textOverlayLayer.viewportOrigin = visible.origin
        if interactionController.isInteractionActive {
            // Preserve previously visible note labels while dragging and only add
            // the actively dragged live-note labels. This avoids costly relayout
            // of the whole MIDI text set and prevents labels from disappearing.
            let liveLabels = buildLiveMIDINoteOverlayLabels(
                snapshot: snapshot,
                midiOverlays: midiOverlays
            )
            textOverlayLayer.midiNoteLabels = cachedMIDINoteLabels + liveLabels
        } else {
            let labels = buildMIDINoteLabels(
                snapshot: snapshot,
                midiOverlays: midiOverlays
            )
            cachedMIDINoteLabels = labels
            textOverlayLayer.midiNoteLabels = labels
        }
        if textOverlayLayer.updateIfNeeded() {
            textOverlayLayer.displayIfNeeded()
        }
        PlaybackGridPerfLogger.end("grid.updateLayer.textOverlay.ms", textStart)

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1)

        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else {
            renderer.frameSemaphore.signal()
            PlaybackGridPerfLogger.bump("grid.updateLayer.encoderFailed")
            return
        }

        let texW = drawable.texture.width
        let texH = drawable.texture.height

        encoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(texW),
            height: Double(texH),
            znear: 0,
            zfar: 1
        ))

        let encodeStart = PlaybackGridPerfLogger.begin()
        renderer.encode(
            into: encoder,
            visibleRect: visible,
            canvasHeight: bounds.height,
            viewportSize: MTLSize(width: texW, height: texH, depth: 1),
            pixelsPerBar: snapshot.pixelsPerBar
        )
        PlaybackGridPerfLogger.end("grid.updateLayer.encode.ms", encodeStart)

        encoder.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.renderer?.frameSemaphore.signal()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()

        lastDrawDuration = CACurrentMediaTime() - drawStart
        PlaybackGridPerfLogger.recordDurationMs("grid.updateLayer.lastDraw.ms", lastDrawDuration * 1000.0)
    }

    public override var intrinsicContentSize: NSSize {
        guard let snapshot else {
            return NSSize(width: 2000, height: PlaybackGridLayout.trackAreaTop + 400)
        }

        let width = CGFloat(snapshot.totalBars) * snapshot.pixelsPerBar
        return NSSize(width: width, height: scene.contentHeight)
    }

    private func staticSnapshotEqual(_ lhs: PlaybackGridSnapshot, _ rhs: PlaybackGridSnapshot) -> Bool {
        lhs.tracks == rhs.tracks
            && lhs.sections == rhs.sections
            && lhs.timeSignature == rhs.timeSignature
            && lhs.pixelsPerBar == rhs.pixelsPerBar
            && lhs.totalBars == rhs.totalBars
            && lhs.trackHeights == rhs.trackHeights
            && lhs.inlineMIDILaneHeights == rhs.inlineMIDILaneHeights
            && lhs.inlineMIDIConfigs == rhs.inlineMIDIConfigs
            && lhs.automationExpandedTrackIDs == rhs.automationExpandedTrackIDs
            && lhs.automationSubLaneHeight == rhs.automationSubLaneHeight
            && lhs.automationToolbarHeight == rhs.automationToolbarHeight
            && lhs.defaultTrackHeight == rhs.defaultTrackHeight
            && lhs.gridMode == rhs.gridMode
            && lhs.selectedAutomationTool == rhs.selectedAutomationTool
            && lhs.selectedContainerIDs == rhs.selectedContainerIDs
            && lhs.selectedSectionID == rhs.selectedSectionID
            && lhs.selectedRange == rhs.selectedRange
            && lhs.rangeSelection == rhs.rangeSelection
            && lhs.isSnapEnabled == rhs.isSnapEnabled
            && lhs.showRulerAndSections == rhs.showRulerAndSections
            && lhs.bottomPadding == rhs.bottomPadding
            && lhs.minimumContentHeight == rhs.minimumContentHeight
    }

    private func buildMIDINoteLabels(
        snapshot: PlaybackGridSnapshot,
        midiOverlays: [PlaybackGridMIDINoteOverlay]
    ) -> [TimelineTextOverlayLayer.MIDINoteLabelLayout] {
        var labels: [TimelineTextOverlayLayer.MIDINoteLabelLayout] = []
        let focusedNoteID: ID<MIDINoteEvent>? = hoveredPick.kind == .midiNote ? hoveredPick.midiNoteID : nil
        let liveOverlayNotes = midiOverlays.filter { !$0.isGhost }
        if !liveOverlayNotes.isEmpty {
            var trackLayoutsByID: [ID<Track>: PlaybackGridTrackLayout] = [:]
            var containerLayoutsByID: [ID<Container>: PlaybackGridContainerLayout] = [:]
            for trackLayout in scene.trackLayouts {
                trackLayoutsByID[trackLayout.track.id] = trackLayout
                for containerLayout in trackLayout.containers {
                    containerLayoutsByID[containerLayout.container.id] = containerLayout
                }
            }
            for overlay in liveOverlayNotes {
                guard let trackLayout = trackLayoutsByID[overlay.trackID],
                      let containerLayout = containerLayoutsByID[overlay.containerID] else {
                    continue
                }
                let midiRect = midiEditorRect(
                    trackLayout: trackLayout,
                    for: containerLayout,
                    snapshot: snapshot
                )
                let inlineMIDILaneHeight = snapshot.inlineMIDILaneHeights[trackLayout.track.id] ?? 0
                let laneHeight = inlineMIDILaneHeight > 0
                    ? inlineMIDILaneHeight
                    : (snapshot.trackHeights[trackLayout.track.id] ?? snapshot.defaultTrackHeight)
                let resolved = PlaybackGridMIDIViewResolver.resolveTrackLayout(
                    trackLayout: trackLayout,
                    laneHeight: laneHeight,
                    snapshot: snapshot
                )
                guard let noteRect = PlaybackGridMIDIViewResolver.noteRect(
                    note: overlay.note,
                    containerLengthBars: containerLayout.container.lengthBars,
                    laneRect: midiRect,
                    timeSignature: snapshot.timeSignature,
                    resolved: resolved
                ) else { continue }
                guard noteRect.width >= 20, noteRect.height >= 10 else { continue }
                labels.append(.init(
                    text: PianoLayout.noteName(overlay.note.pitch),
                    worldRect: noteRect,
                    isFocused: true
                ))
            }
            return labels
        }

        let liveOverlayNoteIDs = Set(liveOverlayNotes.map(\.note.id))
        var midiLayoutsByTrack: [ID<Track>: PlaybackGridMIDIResolvedLayout] = [:]

        for trackLayout in scene.trackLayouts where trackLayout.track.kind == .midi {
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

        for trackLayout in scene.trackLayouts where trackLayout.track.kind == .midi {
            let inlineMIDILaneHeight = snapshot.inlineMIDILaneHeights[trackLayout.track.id] ?? 0
            guard inlineMIDILaneHeight > 0 else { continue }
            guard let resolved = midiLayoutsByTrack[trackLayout.track.id] else { continue }
            for containerLayout in trackLayout.containers {
                guard let notes = containerLayout.resolvedMIDINotes, !notes.isEmpty else { continue }
                let midiRect = midiEditorRect(
                    trackLayout: trackLayout,
                    for: containerLayout,
                    snapshot: snapshot
                )
                for note in notes {
                    if liveOverlayNoteIDs.contains(note.id) {
                        continue
                    }
                    guard let noteRect = PlaybackGridMIDIViewResolver.noteRect(
                        note: note,
                        containerLengthBars: containerLayout.container.lengthBars,
                        laneRect: midiRect,
                        timeSignature: snapshot.timeSignature,
                        resolved: resolved
                    ) else { continue }
                    guard noteRect.width >= 30, noteRect.height >= 11 else { continue }
                    labels.append(.init(
                        text: PianoLayout.noteName(note.pitch),
                        worldRect: noteRect,
                        isFocused: focusedNoteID == note.id
                    ))
                }
            }
        }

        for overlay in liveOverlayNotes {
            guard let trackLayout = scene.trackLayouts.first(where: { $0.track.id == overlay.trackID }),
                  let containerLayout = trackLayout.containers.first(where: { $0.container.id == overlay.containerID }) else {
                continue
            }
            let midiRect = midiEditorRect(
                trackLayout: trackLayout,
                for: containerLayout,
                snapshot: snapshot
            )
            let resolved = midiLayoutsByTrack[overlay.trackID]
                ?? PlaybackGridMIDIViewResolver.resolveTrackLayout(
                    trackLayout: trackLayout,
                    laneHeight: midiRect.height,
                    snapshot: snapshot
                )
            guard let noteRect = PlaybackGridMIDIViewResolver.noteRect(
                note: overlay.note,
                containerLengthBars: containerLayout.container.lengthBars,
                laneRect: midiRect,
                timeSignature: snapshot.timeSignature,
                resolved: resolved
            ) else { continue }
            guard noteRect.width >= 30, noteRect.height >= 11 else { continue }
            labels.append(.init(
                text: PianoLayout.noteName(overlay.note.pitch),
                worldRect: noteRect,
                isFocused: true
            ))
        }
        return labels
    }

    private func buildLiveMIDINoteOverlayLabels(
        snapshot: PlaybackGridSnapshot,
        midiOverlays: [PlaybackGridMIDINoteOverlay]
    ) -> [TimelineTextOverlayLayer.MIDINoteLabelLayout] {
        let liveOverlayNotes = midiOverlays.filter { !$0.isGhost }
        guard !liveOverlayNotes.isEmpty else { return [] }

        var labels: [TimelineTextOverlayLayer.MIDINoteLabelLayout] = []
        var trackLayoutsByID: [ID<Track>: PlaybackGridTrackLayout] = [:]
        var containerLayoutsByID: [ID<Container>: PlaybackGridContainerLayout] = [:]
        for trackLayout in scene.trackLayouts {
            trackLayoutsByID[trackLayout.track.id] = trackLayout
            for containerLayout in trackLayout.containers {
                containerLayoutsByID[containerLayout.container.id] = containerLayout
            }
        }

        for overlay in liveOverlayNotes {
            guard let trackLayout = trackLayoutsByID[overlay.trackID],
                  let containerLayout = containerLayoutsByID[overlay.containerID] else {
                continue
            }
            let midiRect = midiEditorRect(
                trackLayout: trackLayout,
                for: containerLayout,
                snapshot: snapshot
            )
            let inlineMIDILaneHeight = snapshot.inlineMIDILaneHeights[trackLayout.track.id] ?? 0
            let laneHeight = inlineMIDILaneHeight > 0
                ? inlineMIDILaneHeight
                : (snapshot.trackHeights[trackLayout.track.id] ?? snapshot.defaultTrackHeight)
            let resolved = PlaybackGridMIDIViewResolver.resolveTrackLayout(
                trackLayout: trackLayout,
                laneHeight: laneHeight,
                snapshot: snapshot
            )
            guard let noteRect = PlaybackGridMIDIViewResolver.noteRect(
                note: overlay.note,
                containerLengthBars: containerLayout.container.lengthBars,
                laneRect: midiRect,
                timeSignature: snapshot.timeSignature,
                resolved: resolved
            ) else { continue }
            guard noteRect.width >= 20, noteRect.height >= 10 else { continue }
            labels.append(.init(
                text: PianoLayout.noteName(overlay.note.pitch),
                worldRect: noteRect,
                isFocused: true
            ))
        }
        return labels
    }

    private func updateLiveCursor(at x: CGFloat) {
        if let last = lastCursorXSent, abs(last - x) >= 0.5 {
            lastCursorXSent = x
        } else if lastCursorXSent == nil {
            lastCursorXSent = x
        }
        liveCursorX = x
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.frame = CGRect(x: x - 0.5, y: 0, width: 1, height: scene.contentHeight)
        cursorLayer.isHidden = false
        CATransaction.commit()

        if Self.publishCursorToViewModel {
            let now = CACurrentMediaTime()
            if (now - lastCursorPublishTime) >= Self.cursorPublishInterval {
                lastCursorPublishTime = now
                onCursorPosition?(x)
            }
        }
    }

    private func midiEditorRect(
        trackLayout: PlaybackGridTrackLayout,
        for containerLayout: PlaybackGridContainerLayout,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect {
        let inlineHeight = snapshot.inlineMIDILaneHeights[trackLayout.track.id] ?? 0
        guard inlineHeight > 0 else { return containerLayout.rect }
        let automationHeight = trackLayout.automationToolbarHeight
            + (CGFloat(trackLayout.automationLaneLayouts.count) * snapshot.automationSubLaneHeight)
        return CGRect(
            x: containerLayout.rect.minX,
            y: trackLayout.yOrigin + trackLayout.clipHeight + automationHeight,
            width: containerLayout.rect.width,
            height: inlineHeight
        )
    }

    private func isPointNearInlineMIDILaneResizeHandle(
        _ point: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) -> Bool {
        var yOffset: CGFloat = snapshot.showRulerAndSections ? PlaybackGridLayout.trackAreaTop : 0
        let threshold: CGFloat = 10
        for track in snapshot.tracks {
            let baseHeight = snapshot.trackHeights[track.id] ?? snapshot.defaultTrackHeight
            let automationExtra = automationTrackExtraHeight(track: track, snapshot: snapshot)
            let inlineHeight = snapshot.inlineMIDILaneHeights[track.id] ?? 0
            defer { yOffset += baseHeight + automationExtra + inlineHeight }
            guard track.kind == .midi, inlineHeight > 0 else { continue }
            let laneBottom = yOffset + baseHeight + automationExtra + inlineHeight
            if point.y >= laneBottom - threshold && point.y <= laneBottom + threshold {
                return true
            }
        }
        return false
    }

    private func inlineMIDITrackID(
        at point: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) -> ID<Track>? {
        var yOffset: CGFloat = snapshot.showRulerAndSections ? PlaybackGridLayout.trackAreaTop : 0
        for track in snapshot.tracks {
            let baseHeight = snapshot.trackHeights[track.id] ?? snapshot.defaultTrackHeight
            let automationExtra = automationTrackExtraHeight(track: track, snapshot: snapshot)
            let inlineHeight = snapshot.inlineMIDILaneHeights[track.id] ?? 0
            defer { yOffset += baseHeight + automationExtra + inlineHeight }
            guard track.kind == .midi, inlineHeight > 0 else { continue }
            let laneRect = CGRect(
                x: 0,
                y: yOffset + baseHeight + automationExtra,
                width: bounds.width,
                height: inlineHeight
            )
            if laneRect.contains(point) {
                return track.id
            }
        }
        return nil
    }

    private func presentAutomationValueEditor(
        pick: GridPickObject,
        event: NSEvent,
        snapshot: PlaybackGridSnapshot
    ) -> Bool {
        guard let trackID = pick.trackID,
              let laneID = pick.automationLaneID,
              let breakpointID = pick.automationBreakpointID,
              let track = snapshot.tracks.first(where: { $0.id == trackID }) else {
            return false
        }

        let laneAndBreakpoint: (lane: AutomationLane, breakpoint: AutomationBreakpoint, containerID: ID<Container>?)
        if let containerID = pick.containerID {
            guard let container = track.containers.first(where: { $0.id == containerID }),
                  let lane = container.automationLanes.first(where: { $0.id == laneID }),
                  let breakpoint = lane.breakpoints.first(where: { $0.id == breakpointID }) else {
                return false
            }
            laneAndBreakpoint = (lane, breakpoint, containerID)
        } else {
            guard let lane = track.trackAutomationLanes.first(where: { $0.id == laneID }),
                  let breakpoint = lane.breakpoints.first(where: { $0.id == breakpointID }) else {
                return false
            }
            laneAndBreakpoint = (lane, breakpoint, nil)
        }

        let currentDisplay = automationDisplayValue(
            normalized: laneAndBreakpoint.breakpoint.value,
            lane: laneAndBreakpoint.lane
        )
        let title = laneAndBreakpoint.lane.parameterName?.isEmpty == false
            ? laneAndBreakpoint.lane.parameterName!
            : "Automation Value"
        let unit = (laneAndBreakpoint.lane.parameterUnit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let alert = NSAlert()
        alert.messageText = "Set \(title)"
        alert.informativeText = unit.isEmpty
            ? "Enter value. Use +/- for relative adjustment."
            : "Enter value (\(unit)). Use +/- for relative adjustment."

        let input = NSTextField(frame: CGRect(x: 0, y: 0, width: 220, height: 22))
        input.stringValue = String(format: "%.3f", currentDisplay)
        alert.accessoryView = input
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() != .alertFirstButtonReturn {
            return true
        }

        guard let normalized = normalizedAutomationValue(
            input: input.stringValue,
            lane: laneAndBreakpoint.lane,
            currentNormalized: laneAndBreakpoint.breakpoint.value,
            fineMode: event.modifierFlags.contains(.shift)
        ) else {
            NSSound.beep()
            return true
        }

        var updated = laneAndBreakpoint.breakpoint
        updated.value = normalized
        if let containerID = laneAndBreakpoint.containerID {
            commandSink?.updateAutomationBreakpoint(containerID, laneID: laneID, breakpoint: updated)
        } else {
            commandSink?.updateTrackAutomationBreakpoint(trackID: trackID, laneID: laneID, breakpoint: updated)
        }
        return true
    }

    private func automationDisplayValue(
        normalized: Float,
        lane: AutomationLane
    ) -> Double {
        let minValue = Double(lane.parameterMin ?? 0)
        let maxValue = Double(lane.parameterMax ?? 1)
        guard maxValue > minValue else { return Double(normalized) }
        let unit = (lane.parameterUnit ?? "").lowercased()
        let clamped = Double(max(0, min(1, normalized)))
        if unit.contains("hz"), minValue > 0 {
            let ratio = maxValue / minValue
            return minValue * pow(ratio, clamped)
        }
        return minValue + (clamped * (maxValue - minValue))
    }

    private func normalizedAutomationValue(
        input: String,
        lane: AutomationLane,
        currentNormalized: Float,
        fineMode: Bool
    ) -> Float? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let minValue = Double(lane.parameterMin ?? 0)
        let maxValue = Double(lane.parameterMax ?? 1)
        guard maxValue > minValue else {
            return Float(max(0, min(1, (Double(trimmed) ?? Double(currentNormalized)))))
        }

        let currentDisplay = automationDisplayValue(normalized: currentNormalized, lane: lane)
        let displayValue: Double
        if let first = trimmed.first, (first == "+" || first == "-"), let delta = Double(trimmed) {
            let scaledDelta = fineMode ? (delta * 0.1) : delta
            displayValue = currentDisplay + scaledDelta
        } else if let absolute = Double(trimmed) {
            displayValue = absolute
        } else {
            return nil
        }

        let clampedDisplay = max(minValue, min(maxValue, displayValue))
        let unit = (lane.parameterUnit ?? "").lowercased()
        let normalized: Double
        if unit.contains("hz"), minValue > 0 {
            let ratio = maxValue / minValue
            guard ratio > 0 else { return nil }
            normalized = log(clampedDisplay / minValue) / log(ratio)
        } else {
            normalized = (clampedDisplay - minValue) / (maxValue - minValue)
        }
        return Float(max(0, min(1, normalized)))
    }

    private func automationTrackExtraHeight(track: Track, snapshot: PlaybackGridSnapshot) -> CGFloat {
        guard snapshot.automationExpandedTrackIDs.contains(track.id) else { return 0 }
        let laneCount = automationLanePaths(for: track).count
        guard laneCount > 0 else { return 0 }
        return snapshot.automationToolbarHeight + (CGFloat(laneCount) * snapshot.automationSubLaneHeight)
    }

    private func automationLanePaths(for track: Track) -> [EffectPath] {
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
}
