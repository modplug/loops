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
    var onSelect: (() -> Void)?
    var onDelete: (() -> Void)?
    var onMove: ((_ newStartBar: Int) -> Bool)?
    var onResizeLeft: ((_ newStartBar: Int, _ newLength: Int) -> Bool)?
    var onResizeRight: ((_ newLength: Int) -> Bool)?
    var onDoubleClick: (() -> Void)?

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var resizeLeftDelta: CGFloat = 0
    @State private var resizeRightDelta: CGFloat = 0
    @State private var isResizingLeft = false
    @State private var isResizingRight = false

    public init(
        container: Container,
        pixelsPerBar: CGFloat,
        height: CGFloat = 76,
        isSelected: Bool = false,
        trackColor: Color = .blue,
        waveformPeaks: [Float]? = nil,
        onSelect: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onMove: ((_ newStartBar: Int) -> Bool)? = nil,
        onResizeLeft: ((_ newStartBar: Int, _ newLength: Int) -> Bool)? = nil,
        onResizeRight: ((_ newLength: Int) -> Bool)? = nil,
        onDoubleClick: (() -> Void)? = nil
    ) {
        self.container = container
        self.pixelsPerBar = pixelsPerBar
        self.height = height
        self.isSelected = isSelected
        self.trackColor = trackColor
        self.waveformPeaks = waveformPeaks
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onMove = onMove
        self.onResizeLeft = onResizeLeft
        self.onResizeRight = onResizeRight
        self.onDoubleClick = onDoubleClick
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
                Text(container.name)
                    .font(.caption2.bold())
                    .lineLimit(1)
                Text("\(container.lengthBars) bar\(container.lengthBars == 1 ? "" : "s")")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
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
        .gesture(moveGesture)
        .contextMenu {
            Button("Delete Container", role: .destructive) {
                onDelete?()
            }
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
}
