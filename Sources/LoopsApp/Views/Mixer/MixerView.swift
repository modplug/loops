import SwiftUI
import LoopsCore

/// The main mixer panel showing all tracks as vertical mixer strips with a master fader on the right.
public struct MixerView: View {
    let tracks: [Track]
    let mixerViewModel: MixerViewModel
    var selectedTrackID: ID<Track>?
    var onVolumeChange: ((ID<Track>, Float) -> Void)?
    var onPanChange: ((ID<Track>, Float) -> Void)?
    var onMuteToggle: ((ID<Track>) -> Void)?
    var onSoloToggle: ((ID<Track>) -> Void)?
    var onRecordArmToggle: ((ID<Track>, Bool) -> Void)?
    var onMonitorToggle: ((ID<Track>, Bool) -> Void)?
    var onTrackSelect: ((ID<Track>) -> Void)?

    public init(
        tracks: [Track],
        mixerViewModel: MixerViewModel,
        selectedTrackID: ID<Track>? = nil,
        onVolumeChange: ((ID<Track>, Float) -> Void)? = nil,
        onPanChange: ((ID<Track>, Float) -> Void)? = nil,
        onMuteToggle: ((ID<Track>) -> Void)? = nil,
        onSoloToggle: ((ID<Track>) -> Void)? = nil,
        onRecordArmToggle: ((ID<Track>, Bool) -> Void)? = nil,
        onMonitorToggle: ((ID<Track>, Bool) -> Void)? = nil,
        onTrackSelect: ((ID<Track>) -> Void)? = nil
    ) {
        self.tracks = tracks
        self.mixerViewModel = mixerViewModel
        self.selectedTrackID = selectedTrackID
        self.onVolumeChange = onVolumeChange
        self.onPanChange = onPanChange
        self.onMuteToggle = onMuteToggle
        self.onSoloToggle = onSoloToggle
        self.onRecordArmToggle = onRecordArmToggle
        self.onMonitorToggle = onMonitorToggle
        self.onTrackSelect = onTrackSelect
    }

    private var regularTracks: [Track] {
        tracks.filter { $0.kind != .master }
    }

    private var masterTrack: Track? {
        tracks.first { $0.kind == .master }
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Regular tracks in a horizontal scroll view
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 4) {
                    ForEach(regularTracks) { track in
                        stripView(for: track)
                    }
                }
                .padding(8)
            }

            // Divider between regular tracks and master
            if masterTrack != nil {
                Divider()
            }

            // Master strip (fixed on the right)
            if let master = masterTrack {
                stripView(for: master)
                    .padding(8)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func stripView(for track: Track) -> some View {
        MixerStripView(
            track: track,
            stripState: track.kind == .master
                ? mixerViewModel.masterStripState
                : mixerViewModel.stripState(for: track.id),
            isTrackSelected: selectedTrackID == track.id,
            onVolumeChange: { newVolume in
                onVolumeChange?(track.id, newVolume)
            },
            onPanChange: { newPan in
                onPanChange?(track.id, newPan)
            },
            onMuteToggle: {
                onMuteToggle?(track.id)
            },
            onSoloToggle: {
                onSoloToggle?(track.id)
            },
            onRecordArmToggle: {
                onRecordArmToggle?(track.id, !track.isRecordArmed)
            },
            onMonitorToggle: {
                onMonitorToggle?(track.id, !track.isMonitoring)
            },
            onTrackSelect: {
                onTrackSelect?(track.id)
            }
        )
    }
}
