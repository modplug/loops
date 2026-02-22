import SwiftUI
import LoopsCore

/// Displays the track header on the left side of the timeline:
/// track name, type icon/color, mute/solo buttons, and I/O routing.
public struct TrackHeaderView: View {
    let track: Track
    let height: CGFloat
    /// Display name for the track's current input port.
    var inputPortName: String?
    /// Display name for the track's current output port.
    var outputPortName: String?
    var onMuteToggle: (() -> Void)?
    var onSoloToggle: (() -> Void)?

    public init(
        track: Track,
        height: CGFloat = 80,
        inputPortName: String? = nil,
        outputPortName: String? = nil,
        onMuteToggle: (() -> Void)? = nil,
        onSoloToggle: (() -> Void)? = nil
    ) {
        self.track = track
        self.height = height
        self.inputPortName = inputPortName
        self.outputPortName = outputPortName
        self.onMuteToggle = onMuteToggle
        self.onSoloToggle = onSoloToggle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Top row: track info + M/S buttons
            HStack(spacing: 6) {
                Circle()
                    .fill(trackColor)
                    .frame(width: 8, height: 8)

                Text(track.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Button(action: { onMuteToggle?() }) {
                    Text("M")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(track.isMuted ? .white : .secondary)
                        .frame(width: 18, height: 18)
                        .background(track.isMuted ? Color.red.opacity(0.8) : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)

                Button(action: { onSoloToggle?() }) {
                    Text("S")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(track.isSoloed ? .white : .secondary)
                        .frame(width: 18, height: 18)
                        .background(track.isSoloed ? Color.yellow.opacity(0.8) : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }

            // I/O routing labels (audio tracks only)
            if track.kind == .audio {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                    Text(inputPortName ?? "Default")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                HStack(spacing: 2) {
                    Image(systemName: "arrow.left.circle")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                    Text(outputPortName ?? "Default")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
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
