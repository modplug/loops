import SwiftUI
import AppKit
import LoopsCore

/// Smart Tool zone: determines behavior based on where in the container the user interacts.
private enum SmartZone {
    case fadeLeft        // top-left corner: enter fade drag
    case fadeRight       // top-right corner: exit fade drag
    case selector        // top center: ibeam / selection (future)
    case resizeLeft      // middle left edge: resize
    case resizeRight     // middle right edge: resize
    case move            // middle center: grab & move
    case trimLeft        // bottom left edge: trim (adjusts audioStartOffset + startBar)
    case trimRight       // bottom right edge: trim (adjusts lengthBars)
    case trimMove        // bottom center: falls through to move
}

/// Renders a single container as a colored rectangle on the track lane.
/// Uses a Pro Tools Smart Tool-inspired zone-based gesture system.
public struct ContainerView: View {
    let container: Container
    let pixelsPerBar: CGFloat
    let height: CGFloat
    var selectionState: SelectionState?
    let trackColor: Color
    let waveformPeaks: [Float]?
    let isClone: Bool
    let overriddenFields: Set<ContainerField>
    /// Resolved MIDI sequence for minimap display (inherits from parent for clones).
    var resolvedMIDISequence: MIDISequence?
    /// Total duration of the source recording in bars (nil if unknown or no recording).
    /// Used to compute waveform start/length fractions for cropped display.
    let recordingDurationBars: Double?
    var onSelect: (() -> Void)?
    var onPlayheadTap: ((_ timelineX: CGFloat) -> Void)?
    var onDelete: (() -> Void)?
    var onMove: ((_ newStartBar: Double) -> Bool)?
    var onResizeLeft: ((_ newStartBar: Double, _ newLength: Double) -> Bool)?
    var onResizeRight: ((_ newLength: Double) -> Bool)?
    var onTrimLeft: ((_ newAudioStartOffset: Double, _ newStartBar: Double, _ newLength: Double) -> Bool)?
    var onTrimRight: ((_ newLength: Double) -> Bool)?
    var onDoubleClick: (() -> Void)?
    var onClone: ((_ newStartBar: Double) -> Void)?
    var onCopy: (() -> Void)?
    var onCopyToSong: ((_ songID: ID<Song>) -> Void)?
    var otherSongs: [(id: ID<Song>, name: String)]
    var onDuplicate: (() -> Void)?
    var onLinkClone: (() -> Void)?
    var onUnlink: (() -> Void)?
    var onArmToggle: (() -> Void)?
    var onSetEnterFade: ((FadeSettings?) -> Void)?
    var onSetExitFade: ((FadeSettings?) -> Void)?
    var onSplit: (() -> Void)?
    var onRangeSelect: ((_ startBar: Double, _ endBar: Double) -> Void)?
    var onGlue: (() -> Void)?
    /// Snaps a bar value to the current grid resolution. Falls back to whole-bar rounding if nil.
    var snapToGrid: ((_ bar: Double) -> Double)?

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var resizeLeftDelta: CGFloat = 0
    @State private var resizeRightDelta: CGFloat = 0
    @State private var isResizingLeft = false
    @State private var isResizingRight = false
    @State private var isTrimming = false
    @State private var trimLeftDelta: CGFloat = 0
    @State private var trimRightDelta: CGFloat = 0
    @State private var isTrimmingLeft = false
    @State private var isTrimmingRight = false
    @State private var isAltDragging = false
    @State private var altDragOffset: CGFloat = 0
    @State private var isHovering = false
    @State private var hoverZone: SmartZone?
    @State private var enterFadeDragWidth: CGFloat?
    @State private var exitFadeDragWidth: CGFloat?
    @State private var selectorDragStartX: CGFloat?
    @State private var selectorDragCurrentX: CGFloat?
    /// Zone locked at drag start so it doesn't change mid-gesture.
    @State private var activeDragZone: SmartZone?

    /// Edge threshold in points for zone detection.
    private static let edgeThreshold: CGFloat = 12

    public init(
        container: Container,
        pixelsPerBar: CGFloat,
        height: CGFloat = 76,
        selectionState: SelectionState? = nil,
        trackColor: Color = .blue,
        waveformPeaks: [Float]? = nil,
        isClone: Bool = false,
        overriddenFields: Set<ContainerField> = [],
        resolvedMIDISequence: MIDISequence? = nil,
        recordingDurationBars: Double? = nil,
        onSelect: (() -> Void)? = nil,
        onPlayheadTap: ((_ timelineX: CGFloat) -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onMove: ((_ newStartBar: Double) -> Bool)? = nil,
        onResizeLeft: ((_ newStartBar: Double, _ newLength: Double) -> Bool)? = nil,
        onResizeRight: ((_ newLength: Double) -> Bool)? = nil,
        onTrimLeft: ((_ newAudioStartOffset: Double, _ newStartBar: Double, _ newLength: Double) -> Bool)? = nil,
        onTrimRight: ((_ newLength: Double) -> Bool)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onClone: ((_ newStartBar: Double) -> Void)? = nil,
        onCopy: (() -> Void)? = nil,
        onCopyToSong: ((_ songID: ID<Song>) -> Void)? = nil,
        otherSongs: [(id: ID<Song>, name: String)] = [],
        onDuplicate: (() -> Void)? = nil,
        onLinkClone: (() -> Void)? = nil,
        onUnlink: (() -> Void)? = nil,
        onArmToggle: (() -> Void)? = nil,
        onSetEnterFade: ((FadeSettings?) -> Void)? = nil,
        onSetExitFade: ((FadeSettings?) -> Void)? = nil,
        onSplit: (() -> Void)? = nil,
        onRangeSelect: ((_ startBar: Double, _ endBar: Double) -> Void)? = nil,
        onGlue: (() -> Void)? = nil,
        snapToGrid: ((_ bar: Double) -> Double)? = nil
    ) {
        self.container = container
        self.pixelsPerBar = pixelsPerBar
        self.height = height
        self.selectionState = selectionState
        self.trackColor = trackColor
        self.waveformPeaks = waveformPeaks
        self.isClone = isClone
        self.overriddenFields = overriddenFields
        self.resolvedMIDISequence = resolvedMIDISequence
        self.recordingDurationBars = recordingDurationBars
        self.onSelect = onSelect
        self.onPlayheadTap = onPlayheadTap
        self.onDelete = onDelete
        self.onMove = onMove
        self.onResizeLeft = onResizeLeft
        self.onResizeRight = onResizeRight
        self.onTrimLeft = onTrimLeft
        self.onTrimRight = onTrimRight
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
        self.onSplit = onSplit
        self.onRangeSelect = onRangeSelect
        self.onGlue = onGlue
        self.snapToGrid = snapToGrid
    }

    /// Derived from SelectionState observable — only this ContainerView re-evaluates
    /// when selection changes, not the parent TrackLaneView or TimelineView.
    private var isSelected: Bool {
        selectionState?.selectedContainerID == container.id
    }

    private var containerWidth: CGFloat {
        CGFloat(container.lengthBars) * pixelsPerBar
    }

    /// Container's left edge X in the trackLane coordinate space.
    private var containerOriginX: CGFloat {
        CGFloat(container.startBar - 1) * pixelsPerBar
    }

    private var waveformStartFraction: CGFloat {
        guard let totalBars = recordingDurationBars, totalBars > 0 else { return 0 }
        return CGFloat(container.audioStartOffset / totalBars)
    }

    private var waveformLengthFraction: CGFloat {
        guard let totalBars = recordingDurationBars, totalBars > 0 else { return 1 }
        // Use the actual audible bars (clamped to recording end) so peaks
        // exactly match the audio — avoids slight stretch when container
        // extends past the recording due to ceil() rounding.
        let audibleBars = min(container.lengthBars, totalBars - container.audioStartOffset)
        return min(1.0, CGFloat(max(0, audibleBars) / totalBars))
    }

    /// Fraction of the container's pixel width that actually contains audio.
    /// When barsForDuration rounds up (ceil), the container is wider than the recording,
    /// so the waveform should only fill the portion with audio, aligned to the leading edge.
    private var waveformWidthFraction: CGFloat {
        guard let totalBars = recordingDurationBars, totalBars > 0 else { return 1.0 }
        let audioEnd = min(container.audioStartOffset + container.lengthBars, totalBars)
        let audibleBars = max(0, audioEnd - container.audioStartOffset)
        return min(1.0, CGFloat(audibleBars / container.lengthBars))
    }

    // MARK: - Extension Preview (Resize or Trim)

    /// Whether the container is being extended rightward (resize or trim).
    private var isExtendingRight: Bool {
        (isResizingRight && resizeRightDelta > 0) || (isTrimmingRight && trimRightDelta > 0)
    }

    /// Whether the container is being extended leftward (resize or trim).
    private var isExtendingLeft: Bool {
        (isResizingLeft && resizeLeftDelta < 0) || (isTrimmingLeft && trimLeftDelta < 0)
    }

    /// Pixel width of a right extension (from either resize or trim).
    private var rightExtendPixels: CGFloat {
        if isResizingRight, resizeRightDelta > 0 { return resizeRightDelta }
        if isTrimmingRight, trimRightDelta > 0 { return trimRightDelta }
        return 0
    }

    /// Pixel width of a left extension (from either resize or trim).
    private var leftExtendPixels: CGFloat {
        if isResizingLeft, resizeLeftDelta < 0 { return -resizeLeftDelta }
        if isTrimmingLeft, trimLeftDelta < 0 { return -trimLeftDelta }
        return 0
    }

    /// Preview audioStartOffset during trim-left extending.
    /// Trim-left reveals earlier audio; resize-left does not change audioStartOffset.
    private var previewAudioStartOffset: Double {
        if isTrimmingLeft, trimLeftDelta < 0 {
            let barDelta = round(trimLeftDelta / pixelsPerBar)
            return max(0, container.audioStartOffset + Double(barDelta))
        }
        return container.audioStartOffset
    }

    /// Waveform start fraction accounting for trim-left extension preview.
    private var activeWaveformStartFraction: CGFloat {
        guard let totalBars = recordingDurationBars, totalBars > 0 else { return 0 }
        return CGFloat(previewAudioStartOffset / totalBars)
    }

    /// Waveform length fraction accounting for right-extend preview.
    /// Shows additional peaks from the recording when extending the container.
    private var activeWaveformLengthFraction: CGFloat {
        guard isExtendingRight || isExtendingLeft,
              let totalBars = recordingDurationBars, totalBars > 0 else {
            return waveformLengthFraction
        }
        let barDelta = round((rightExtendPixels > 0 ? rightExtendPixels : -leftExtendPixels) / pixelsPerBar)
        let previewLength = container.lengthBars + Double(abs(barDelta))
        let offset = previewAudioStartOffset
        let audibleBars = min(previewLength, totalBars - offset)
        return min(1.0, CGFloat(max(0, audibleBars) / totalBars))
    }

    /// Waveform width fraction accounting for extension preview.
    private var activeWaveformWidthFraction: CGFloat {
        guard isExtendingRight || isExtendingLeft,
              let totalBars = recordingDurationBars, totalBars > 0 else {
            return waveformWidthFraction
        }
        let barDelta = round((rightExtendPixels > 0 ? rightExtendPixels : -leftExtendPixels) / pixelsPerBar)
        let previewLength = max(1, container.lengthBars + Double(abs(barDelta)))
        let offset = previewAudioStartOffset
        let audioEnd = min(offset + previewLength, totalBars)
        let audibleBars = max(0, audioEnd - offset)
        return min(1.0, CGFloat(audibleBars / previewLength))
    }

    /// Container width used for waveform frame calculation (includes extension).
    private var activeWaveformContainerWidth: CGFloat {
        (isExtendingRight || isExtendingLeft) ? displayWidth : containerWidth
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
                WaveformView(
                    peaks: peaks,
                    color: trackColor,
                    startFraction: activeWaveformStartFraction,
                    lengthFraction: activeWaveformLengthFraction
                )
                .frame(width: max(1, (activeWaveformContainerWidth - 4) * activeWaveformWidthFraction))
                .frame(maxWidth: .infinity, alignment: .leading)
                // During resize-left extension (no audioStartOffset change),
                // keep waveform at its original position by offsetting right.
                // Trim-left extension changes audioStartOffset, so the waveform
                // naturally extends from the leading edge.
                .offset(x: (isResizingLeft && resizeLeftDelta < 0) ? -resizeLeftDelta : 0)
                .padding(.horizontal, 2)
                .padding(.vertical, 16)
                .allowsHitTesting(false)
            }

            // MIDI note minimap (MIDI containers) — uses resolved sequence for clone inheritance
            if let sequence = resolvedMIDISequence ?? container.midiSequence, !sequence.notes.isEmpty {
                let isInheritedMIDI = isClone && !overriddenFields.contains(.midiSequence)
                MIDINoteMinimapView(
                    notes: sequence.notes,
                    containerLengthBars: Int(container.lengthBars),
                    beatsPerBar: 4,
                    color: trackColor.opacity(isInheritedMIDI ? 0.4 : 1.0)
                )
                .padding(.horizontal, 2)
                .padding(.vertical, 16)
                .allowsHitTesting(false)
            }

            // Automation overlay curves
            if !container.automationLanes.isEmpty {
                AutomationOverlayView(
                    automationLanes: container.automationLanes,
                    containerLengthBars: Int(container.lengthBars),
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

            // Selector drag highlight (during active drag)
            if let startX = selectorDragStartX, let endX = selectorDragCurrentX, endX > startX {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: endX - startX, height: height)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: startX)
                    .allowsHitTesting(false)
            }

            // Persistent range selection highlight (from SelectionState)
            if let range = selectionState?.rangeSelection, range.containerID == container.id {
                let rangeStartX = CGFloat(Double(range.startBar) - container.startBar) * pixelsPerBar
                let rangeWidth = CGFloat(range.endBar - range.startBar) * pixelsPerBar
                Rectangle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: rangeWidth, height: height)
                    .overlay(
                        HStack(spacing: 0) {
                            Rectangle().fill(Color.accentColor.opacity(0.6)).frame(width: 1)
                            Spacer()
                            Rectangle().fill(Color.accentColor.opacity(0.6)).frame(width: 1)
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: rangeStartX)
                    .allowsHitTesting(false)
            }

            // Trim crop overlay: darkens the area being cropped away
            // so the user can see what will remain vs what is trimmed.
            if isTrimmingLeft, trimLeftDelta > 0 {
                // Dark overlay on the left portion being cropped
                Rectangle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: trimLeftDelta)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                // Bright edge line at the new left boundary
                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .offset(x: trimLeftDelta)
                    .allowsHitTesting(false)
            }

            if isTrimmingRight, trimRightDelta < 0 {
                let cropWidth = -trimRightDelta
                // Dark overlay on the right portion being cropped
                Rectangle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: cropWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .allowsHitTesting(false)
                // Bright edge line at the new right boundary
                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .offset(x: -cropWidth)
                    .allowsHitTesting(false)
            }

            // Extension overlay (resize or trim extending): darkens the area being added
            // so the user can see the original vs extended boundary.
            if isExtendingRight {
                let extendWidth = rightExtendPixels
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: extendWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .allowsHitTesting(false)
                // Edge line at the original right boundary
                Rectangle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .offset(x: -extendWidth)
                    .allowsHitTesting(false)
            }

            if isExtendingLeft {
                let extendWidth = leftExtendPixels
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: extendWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                // Edge line at the original left boundary
                Rectangle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .offset(x: extendWidth)
                    .allowsHitTesting(false)
            }

            // Zone-dependent visual indicators
            zoneIndicatorOverlay

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
                    Text(formatBarLength(container.lengthBars))
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
            .allowsHitTesting(false)

            // Unified smart tool gesture overlay
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            isHovering = true
                            let zone = detectZone(at: location, in: geo.size)
                            if zone != hoverZone {
                                if hoverZone != nil { NSCursor.pop() }
                                hoverZone = zone
                                cursorForZone(zone).push()
                            }
                        case .ended:
                            if hoverZone != nil { NSCursor.pop() }
                            isHovering = false
                            hoverZone = nil
                        }
                    }
                    .gesture(altCloneGesture)
                    .gesture(smartDragGesture(size: geo.size))
            }
        }
        .drawingGroup()
        .clipped()
        .frame(width: displayWidth, height: height)
        .offset(x: displayOffset)
        .onTapGesture(count: 2) { onDoubleClick?() }
        .onTapGesture { location in
            // Clear any range selection on tap
            selectionState?.rangeSelection = nil
            let zone = detectZone(at: location, in: CGSize(width: containerWidth, height: height))
            if zone == .selector, onPlayheadTap != nil {
                let timelineX = CGFloat(container.startBar - 1) * pixelsPerBar + location.x
                onPlayheadTap?(timelineX)
            } else {
                onSelect?()
            }
        }
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
            if let selection = selectionState, selection.selectedContainerIDs.count >= 2 {
                Button("Glue (Cmd+J)") { onGlue?() }
            }
            Divider()
            Button("Split at Playhead") { onSplit?() }
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
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .green)
                        .offset(x: 4, y: -4)
                }
                .offset(x: altDragOffset)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Zone Detection

    private func detectZone(at point: CGPoint, in size: CGSize) -> SmartZone {
        let yFraction = point.y / size.height
        let nearLeft = point.x < Self.edgeThreshold
        let nearRight = point.x > size.width - Self.edgeThreshold

        if yFraction < 0.25 {
            // Top 25%: fade zone
            if nearLeft { return .fadeLeft }
            if nearRight { return .fadeRight }
            return .selector
        } else if yFraction < 0.75 {
            // Middle 50%: move/resize
            if nearLeft { return .resizeLeft }
            if nearRight { return .resizeRight }
            return .move
        } else {
            // Bottom 25%: trim zone
            if nearLeft { return .trimLeft }
            if nearRight { return .trimRight }
            return .trimMove
        }
    }

    private func cursorForZone(_ zone: SmartZone) -> NSCursor {
        switch zone {
        case .fadeLeft, .fadeRight:
            return .resizeLeftRight
        case .selector:
            return .iBeam
        case .resizeLeft, .resizeRight:
            return .resizeLeftRight
        case .trimLeft, .trimRight:
            return .resizeLeftRight
        case .move, .trimMove:
            return .openHand
        }
    }

    // MARK: - Zone Indicators

    @ViewBuilder
    private var zoneIndicatorOverlay: some View {
        if isHovering {
            // Fade handles: show when hovering in top area or when fades exist
            if showFadeHandles {
                // Enter fade handle dot (top-left)
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: Self.fadeHandleSize, height: Self.fadeHandleSize)
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    .offset(x: enterFadeWidth - Self.fadeHandleSize / 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 2)
                    .allowsHitTesting(false)

                // Exit fade handle dot (top-right)
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: Self.fadeHandleSize, height: Self.fadeHandleSize)
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    .offset(x: -exitFadeWidth + Self.fadeHandleSize / 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 2)
                    .allowsHitTesting(false)
            }

            // Trim zone bracket indicators at bottom edges
            if hoverZone == .trimLeft || hoverZone == .trimRight {
                HStack {
                    if hoverZone == .trimLeft {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 3, height: height * 0.2)
                    }
                    Spacer()
                    if hoverZone == .trimRight {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 3, height: height * 0.2)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 4)
                .padding(.horizontal, 2)
                .allowsHitTesting(false)
            }
        } else if container.enterFade != nil || container.exitFade != nil {
            // Always show fade handles when fades exist (even when not hovering)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: Self.fadeHandleSize, height: Self.fadeHandleSize)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                .offset(x: enterFadeWidth - Self.fadeHandleSize / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 2)
                .allowsHitTesting(false)

            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: Self.fadeHandleSize, height: Self.fadeHandleSize)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                .offset(x: -exitFadeWidth + Self.fadeHandleSize / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 2)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Display Metrics

    private var displayWidth: CGFloat {
        if isResizingLeft {
            return max(pixelsPerBar, containerWidth - resizeLeftDelta)
        } else if isResizingRight {
            return max(pixelsPerBar, containerWidth + resizeRightDelta)
        }
        // During trim crop, container stays at original size (dark overlay shows).
        // During trim extend, container grows to show the preview.
        if isTrimmingRight, trimRightDelta > 0 {
            return containerWidth + trimRightDelta
        }
        if isTrimmingLeft, trimLeftDelta < 0 {
            return containerWidth - trimLeftDelta
        }
        return containerWidth
    }

    private var displayOffset: CGFloat {
        if isDragging {
            return dragOffset
        } else if isResizingLeft {
            return resizeLeftDelta
        }
        // During trim-left extend, shift left to show the new area
        if isTrimmingLeft, trimLeftDelta < 0 {
            return trimLeftDelta
        }
        return 0
    }

    /// Snaps a bar delta to the grid resolution by snapping the target bar and returning the delta.
    private func snappedBarDelta(from translation: CGFloat) -> Double {
        let rawTarget = container.startBar + Double(translation) / Double(pixelsPerBar)
        let snapped = snapToGrid?(rawTarget) ?? rawTarget.rounded()
        return snapped - container.startBar
    }

    /// Snaps a length delta to the grid resolution.
    private func snappedLengthDelta(from translation: CGFloat) -> Double {
        let rawTarget = container.lengthBars + Double(translation) / Double(pixelsPerBar)
        let snapped = snapToGrid?(container.startBar + rawTarget) ?? (container.startBar + rawTarget).rounded()
        return snapped - container.startBar - container.lengthBars
    }

    // MARK: - Unified Smart Gesture

    /// Uses the stable "trackLane" coordinate space from the parent TrackLaneView.
    /// This prevents jitter: if we used `.local`, the `.offset()` and `.frame(width:)`
    /// applied during drag/resize/trim would shift the coordinate space mid-gesture,
    /// causing `value.translation` to oscillate.
    private func smartDragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("trackLane"))
            .onChanged { value in
                // Detect zone once at drag start (local coordinates)
                let zone: SmartZone
                if let active = activeDragZone {
                    zone = active
                } else {
                    let localStart = CGPoint(
                        x: value.startLocation.x - containerOriginX,
                        y: value.startLocation.y - 2 // account for y: 2 offset in TrackLaneView
                    )
                    zone = detectZone(at: localStart, in: size)
                    activeDragZone = zone
                }

                // Translation is stable in trackLane space — snap to grid
                let barDelta = snappedBarDelta(from: value.translation.width)

                switch zone {
                case .fadeLeft:
                    let currentWidth = CGFloat(container.enterFade?.duration ?? 0) * pixelsPerBar
                    let newWidth = max(0, min(currentWidth + value.translation.width, containerWidth))
                    enterFadeDragWidth = newWidth

                case .fadeRight:
                    let currentWidth = CGFloat(container.exitFade?.duration ?? 0) * pixelsPerBar
                    let newWidth = max(0, min(currentWidth - value.translation.width, containerWidth))
                    exitFadeDragWidth = newWidth

                case .resizeLeft:
                    isResizingLeft = true
                    resizeLeftDelta = CGFloat(barDelta) * pixelsPerBar

                case .resizeRight:
                    isResizingRight = true
                    resizeRightDelta = CGFloat(barDelta) * pixelsPerBar

                case .trimLeft:
                    isTrimmingLeft = true
                    trimLeftDelta = CGFloat(barDelta) * pixelsPerBar

                case .trimRight:
                    isTrimmingRight = true
                    trimRightDelta = CGFloat(barDelta) * pixelsPerBar

                case .selector:
                    // Convert trackLane coordinates to local for bar computation
                    let localStartX = value.startLocation.x - containerOriginX
                    let localCurrentX = value.location.x - containerOriginX
                    let rawStartX = min(localStartX, localCurrentX)
                    let rawEndX = max(localStartX, localCurrentX)
                    let startBarLocal = max(0, round(rawStartX / pixelsPerBar))
                    let endBarLocal = min(container.lengthBars, round(rawEndX / pixelsPerBar))
                    selectorDragStartX = startBarLocal * pixelsPerBar
                    selectorDragCurrentX = endBarLocal * pixelsPerBar

                case .move, .trimMove:
                    isDragging = true
                    dragOffset = CGFloat(barDelta) * pixelsPerBar
                }
            }
            .onEnded { value in
                let zone = activeDragZone ?? .move
                activeDragZone = nil
                let barDelta = snappedBarDelta(from: value.translation.width)

                switch zone {
                case .fadeLeft:
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

                case .fadeRight:
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

                case .resizeLeft:
                    isResizingLeft = false
                    let newStart = container.startBar + barDelta
                    let newLength = container.lengthBars - barDelta
                    if newLength >= 1.0 && newStart >= 1.0 {
                        let _ = onResizeLeft?(newStart, newLength)
                    }
                    resizeLeftDelta = 0

                case .resizeRight:
                    isResizingRight = false
                    let newLength = container.lengthBars + barDelta
                    if newLength >= 1.0 {
                        let _ = onResizeRight?(newLength)
                    }
                    resizeRightDelta = 0

                case .trimLeft:
                    isTrimmingLeft = false
                    let newStart = container.startBar + barDelta
                    let newLength = container.lengthBars - barDelta
                    let newOffset = container.audioStartOffset + barDelta
                    if newLength >= 1.0 && newStart >= 1.0 && newOffset >= 0 {
                        let _ = onTrimLeft?(newOffset, newStart, newLength)
                    }
                    trimLeftDelta = 0

                case .trimRight:
                    isTrimmingRight = false
                    let newLength = container.lengthBars + barDelta
                    if newLength >= 1.0 {
                        let _ = onTrimRight?(newLength)
                    }
                    trimRightDelta = 0

                case .selector:
                    if let startX = selectorDragStartX, let endX = selectorDragCurrentX, endX > startX {
                        let startBar = container.startBar + max(0, round(startX / pixelsPerBar))
                        let endBar = container.startBar + min(container.lengthBars, round(endX / pixelsPerBar))
                        if endBar > startBar {
                            onSelect?()
                            onRangeSelect?(startBar, endBar)
                        }
                    }
                    selectorDragStartX = nil
                    selectorDragCurrentX = nil

                case .move, .trimMove:
                    isDragging = false
                    let newStart = container.startBar + barDelta
                    let _ = onMove?(newStart)
                    dragOffset = 0
                }
            }
    }

    private var altCloneGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .modifiers(.option)
            .onChanged { value in
                isAltDragging = true
                let barDelta = snappedBarDelta(from: value.translation.width)
                altDragOffset = CGFloat(barDelta) * pixelsPerBar
            }
            .onEnded { value in
                isAltDragging = false
                let barDelta = snappedBarDelta(from: value.translation.width)
                let newStart = container.startBar + barDelta
                if newStart >= 1.0 {
                    onClone?(newStart)
                }
                altDragOffset = 0
            }
    }

    // MARK: - Fade Metrics

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

    private func formatBarLength(_ bars: Double) -> String {
        if bars == bars.rounded() && bars == Double(Int(bars)) {
            let intBars = Int(bars)
            return "\(intBars) bar\(intBars == 1 ? "" : "s")"
        }
        return String(format: "%.1f bars", bars)
    }
}

// MARK: - Equatable

extension ContainerView: Equatable {
    public static func == (lhs: ContainerView, rhs: ContainerView) -> Bool {
        // selectionState is not compared — it's the same object reference.
        // Selection changes are observed directly via @Observable in each ContainerView's body.
        lhs.container == rhs.container &&
        lhs.pixelsPerBar == rhs.pixelsPerBar &&
        lhs.height == rhs.height &&
        lhs.trackColor == rhs.trackColor &&
        lhs.waveformPeaks == rhs.waveformPeaks &&
        lhs.isClone == rhs.isClone &&
        lhs.overriddenFields == rhs.overriddenFields &&
        lhs.resolvedMIDISequence == rhs.resolvedMIDISequence &&
        lhs.recordingDurationBars == rhs.recordingDurationBars &&
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
