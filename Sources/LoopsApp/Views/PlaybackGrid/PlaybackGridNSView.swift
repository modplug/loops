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
    private static let debugLogsEnabled = false

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
        backingLayer.addSublayer(playheadLayer)

        cursorLayer.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
        cursorLayer.zPosition = 99
        cursorLayer.isHidden = true
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
        if let oldSnapshot = snapshot,
           staticSnapshotEqual(oldSnapshot, newSnapshot) {
            configureSkipCount += 1
            snapshot = newSnapshot
            updateOverlayLayers(using: newSnapshot)
            return
        }

        configureHitCount += 1
        snapshot = newSnapshot
        scene = sceneBuilder.build(snapshot: newSnapshot)
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let playheadX = CGFloat(snapshot.playheadBar - 1.0) * snapshot.pixelsPerBar
        playheadLayer.frame = CGRect(x: playheadX - 0.5, y: 0, width: 1, height: scene.contentHeight)
        playheadLayer.isHidden = false

        if let cursorX = snapshot.cursorX {
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
        let local = convert(event.locationInWindow, from: nil)
        if let last = lastCursorXSent, abs(last - local.x) < 0.5 {
            return
        }
        lastCursorXSent = local.x
        onCursorPosition?(local.x)
    }

    public override func mouseExited(with event: NSEvent) {
        lastCursorXSent = nil
        onCursorPosition?(nil)
    }

    public override func mouseDown(with event: NSEvent) {
        guard let snapshot else { return }
        let local = convert(event.locationInWindow, from: nil)
        let pick = pickingRenderer.pick(
            at: local,
            scene: scene,
            snapshot: snapshot,
            visibleRect: visibleRect,
            canvasWidth: bounds.width
        )

        interactionController.handleMouseDown(
            event: event,
            point: local,
            pick: pick,
            snapshot: snapshot
        )
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let snapshot else { return }
        let local = convert(event.locationInWindow, from: nil)
        interactionController.handleMouseDragged(point: local, snapshot: snapshot)
    }

    public override func mouseUp(with event: NSEvent) {
        guard let snapshot else { return }
        let local = convert(event.locationInWindow, from: nil)
        interactionController.handleMouseUp(point: local, snapshot: snapshot)
    }

    public override func updateLayer() {
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

        guard let drawable = metalLayer.nextDrawable() else { return }
        guard renderer.frameSemaphore.wait(timeout: .now()) == .success else { return }

        if needsBufferRebuild {
            renderer.buildBuffers(
                scene: scene,
                snapshot: snapshot,
                canvasSize: bounds.size,
                visibleRect: visible
            )
            needsBufferRebuild = false
        }

        if Self.debugLogsEnabled {
            let now = CACurrentMediaTime()
            if now - lastDebugLogTime > 0.5 {
                lastDebugLogTime = now
                let stats = renderer.debugStats
                print("[GRIDDBG][\(debugLabel)] draw visible=\(NSStringFromRect(visible)) rawVisible=\(NSStringFromRect(rawVisible)) bounds=\(NSStringFromRect(bounds)) canvasH=\(String(format: "%.1f", bounds.height)) stats rect=\(stats.rectCount) line=\(stats.lineCount) wave=\(stats.waveformCount) midi=\(stats.midiCount) border=\(stats.borderCount)")
            }
        }

        textOverlayLayer.pixelsPerBar = snapshot.pixelsPerBar
        textOverlayLayer.totalBars = snapshot.totalBars
        textOverlayLayer.timeSignature = snapshot.timeSignature
        textOverlayLayer.sections = scene.asLegacySectionLayouts()
        textOverlayLayer.selectedRange = snapshot.selectedRange
        textOverlayLayer.showRulerAndSections = snapshot.showRulerAndSections
        textOverlayLayer.viewportOrigin = visible.origin
        if textOverlayLayer.updateIfNeeded() {
            textOverlayLayer.displayIfNeeded()
        }

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
            originX: 0,
            originY: 0,
            width: Double(texW),
            height: Double(texH),
            znear: 0,
            zfar: 1
        ))

        renderer.encode(
            into: encoder,
            visibleRect: visible,
            canvasHeight: bounds.height,
            viewportSize: MTLSize(width: texW, height: texH, depth: 1),
            pixelsPerBar: snapshot.pixelsPerBar
        )

        encoder.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.renderer?.frameSemaphore.signal()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()

        lastDrawDuration = CACurrentMediaTime() - drawStart
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
            && lhs.defaultTrackHeight == rhs.defaultTrackHeight
            && lhs.gridMode == rhs.gridMode
            && lhs.selectedContainerIDs == rhs.selectedContainerIDs
            && lhs.selectedSectionID == rhs.selectedSectionID
            && lhs.selectedRange == rhs.selectedRange
            && lhs.rangeSelection == rhs.rangeSelection
            && lhs.isSnapEnabled == rhs.isSnapEnabled
            && lhs.showRulerAndSections == rhs.showRulerAndSections
            && lhs.bottomPadding == rhs.bottomPadding
            && lhs.minimumContentHeight == rhs.minimumContentHeight
    }
}
