import SwiftUI
import LoopsCore

/// A single mixer channel strip with fader, pan, mute, solo, record arm, monitor, and level meter.
public struct MixerStripView: View {
    let track: Track
    let level: Float
    var isTrackSelected: Bool
    var onVolumeChange: ((Float) -> Void)?
    var onPanChange: ((Float) -> Void)?
    var onMuteToggle: (() -> Void)?
    var onSoloToggle: (() -> Void)?
    var onRecordArmToggle: (() -> Void)?
    var onMonitorToggle: (() -> Void)?
    var onTrackSelect: (() -> Void)?

    @State private var volume: Float
    @State private var pan: Float

    public init(
        track: Track,
        level: Float = 0.0,
        isTrackSelected: Bool = false,
        onVolumeChange: ((Float) -> Void)? = nil,
        onPanChange: ((Float) -> Void)? = nil,
        onMuteToggle: (() -> Void)? = nil,
        onSoloToggle: (() -> Void)? = nil,
        onRecordArmToggle: (() -> Void)? = nil,
        onMonitorToggle: (() -> Void)? = nil,
        onTrackSelect: (() -> Void)? = nil
    ) {
        self.track = track
        self.level = level
        self.isTrackSelected = isTrackSelected
        self.onVolumeChange = onVolumeChange
        self.onPanChange = onPanChange
        self.onMuteToggle = onMuteToggle
        self.onSoloToggle = onSoloToggle
        self.onRecordArmToggle = onRecordArmToggle
        self.onMonitorToggle = onMonitorToggle
        self.onTrackSelect = onTrackSelect
        _volume = State(initialValue: track.volume)
        _pan = State(initialValue: track.pan)
    }

    private var isMaster: Bool { track.kind == .master }

    public var body: some View {
        VStack(spacing: 6) {
            // Track name
            Text(track.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 64)

            // Track kind label
            Text(track.kind.displayName)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

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

            // Button row
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

            // Record Arm and Monitor buttons (not shown for master track)
            if !isMaster {
                HStack(spacing: 4) {
                    Button(action: { onRecordArmToggle?() }) {
                        Circle()
                            .fill(track.isRecordArmed ? Color.red : Color.clear)
                            .overlay(
                                Circle().stroke(track.isRecordArmed ? Color.red : Color.secondary, lineWidth: 1.5)
                            )
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .help("Record Arm")

                    Button(action: { onMonitorToggle?() }) {
                        Image(systemName: "headphones")
                            .font(.system(size: 9))
                            .foregroundStyle(track.isMonitoring ? .white : .secondary)
                            .frame(width: 20, height: 18)
                            .background(track.isMonitoring ? Color.orange.opacity(0.8) : Color.clear)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    .help("Input Monitor")
                }
            }
        }
        .padding(6)
        .background(
            isTrackSelected
                ? Color.accentColor.opacity(0.15)
                : isMaster
                    ? Color(nsColor: .controlBackgroundColor).opacity(0.8)
                    : Color(nsColor: .controlBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    isTrackSelected
                        ? Color.accentColor
                        : isMaster
                            ? Color.gray.opacity(0.5)
                            : Color.clear,
                    lineWidth: isTrackSelected ? 1.5 : 1
                )
        )
        .cornerRadius(4)
        .onTapGesture {
            onTrackSelect?()
        }
        .onChange(of: track.volume) { _, newValue in
            volume = newValue
        }
        .onChange(of: track.pan) { _, newValue in
            pan = newValue
        }
    }
}
