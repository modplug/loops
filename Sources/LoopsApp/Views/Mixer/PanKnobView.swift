import SwiftUI

/// A pan knob control showing L-C-R position using a custom horizontal drag gesture.
/// Minimum 44pt wide for reliable drag targeting.
public struct PanKnobView: View {
    @Binding var value: Float
    var onEditingEnd: (() -> Void)?

    @State private var isDragging = false

    private let knobWidth: CGFloat = 60
    private let knobHeight: CGFloat = 22
    private let thumbWidth: CGFloat = 10

    public init(value: Binding<Float>, onEditingEnd: (() -> Void)? = nil) {
        self._value = value
        self.onEditingEnd = onEditingEnd
    }

    public var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geometry in
                let trackWidth = geometry.size.width - thumbWidth
                let fraction = CGFloat((value + 1.0) / 2.0) // -1..1 → 0..1
                let clampedFraction = min(max(fraction, 0), 1)
                let thumbX = clampedFraction * trackWidth
                let centerX = trackWidth / 2

                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 4)
                        .padding(.horizontal, thumbWidth / 2)

                    // Center tick
                    Rectangle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 1, height: 10)
                        .offset(x: centerX + thumbWidth / 2 - 0.5)

                    // Fill from center to thumb
                    let fillStart = min(centerX, thumbX)
                    let fillWidth = abs(thumbX - centerX)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: fillWidth, height: 4)
                        .offset(x: fillStart + thumbWidth / 2)

                    // Thumb
                    Circle()
                        .fill(isDragging ? Color.accentColor : Color(nsColor: .controlColor))
                        .overlay(
                            Circle()
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                        .frame(width: thumbWidth, height: thumbWidth)
                        .offset(x: thumbX)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            isDragging = true
                            let x = drag.location.x
                            let clamped = min(max(x - thumbWidth / 2, 0), trackWidth)
                            let newFraction = Float(clamped / trackWidth)
                            value = newFraction * 2.0 - 1.0 // 0..1 → -1..1
                        }
                        .onEnded { _ in
                            isDragging = false
                            onEditingEnd?()
                        }
                )
            }
            .frame(width: knobWidth, height: knobHeight)

            Text(panLabel)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var panLabel: String {
        if abs(value) < 0.05 { return "C" }
        if value < 0 { return "L\(Int(abs(value) * 100))" }
        return "R\(Int(value * 100))"
    }
}
