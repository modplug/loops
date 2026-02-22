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
    /// Display name for the track's current MIDI input device.
    var midiDeviceName: String?
    /// Display string for the track's MIDI channel (e.g., "Omni", "Ch 1").
    var midiChannelLabel: String?
    var isAutomationExpanded: Bool
    var automationLaneLabels: [String]
    var onMuteToggle: (() -> Void)?
    var onSoloToggle: (() -> Void)?
    var onRecordArmToggle: (() -> Void)?
    var onMonitorToggle: (() -> Void)?
    var onAutomationToggle: (() -> Void)?

    public init(
        track: Track,
        height: CGFloat = 80,
        inputPortName: String? = nil,
        outputPortName: String? = nil,
        midiDeviceName: String? = nil,
        midiChannelLabel: String? = nil,
        isAutomationExpanded: Bool = false,
        automationLaneLabels: [String] = [],
        onMuteToggle: (() -> Void)? = nil,
        onSoloToggle: (() -> Void)? = nil,
        onRecordArmToggle: (() -> Void)? = nil,
        onMonitorToggle: (() -> Void)? = nil,
        onAutomationToggle: (() -> Void)? = nil
    ) {
        self.track = track
        self.height = height
        self.inputPortName = inputPortName
        self.outputPortName = outputPortName
        self.midiDeviceName = midiDeviceName
        self.midiChannelLabel = midiChannelLabel
        self.isAutomationExpanded = isAutomationExpanded
        self.automationLaneLabels = automationLaneLabels
        self.onMuteToggle = onMuteToggle
        self.onSoloToggle = onSoloToggle
        self.onRecordArmToggle = onRecordArmToggle
        self.onMonitorToggle = onMonitorToggle
        self.onAutomationToggle = onAutomationToggle
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Main track header
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

                    Button(action: { onRecordArmToggle?() }) {
                        Circle()
                            .fill(track.isRecordArmed ? Color.red : Color.clear)
                            .overlay(
                                Circle()
                                    .strokeBorder(track.isRecordArmed ? Color.red : Color.secondary, lineWidth: 1.5)
                            )
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 18, height: 18)

                    Button(action: { onMonitorToggle?() }) {
                        Image(systemName: track.isMonitoring ? "headphones" : "headphones")
                            .font(.system(size: 10))
                            .foregroundStyle(track.isMonitoring ? .white : .secondary)
                            .frame(width: 18, height: 18)
                            .background(track.isMonitoring ? Color.orange.opacity(0.8) : Color.clear)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }

                // Automation toggle
                HStack(spacing: 2) {
                    Button(action: { onAutomationToggle?() }) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 9))
                            .foregroundStyle(isAutomationExpanded ? .white : .secondary)
                            .frame(width: 18, height: 18)
                            .background(isAutomationExpanded ? Color.purple.opacity(0.8) : Color.clear)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Automation Lanes")

                    if hasAutomation {
                        Text("Auto")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
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

                // MIDI routing labels (MIDI tracks only)
                if track.kind == .midi {
                    HStack(spacing: 2) {
                        Image(systemName: "pianokeys")
                            .font(.system(size: 7))
                            .foregroundStyle(.secondary)
                        Text(midiDeviceName ?? "All Devices")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    HStack(spacing: 2) {
                        Image(systemName: "number")
                            .font(.system(size: 7))
                            .foregroundStyle(.secondary)
                        Text(midiChannelLabel ?? "Omni")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)

            // Automation sub-lane labels
            if isAutomationExpanded && !automationLaneLabels.isEmpty {
                ForEach(Array(automationLaneLabels.enumerated()), id: \.offset) { index, label in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(AutomationColors.color(at: index))
                            .frame(width: 6, height: 6)
                        Text(label)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 6)
                    .frame(width: 160, height: TimelineViewModel.automationSubLaneHeight, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .overlay(
                        Rectangle()
                            .frame(height: 0.5)
                            .foregroundStyle(Color.secondary.opacity(0.15)),
                        alignment: .bottom
                    )
                }
            }
        }
        .frame(width: 160, height: height)
        .background(
            track.isRecordArmed
                ? Color.red.opacity(0.1)
                : track.isMonitoring
                    ? Color.orange.opacity(0.1)
                    : Color(nsColor: .controlBackgroundColor)
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.secondary.opacity(0.3)),
            alignment: .bottom
        )
    }

    private var hasAutomation: Bool {
        track.containers.contains { !$0.automationLanes.isEmpty }
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
