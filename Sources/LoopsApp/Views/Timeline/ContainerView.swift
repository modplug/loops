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

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var resizeLeftDelta: CGFloat = 0
    @State private var resizeRightDelta: CGFloat = 0
    @State private var isResizingLeft = false
    @State private var isResizingRight = false
    @State private var isAltDragging = false
    @State private var altDragOffset: CGFloat = 0

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
        onClone: ((_ newStartBar: Int) -> Void)? = nil
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
    }

    private var containerWidth: CGFloat {
        CGFloat(container.lengthBars) * pixelsPerBar
    }

    public var body: some View {
        ZStack {
            // Container body
            RoundedRectangle(cornerRadius: 4)
                .fill(trackColor.opacity(isSelected ? 0.5 : 0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            isSelected ? Color.accentColor : trackColor.opacity(0.6),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

            // Waveform
            if let peaks = waveformPeaks, !peaks.isEmpty {
                WaveformView(peaks: peaks, color: trackColor)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }

            // Container label
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
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
        .onTapGesture(count: 2) { onDoubleClick?() }
        .onTapGesture { onSelect?() }
        .gesture(altCloneGesture)
        .gesture(moveGesture)
        .contextMenu {
            Button("Delete Container", role: .destructive) {
                onDelete?()
            }
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
}
