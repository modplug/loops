import SwiftUI
import AppKit
import LoopsCore

/// Renders a single container as a colored rectangle on the track lane.
/// Supports selection highlight, context menu for deletion, and displays
/// the container name and length.
public struct ContainerView: View {
    let container: Container
    let pixelsPerBar: CGFloat
    let height: CGFloat
    let isSelected: Bool
    let trackColor: Color
    let waveformPeaks: [Float]?
    let isClone: Bool
    let overriddenFields: Set<ContainerField>
    var onSelect: (() -> Void)?
    var onDelete: (() -> Void)?
    var onMove: ((_ newStartBar: Int) -> Bool)?
    var onResizeLeft: ((_ newStartBar: Int, _ newLength: Int) -> Bool)?
    var onResizeRight: ((_ newLength: Int) -> Bool)?
    var onDoubleClick: (() -> Void)?
    var onClone: ((_ newStartBar: Int) -> Void)?
    var onCopy: (() -> Void)?
    var onCopyToSong: ((_ songID: ID<Song>) -> Void)?
    var otherSongs: [(id: ID<Song>, name: String)]
    var onDuplicate: (() -> Void)?
    var onLinkClone: (() -> Void)?
    var onUnlink: (() -> Void)?
    var onArmToggle: (() -> Void)?
    var onSetEnterFade: ((FadeSettings?) -> Void)?
    var onSetExitFade: ((FadeSettings?) -> Void)?

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var resizeLeftDelta: CGFloat = 0
    @State private var resizeRightDelta: CGFloat = 0
    @State private var isResizingLeft = false
    @State private var isResizingRight = false
    @State private var isAltDragging = false
    @State private var altDragOffset: CGFloat = 0
    @State private var isHovering = false
    @State private var enterFadeDragWidth: CGFloat?
    @State private var exitFadeDragWidth: CGFloat?

    public init(
        container: Container,
        pixelsPerBar: CGFloat,
        height: CGFloat = 76,
        isSelected: Bool = false,
        trackColor: Color = .blue,
        waveformPeaks: [Float]? = nil,
        isClone: Bool = false,
        overriddenFields: Set<ContainerField> = [],
        onSelect: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onMove: ((_ newStartBar: Int) -> Bool)? = nil,
        onResizeLeft: ((_ newStartBar: Int, _ newLength: Int) -> Bool)? = nil,
        onResizeRight: ((_ newLength: Int) -> Bool)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onClone: ((_ newStartBar: Int) -> Void)? = nil,
        onCopy: (() -> Void)? = nil,
        onCopyToSong: ((_ songID: ID<Song>) -> Void)? = nil,
        otherSongs: [(id: ID<Song>, name: String)] = [],
        onDuplicate: (() -> Void)? = nil,
        onLinkClone: (() -> Void)? = nil,
        onUnlink: (() -> Void)? = nil,
        onArmToggle: (() -> Void)? = nil,
        onSetEnterFade: ((FadeSettings?) -> Void)? = nil,
        onSetExitFade: ((FadeSettings?) -> Void)? = nil
    ) {
        self.container = container
        self.pixelsPerBar = pixelsPerBar
        self.height = height
        self.isSelected = isSelected
        self.trackColor = trackColor
        self.waveformPeaks = waveformPeaks
        self.isClone = isClone
        self.overriddenFields = overriddenFields
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onMove = onMove
        self.onResizeLeft = onResizeLeft
        self.onResizeRight = onResizeRight
        self.onDoubleClick = onDoubleClick
        self.onClone = onClone
        self.onCopy = onCopy
        self.onCopyToSong = onCopyToSong
        self.otherSongs = otherSongs
        self.onDuplicate = onDuplicate
        self.onLinkClone = onLinkClone
        self.onUnlink = onUnlink
        self.onArmToggle = onArmToggle
        self.onSetEnterFade = onSetEnterFade
        self.onSetExitFade = onSetExitFade
    }

    private var containerWidth: CGFloat {
        CGFloat(container.lengthBars) * pixelsPerBar
    }

    public var body: some View {
        ZStack {
            // Container body
            RoundedRectangle(cornerRadius: 4)
                .fill(container.isRecordArmed ? Color.red.opacity(0.15) : trackColor.opacity(isSelected ? 0.5 : 0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            container.isRecordArmed ? Color.red : (isSelected ? Color.accentColor : trackColor.opacity(0.6)),
                            lineWidth: container.isRecordArmed || isSelected ? 2 : 1
                        )
                )

            // Waveform (audio containers)
            if let peaks = waveformPeaks, !peaks.isEmpty {
                WaveformView(peaks: peaks, color: trackColor)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }

            // MIDI note minimap (MIDI containers)
            if let sequence = container.midiSequence, !sequence.notes.isEmpty {
                MIDINoteMinimapView(
                    notes: sequence.notes,
                    containerLengthBars: container.lengthBars,
                    beatsPerBar: 4,
                    color: trackColor
                )
                .padding(.horizontal, 2)
                .padding(.vertical, 16)
                .allowsHitTesting(false)
            }

            // Automation overlay curves
            if !container.automationLanes.isEmpty {
                AutomationOverlayView(
                    automationLanes: container.automationLanes,
                    containerLengthBars: container.lengthBars,
                    pixelsPerBar: pixelsPerBar,
                    height: height
                )
                .padding(2)
                .allowsHitTesting(false)
            }

            // Fade curve overlays
            if container.enterFade != nil || container.exitFade != nil || enterFadeDragWidth != nil || exitFadeDragWidth != nil {
                FadeOverlayShape(
                    containerWidth: containerWidth,
                    height: height,
                    enterFade: container.enterFade,
                    exitFade: container.exitFade,
                    enterFadeDragWidth: enterFadeDragWidth,
                    exitFadeDragWidth: exitFadeDragWidth,
                    pixelsPerBar: pixelsPerBar
                )
                .fill(Color.black.opacity(0.25))
                .allowsHitTesting(false)
            }

            // Fade handles
            fadeHandleOverlay

            // Container label
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    if container.isRecordArmed {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.red)
                    }
                    if isClone {
                        Image(systemName: "link")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    Text(container.name)
                        .font(.caption2.bold())
                        .lineLimit(1)
                }
                HStack(spacing: 2) {
                    Text("\(container.lengthBars) bar\(container.lengthBars == 1 ? "" : "s")")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    if isClone && !overriddenFields.isEmpty {
                        Text("\(overriddenFields.count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.8)))
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Left resize handle
            Rectangle()
                .fill(Color.clear)
                .frame(width: 6)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(leftResizeGesture)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Right resize handle
            Rectangle()
                .fill(Color.clear)
                .frame(width: 6)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(rightResizeGesture)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: displayWidth, height: height)
        .offset(x: displayOffset)
        .onHover { hovering in isHovering = hovering }
        .onTapGesture(count: 2) { onDoubleClick?() }
        .onTapGesture { onSelect?() }
        .gesture(altCloneGesture)
        .gesture(moveGesture)
        .contextMenu {
            Button("Copy") { onCopy?() }
            Button("Duplicate") { onDuplicate?() }
            Button("Link (Create Clone)") { onLinkClone?() }
            if isClone {
                Button("Unlink (Consolidate)") { onUnlink?() }
            }
            if !otherSongs.isEmpty {
                Menu("Copy to Song\u{2026}") {
                    ForEach(otherSongs, id: \.id) { song in
                        Button(song.name) { onCopyToSong?(song.id) }
                    }
                }
            }
            Divider()
            Button("Edit...") { onDoubleClick?() }
            Button("Arm/Disarm") { onArmToggle?() }
            Divider()
            Button("Delete", role: .destructive) { onDelete?() }
        }

        // Alt-drag clone ghost preview
        if isAltDragging {
            RoundedRectangle(cornerRadius: 4)
                .fill(trackColor.opacity(0.2))
                .strokeBorder(trackColor.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
                .frame(width: containerWidth, height: height)
                .offset(x: altDragOffset)
                .allowsHitTesting(false)
        }
    }

    private var displayWidth: CGFloat {
        if isResizingLeft {
            return max(pixelsPerBar, containerWidth - resizeLeftDelta)
        } else if isResizingRight {
            return max(pixelsPerBar, containerWidth + resizeRightDelta)
        }
        return containerWidth
    }

    private var displayOffset: CGFloat {
        if isDragging {
            return dragOffset
        } else if isResizingLeft {
            return resizeLeftDelta
        }
        return 0
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                isDragging = true
                // Snap to bar boundaries
                let barDelta = round(value.translation.width / pixelsPerBar)
                dragOffset = barDelta * pixelsPerBar
            }
            .onEnded { value in
                isDragging = false
                let barDelta = Int(round(value.translation.width / pixelsPerBar))
                let newStart = container.startBar + barDelta
                let _ = onMove?(newStart)
                dragOffset = 0
            }
    }

    private var leftResizeGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                isResizingLeft = true
                let barDelta = round(value.translation.width / pixelsPerBar)
                resizeLeftDelta = barDelta * pixelsPerBar
            }
            .onEnded { value in
                isResizingLeft = false
                let barDelta = Int(round(value.translation.width / pixelsPerBar))
                let newStart = container.startBar + barDelta
                let newLength = container.lengthBars - barDelta
                if newLength >= 1 && newStart >= 1 {
                    let _ = onResizeLeft?(newStart, newLength)
                }
                resizeLeftDelta = 0
            }
    }

    private var rightResizeGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                isResizingRight = true
                let barDelta = round(value.translation.width / pixelsPerBar)
                resizeRightDelta = barDelta * pixelsPerBar
            }
            .onEnded { value in
                isResizingRight = false
                let barDelta = Int(round(value.translation.width / pixelsPerBar))
                let newLength = container.lengthBars + barDelta
                if newLength >= 1 {
                    let _ = onResizeRight?(newLength)
                }
                resizeRightDelta = 0
            }
    }

    private var altCloneGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .modifiers(.option)
            .onChanged { value in
                isAltDragging = true
                let barDelta = round(value.translation.width / pixelsPerBar)
                altDragOffset = barDelta * pixelsPerBar
            }
            .onEnded { value in
                isAltDragging = false
                let barDelta = Int(round(value.translation.width / pixelsPerBar))
                let newStart = container.startBar + barDelta
                if newStart >= 1 {
                    onClone?(newStart)
                }
                altDragOffset = 0
            }
    }

    // MARK: - Fade Handles

    private var showFadeHandles: Bool {
        isHovering || container.enterFade != nil || container.exitFade != nil
    }

    private var enterFadeWidth: CGFloat {
        if let dragW = enterFadeDragWidth { return dragW }
        guard let fade = container.enterFade else { return 0 }
        return CGFloat(fade.duration) * pixelsPerBar
    }

    private var exitFadeWidth: CGFloat {
        if let dragW = exitFadeDragWidth { return dragW }
        guard let fade = container.exitFade else { return 0 }
        return CGFloat(fade.duration) * pixelsPerBar
    }

    private static let fadeHandleSize: CGFloat = 10

    @ViewBuilder
    private var fadeHandleOverlay: some View {
        if showFadeHandles {
            // Enter fade handle (top-left)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: Self.fadeHandleSize, height: Self.fadeHandleSize)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                .offset(x: enterFadeWidth - Self.fadeHandleSize / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 2)
                .gesture(enterFadeDragGesture)
                .onHover { hovering in
                    if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }

            // Exit fade handle (top-right)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: Self.fadeHandleSize, height: Self.fadeHandleSize)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                .offset(x: -exitFadeWidth + Self.fadeHandleSize / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 2)
                .gesture(exitFadeDragGesture)
                .onHover { hovering in
                    if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
        }
    }

    private var enterFadeDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let currentWidth = CGFloat(container.enterFade?.duration ?? 0) * pixelsPerBar
                let newWidth = max(0, min(currentWidth + value.translation.width, containerWidth))
                enterFadeDragWidth = newWidth
            }
            .onEnded { value in
                let currentWidth = CGFloat(container.enterFade?.duration ?? 0) * pixelsPerBar
                let newWidth = max(0, min(currentWidth + value.translation.width, containerWidth))
                let newDuration = Double(newWidth) / Double(pixelsPerBar)
                enterFadeDragWidth = nil
                if newDuration < 0.125 {
                    onSetEnterFade?(nil)
                } else {
                    let snapped = round(newDuration * 4.0) / 4.0
                    let curve = container.enterFade?.curve ?? .linear
                    onSetEnterFade?(FadeSettings(duration: max(0.25, snapped), curve: curve))
                }
            }
    }

    private var exitFadeDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let currentWidth = CGFloat(container.exitFade?.duration ?? 0) * pixelsPerBar
                let newWidth = max(0, min(currentWidth - value.translation.width, containerWidth))
                exitFadeDragWidth = newWidth
            }
            .onEnded { value in
                let currentWidth = CGFloat(container.exitFade?.duration ?? 0) * pixelsPerBar
                let newWidth = max(0, min(currentWidth - value.translation.width, containerWidth))
                let newDuration = Double(newWidth) / Double(pixelsPerBar)
                exitFadeDragWidth = nil
                if newDuration < 0.125 {
                    onSetExitFade?(nil)
                } else {
                    let snapped = round(newDuration * 4.0) / 4.0
                    let curve = container.exitFade?.curve ?? .linear
                    onSetExitFade?(FadeSettings(duration: max(0.25, snapped), curve: curve))
                }
            }
    }
}

// MARK: - Equatable

extension ContainerView: Equatable {
    public static func == (lhs: ContainerView, rhs: ContainerView) -> Bool {
        lhs.container == rhs.container &&
        lhs.pixelsPerBar == rhs.pixelsPerBar &&
        lhs.height == rhs.height &&
        lhs.isSelected == rhs.isSelected &&
        lhs.trackColor == rhs.trackColor &&
        lhs.waveformPeaks == rhs.waveformPeaks &&
        lhs.isClone == rhs.isClone &&
        lhs.overriddenFields == rhs.overriddenFields &&
        lhs.otherSongs.count == rhs.otherSongs.count &&
        zip(lhs.otherSongs, rhs.otherSongs).allSatisfy { $0.id == $1.id && $0.name == $1.name }
    }
}

// MARK: - Fade Overlay Shape

/// Draws the semi-transparent fade overlay on a container.
/// For fade-in: a shape covering the top of the container that tapers down following the curve.
/// For fade-out: a shape covering the top of the container that rises following the inverse curve.
/// The shaded area represents the gain reduction (area above the curve = silence).
struct FadeOverlayShape: Shape {
    let containerWidth: CGFloat
    let height: CGFloat
    let enterFade: FadeSettings?
    let exitFade: FadeSettings?
    let enterFadeDragWidth: CGFloat?
    let exitFadeDragWidth: CGFloat?
    let pixelsPerBar: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Enter fade overlay (gain ramps 0→1, so overlay shows the silence portion above the curve)
        let enterWidth: CGFloat
        if let dragW = enterFadeDragWidth {
            enterWidth = dragW
        } else if let fade = enterFade {
            enterWidth = CGFloat(fade.duration) * pixelsPerBar
        } else {
            enterWidth = 0
        }
        let enterCurve = enterFade?.curve ?? .linear

        if enterWidth > 0 {
            path.move(to: CGPoint(x: 0, y: 0))
            let steps = max(Int(enterWidth / 2), 20)
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let gain = enterCurve.gain(at: t)
                let x = CGFloat(t) * enterWidth
                let y = CGFloat(1.0 - gain) * rect.height
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.closeSubpath()
        }

        // Exit fade overlay (gain ramps 1→0)
        let exitWidth: CGFloat
        if let dragW = exitFadeDragWidth {
            exitWidth = dragW
        } else if let fade = exitFade {
            exitWidth = CGFloat(fade.duration) * pixelsPerBar
        } else {
            exitWidth = 0
        }
        let exitCurve = exitFade?.curve ?? .linear

        if exitWidth > 0 {
            let startX = rect.width - exitWidth
            path.move(to: CGPoint(x: rect.width, y: 0))
            let steps = max(Int(exitWidth / 2), 20)
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let gain = exitCurve.gain(at: 1.0 - t)
                let x = startX + CGFloat(t) * exitWidth
                let y = CGFloat(1.0 - gain) * rect.height
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: rect.width, y: 0))
            path.closeSubpath()
        }

        return path
    }
}
