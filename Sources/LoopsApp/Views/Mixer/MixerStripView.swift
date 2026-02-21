import SwiftUI
import LoopsCore

/// A single mixer channel strip with fader, pan, mute, solo, and level meter.
public struct MixerStripView: View {
    let track: Track
    let level: Float
    var onVolumeChange: ((Float) -> Void)?
    var onPanChange: ((Float) -> Void)?
    var onMuteToggle: (() -> Void)?
    var onSoloToggle: (() -> Void)?

    @State private var volume: Float
    @State private var pan: Float

    public init(
        track: Track,
        level: Float = 0.0,
        onVolumeChange: ((Float) -> Void)? = nil,
        onPanChange: ((Float) -> Void)? = nil,
        onMuteToggle: (() -> Void)? = nil,
        onSoloToggle: (() -> Void)? = nil
    ) {
        self.track = track
        self.level = level
        self.onVolumeChange = onVolumeChange
        self.onPanChange = onPanChange
        self.onMuteToggle = onMuteToggle
        self.onSoloToggle = onSoloToggle
        _volume = State(initialValue: track.volume)
        _pan = State(initialValue: track.pan)
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Track name
            Text(track.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 60)

            // Pan knob
            PanKnobView(value: $pan)
                .onChange(of: pan) { _, newValue in
                    onPanChange?(newValue)
                }

            // Fader + meter
            HStack(spacing: 4) {
                FaderView(value: $volume)
                    .onChange(of: volume) { _, newValue in
                        onVolumeChange?(newValue)
                    }
                LevelMeterView(level: level, width: 4)
                    .frame(height: 100)
            }

            // Mute/Solo
            HStack(spacing: 4) {
                Button(action: { onMuteToggle?() }) {
                    Text("M")
                        .font(.caption2.bold())
                        .foregroundStyle(track.isMuted ? .white : .secondary)
                        .frame(width: 20, height: 18)
                        .background(track.isMuted ? Color.red.opacity(0.8) : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)

                Button(action: { onSoloToggle?() }) {
                    Text("S")
                        .font(.caption2.bold())
                        .foregroundStyle(track.isSoloed ? .white : .secondary)
                        .frame(width: 20, height: 18)
                        .background(track.isSoloed ? Color.yellow.opacity(0.8) : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(4)
    }
}
