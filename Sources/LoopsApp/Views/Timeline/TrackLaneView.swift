import SwiftUI
import LoopsCore

/// Renders a single track's horizontal lane on the timeline.
/// Containers will be drawn within this lane in future issues.
public struct TrackLaneView: View {
    let track: Track
    let pixelsPerBar: CGFloat
    let totalBars: Int
    let height: CGFloat

    public init(track: Track, pixelsPerBar: CGFloat, totalBars: Int, height: CGFloat = 80) {
        self.track = track
        self.pixelsPerBar = pixelsPerBar
        self.totalBars = totalBars
        self.height = height
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            // Track background
            Rectangle()
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.3))

            // Render containers
            ForEach(track.containers) { container in
                containerRect(container)
            }
        }
        .frame(width: CGFloat(totalBars) * pixelsPerBar, height: height)
    }

    private func containerRect(_ container: Container) -> some View {
        let x = CGFloat(container.startBar - 1) * pixelsPerBar
        let width = CGFloat(container.lengthBars) * pixelsPerBar

        return RoundedRectangle(cornerRadius: 4)
            .fill(trackColor.opacity(0.3))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(trackColor.opacity(0.6), lineWidth: 1)
            )
            .overlay(
                Text(container.name)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .padding(.leading, 4),
                alignment: .topLeading
            )
            .frame(width: width, height: height - 4)
            .offset(x: x, y: 0)
            .padding(.vertical, 2)
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
