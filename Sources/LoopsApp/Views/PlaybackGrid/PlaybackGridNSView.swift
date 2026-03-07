import AppKit
import Metal
import QuartzCore
import LoopsCore

public final class PlaybackGridNSView: NSView {
    public var debugLabel: String = "grid"

    private var renderer: PlaybackGridRenderer?
    private let metalLayer: CAMetalLayer
    private let waveformOverlayLayer = CALayer()
    private let textOverlayLayer = TimelineTextOverlayLayer()
    private let midiMarqueeLayer = CAShapeLayer()
    private let waveformTileCache = WaveformTileCache()
    private var waveformTileLayers: [ID<Container>: CALayer] = [:]
    private var waveformTileHashes: [ID<Container>: Int] = [:]

    private let sceneBuilder = PlaybackGridSceneBuilder()
    private let pickingRenderer = PlaybackGridPickingRenderer()
    private var interactionController = PlaybackGridInteractionController(sink: nil)
    private var commandSink: (any PlaybackGridCommandSink)?
    private var contextMenuTargetContainerID: ID<Container>?
    private var contextMenuTargetTrackID: ID<Track>?
    private var contextMenuTargetMIDINoteID: ID<MIDINoteEvent>?
    private var contextMenuTargetAutomationLaneID: ID<AutomationLane>?
    private var contextMenuTargetAutomationBreakpointID: ID<AutomationBreakpoint>?
    private var contextMenuTargetPoint: CGPoint?

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
    private var lastSuppressedAutomationLanes: Set<PlaybackGridAutomationSuppression> = []
    private var currentCursorStyle: CursorStyle = .arrow

    private enum CursorStyle: Equatable {
        case arrow
        case crosshair
        case openHand
        case closedHand
        case resizeLeftRight
        case resizeUpDown
        case iBeam
        case dragCopy
    }

    public var waveformPeaksProvider: ((_ container: Container) -> [Float]?)? {
        didSet {
            sceneBuilder.waveformPeaksProvider = waveformPeaksProvider
            updateInteractionWaveformProviders()
        }
    }

    public var waveformExtremaProvider: ((_ container: Container) -> [WaveformExtrema]?)? {
        didSet {
            sceneBuilder.waveformExtremaProvider = waveformExtremaProvider
            updateInteractionWaveformProviders()
        }
    }

    public var waveformRMSProvider: ((_ container: Container) -> [Float]?)? {
        didSet {
            sceneBuilder.waveformRMSProvider = waveformRMSProvider
            updateInteractionWaveformProviders()
        }
    }

    public var audioDurationBarsProvider: ((_ container: Container) -> Double?)? {
        didSet {
            sceneBuilder.audioDurationBarsProvider = audioDurationBarsProvider
            updateInteractionWaveformProviders()
        }
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
        ProcessInfo.processInfo.environment["LOOPS_GRID_CURSOR_PUBLISH"] != "0"
        && !UserDefaults.standard.bool(forKey: "PlaybackGridDisableCursorPublish")
    }()
    private static let cursorPublishInterval: CFTimeInterval = 1.0 / 60.0
    private static let waveformTilesEnabled: Bool = {
        ProcessInfo.processInfo.environment["LOOPS_GRID_WAVEFORM_TILES"] == "1"
        || UserDefaults.standard.bool(forKey: "PlaybackGridWaveformTiles")
    }()
    private var lastCursorPublishTime: CFTimeInterval = 0

    private struct WaveformTileData {
        let extrema: [WaveformExtrema]
        let rms: [Float]
    }

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
            renderer?.useWaveformTileOverlay = Self.waveformTilesEnabled
        }

        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        backingLayer.addSublayer(metalLayer)

        waveformOverlayLayer.zPosition = 0.5
        waveformOverlayLayer.contentsScale = metalLayer.contentsScale
        waveformOverlayLayer.masksToBounds = true
        backingLayer.addSublayer(waveformOverlayLayer)

        textOverlayLayer.zPosition = 1
        textOverlayLayer.contentsScale = metalLayer.contentsScale
        backingLayer.addSublayer(textOverlayLayer)

        midiMarqueeLayer.zPosition = 2
        midiMarqueeLayer.fillColor = NSColor.systemPink.withAlphaComponent(0.14).cgColor
        midiMarqueeLayer.strokeColor = NSColor.systemPink.withAlphaComponent(0.8).cgColor
        midiMarqueeLayer.lineWidth = 1
        midiMarqueeLayer.lineDashPattern = [5, 4]
        midiMarqueeLayer.isHidden = true
        backingLayer.addSublayer(midiMarqueeLayer)

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
        sceneBuilder.waveformExtremaProvider = waveformExtremaProvider
        sceneBuilder.waveformRMSProvider = waveformRMSProvider
        sceneBuilder.audioDurationBarsProvider = audioDurationBarsProvider
        sceneBuilder.resolvedMIDISequenceProvider = resolvedMIDISequenceProvider
        updateInteractionWaveformProviders()
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
            waveformOverlayLayer.contentsScale = scale
            textOverlayLayer.contentsScale = scale
            midiMarqueeLayer.contentsScale = scale
        }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2.0
        metalLayer.contentsScale = scale
        waveformOverlayLayer.contentsScale = scale
        textOverlayLayer.contentsScale = scale
        midiMarqueeLayer.contentsScale = scale
        needsDisplay = true
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        invalidateAndRedraw()
    }

    @objc private func invalidateAndRedraw() {
        waveformTileCache.invalidateAll()
        needsBufferRebuild = true
        needsDisplay = true
    }

    public func setCommandSink(_ sink: PlaybackGridCommandSink?) {
        commandSink = sink
        interactionController.setCommandSink(sink)
    }

    private func updateInteractionWaveformProviders() {
        interactionController.setWaveformProviders(
            peaks: waveformPeaksProvider,
            extrema: waveformExtremaProvider,
            rms: waveformRMSProvider,
            audioDurationBars: audioDurationBarsProvider
        )
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
        resetContextMenuTargets()
        contextMenuTargetPoint = local

        let menu: NSMenu?
        switch pick.kind {
        case .containerZone:
            guard let containerID = pick.containerID, let trackID = pick.trackID else {
                return super.menu(for: event)
            }
            contextMenuTargetContainerID = containerID
            contextMenuTargetTrackID = trackID
            commandSink?.selectContainer(containerID, trackID: trackID, modifiers: event.modifierFlags)
            menu = buildContainerContextMenu(snapshot: snapshot, containerID: containerID, trackID: trackID)

        case .midiNote:
            guard let containerID = pick.containerID,
                  let trackID = pick.trackID,
                  let noteID = pick.midiNoteID else {
                return super.menu(for: event)
            }
            contextMenuTargetContainerID = containerID
            contextMenuTargetTrackID = trackID
            contextMenuTargetMIDINoteID = noteID
            commandSink?.selectContainer(containerID, trackID: trackID, modifiers: event.modifierFlags)
            commandSink?.setSelectedMIDINotes(containerID: containerID, trackID: trackID, noteIDs: [noteID], additive: false)
            menu = buildMIDINoteContextMenu()

        case .automationBreakpoint, .automationSegment:
            guard let trackID = pick.trackID,
                  let laneID = pick.automationLaneID else {
                return super.menu(for: event)
            }
            contextMenuTargetTrackID = trackID
            contextMenuTargetContainerID = pick.containerID
            contextMenuTargetAutomationLaneID = laneID
            contextMenuTargetAutomationBreakpointID = pick.automationBreakpointID
            if let containerID = pick.containerID {
                commandSink?.selectContainer(containerID, trackID: trackID, modifiers: event.modifierFlags)
            }
            menu = buildAutomationContextMenu(isBreakpoint: pick.kind == .automationBreakpoint)

        case .trackBackground, .none:
            if let trackID = inlineMIDITrackID(at: local, snapshot: snapshot),
               let target = midiContextTarget(at: local, preferredTrackID: trackID, snapshot: snapshot) {
                contextMenuTargetTrackID = target.track.id
                contextMenuTargetContainerID = target.container.id
                commandSink?.selectContainer(target.container.id, trackID: target.track.id, modifiers: event.modifierFlags)
                menu = buildMIDILaneContextMenu()
            } else if let trackID = pick.trackID ?? trackID(at: local) {
                contextMenuTargetTrackID = trackID
                menu = buildTrackContextMenu()
            } else {
                menu = nil
            }

        default:
            menu = nil
        }

        guard let menu else { return super.menu(for: event) }
        for item in menu.items where item.target == nil && !item.isSeparatorItem && item.action != nil {
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

    @objc private func contextDeleteMIDINote(_ sender: NSMenuItem) {
        guard let containerID = contextMenuTargetContainerID,
              let noteID = contextMenuTargetMIDINoteID else { return }
        commandSink?.removeMIDINote(containerID, noteID: noteID)
    }

    @objc private func contextInsertMIDINote(_ sender: NSMenuItem) {
        guard let snapshot,
              let point = contextMenuTargetPoint,
              let trackID = contextMenuTargetTrackID,
              let target = midiContextTarget(at: point, preferredTrackID: trackID, snapshot: snapshot) else { return }
        let note = makeContextMIDINote(at: point, container: target.container, trackID: target.track.id, snapshot: snapshot)
        commandSink?.addMIDINote(target.container.id, note: note)
    }

    @objc private func contextCreateContainerAtPoint(_ sender: NSMenuItem) {
        guard let snapshot,
              let point = contextMenuTargetPoint,
              let trackID = contextMenuTargetTrackID else { return }
        let startBar = snappedBarForContextX(point.x, snapshot: snapshot)
        _ = commandSink?.createContainer(trackID: trackID, startBar: startBar, lengthBars: 1)
    }

    @objc private func contextDeleteAutomationBreakpoint(_ sender: NSMenuItem) {
        guard let trackID = contextMenuTargetTrackID,
              let laneID = contextMenuTargetAutomationLaneID,
              let breakpointID = contextMenuTargetAutomationBreakpointID else { return }
        if let containerID = contextMenuTargetContainerID {
            commandSink?.removeAutomationBreakpoint(containerID, laneID: laneID, breakpointID: breakpointID)
        } else {
            commandSink?.removeTrackAutomationBreakpoint(trackID: trackID, laneID: laneID, breakpointID: breakpointID)
        }
    }

    @objc private func contextAddAutomationBreakpoint(_ sender: NSMenuItem) {
        guard let snapshot,
              let point = contextMenuTargetPoint,
              let trackID = contextMenuTargetTrackID,
              let laneID = contextMenuTargetAutomationLaneID,
              let breakpoint = makeContextAutomationBreakpoint(
                at: point,
                trackID: trackID,
                containerID: contextMenuTargetContainerID,
                laneID: laneID,
                snapshot: snapshot
              ) else { return }
        if let containerID = contextMenuTargetContainerID {
            commandSink?.addAutomationBreakpoint(containerID, laneID: laneID, breakpoint: breakpoint)
        } else {
            commandSink?.addTrackAutomationBreakpoint(trackID: trackID, laneID: laneID, breakpoint: breakpoint)
        }
    }

    @objc private func contextLinkContainer(_ sender: NSMenuItem) {
        withContextTarget { containerID, trackID in
            commandSink?.linkContainer(containerID, trackID: trackID)
        }
    }

    @objc private func contextUnlinkContainer(_ sender: NSMenuItem) {
        withContextTarget { containerID, trackID in
            commandSink?.unlinkContainer(containerID, trackID: trackID)
        }
    }

    @objc private func contextGlueContainers(_ sender: NSMenuItem) {
        guard let snapshot else { return }
        commandSink?.glueContainers(containerIDs: snapshot.selectedContainerIDs)
    }

    @objc private func contextToggleArm(_ sender: NSMenuItem) {
        withContextTarget { containerID, trackID in
            commandSink?.toggleContainerArm(containerID, trackID: trackID)
        }
    }

    @objc private func contextEditContainer(_ sender: NSMenuItem) {
        withContextTarget { containerID, trackID in
            commandSink?.openContainerEditor(containerID, trackID: trackID)
        }
    }

    @objc private func contextSetCrossfadeCurve(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? CrossfadeCurveMenuInfo else { return }
        commandSink?.setCrossfadeCurveType(trackID: info.trackID, crossfadeID: info.crossfadeID, curveType: info.curveType)
    }

    private func withContextTarget(_ action: (_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void) {
        guard let containerID = contextMenuTargetContainerID,
              let trackID = contextMenuTargetTrackID else { return }
        action(containerID, trackID)
    }

    private func resetContextMenuTargets() {
        contextMenuTargetContainerID = nil
        contextMenuTargetTrackID = nil
        contextMenuTargetMIDINoteID = nil
        contextMenuTargetAutomationLaneID = nil
        contextMenuTargetAutomationBreakpointID = nil
        contextMenuTargetPoint = nil
    }

    private func buildContainerContextMenu(
        snapshot: PlaybackGridSnapshot,
        containerID: ID<Container>,
        trackID: ID<Track>
    ) -> NSMenu {
        let container = snapshot.tracks
            .first { $0.id == trackID }?
            .containers
            .first { $0.id == containerID }
        let track = snapshot.tracks.first { $0.id == trackID }
        let selectedCount = snapshot.selectedContainerIDs.count
        let isClone = container?.parentContainerID != nil
        let crossfades = track?.crossfades
            .filter { $0.containerAID == containerID || $0.containerBID == containerID } ?? []

        let menu = NSMenu(title: "Container")
        if selectedCount > 1 {
            menu.addItem(NSMenuItem(title: "Copy \(selectedCount) Containers", action: #selector(contextCopyContainer(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Duplicate \(selectedCount) Containers", action: #selector(contextDuplicateContainer(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Split \(selectedCount) at Playhead", action: #selector(contextSplitContainer(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Glue", action: #selector(contextGlueContainers(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Delete \(selectedCount) Containers", action: #selector(contextDeleteContainer(_:)), keyEquivalent: ""))
            return menu
        }

        menu.addItem(NSMenuItem(title: "Copy", action: #selector(contextCopyContainer(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Duplicate", action: #selector(contextDuplicateContainer(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Link (Create Clone)", action: #selector(contextLinkContainer(_:)), keyEquivalent: ""))
        if isClone {
            menu.addItem(NSMenuItem(title: "Unlink (Consolidate)", action: #selector(contextUnlinkContainer(_:)), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Split at Playhead", action: #selector(contextSplitContainer(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Edit…", action: #selector(contextEditContainer(_:)), keyEquivalent: ""))

        let armTitle = container?.isRecordArmed == true ? "Disarm" : "Arm"
        menu.addItem(NSMenuItem(title: armTitle, action: #selector(contextToggleArm(_:)), keyEquivalent: ""))

        if !crossfades.isEmpty {
            let crossfadeMenu = NSMenu(title: "Crossfade Curve")
            for crossfade in crossfades {
                let submenu = NSMenu(title: "Crossfade")
                for curveType in CrossfadeCurveType.allCases {
                    let item = NSMenuItem(title: curveType.displayName, action: #selector(contextSetCrossfadeCurve(_:)), keyEquivalent: "")
                    item.representedObject = CrossfadeCurveMenuInfo(crossfadeID: crossfade.id, trackID: trackID, curveType: curveType)
                    item.target = self
                    if crossfade.curveType == curveType {
                        item.state = .on
                    }
                    submenu.addItem(item)
                }
                if crossfades.count == 1 {
                    let curveItem = NSMenuItem(title: "Crossfade Curve", action: nil, keyEquivalent: "")
                    curveItem.submenu = submenu
                    menu.addItem(curveItem)
                } else {
                    let label = crossfade.containerAID == containerID ? "Crossfade (exit)" : "Crossfade (enter)"
                    let curveItem = NSMenuItem(title: label, action: nil, keyEquivalent: "")
                    curveItem.submenu = submenu
                    crossfadeMenu.addItem(curveItem)
                }
            }
            if crossfades.count > 1 {
                let parentItem = NSMenuItem(title: "Crossfade Curves", action: nil, keyEquivalent: "")
                parentItem.submenu = crossfadeMenu
                menu.addItem(parentItem)
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Delete", action: #selector(contextDeleteContainer(_:)), keyEquivalent: ""))
        return menu
    }

    private func buildMIDINoteContextMenu() -> NSMenu {
        let menu = NSMenu(title: "MIDI Note")
        menu.addItem(NSMenuItem(title: "Delete Note", action: #selector(contextDeleteMIDINote(_:)), keyEquivalent: ""))
        return menu
    }

    private func buildMIDILaneContextMenu() -> NSMenu {
        let menu = NSMenu(title: "MIDI Lane")
        menu.addItem(NSMenuItem(title: "Insert Note Here", action: #selector(contextInsertMIDINote(_:)), keyEquivalent: ""))
        return menu
    }

    private func buildAutomationContextMenu(isBreakpoint: Bool) -> NSMenu {
        let menu = NSMenu(title: "Automation Lane")
        menu.addItem(NSMenuItem(title: "Add Breakpoint Here", action: #selector(contextAddAutomationBreakpoint(_:)), keyEquivalent: ""))
        if isBreakpoint {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Delete Breakpoint", action: #selector(contextDeleteAutomationBreakpoint(_:)), keyEquivalent: ""))
        }
        return menu
    }

    private func buildTrackContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Track")
        menu.addItem(NSMenuItem(title: "Create Container Here", action: #selector(contextCreateContainerAtPoint(_:)), keyEquivalent: ""))
        return menu
    }

    private func midiContextTarget(
        at point: CGPoint,
        preferredTrackID: ID<Track>?,
        snapshot: PlaybackGridSnapshot
    ) -> (track: Track, container: Container)? {
        let bar = (Double(max(0, point.x)) / Double(snapshot.pixelsPerBar)) + 1.0

        func containerForTrack(_ track: Track) -> Container? {
            guard track.kind == .midi else { return nil }
            let candidates = track.containers.filter { bar >= $0.startBar && bar <= $0.endBar }
            let laneCandidates = candidates.filter { container in
                guard let laneRect = midiLaneRect(
                    containerID: container.id,
                    trackID: track.id,
                    snapshot: snapshot
                ) else { return false }
                return laneRect.contains(point)
            }
            if let selected = laneCandidates.first(where: { snapshot.selectedContainerIDs.contains($0.id) }) {
                return selected
            }
            return laneCandidates.first
        }

        if let preferredTrackID,
           let preferredTrack = snapshot.tracks.first(where: { $0.id == preferredTrackID }),
           let preferredContainer = containerForTrack(preferredTrack) {
            return (preferredTrack, preferredContainer)
        }

        for track in snapshot.tracks where track.kind == .midi {
            if let container = containerForTrack(track) {
                return (track, container)
            }
        }
        return nil
    }

    private func makeContextMIDINote(
        at point: CGPoint,
        container: Container,
        trackID: ID<Track>,
        snapshot: PlaybackGridSnapshot
    ) -> MIDINoteEvent {
        guard let laneRect = midiLaneRect(containerID: container.id, trackID: trackID, snapshot: snapshot) else {
            return MIDINoteEvent(pitch: 60, velocity: 100, startBeat: 0, duration: 1)
        }
        let resolved = PlaybackGridMIDIViewResolver.resolveTrackLayout(
            track: snapshot.tracks.first(where: { $0.id == trackID }) ?? Track(name: "MIDI", kind: .midi),
            laneHeight: laneRect.height,
            snapshot: snapshot
        )
        let beatsPerBar = Double(snapshot.timeSignature.beatsPerBar)
        let rawOffsetBars = Double(point.x / snapshot.pixelsPerBar) - (container.startBar - 1.0)
        let rawOffsetBeats = max(0, min(container.lengthBars * beatsPerBar, rawOffsetBars * beatsPerBar))
        let startBeat = snapBeat(rawOffsetBeats, snapshot: snapshot)
        let pitch = pitchForContextPointY(point.y, laneRect: laneRect, resolved: resolved)
        let duration = snapshot.isSnapEnabled ? contextSnapResolution(snapshot).beatsPerUnit : 1.0
        let maxStart = max(0, (container.lengthBars * beatsPerBar) - duration)
        return MIDINoteEvent(
            pitch: pitch,
            velocity: 100,
            startBeat: min(startBeat, maxStart),
            duration: duration
        )
    }

    private func makeContextAutomationBreakpoint(
        at point: CGPoint,
        trackID: ID<Track>,
        containerID: ID<Container>?,
        laneID: ID<AutomationLane>,
        snapshot: PlaybackGridSnapshot
    ) -> AutomationBreakpoint? {
        guard let laneRect = automationLaneRect(trackID: trackID, containerID: containerID, laneID: laneID, snapshot: snapshot) else {
            return nil
        }
        let clampedValue = max(0, min(1, 1 - ((point.y - laneRect.minY) / max(laneRect.height, 1))))
        if let containerID,
           let track = snapshot.tracks.first(where: { $0.id == trackID }),
           let container = track.containers.first(where: { $0.id == containerID }) {
            let rawBar = (Double(max(0, point.x)) / Double(snapshot.pixelsPerBar)) + 1.0
            let clampedBar = max(container.startBar, min(container.endBar, rawBar))
            let normalized = max(0, min(1, (clampedBar - container.startBar) / max(container.lengthBars, 0.0001)))
            return AutomationBreakpoint(position: normalized, value: Float(clampedValue))
        }

        let snappedBar = snappedBarForContextX(point.x, snapshot: snapshot)
        return AutomationBreakpoint(position: snappedBar, value: Float(clampedValue))
    }

    private func automationLaneRect(
        trackID: ID<Track>,
        containerID: ID<Container>?,
        laneID: ID<AutomationLane>,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect? {
        guard let trackLayout = scene.trackLayouts.first(where: { $0.track.id == trackID }),
              let track = snapshot.tracks.first(where: { $0.id == trackID }) else {
            return nil
        }

        let targetPath: EffectPath?
        if let containerID,
           let container = track.containers.first(where: { $0.id == containerID }) {
            targetPath = container.automationLanes.first(where: { $0.id == laneID })?.targetPath
        } else {
            targetPath = track.trackAutomationLanes.first(where: { $0.id == laneID })?.targetPath
        }
        guard let targetPath,
              let layout = trackLayout.automationLaneLayouts.first(where: { $0.targetPath == targetPath }) else {
            return nil
        }

        if let containerID,
           let containerRect = containerRect(containerID: containerID, trackID: trackID, snapshot: snapshot) {
            return CGRect(x: containerRect.minX, y: layout.rect.minY, width: containerRect.width, height: layout.rect.height)
        }
        return layout.rect
    }

    private func containerRect(
        containerID: ID<Container>,
        trackID: ID<Track>,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect? {
        for layout in scene.trackLayouts where layout.track.id == trackID {
            guard let containerLayout = layout.containers.first(where: { $0.container.id == containerID }) else { return nil }
            return containerLayout.rect
        }
        return nil
    }

    private func midiLaneRect(
        containerID: ID<Container>,
        trackID: ID<Track>,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect? {
        guard let baseRect = containerRect(containerID: containerID, trackID: trackID, snapshot: snapshot) else {
            return nil
        }
        let inlineHeight = snapshot.inlineMIDILaneHeights[trackID] ?? 0
        guard inlineHeight > 0 else { return baseRect }
        let automationExtra = automationTrackExtraHeight(trackID: trackID, snapshot: snapshot)
        let noteAreaHeight = snapshot.inlineMIDIConfigs[trackID]?.noteAreaHeight(totalInlineHeight: inlineHeight) ?? inlineHeight
        return CGRect(
            x: baseRect.minX,
            y: baseRect.maxY + automationExtra,
            width: baseRect.width,
            height: noteAreaHeight
        )
    }

    private func midiVelocityLaneRect(
        containerID: ID<Container>,
        trackID: ID<Track>,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect? {
        guard let config = snapshot.inlineMIDIConfigs[trackID],
              let velocityLane = config.detailLanes.first(where: { $0.lane == .velocity }),
              let noteAreaRect = midiLaneRect(
                containerID: containerID,
                trackID: trackID,
                snapshot: snapshot
              ) else {
            return nil
        }
        return CGRect(
            x: noteAreaRect.minX,
            y: noteAreaRect.maxY,
            width: noteAreaRect.width,
            height: velocityLane.height
        )
    }

    private func automationTrackExtraHeight(trackID: ID<Track>, snapshot: PlaybackGridSnapshot) -> CGFloat {
        guard let track = snapshot.tracks.first(where: { $0.id == trackID }),
              snapshot.automationExpandedTrackIDs.contains(track.id) else {
            return 0
        }
        var seen = Set<EffectPath>()
        var count = 0
        for lane in track.trackAutomationLanes where seen.insert(lane.targetPath).inserted {
            count += 1
        }
        for container in track.containers {
            for lane in container.automationLanes where seen.insert(lane.targetPath).inserted {
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        return snapshot.automationToolbarHeight + (CGFloat(count) * snapshot.automationSubLaneHeight)
    }

    private func pitchForContextPointY(
        _ y: CGFloat,
        laneRect: CGRect,
        resolved: PlaybackGridMIDIResolvedLayout
    ) -> UInt8 {
        let clampedY = max(laneRect.minY, min(laneRect.maxY - 0.001, y))
        let rowFromTop = Int(floor((clampedY - laneRect.minY) / max(resolved.rowHeight, 1)))
        let clampedRow = max(0, min(max(resolved.rows - 1, 0), rowFromTop))
        return UInt8(clamping: Int(resolved.highPitch) - clampedRow)
    }

    private func snappedBarForContextX(_ x: CGFloat, snapshot: PlaybackGridSnapshot) -> Double {
        let rawBar = (Double(max(0, x)) / Double(snapshot.pixelsPerBar)) + 1.0
        let beatsPerBar = Double(snapshot.timeSignature.beatsPerBar)
        let totalBeats = (rawBar - 1.0) * beatsPerBar
        let snappedBeats = snapBeat(totalBeats, snapshot: snapshot)
        return max((snappedBeats / beatsPerBar) + 1.0, 1.0)
    }

    private func snapBeat(_ beat: Double, snapshot: PlaybackGridSnapshot) -> Double {
        guard snapshot.isSnapEnabled else { return beat }
        let unit = contextSnapResolution(snapshot).beatsPerUnit
        return (beat / unit).rounded() * unit
    }

    private func contextSnapResolution(_ snapshot: PlaybackGridSnapshot) -> SnapResolution {
        switch snapshot.gridMode {
        case .fixed(let resolution):
            return resolution
        case .adaptive:
            let ppBeat = snapshot.pixelsPerBar / CGFloat(snapshot.timeSignature.beatsPerBar)
            if ppBeat >= 150 { return .thirtySecond }
            if ppBeat >= 80 { return .sixteenth }
            if ppBeat >= 40 { return .quarter }
            return .whole
        }
    }

    public func configure(snapshot newSnapshot: PlaybackGridSnapshot, prebuiltScene: PlaybackGridScene? = nil) {
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
        let oldSnapshot = snapshot
        let oldScene = scene
        snapshot = newSnapshot
        let buildStart = PlaybackGridPerfLogger.begin()
        scene = prebuiltScene ?? sceneBuilder.build(snapshot: newSnapshot)
        PlaybackGridPerfLogger.end("grid.configure.sceneBuild.ms", buildStart)
        needsBufferRebuild = true
        configureWillRedraw = true
        if let oldSnapshot {
            let dirtyRect = dirtyRectForSnapshotChange(
                oldSnapshot: oldSnapshot,
                oldScene: oldScene,
                newSnapshot: newSnapshot,
                newScene: scene
            )
            if !dirtyRect.isNull {
                setNeedsDisplay(dirtyRect)
            } else {
                needsDisplay = true
            }
        } else {
            needsDisplay = true
        }

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
        let exposedRect = exposedRect(from: lastObservedVisibleRect, to: currentVisible)
        lastObservedVisibleRect = currentVisible
        needsBufferRebuild = true
        if !exposedRect.isNull {
            setNeedsDisplay(exposedRect)
        } else {
            needsDisplay = true
        }
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
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect],
            owner: self
        ))
    }

    public override func cursorUpdate(with event: NSEvent) {
        guard let snapshot else { return }
        let local = convert(event.locationInWindow, from: nil)
        applyCursorStyle(desiredCursorStyle(at: local, snapshot: snapshot))
    }

    public override func mouseMoved(with event: NSEvent) {
        PlaybackGridPerfLogger.bump("input.mouseMoved")
        guard let snapshot else { return }
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
            applyCursorStyle(desiredCursorStyle(at: local, snapshot: snapshot))
            PlaybackGridPerfLogger.bump("grid.pick.skippedWhileInteracting")
            return
        }

        if let trackID = inlineMIDITrackID(at: local, snapshot: snapshot),
           !isPointNearInlineMIDILaneResizeHandle(local, snapshot: snapshot) {
            applyCursorStyle(inlineMIDICursorStyle(trackID: trackID, snapshot: snapshot))
            if hoveredPick != .none {
                hoveredPick = .none
                needsDisplay = true
            }
            return
        }

        let pickStart = PlaybackGridPerfLogger.begin()
        let pick = pickingRenderer.pick(
            at: local,
            scene: scene,
            snapshot: snapshot,
            visibleRect: visibleRect,
            canvasWidth: bounds.width
        )
        PlaybackGridPerfLogger.end("grid.pick.mouseMoved.ms", pickStart)
        applyCursorStyle(cursorStyle(forHoverPick: pick, point: local, snapshot: snapshot))

        let newHoveredPick: GridPickObject
        switch pick.kind {
        case .containerZone, .midiNote, .automationBreakpoint:
            newHoveredPick = pick
        default:
            newHoveredPick = .none
        }
        if newHoveredPick != hoveredPick {
            hoveredPick = newHoveredPick
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
            needsDisplay = true
        }
        currentCursorStyle = .arrow
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
        applyCursorStyle(desiredCursorStyle(at: local, snapshot: snapshot))
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
        applyCursorStyle(desiredCursorStyle(at: local, snapshot: snapshot))
        needsDisplay = true
    }

    public override func scrollWheel(with event: NSEvent) {
        PlaybackGridPerfLogger.bump("input.scrollWheel")
        guard let snapshot else {
            super.scrollWheel(with: event)
            return
        }
        let local = convert(event.locationInWindow, from: nil)
        let mods = event.modifierFlags

        if mods.contains(.option), abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            if let trackID = inlineMIDITrackID(at: local, snapshot: snapshot) {
                commandSink?.adjustInlineMIDIRowHeight(
                    trackID: trackID,
                    delta: inlineMIDIZoomDelta(for: event)
                )
                return
            }
            if let trackID = trackID(at: local) {
                commandSink?.adjustTrackHeight(
                    trackID: trackID,
                    delta: trackHeightZoomDelta(for: event)
                )
                return
            }
        }

        guard let trackID = inlineMIDIKeyboardTrackID(at: local, snapshot: snapshot) else {
            midiRangeScrollAccumulator = 0
            super.scrollWheel(with: event)
            return
        }

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
        let useWaveformTiles = Self.waveformTilesEnabled && snapshot.pixelsPerBar < 48

        let scale = metalLayer.contentsScale

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = visible
        metalLayer.drawableSize = CGSize(width: visible.width * scale, height: visible.height * scale)
        waveformOverlayLayer.frame = visible
        waveformOverlayLayer.isHidden = !useWaveformTiles
        textOverlayLayer.frame = visible
        midiMarqueeLayer.frame = visible
        CATransaction.commit()

        renderer.useWaveformTileOverlay = useWaveformTiles
        if useWaveformTiles {
            updateWaveformTileOverlay(visibleRect: visible, snapshot: snapshot)
        } else {
            hideWaveformTileOverlay()
        }

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
        let containerOverlays = interactionController.activeContainerOverlays
        let automationOverlays = interactionController.activeAutomationBreakpointOverlays
        let automationShapeOverlays = interactionController.activeAutomationShapeOverlays
        let suppressedAutomationLanes = interactionController.activeAutomationSuppressedLanes
        if suppressedAutomationLanes != lastSuppressedAutomationLanes {
            lastSuppressedAutomationLanes = suppressedAutomationLanes
            needsDisplay = true
        }

        if needsBufferRebuild || !midiOverlays.isEmpty {
            PlaybackGridPerfLogger.bump("grid.updateLayer.bufferRebuild")
            let rebuildStart = PlaybackGridPerfLogger.begin()
            renderer.buildBuffers(
                scene: scene,
                snapshot: snapshot,
                canvasSize: bounds.size,
                visibleRect: visible,
                midiOverlays: midiOverlays,
                focusedPick: .none,
                suppressedAutomationLanes: suppressedAutomationLanes
            )
            PlaybackGridPerfLogger.end("grid.updateLayer.buildBuffers.ms", rebuildStart)
            needsBufferRebuild = false
        }
        let focusOverlayStart = PlaybackGridPerfLogger.begin()
        renderer.buildFocusOverlayBuffer(
            scene: scene,
            snapshot: snapshot,
            focusedPick: hoveredPick
        )
        PlaybackGridPerfLogger.end("grid.updateLayer.focusOverlayBuffer.ms", focusOverlayStart)
        let overlayBufferStart = PlaybackGridPerfLogger.begin()
        renderer.buildMIDIOverlayBuffer(
            scene: scene,
            snapshot: snapshot,
            midiOverlays: midiOverlays
        )
        PlaybackGridPerfLogger.end("grid.updateLayer.midiOverlayBuffer.ms", overlayBufferStart)
        let containerOverlayStart = PlaybackGridPerfLogger.begin()
        renderer.buildContainerOverlayBuffer(
            scene: scene,
            snapshot: snapshot,
            overlays: containerOverlays
        )
        PlaybackGridPerfLogger.end("grid.updateLayer.containerOverlayBuffer.ms", containerOverlayStart)
        let automationOverlayStart = PlaybackGridPerfLogger.begin()
        renderer.buildAutomationOverlayBuffer(
            scene: scene,
            snapshot: snapshot,
            overlays: automationOverlays
        )
        PlaybackGridPerfLogger.end("grid.updateLayer.automationOverlayBuffer.ms", automationOverlayStart)
        let automationShapeOverlayStart = PlaybackGridPerfLogger.begin()
        renderer.buildAutomationShapeOverlayBuffer(
            scene: scene,
            snapshot: snapshot,
            overlays: automationShapeOverlays
        )
        PlaybackGridPerfLogger.end("grid.updateLayer.automationShapeOverlayBuffer.ms", automationShapeOverlayStart)

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
            // While dragging MIDI notes, render only the live overlay labels so
            // the text stays attached to the moving note instead of leaving a
            // stale cached label behind.
            let liveLabels = buildLiveMIDINoteOverlayLabels(
                snapshot: snapshot,
                midiOverlays: midiOverlays
            )
            textOverlayLayer.midiNoteLabels = liveLabels + buildMIDIVelocityValueLabels(
                snapshot: snapshot,
                midiOverlays: midiOverlays
            )
        } else {
            let labels = buildMIDINoteLabels(
                snapshot: snapshot,
                midiOverlays: midiOverlays
            )
            let combinedLabels = labels + buildMIDIVelocityValueLabels(
                snapshot: snapshot,
                midiOverlays: midiOverlays
            )
            cachedMIDINoteLabels = combinedLabels
            textOverlayLayer.midiNoteLabels = combinedLabels
        }
        if textOverlayLayer.updateIfNeeded() {
            textOverlayLayer.displayIfNeeded()
        }
        PlaybackGridPerfLogger.end("grid.updateLayer.textOverlay.ms", textStart)

        updateMIDIMarqueeLayer(visibleRect: visible)

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

    private func updateMIDIMarqueeLayer(visibleRect: CGRect) {
        guard let rect = interactionController.activeMIDIMarqueeRect else {
            midiMarqueeLayer.path = nil
            midiMarqueeLayer.isHidden = true
            return
        }
        let localRect = rect.offsetBy(dx: -visibleRect.minX, dy: -visibleRect.minY).integral.insetBy(dx: 0.5, dy: 0.5)
        midiMarqueeLayer.path = CGPath(rect: localRect, transform: nil)
        midiMarqueeLayer.isHidden = localRect.isEmpty
    }

    public override var intrinsicContentSize: NSSize {
        guard let snapshot else {
            return NSSize(width: 2000, height: PlaybackGridLayout.trackAreaTop + 400)
        }

        let width = CGFloat(snapshot.totalBars) * snapshot.pixelsPerBar
        return NSSize(width: width, height: scene.contentHeight)
    }

    private func updateWaveformTileOverlay(visibleRect: CGRect, snapshot: PlaybackGridSnapshot) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        var visibleContainerIDs = Set<ID<Container>>()
        let tilePixelsPerBar = quantizedWaveformPixelsPerBar(for: snapshot.pixelsPerBar)

        for trackLayout in scene.trackLayouts {
            for containerLayout in trackLayout.containers {
                guard containerLayout.rect.intersects(visibleRect),
                      let waveformData = tileWaveformData(for: containerLayout),
                      !waveformData.extrema.isEmpty else {
                    continue
                }

                let waveformRect = waveformRectForTile(
                    containerLayout: containerLayout,
                    pixelsPerBar: snapshot.pixelsPerBar
                )
                guard waveformRect.width >= 2,
                      waveformRect.height >= 2,
                      waveformRect.intersects(visibleRect) else {
                    continue
                }

                visibleContainerIDs.insert(containerLayout.container.id)

                let tileHash = hashWaveformTile(
                    waveformData: waveformData,
                    containerLayout: containerLayout,
                    waveformHeight: waveformRect.height
                )
                if waveformTileHashes[containerLayout.container.id] != tileHash {
                    waveformTileCache.invalidate(containerID: containerLayout.container.id)
                    waveformTileHashes[containerLayout.container.id] = tileHash
                }

                let containerLengthBars = max(0.0001, Double(waveformRect.width / snapshot.pixelsPerBar))
                let tile = waveformTileCache.tile(
                    forContainerID: containerLayout.container.id,
                    pixelsPerBar: tilePixelsPerBar
                ) ?? waveformTileCache.generateTile(
                    containerID: containerLayout.container.id,
                    extrema: waveformData.extrema,
                    rms: waveformData.rms,
                    containerLengthBars: containerLengthBars,
                    pixelsPerBar: tilePixelsPerBar,
                    height: waveformRect.height,
                    color: .white,
                    contentsScale: waveformOverlayLayer.contentsScale
                )

                guard let tile else { continue }

                let layer = waveformTileLayers[containerLayout.container.id] ?? {
                    let layer = CALayer()
                    layer.actions = [
                        "position": NSNull(),
                        "bounds": NSNull(),
                        "frame": NSNull(),
                        "hidden": NSNull(),
                        "contents": NSNull()
                    ]
                    layer.contentsGravity = .resize
                    layer.masksToBounds = true
                    layer.cornerRadius = 3
                    layer.minificationFilter = .linear
                    layer.magnificationFilter = .linear
                    layer.contentsScale = waveformOverlayLayer.contentsScale
                    waveformOverlayLayer.addSublayer(layer)
                    waveformTileLayers[containerLayout.container.id] = layer
                    return layer
                }()

                layer.contentsScale = waveformOverlayLayer.contentsScale
                layer.contents = tile.image
                layer.frame = waveformRect.offsetBy(dx: -visibleRect.minX, dy: -visibleRect.minY)
                layer.isHidden = false
            }
        }

        for (containerID, layer) in waveformTileLayers where !visibleContainerIDs.contains(containerID) {
            layer.isHidden = true
        }

        CATransaction.commit()
    }

    private func hideWaveformTileOverlay() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in waveformTileLayers.values {
            layer.isHidden = true
        }
        CATransaction.commit()
    }

    private func waveformRectForTile(
        containerLayout: PlaybackGridContainerLayout,
        pixelsPerBar: CGFloat
    ) -> CGRect {
        var rect = containerLayout.rect
        rect.origin.y += 1
        rect.size.height = max(0, rect.height - 2)

        if let audioDurationBars = containerLayout.audioDurationBars {
            let availableBars = max(0, audioDurationBars - containerLayout.container.audioStartOffset)
            let visibleBars = min(containerLayout.container.lengthBars, availableBars)
            if visibleBars > 0 {
                rect.size.width = CGFloat(visibleBars) * pixelsPerBar
            }
        }

        return rect
    }

    private func quantizedWaveformPixelsPerBar(for pixelsPerBar: CGFloat) -> CGFloat {
        let standard = WaveformTileCache.standardZoomLevels
        guard let nearest = standard.min(by: { abs($0 - pixelsPerBar) < abs($1 - pixelsPerBar) }) else {
            return pixelsPerBar
        }
        let ratio = pixelsPerBar / nearest
        if ratio >= 0.75 && ratio <= 1.5 {
            return nearest
        }
        return pixelsPerBar
    }

    private func tileWaveformData(for containerLayout: PlaybackGridContainerLayout) -> WaveformTileData? {
        if let extrema = containerLayout.waveformExtrema, !extrema.isEmpty {
            let rms = containerLayout.waveformRMS ?? extrema.map { max(abs($0.minimum), abs($0.maximum)) * 0.65 }
            return WaveformTileData(extrema: extrema, rms: rms)
        }
        if let peaks = containerLayout.waveformPeaks, !peaks.isEmpty {
            return WaveformTileData(
                extrema: peaks.map { WaveformExtrema(minimum: -$0, maximum: $0) },
                rms: containerLayout.waveformRMS ?? peaks
            )
        }
        return nil
    }

    private func hashWaveformTile(
        waveformData: WaveformTileData,
        containerLayout: PlaybackGridContainerLayout,
        waveformHeight: CGFloat
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(waveformData.extrema.count)
        hasher.combine(waveformData.rms.count)
        hasher.combine(Int(waveformHeight.rounded(.toNearestOrAwayFromZero)))
        hasher.combine(containerLayout.container.lengthBars.bitPattern)
        hasher.combine(containerLayout.container.audioStartOffset.bitPattern)
        hasher.combine(containerLayout.audioDurationBars?.bitPattern)

        let sampleCount = min(16, waveformData.extrema.count)
        let stride = max(1, waveformData.extrema.count / sampleCount)
        var index = 0
        while index < waveformData.extrema.count {
            let value = waveformData.extrema[index]
            hasher.combine(value.minimum.bitPattern)
            hasher.combine(value.maximum.bitPattern)
            index += stride
        }
        if let last = waveformData.extrema.last {
            hasher.combine(last.minimum.bitPattern)
            hasher.combine(last.maximum.bitPattern)
        }

        let rmsSampleCount = min(8, waveformData.rms.count)
        if rmsSampleCount > 0 {
            let rmsStride = max(1, waveformData.rms.count / rmsSampleCount)
            var rmsIndex = 0
            while rmsIndex < waveformData.rms.count {
                hasher.combine(waveformData.rms[rmsIndex].bitPattern)
                rmsIndex += rmsStride
            }
        }

        return hasher.finalize()
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

    private func dirtyRectForSnapshotChange(
        oldSnapshot: PlaybackGridSnapshot,
        oldScene: PlaybackGridScene,
        newSnapshot: PlaybackGridSnapshot,
        newScene: PlaybackGridScene
    ) -> CGRect {
        if oldSnapshot.pixelsPerBar != newSnapshot.pixelsPerBar
            || oldSnapshot.totalBars != newSnapshot.totalBars
            || oldSnapshot.timeSignature != newSnapshot.timeSignature
            || oldSnapshot.trackHeights != newSnapshot.trackHeights
            || oldSnapshot.inlineMIDILaneHeights != newSnapshot.inlineMIDILaneHeights
            || oldSnapshot.inlineMIDIConfigs != newSnapshot.inlineMIDIConfigs
            || oldSnapshot.automationExpandedTrackIDs != newSnapshot.automationExpandedTrackIDs
            || oldSnapshot.automationSubLaneHeight != newSnapshot.automationSubLaneHeight
            || oldSnapshot.automationToolbarHeight != newSnapshot.automationToolbarHeight
            || oldSnapshot.defaultTrackHeight != newSnapshot.defaultTrackHeight
            || oldSnapshot.gridMode != newSnapshot.gridMode
            || oldSnapshot.showRulerAndSections != newSnapshot.showRulerAndSections
            || oldSnapshot.minimumContentHeight != newSnapshot.minimumContentHeight {
            return visibleRect.intersection(bounds)
        }

        if oldSnapshot.selectedRange != newSnapshot.selectedRange
            || oldSnapshot.rangeSelection != newSnapshot.rangeSelection {
            return visibleRect.intersection(bounds)
        }

        var dirtyRect = CGRect.null

        let oldContainers = Dictionary(uniqueKeysWithValues: oldScene.trackLayouts.flatMap { layout in
            layout.containers.map { ($0.container.id, $0.rect) }
        })
        let newContainers = Dictionary(uniqueKeysWithValues: newScene.trackLayouts.flatMap { layout in
            layout.containers.map { ($0.container.id, $0.rect) }
        })
        let containerIDs = Set(oldContainers.keys).union(newContainers.keys)
        for containerID in containerIDs {
            let oldRect = oldContainers[containerID]
            let newRect = newContainers[containerID]
            if oldRect != newRect {
                if let oldRect { dirtyRect = dirtyRect.union(oldRect.insetBy(dx: -4, dy: -4)) }
                if let newRect { dirtyRect = dirtyRect.union(newRect.insetBy(dx: -4, dy: -4)) }
            } else if oldSnapshot.selectedContainerIDs.contains(containerID) != newSnapshot.selectedContainerIDs.contains(containerID),
                      let newRect {
                dirtyRect = dirtyRect.union(newRect.insetBy(dx: -4, dy: -4))
            }
        }

        let oldSections = Dictionary(uniqueKeysWithValues: oldScene.sectionLayouts.map { ($0.section.id, $0.rect) })
        let newSections = Dictionary(uniqueKeysWithValues: newScene.sectionLayouts.map { ($0.section.id, $0.rect) })
        let sectionIDs = Set(oldSections.keys).union(newSections.keys)
        for sectionID in sectionIDs {
            let oldRect = oldSections[sectionID]
            let newRect = newSections[sectionID]
            if oldRect != newRect {
                if let oldRect { dirtyRect = dirtyRect.union(oldRect.insetBy(dx: -2, dy: -2)) }
                if let newRect { dirtyRect = dirtyRect.union(newRect.insetBy(dx: -2, dy: -2)) }
            }
        }

        if dirtyRect.isNull {
            return visibleRect.intersection(bounds)
        }
        return dirtyRect.intersection(bounds)
    }

    private func exposedRect(from oldVisible: CGRect, to newVisible: CGRect) -> CGRect {
        guard !oldVisible.isNull else { return newVisible }
        var dirtyRect = CGRect.null

        if newVisible.minX < oldVisible.minX {
            dirtyRect = dirtyRect.union(CGRect(
                x: newVisible.minX,
                y: newVisible.minY,
                width: oldVisible.minX - newVisible.minX,
                height: newVisible.height
            ))
        }
        if newVisible.maxX > oldVisible.maxX {
            dirtyRect = dirtyRect.union(CGRect(
                x: oldVisible.maxX,
                y: newVisible.minY,
                width: newVisible.maxX - oldVisible.maxX,
                height: newVisible.height
            ))
        }
        if newVisible.minY < oldVisible.minY {
            dirtyRect = dirtyRect.union(CGRect(
                x: newVisible.minX,
                y: newVisible.minY,
                width: newVisible.width,
                height: oldVisible.minY - newVisible.minY
            ))
        }
        if newVisible.maxY > oldVisible.maxY {
            dirtyRect = dirtyRect.union(CGRect(
                x: newVisible.minX,
                y: oldVisible.maxY,
                width: newVisible.width,
                height: newVisible.maxY - oldVisible.maxY
            ))
        }

        return dirtyRect.intersection(bounds)
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
                    noteID: overlay.note.id,
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
                        noteID: note.id,
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
                noteID: overlay.note.id,
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
                noteID: overlay.note.id,
                text: PianoLayout.noteName(overlay.note.pitch),
                worldRect: noteRect,
                isFocused: true
            ))
        }
        return labels
    }

    private func buildMIDIVelocityValueLabels(
        snapshot: PlaybackGridSnapshot,
        midiOverlays: [PlaybackGridMIDINoteOverlay]
    ) -> [TimelineTextOverlayLayer.MIDINoteLabelLayout] {
        guard let target = velocityValueTarget(snapshot: snapshot, midiOverlays: midiOverlays),
              let trackLayout = scene.trackLayouts.first(where: { $0.track.id == target.trackID }),
              let containerLayout = trackLayout.containers.first(where: { $0.container.id == target.containerID }),
              let laneRect = midiVelocityLaneRect(
                containerID: target.containerID,
                trackID: target.trackID,
                snapshot: snapshot
              ) else {
            return []
        }

        let midiRect = midiEditorRect(
            trackLayout: trackLayout,
            for: containerLayout,
            snapshot: snapshot
        )
        let resolved = PlaybackGridMIDIViewResolver.resolveTrackLayout(
            trackLayout: trackLayout,
            laneHeight: midiRect.height,
            snapshot: snapshot
        )
        guard let noteRect = PlaybackGridMIDIViewResolver.noteRect(
            note: target.note,
            containerLengthBars: containerLayout.container.lengthBars,
            laneRect: midiRect,
            timeSignature: snapshot.timeSignature,
            resolved: resolved
        ) else {
            return []
        }

        let x = min(
            max(noteRect.minX + min(noteRect.width * 0.25, 10), laneRect.minX + 6),
            laneRect.maxX - 6
        )
        let normalized = max(0.0, min(1.0, CGFloat(target.note.velocity) / 127.0))
        let topY = laneRect.maxY - max(5, normalized * max(laneRect.height - 8, 1))
        let labelWidth: CGFloat = 36
        let labelRect = CGRect(
            x: min(max(x - (labelWidth * 0.5), laneRect.minX + 2), laneRect.maxX - labelWidth - 2),
            y: max(laneRect.minY + 2, topY - 16),
            width: labelWidth,
            height: 12
        )
        return [
            .init(
                noteID: target.note.id,
                text: "\(target.note.velocity)",
                worldRect: labelRect,
                isFocused: true
            )
        ]
    }

    private func velocityValueTarget(
        snapshot: PlaybackGridSnapshot,
        midiOverlays: [PlaybackGridMIDINoteOverlay]
    ) -> (note: MIDINoteEvent, containerID: ID<Container>, trackID: ID<Track>)? {
        if case let .draggingMIDINote(context) = interactionController.state,
           context.kind == .velocity {
            if let overlay = midiOverlays.last(where: {
                !$0.isGhost
                && $0.containerID == context.containerID
                && $0.trackID == context.trackID
                && $0.note.id == context.noteID
            }) {
                return (overlay.note, overlay.containerID, overlay.trackID)
            }
            if let note = resolveMIDINote(
                noteID: context.noteID,
                containerID: context.containerID,
                trackID: context.trackID
            ) {
                return (note, context.containerID, context.trackID)
            }
        }

        guard hoveredPick.kind == .midiNote,
              let noteID = hoveredPick.midiNoteID,
              let containerID = hoveredPick.containerID,
              let trackID = hoveredPick.trackID else {
            return nil
        }

        if let overlay = midiOverlays.last(where: {
            !$0.isGhost
            && $0.containerID == containerID
            && $0.trackID == trackID
            && $0.note.id == noteID
        }) {
            return (overlay.note, overlay.containerID, overlay.trackID)
        }
        guard let note = resolveMIDINote(
            noteID: noteID,
            containerID: containerID,
            trackID: trackID
        ) else {
            return nil
        }
        return (note, containerID, trackID)
    }

    private func resolveMIDINote(
        noteID: ID<MIDINoteEvent>,
        containerID: ID<Container>,
        trackID: ID<Track>
    ) -> MIDINoteEvent? {
        guard let trackLayout = scene.trackLayouts.first(where: { $0.track.id == trackID }),
              let containerLayout = trackLayout.containers.first(where: { $0.container.id == containerID }) else {
            return nil
        }
        return containerLayout.resolvedMIDINotes?.first(where: { $0.id == noteID })
    }

    private func desiredCursorStyle(at point: CGPoint, snapshot: PlaybackGridSnapshot) -> CursorStyle {
        if let trackID = inlineMIDITrackID(at: point, snapshot: snapshot),
           !isPointNearInlineMIDILaneResizeHandle(point, snapshot: snapshot) {
            return inlineMIDICursorStyle(trackID: trackID, snapshot: snapshot)
        }
        if interactionController.isInteractionActive {
            return cursorStyle(forInteractionState: interactionController.state)
        }
        let pick = pickingRenderer.pick(
            at: point,
            scene: scene,
            snapshot: snapshot,
            visibleRect: visibleRect,
            canvasWidth: bounds.width
        )
        return cursorStyle(forHoverPick: pick, point: point, snapshot: snapshot)
    }

    private func inlineMIDICursorStyle(trackID: ID<Track>, snapshot: PlaybackGridSnapshot) -> CursorStyle {
        switch snapshot.inlineMIDIConfigs[trackID]?.tool {
        case .pencil:
            return .crosshair
        case .pointer, .none:
            return .arrow
        }
    }

    private func cursorStyle(forHoverPick pick: GridPickObject, point: CGPoint, snapshot: PlaybackGridSnapshot) -> CursorStyle {
        if isPointNearInlineMIDILaneResizeHandle(point, snapshot: snapshot) {
            return .resizeUpDown
        }
        switch pick.kind {
        case .midiNote:
            return (pick.zone == .resizeLeft || pick.zone == .resizeRight) ? .resizeLeftRight : .openHand
        case .containerZone:
            switch pick.zone {
            case .fadeLeft, .fadeRight:
                return .crosshair
            case .resizeLeft, .resizeRight, .trimLeft, .trimRight:
                return .resizeLeftRight
            case .selector:
                return .iBeam
            case .move:
                return .openHand
            case nil:
                return .arrow
            }
        default:
            return .arrow
        }
    }

    private func cursorStyle(forInteractionState state: PlaybackGridInteractionState) -> CursorStyle {
        switch state {
        case .idle:
            return .arrow
        case .scrubbingRuler, .selectingRange:
            return .iBeam
        case .selectingMIDINotes:
            return .arrow
        case .resizingMIDILane:
            return .resizeUpDown
        case .creatingMIDINote, .drawingAutomationShape, .drawingTrackAutomationShape:
            return .crosshair
        case let .draggingMIDINote(context):
            switch context.kind {
            case .move:
                return .closedHand
            case .resizeLeft, .resizeRight:
                return .resizeLeftRight
            case .velocity:
                return .resizeUpDown
            }
        case let .draggingContainer(context):
            switch context.kind {
            case .clone:
                return .dragCopy
            case .move:
                return .closedHand
            case .resizeLeft, .resizeRight, .trimLeft, .trimRight:
                return .resizeLeftRight
            case .fadeLeft, .fadeRight:
                return .crosshair
            }
        case .creatingContainer:
            return .crosshair
        case .draggingAutomationBreakpoint, .draggingTrackAutomationBreakpoint:
            return .crosshair
        }
    }

    private func applyCursorStyle(_ style: CursorStyle) {
        guard style != currentCursorStyle else { return }
        currentCursorStyle = style
        switch style {
        case .arrow:
            NSCursor.arrow.set()
        case .crosshair:
            NSCursor.crosshair.set()
        case .openHand:
            NSCursor.openHand.set()
        case .closedHand:
            NSCursor.closedHand.set()
        case .resizeLeftRight:
            NSCursor.resizeLeftRight.set()
        case .resizeUpDown:
            NSCursor.resizeUpDown.set()
        case .iBeam:
            NSCursor.iBeam.set()
        case .dragCopy:
            NSCursor.dragCopy.set()
        }
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
        let noteAreaHeight = snapshot.inlineMIDIConfigs[trackLayout.track.id]?.noteAreaHeight(totalInlineHeight: inlineHeight) ?? inlineHeight
        let automationHeight = trackLayout.automationToolbarHeight
            + (CGFloat(trackLayout.automationLaneLayouts.count) * snapshot.automationSubLaneHeight)
        return CGRect(
            x: containerLayout.rect.minX,
            y: trackLayout.yOrigin + trackLayout.clipHeight + automationHeight,
            width: containerLayout.rect.width,
            height: noteAreaHeight
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

    private func trackID(at point: CGPoint) -> ID<Track>? {
        for layout in scene.trackLayouts {
            let trackRect = CGRect(
                x: 0,
                y: layout.yOrigin,
                width: bounds.width,
                height: layout.height
            )
            if trackRect.contains(point) {
                return layout.track.id
            }
        }
        return nil
    }

    private func inlineMIDIKeyboardTrackID(
        at point: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) -> ID<Track>? {
        guard point.x <= PianoRollLayout.keyboardWidth else { return nil }
        return inlineMIDITrackID(at: point, snapshot: snapshot)
    }

    private func inlineMIDIZoomDelta(for event: NSEvent) -> CGFloat {
        if event.hasPreciseScrollingDeltas {
            return max(-3.0, min(3.0, CGFloat(event.scrollingDeltaY) * 0.12))
        }
        return event.scrollingDeltaY > 0 ? 1.5 : -1.5
    }

    private func trackHeightZoomDelta(for event: NSEvent) -> CGFloat {
        if event.hasPreciseScrollingDeltas {
            return max(-18.0, min(18.0, CGFloat(event.scrollingDeltaY) * 0.75))
        }
        return event.scrollingDeltaY > 0 ? 12 : -12
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

private final class CrossfadeCurveMenuInfo: NSObject {
    let crossfadeID: ID<Crossfade>
    let trackID: ID<Track>
    let curveType: CrossfadeCurveType

    init(crossfadeID: ID<Crossfade>, trackID: ID<Track>, curveType: CrossfadeCurveType) {
        self.crossfadeID = crossfadeID
        self.trackID = trackID
        self.curveType = curveType
    }
}
