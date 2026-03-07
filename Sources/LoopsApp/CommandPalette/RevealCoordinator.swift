import Foundation
import AppKit
import LoopsCore

@MainActor
public final class RevealCoordinator {
    private let projectViewModel: ProjectViewModel
    private let timelineViewModel: TimelineViewModel
    private let previewState: PreviewState
    private let currentContentMode: () -> ContentMode
    private let setContentMode: (ContentMode) -> Void
    private let horizontalOffset: () -> CGFloat
    private let setHorizontalOffset: (CGFloat) -> Void
    private let verticalOffset: () -> CGFloat
    private let setVerticalOffset: (CGFloat) -> Void

    public init(
        projectViewModel: ProjectViewModel,
        timelineViewModel: TimelineViewModel,
        previewState: PreviewState,
        currentContentMode: @escaping () -> ContentMode,
        setContentMode: @escaping (ContentMode) -> Void,
        horizontalOffset: @escaping () -> CGFloat,
        setHorizontalOffset: @escaping (CGFloat) -> Void,
        verticalOffset: @escaping () -> CGFloat,
        setVerticalOffset: @escaping (CGFloat) -> Void
    ) {
        self.projectViewModel = projectViewModel
        self.timelineViewModel = timelineViewModel
        self.previewState = previewState
        self.currentContentMode = currentContentMode
        self.setContentMode = setContentMode
        self.horizontalOffset = horizontalOffset
        self.setHorizontalOffset = setHorizontalOffset
        self.verticalOffset = verticalOffset
        self.setVerticalOffset = setVerticalOffset
    }

    public func preview(node: CommandNode?) {
        guard let node, let target = node.previewTarget else {
            clear(committed: false)
            return
        }

        let restoreToken = PreviewRestoreToken(
            contentMode: currentContentMode(),
            automationExpanded: timelineViewModel.automationExpanded,
            horizontalOffset: horizontalOffset(),
            verticalOffset: verticalOffset()
        )
        previewState.begin(target: target, style: node.previewStyle, restoreToken: restoreToken)
        reveal(target: target)
    }

    public func clear(committed: Bool) {
        if !committed, let restoreToken = previewState.restoreToken {
            setContentMode(restoreToken.contentMode)
            timelineViewModel.automationExpanded = restoreToken.automationExpanded
            setHorizontalOffset(restoreToken.horizontalOffset)
            setVerticalOffset(restoreToken.verticalOffset)
        }
        previewState.clear(resetRestoreToken: true)
    }

    public func revealCommitted(target: PreviewTarget) {
        previewState.clear(resetRestoreToken: true)
        reveal(target: target)
    }

    private func reveal(target: PreviewTarget) {
        setContentMode(.timeline)

        switch target {
        case .track(let trackID):
            selectSong(containingTrackID: trackID)
            centerOn(trackID: trackID, xCenter: nil)

        case .container(let trackID, let containerID):
            selectSong(containingTrackID: trackID)
            let xCenter = containerXCenter(containerID: containerID)
            centerOn(trackID: trackID, xCenter: xCenter)

        case .pluginInstance(let reference):
            selectSong(containingTrackID: reference.trackID)
            if let containerID = reference.containerID {
                let xCenter = containerXCenter(containerID: containerID)
                centerOn(trackID: reference.trackID, xCenter: xCenter)
            } else {
                centerOn(trackID: reference.trackID, xCenter: nil)
            }

        case .automation(let trackID, _, let targetPath):
            selectSong(containingTrackID: trackID)
            timelineViewModel.automationExpanded.insert(trackID)
            let yCenter = automationYCenter(trackID: trackID, targetPath: targetPath)
            setVerticalOffset(max(0, yCenter - 140))
        }
    }

    private func centerOn(trackID: ID<Track>, xCenter: CGFloat?) {
        let yCenter = trackYOrigin(trackID: trackID) + (trackHeight(trackID: trackID) / 2)
        setVerticalOffset(max(0, yCenter - 180))
        if let xCenter {
            setHorizontalOffset(max(0, xCenter - 320))
        }
    }

    private func selectSong(containingTrackID trackID: ID<Track>) {
        guard let songID = projectViewModel.project.songs.first(where: { song in
            song.tracks.contains(where: { $0.id == trackID })
        })?.id else { return }
        if projectViewModel.currentSongID != songID {
            projectViewModel.selectSong(id: songID)
        }
    }

    private func trackHeight(trackID: ID<Track>) -> CGFloat {
        guard let track = projectViewModel.currentSong?.tracks.first(where: { $0.id == trackID }) else {
            return TimelineViewModel.defaultTrackHeight
        }
        let base = timelineViewModel.baseTrackHeight(for: track.id)
        return timelineViewModel.trackHeight(for: track, baseHeight: base)
    }

    private func trackYOrigin(trackID: ID<Track>) -> CGFloat {
        guard let song = projectViewModel.currentSong else { return PlaybackGridLayout.trackAreaTop }
        var y = PlaybackGridLayout.trackAreaTop
        for track in song.tracks {
            if track.id == trackID {
                return y
            }
            y += totalTrackHeight(track: track) + PlaybackGridLayout.trackGap
        }
        return y
    }

    private func totalTrackHeight(track: Track) -> CGFloat {
        let base = timelineViewModel.baseTrackHeight(for: track.id)
        let height = timelineViewModel.trackHeight(for: track, baseHeight: base)
        let laneCount = uniqueAutomationPaths(for: track).count
        if timelineViewModel.automationExpanded.contains(track.id), laneCount > 0 {
            return height
        }
        return height
    }

    private func uniqueAutomationPaths(for track: Track) -> [EffectPath] {
        var seen = Set<EffectPath>()
        var ordered: [EffectPath] = []
        for lane in track.trackAutomationLanes where seen.insert(lane.targetPath).inserted {
            ordered.append(lane.targetPath)
        }
        for container in track.containers {
            for lane in container.automationLanes where seen.insert(lane.targetPath).inserted {
                ordered.append(lane.targetPath)
            }
        }
        return ordered
    }

    private func automationYCenter(trackID: ID<Track>, targetPath: EffectPath) -> CGFloat {
        guard let track = projectViewModel.currentSong?.tracks.first(where: { $0.id == trackID }) else {
            return trackYOrigin(trackID: trackID)
        }
        let base = timelineViewModel.baseTrackHeight(for: track.id)
        let trackBaseHeight = timelineViewModel.trackHeight(for: track, baseHeight: base)
        let paths = uniqueAutomationPaths(for: track)
        guard let index = paths.firstIndex(of: targetPath) else {
            return trackYOrigin(trackID: trackID) + trackBaseHeight
        }
        return trackYOrigin(trackID: trackID)
            + trackBaseHeight
            + TimelineViewModel.automationToolbarHeight
            + (CGFloat(index) * TimelineViewModel.automationSubLaneHeight)
            + (TimelineViewModel.automationSubLaneHeight / 2)
    }

    private func containerXCenter(containerID: ID<Container>) -> CGFloat? {
        guard let container = projectViewModel.project.songs
            .flatMap(\.tracks)
            .flatMap(\.containers)
            .first(where: { $0.id == containerID }) else {
            return nil
        }
        return timelineViewModel.xPosition(forBar: container.startBar) + (CGFloat(container.lengthBars) * timelineViewModel.pixelsPerBar / 2)
    }
}
