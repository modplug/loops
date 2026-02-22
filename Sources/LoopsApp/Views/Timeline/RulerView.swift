import SwiftUI
import LoopsCore

/// Displays bar numbers along the top of the timeline with drag-to-select range support.
public struct RulerView: View {
    let totalBars: Int
    let pixelsPerBar: CGFloat
    let timeSignature: TimeSignature
    var selectedRange: ClosedRange<Int>?
    var onRangeSelect: ((ClosedRange<Int>) -> Void)?
    var onRangeDeselect: (() -> Void)?

    @State private var dragStartBar: Int?
    @State private var dragCurrentBar: Int?

    public init(totalBars: Int, pixelsPerBar: CGFloat, timeSignature: TimeSignature, selectedRange: ClosedRange<Int>? = nil, onRangeSelect: ((ClosedRange<Int>) -> Void)? = nil, onRangeDeselect: (() -> Void)? = nil) {
        self.totalBars = totalBars
        self.pixelsPerBar = pixelsPerBar
        self.timeSignature = timeSignature
        self.selectedRange = selectedRange
        self.onRangeSelect = onRangeSelect
        self.onRangeDeselect = onRangeDeselect
    }

    /// The active range: either from an in-progress drag or the committed selection.
    private var activeRange: ClosedRange<Int>? {
        if let start = dragStartBar, let end = dragCurrentBar, start != end {
            return min(start, end)...max(start, end)
        }
        return selectedRange
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let height = size.height

                // Bottom border
                var bottomLine = Path()
                bottomLine.move(to: CGPoint(x: 0, y: height - 0.5))
                bottomLine.addLine(to: CGPoint(x: size.width, y: height - 0.5))
                context.stroke(bottomLine, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)

                for bar in 1...totalBars {
                    let x = CGFloat(bar - 1) * pixelsPerBar

                    // Tick mark at bottom
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: height - 6))
                    path.addLine(to: CGPoint(x: x, y: height))
                    context.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)

                    // Bar number — small, near top
                    let text = Text("\(bar)").font(.system(size: 9, weight: .regular)).foregroundColor(.secondary)
                    context.draw(text, at: CGPoint(x: x + 3, y: 5), anchor: .topLeading)

                    // Beat ticks within bar
                    if pixelsPerBar > 50 {
                        let pixelsPerBeat = pixelsPerBar / CGFloat(timeSignature.beatsPerBar)
                        for beat in 1..<timeSignature.beatsPerBar {
                            let beatX = x + CGFloat(beat) * pixelsPerBeat
                            var beatPath = Path()
                            beatPath.move(to: CGPoint(x: beatX, y: height - 3))
                            beatPath.addLine(to: CGPoint(x: beatX, y: height))
                            context.stroke(beatPath, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)
                        }
                    }
                }
            }

            // Selected range highlight
            if let range = activeRange {
                let startX = CGFloat(range.lowerBound - 1) * pixelsPerBar
                let width = CGFloat(range.count) * pixelsPerBar
                Rectangle()
                    .fill(Color.accentColor.opacity(0.25))
                    .frame(width: width, height: 20)
                    .offset(x: startX)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: CGFloat(totalBars) * pixelsPerBar, height: 20)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let startBar = barForX(value.startLocation.x)
                    let currentBar = barForX(value.location.x)
                    dragStartBar = startBar
                    dragCurrentBar = currentBar
                }
                .onEnded { value in
                    let distance = abs(value.location.x - value.startLocation.x)
                    if distance < 3 {
                        // Tap — clear selection
                        onRangeDeselect?()
                    } else if let start = dragStartBar, let end = dragCurrentBar, start != end {
                        let lower = min(start, end)
                        let upper = max(start, end)
                        onRangeSelect?(lower...upper)
                    }
                    dragStartBar = nil
                    dragCurrentBar = nil
                }
        )
    }

    private func barForX(_ x: CGFloat) -> Int {
        max(1, min(Int(x / pixelsPerBar) + 1, totalBars))
    }
}
