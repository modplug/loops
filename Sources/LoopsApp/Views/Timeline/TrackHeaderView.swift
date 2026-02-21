import SwiftUI
import LoopsCore

/// Displays the track header on the left side of the timeline:
/// track name, type icon/color, mute/solo buttons.
public struct TrackHeaderView: View {
    let track: Track
    let height: CGFloat
    var onMuteToggle: (() -> Void)?
    var onSoloToggle: (() -> Void)?

    public init(
        track: Track,
        height: CGFloat = 80,
        onMuteToggle: (() -> Void)? = nil,
        onSoloToggle: (() -> Void)? = nil
    ) {
        self.track = track
        self.height = height
        self.onMuteToggle = onMuteToggle
        self.onSoloToggle = onSoloToggle
    }

    public var body: some View {
        HStack(spacing: 6) {
            // Track type indicator
            Circle()
                .fill(trackColor)
                .frame(width: 10, height: 10)

            // Track name
            Text(track.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            // Mute button
            Button(action: { onMuteToggle?() }) {
                Text("M")
                    .font(.caption2.bold())
                    .foregroundStyle(track.isMuted ? .white : .secondary)
                    .frame(width: 20, height: 20)
                    .background(track.isMuted ? Color.red.opacity(0.8) : Color.clear)
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)

            // Solo button
            Button(action: { onSoloToggle?() }) {
                Text("S")
                    .font(.caption2.bold())
                    .foregroundStyle(track.isSoloed ? .white : .secondary)
                    .frame(width: 20, height: 20)
                    .background(track.isSoloed ? Color.yellow.opacity(0.8) : Color.clear)
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(width: 160, height: height)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.secondary.opacity(0.3)),
            alignment: .bottom
        )
    }

    private var trackColor: Color {
        switch track.kind {
        case .audio: return .blue
        case .midi: return .purple
        case .bus: return .green
        case .backing: return .orange
        }
    }
}
