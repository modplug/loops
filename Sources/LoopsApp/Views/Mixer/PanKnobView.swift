import SwiftUI

/// A pan knob control showing L-C-R position.
public struct PanKnobView: View {
    @Binding var value: Float

    public init(value: Binding<Float>) {
        self._value = value
    }

    public var body: some View {
        VStack(spacing: 2) {
            Slider(value: $value, in: -1.0...1.0)
                .frame(width: 60)

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
