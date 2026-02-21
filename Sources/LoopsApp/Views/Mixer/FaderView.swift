import SwiftUI

/// A vertical fader control for volume adjustment.
public struct FaderView: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    public init(value: Binding<Float>, range: ClosedRange<Float> = 0.0...2.0) {
        self._value = value
        self.range = range
    }

    public var body: some View {
        VStack(spacing: 2) {
            Slider(value: $value, in: range)
                .rotationEffect(.degrees(-90))
                .frame(width: 24, height: 100)

            Text(MixerViewModel.gainToDBString(value))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
