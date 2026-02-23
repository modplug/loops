import SwiftUI
import LoopsCore

/// Displays bar numbers along the top of the timeline with click-to-position
/// playhead and Shift+drag range selection.
public struct RulerView: View {
    let totalBars: Int
    let pixelsPerBar: CGFloat
    let timeSignature: TimeSignature
    var selectedRange: ClosedRange<Int>?
    var onRangeSelect: ((ClosedRange<Int>) -> Void)?
    var onRangeDeselect: (() -> Void)?
    var onPlayheadPosition: ((Double) -> Void)?
    /// Injected snap closure from TimelineViewModel.snappedBar().
    var snapBarForX: ((CGFloat) -> Double)?

    @State private var dragStartBar: Int?
    @State private var dragCurrentBar: Int?
    @State private var isScrubbing: Bool = false

    public init(totalBars: Int, pixelsPerBar: CGFloat, timeSignature: TimeSignature, selectedRange: ClosedRange<Int>? = nil, onRangeSelect: ((ClosedRange<Int>) -> Void)? = nil, onRangeDeselect: (() -> Void)? = nil, onPlayheadPosition: ((Double) -> Void)? = nil, snapBarForX: ((CGFloat) -> Double)? = nil) {
        self.totalBars = totalBars
        self.pixelsPerBar = pixelsPerBar
        self.timeSignature = timeSignature
        self.selectedRange = selectedRange
        self.onRangeSelect = onRangeSelect
        self.onRangeDeselect = onRangeDeselect
        self.onPlayheadPosition = onPlayheadPosition
        self.snapBarForX = snapBarForX
    }

    /// The active range: either from an in-progress drag or the committed selection.
    private var activeRange: ClosedRange<Int>? {
        if !isScrubbing, let start = dragStartBar, let end = dragCurrentBar, start != end {
            return min(start, end)...max(start, end)
        }
        return selectedRange
    }

    /// Step between labeled bar numbers based on zoom level.
    private var labelStep: Int {
        let minLabelWidth: CGFloat = 30
        let niceSteps = [1, 2, 4, 5, 8, 10, 16, 20, 25, 32, 50, 64, 100, 200, 500, 1000]
        for step in niceSteps {
            if CGFloat(step) * pixelsPerBar >= minLabelWidth {
                return step
            }
        }
        return 1000
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let height = size.height
                let step = labelStep

                // Bottom border
                var bottomLine = Path()
                bottomLine.move(to: CGPoint(x: 0, y: height - 0.5))
                bottomLine.addLine(to: CGPoint(x: size.width, y: height - 0.5))
                context.stroke(bottomLine, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)

                for bar in 1...totalBars {
                    let x = CGFloat(bar - 1) * pixelsPerBar

                    // Tick mark at bottom (skip when bars are too dense)
                    if pixelsPerBar >= 4 {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: height - 6))
                        path.addLine(to: CGPoint(x: x, y: height))
                        context.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)
                    }

                    // Bar number — only at appropriate intervals
                    if bar == 1 || bar % step == 0 {
                        let text = Text("\(bar)").font(.system(size: 9, weight: .regular)).foregroundColor(.secondary)
                        context.draw(text, at: CGPoint(x: x + 3, y: 5), anchor: .topLeading)
                    }

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
                    let isShift = NSEvent.modifierFlags.contains(.shift)
                    if isShift {
                        // Shift+drag: range selection
                        isScrubbing = false
                        let startBar = barForX(value.startLocation.x)
                        let currentBar = barForX(value.location.x)
                        dragStartBar = startBar
                        dragCurrentBar = currentBar
                    } else {
                        // Normal drag: scrub playhead
                        isScrubbing = true
                        let bar = snappedBarForX(value.location.x)
                        onPlayheadPosition?(bar)
                    }
                }
                .onEnded { value in
                    let isShift = NSEvent.modifierFlags.contains(.shift)
                    if isScrubbing || !isShift {
                        // Normal click or scrub end — position playhead
                        let bar = snappedBarForX(value.location.x)
                        onPlayheadPosition?(bar)
                        onRangeDeselect?()
                    } else {
                        // Shift+drag ended — commit range selection
                        let distance = abs(value.location.x - value.startLocation.x)
                        if distance < 3 {
                            onRangeDeselect?()
                        } else if let start = dragStartBar, let end = dragCurrentBar, start != end {
                            let lower = min(start, end)
                            let upper = max(start, end)
                            onRangeSelect?(lower...upper)
                        }
                    }
                    dragStartBar = nil
                    dragCurrentBar = nil
                    isScrubbing = false
                }
        )
    }

    private func barForX(_ x: CGFloat) -> Int {
        max(1, min(Int(x / pixelsPerBar) + 1, totalBars))
    }

    /// Returns a snapped bar position (Double) for the given x-coordinate.
    /// Uses injected snap closure if available, otherwise falls back to local logic.
    private func snappedBarForX(_ x: CGFloat) -> Double {
        if let snap = snapBarForX {
            return snap(x)
        }
        // Fallback: snap to beat if zoomed in enough, otherwise to whole bar
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
}
