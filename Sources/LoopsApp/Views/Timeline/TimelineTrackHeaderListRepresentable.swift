import SwiftUI
import AppKit
import LoopsCore

public struct TimelineTrackHeaderConfiguration {
    public struct InlineMIDIConfiguration {
        public struct DetailLane {
            public var lane: MIDINoteExpressionLane
            public var height: CGFloat
            public var onSetHeight: ((CGFloat) -> Void)?

            public init(
                lane: MIDINoteExpressionLane,
                height: CGFloat,
                onSetHeight: ((CGFloat) -> Void)? = nil
            ) {
                self.lane = lane
                self.height = height
                self.onSetHeight = onSetHeight
            }
        }

        public var lowPitch: UInt8
        public var highPitch: UInt8
        public var rowHeight: CGFloat
        public var height: CGFloat
        public var detailLanes: [DetailLane]
        public var onAdjustRowHeight: ((CGFloat) -> Void)?
        public var onShiftPitchRange: ((Int) -> Void)?

        public init(
            lowPitch: UInt8,
            highPitch: UInt8,
            rowHeight: CGFloat,
            height: CGFloat,
            detailLanes: [DetailLane] = [],
            onAdjustRowHeight: ((CGFloat) -> Void)? = nil,
            onShiftPitchRange: ((Int) -> Void)? = nil
        ) {
            self.lowPitch = lowPitch
            self.highPitch = highPitch
            self.rowHeight = rowHeight
            self.height = height
            self.detailLanes = detailLanes
            self.onAdjustRowHeight = onAdjustRowHeight
            self.onShiftPitchRange = onShiftPitchRange
        }

        public var noteAreaHeight: CGFloat {
            max(0, height - detailLanes.reduce(CGFloat(0)) { $0 + max(0, $1.height) })
        }
    }

    public var track: Track
    public var headerHeight: CGFloat
    public var totalHeight: CGFloat
    public var content: AnyView?
    public var inputPortName: String?
    public var outputPortName: String?
    public var midiDeviceName: String?
    public var midiChannelLabel: String?
    public var isAutomationExpanded: Bool
    public var automationLaneLabels: [String]
    public var isTrackSelected: Bool
    public var isMIDIActive: Bool
    public var headerWidth: CGFloat
    public var availableInputPorts: [InputPort]
    public var availableOutputPorts: [OutputPort]
    public var availableMIDIDevices: [MIDIInputDevice]
    public var inlineMIDI: InlineMIDIConfiguration?
    public var onMuteToggle: (() -> Void)?
    public var onSoloToggle: (() -> Void)?
    public var onRecordArmToggle: (() -> Void)?
    public var onMonitorToggle: (() -> Void)?
    public var onAutomationToggle: (() -> Void)?
    public var onResizeTrack: ((CGFloat) -> Void)?
    public var onResetTrackHeight: (() -> Void)?
    public var onSetInputPort: ((String?) -> Void)?
    public var onSetOutputPort: ((String?) -> Void)?
    public var onSetMIDIInput: ((String?, UInt8?) -> Void)?
    public var onSelect: (() -> Void)?

    public init(
        track: Track,
        headerHeight: CGFloat,
        totalHeight: CGFloat,
        content: AnyView? = nil,
        inputPortName: String? = nil,
        outputPortName: String? = nil,
        midiDeviceName: String? = nil,
        midiChannelLabel: String? = nil,
        isAutomationExpanded: Bool = false,
        automationLaneLabels: [String] = [],
        isTrackSelected: Bool = false,
        isMIDIActive: Bool = false,
        headerWidth: CGFloat,
        availableInputPorts: [InputPort] = [],
        availableOutputPorts: [OutputPort] = [],
        availableMIDIDevices: [MIDIInputDevice] = [],
        inlineMIDI: InlineMIDIConfiguration? = nil,
        onMuteToggle: (() -> Void)? = nil,
        onSoloToggle: (() -> Void)? = nil,
        onRecordArmToggle: (() -> Void)? = nil,
        onMonitorToggle: (() -> Void)? = nil,
        onAutomationToggle: (() -> Void)? = nil,
        onResizeTrack: ((CGFloat) -> Void)? = nil,
        onResetTrackHeight: (() -> Void)? = nil,
        onSetInputPort: ((String?) -> Void)? = nil,
        onSetOutputPort: ((String?) -> Void)? = nil,
        onSetMIDIInput: ((String?, UInt8?) -> Void)? = nil,
        onSelect: (() -> Void)? = nil
    ) {
        self.track = track
        self.headerHeight = headerHeight
        self.totalHeight = totalHeight
        self.content = content
        self.inputPortName = inputPortName
        self.outputPortName = outputPortName
        self.midiDeviceName = midiDeviceName
        self.midiChannelLabel = midiChannelLabel
        self.isAutomationExpanded = isAutomationExpanded
        self.automationLaneLabels = automationLaneLabels
        self.isTrackSelected = isTrackSelected
        self.isMIDIActive = isMIDIActive
        self.headerWidth = headerWidth
        self.availableInputPorts = availableInputPorts
        self.availableOutputPorts = availableOutputPorts
        self.availableMIDIDevices = availableMIDIDevices
        self.inlineMIDI = inlineMIDI
        self.onMuteToggle = onMuteToggle
        self.onSoloToggle = onSoloToggle
        self.onRecordArmToggle = onRecordArmToggle
        self.onMonitorToggle = onMonitorToggle
        self.onAutomationToggle = onAutomationToggle
        self.onResizeTrack = onResizeTrack
        self.onResetTrackHeight = onResetTrackHeight
        self.onSetInputPort = onSetInputPort
        self.onSetOutputPort = onSetOutputPort
        self.onSetMIDIInput = onSetMIDIInput
        self.onSelect = onSelect
    }
}

public struct TimelineTrackHeaderListRepresentable: NSViewRepresentable {
    let configurations: [TimelineTrackHeaderConfiguration]
    let scene: PlaybackGridScene
    let headerWidth: CGFloat

    public init(
        configurations: [TimelineTrackHeaderConfiguration],
        scene: PlaybackGridScene,
        headerWidth: CGFloat
    ) {
        self.configurations = configurations
        self.scene = scene
        self.headerWidth = headerWidth
    }

    public func makeNSView(context: Context) -> TimelineTrackHeaderListNSView {
        let view = TimelineTrackHeaderListNSView(frame: .zero)
        view.configure(configurations: configurations, scene: scene, headerWidth: headerWidth)
        return view
    }

    public func updateNSView(_ nsView: TimelineTrackHeaderListNSView, context: Context) {
        nsView.configure(configurations: configurations, scene: scene, headerWidth: headerWidth)
    }
}

public final class TimelineTrackHeaderListNSView: NSView {
    private var hostingViews: [ID<Track>: NSHostingView<AnyView>] = [:]

    public override var isFlipped: Bool { true }

    public func configure(
        configurations: [TimelineTrackHeaderConfiguration],
        scene: PlaybackGridScene,
        headerWidth: CGFloat
    ) {
        frame = CGRect(x: 0, y: 0, width: headerWidth, height: scene.contentHeight)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let configByTrackID = Dictionary(uniqueKeysWithValues: configurations.map { ($0.track.id, $0) })
        let activeTrackIDs = Set(scene.trackLayouts.map(\.track.id))

        for (trackID, view) in hostingViews where !activeTrackIDs.contains(trackID) {
            view.removeFromSuperview()
            hostingViews.removeValue(forKey: trackID)
        }

        for layout in scene.trackLayouts {
            guard let config = configByTrackID[layout.track.id] else { continue }
            let hosting = hostingViews[layout.track.id] ?? {
                let view = NSHostingView(rootView: AnyView(TimelineTrackHeaderContentView(configuration: config)))
                view.autoresizingMask = [.width]
                hostingViews[layout.track.id] = view
                addSubview(view)
                return view
            }()
            hosting.rootView = AnyView(TimelineTrackHeaderContentView(configuration: config))
            hosting.frame = CGRect(x: 0, y: layout.yOrigin, width: headerWidth, height: layout.height)
        }
    }
}

private struct TimelineTrackHeaderContentView: View {
    let configuration: TimelineTrackHeaderConfiguration

    var body: some View {
        VStack(spacing: 0) {
            if let content = configuration.content {
                content
            } else {
                TrackHeaderView(
                    track: configuration.track,
                    height: configuration.headerHeight,
                    inputPortName: configuration.inputPortName,
                    outputPortName: configuration.outputPortName,
                    midiDeviceName: configuration.midiDeviceName,
                    midiChannelLabel: configuration.midiChannelLabel,
                    isAutomationExpanded: configuration.isAutomationExpanded,
                    automationLaneLabels: configuration.automationLaneLabels,
                    onMuteToggle: configuration.onMuteToggle,
                    onSoloToggle: configuration.onSoloToggle,
                    onRecordArmToggle: configuration.onRecordArmToggle,
                    onMonitorToggle: configuration.onMonitorToggle,
                    onAutomationToggle: configuration.onAutomationToggle,
                    isTrackSelected: configuration.isTrackSelected,
                    isMIDIActive: configuration.isMIDIActive,
                    headerWidth: configuration.headerWidth,
                    onResizeTrack: configuration.onResizeTrack,
                    onResetTrackHeight: configuration.onResetTrackHeight,
                    availableInputPorts: configuration.availableInputPorts,
                    availableOutputPorts: configuration.availableOutputPorts,
                    availableMIDIDevices: configuration.availableMIDIDevices,
                    onSetInputPort: configuration.onSetInputPort,
                    onSetOutputPort: configuration.onSetOutputPort,
                    onSetMIDIInput: configuration.onSetMIDIInput
                )
            }

            if let inline = configuration.inlineMIDI {
                InlinePianoRollKeyboardLabelsView(configuration: inline)
            }
        }
        .frame(width: configuration.headerWidth, height: configuration.totalHeight, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            configuration.onSelect?()
        }
    }
}

private struct InlinePianoRollKeyboardLabelsView: View {
    let configuration: TimelineTrackHeaderConfiguration.InlineMIDIConfiguration

    var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(spacing: 0) {
                        ForEach((Int(configuration.lowPitch)...Int(configuration.highPitch)).reversed(), id: \.self) { pitch in
                            let note = UInt8(pitch)
                            let isBlack = PianoLayout.isBlackKey(note: note)
                            let isC = note % 12 == 0

                            InlinePianoKeyboardKeyRow(
                                note: note,
                                rowHeight: configuration.rowHeight,
                                isBlack: isBlack,
                                isC: isC
                            )
                        }
                    }
                    .frame(width: PianoRollLayout.keyboardWidth, height: configuration.noteAreaHeight, alignment: .topTrailing)
                    .overlay {
                        InlineMIDIKeyboardInteractionOverlay(configuration: configuration)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                if !configuration.detailLanes.isEmpty {
                    ForEach(configuration.detailLanes, id: \.lane) { detailLane in
                        InlineMIDIDetailLaneSidebar(lane: detailLane)
                    }
                }
            }
        .frame(height: configuration.height, alignment: .topTrailing)
        .clipped()
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor).opacity(0.96),
                    Color.black.opacity(0.18)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.22))
                .frame(height: 1)
        }
    }
}

private struct InlineMIDIDetailLaneSidebar: View {
    let lane: TimelineTrackHeaderConfiguration.InlineMIDIConfiguration.DetailLane
    @State private var resizeStartHeight: CGFloat = 0
    @State private var resizePreviewHeight: CGFloat?

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: lane.lane.iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.85))
                Text(lane.lane.shortLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.secondary.opacity(0.9))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(width: PianoRollLayout.keyboardWidth, height: resizePreviewHeight ?? lane.height, alignment: .center)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.16),
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    DetailLaneResizeHandle(
                        onSetHeight: lane.onSetHeight,
                        resizeStartHeight: $resizeStartHeight,
                        resizePreviewHeight: $resizePreviewHeight,
                        currentHeight: lane.height
                    )
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct DetailLaneResizeHandle: View {
    let onSetHeight: ((CGFloat) -> Void)?
    @Binding var resizeStartHeight: CGFloat
    @Binding var resizePreviewHeight: CGFloat?
    let currentHeight: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(height: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard onSetHeight != nil else { return }
                        if resizeStartHeight == 0 {
                            resizeStartHeight = currentHeight
                        }
                        resizePreviewHeight = max(PianoRollEditorState.minDetailLaneHeight, resizeStartHeight + value.translation.height)
                    }
                    .onEnded { _ in
                        if let preview = resizePreviewHeight {
                            onSetHeight?(preview)
                        }
                        resizeStartHeight = 0
                        resizePreviewHeight = nil
                    }
            )
    }
}

private struct InlinePianoKeyboardKeyRow: View {
    let note: UInt8
    let rowHeight: CGFloat
    let isBlack: Bool
    let isC: Bool

    private var labelFontSize: CGFloat {
        max(7, min(rowHeight - 2, 10))
    }

    private var blackKeyWidth: CGFloat {
        max(24, PianoRollLayout.keyboardWidth - 10)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            whiteKeyBody

            if isBlack {
                blackKeyBody
            }

            labelOverlay
        }
        .frame(width: PianoRollLayout.keyboardWidth, height: rowHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isBlack ? Color.black.opacity(0.55) : Color.black.opacity(0.12))
                .frame(height: 0.5)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isC ? Color.accentColor.opacity(0.75) : Color.clear)
                .frame(width: isC ? 2 : 0)
        }
    }

    private var whiteKeyBody: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isBlack ? 0.22 : 0.97),
                        Color.white.opacity(isBlack ? 0.12 : 0.86),
                        Color.black.opacity(isBlack ? 0.14 : 0.08)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(isBlack ? 0.08 : 0.42))
                    .frame(width: 1)
            }
    }

    private var blackKeyBody: some View {
        RoundedRectangle(cornerRadius: max(2, min(rowHeight * 0.18, 4)), style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.24, green: 0.25, blue: 0.29),
                        Color(red: 0.10, green: 0.11, blue: 0.14)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: blackKeyWidth, height: max(rowHeight - 1, 4))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)
                    .padding(.vertical, 2)
            }
            .shadow(color: Color.black.opacity(0.28), radius: 1.2, x: 0, y: 0.8)
    }

    private var labelOverlay: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            if isC {
                Text(PianoLayout.noteName(note))
                    .font(.system(size: labelFontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isBlack ? Color.white.opacity(0.92) : Color.black.opacity(0.82))
                    .padding(.horizontal, 4)
                    .padding(.vertical, max(1, rowHeight * 0.08))
                    .background(
                        Capsule(style: .continuous)
                            .fill(isBlack ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                    )
            } else if !isBlack, rowHeight >= 11 {
                Text(PianoLayout.noteName(note))
                    .font(.system(size: labelFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.48))
            } else if isBlack, rowHeight >= 11 {
                Text(PianoLayout.noteName(note))
                    .font(.system(size: labelFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.58))
            }
        }
        .padding(.leading, 2)
        .padding(.trailing, isBlack ? 4 : 3)
    }
}

private struct InlineMIDIKeyboardInteractionOverlay: NSViewRepresentable {
    let configuration: TimelineTrackHeaderConfiguration.InlineMIDIConfiguration

    func makeNSView(context: Context) -> InlineMIDIKeyboardInteractionNSView {
        let view = InlineMIDIKeyboardInteractionNSView()
        view.configure(configuration: configuration)
        return view
    }

    func updateNSView(_ nsView: InlineMIDIKeyboardInteractionNSView, context: Context) {
        nsView.configure(configuration: configuration)
    }
}

private final class InlineMIDIKeyboardInteractionNSView: NSView {
    private var configuration: TimelineTrackHeaderConfiguration.InlineMIDIConfiguration?
    private var cursorPushed = false
    private var pitchScrollAccumulator: CGFloat = 0

    override var isFlipped: Bool { true }

    func configure(configuration: TimelineTrackHeaderConfiguration.InlineMIDIConfiguration) {
        self.configuration = configuration
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard !cursorPushed else { return }
        NSCursor.openHand.push()
        cursorPushed = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        popCursorIfNeeded()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard !cursorPushed else { return }
        NSCursor.openHand.set()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let configuration else {
            super.scrollWheel(with: event)
            return
        }

        let deltaY = event.scrollingDeltaY
        guard abs(deltaY) > abs(event.scrollingDeltaX) else {
            super.scrollWheel(with: event)
            return
        }

        let zoomModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        if !event.modifierFlags.intersection(zoomModifiers).isEmpty {
            pitchScrollAccumulator = 0
            let signedStep: CGFloat = deltaY > 0 ? 1 : -1
            configuration.onAdjustRowHeight?(signedStep * 1.5)
            return
        }

        pitchScrollAccumulator += deltaY
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 14 : 1
        while abs(pitchScrollAccumulator) >= threshold {
            let semitoneStep = pitchScrollAccumulator > 0 ? 1 : -1
            configuration.onShiftPitchRange?(semitoneStep)
            pitchScrollAccumulator -= CGFloat(semitoneStep) * threshold
        }
    }

    override func magnify(with event: NSEvent) {
        guard let configuration else {
            super.magnify(with: event)
            return
        }
        let delta = max(-8.0, min(8.0, CGFloat(event.magnification * 24.0)))
        guard abs(delta) > 0.01 else { return }
        configuration.onAdjustRowHeight?(delta)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            popCursorIfNeeded()
        }
    }

    deinit {
        popCursorIfNeeded()
    }

    private func popCursorIfNeeded() {
        guard cursorPushed else { return }
        NSCursor.pop()
        cursorPushed = false
    }
}
