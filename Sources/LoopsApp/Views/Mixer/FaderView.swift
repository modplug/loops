import SwiftUI

/// A vertical fader control for volume adjustment using a custom drag gesture.
/// Minimum 44pt wide for reliable drag targeting.
public struct FaderView: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    var onEditingEnd: (() -> Void)?

    @State private var isDragging = false

    private let trackWidth: CGFloat = 4
    private let thumbHeight: CGFloat = 14
    private let faderWidth: CGFloat = 44
    private let faderHeight: CGFloat = 100

    public init(value: Binding<Float>, range: ClosedRange<Float> = 0.0...2.0, onEditingEnd: (() -> Void)? = nil) {
        self._value = value
        self.range = range
        self.onEditingEnd = onEditingEnd
    }

    public var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geometry in
                let trackHeight = geometry.size.height - thumbHeight
                let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
                let clampedFraction = min(max(fraction, 0), 1)
                let thumbY = (1 - clampedFraction) * trackHeight

                ZStack(alignment: .top) {
                    // Track background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: trackWidth, height: trackHeight)
                        .offset(y: thumbHeight / 2)

                    // Track fill (below thumb)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: trackWidth, height: max(0, trackHeight - thumbY))
                        .offset(y: thumbY + thumbHeight / 2)

                    // Unity (0 dB / gain 1.0) tick mark
                    let unityFraction = CGFloat((1.0 - range.lowerBound) / (range.upperBound - range.lowerBound))
                    let unityY = (1 - unityFraction) * trackHeight + thumbHeight / 2
                    Rectangle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 12, height: 1)
                        .offset(y: unityY)

                    // Thumb
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isDragging ? Color.accentColor : Color(nsColor: .controlColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                        .frame(width: 28, height: thumbHeight)
                        .offset(y: thumbY)
                }
                .frame(width: faderWidth, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            isDragging = true
                            let y = drag.location.y
                            let clamped = min(max(y - thumbHeight / 2, 0), trackHeight)
                            let newFraction = Float(1 - clamped / trackHeight)
                            value = range.lowerBound + newFraction * (range.upperBound - range.lowerBound)
                        }
                        .onEnded { _ in
                            isDragging = false
                            onEditingEnd?()
                        }
                )
            }
            .frame(width: faderWidth, height: faderHeight)

            Text(MixerViewModel.gainToDBString(value))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
