import AppKit
import LoopsCore

public final class PlaybackGridSceneBuilder {
    public var waveformPeaksProvider: ((_ container: Container) -> [Float]?)?
    public var waveformExtremaProvider: ((_ container: Container) -> [WaveformExtrema]?)?
    public var waveformRMSProvider: ((_ container: Container) -> [Float]?)?
    public var audioDurationBarsProvider: ((_ container: Container) -> Double?)?
    public var resolvedMIDISequenceProvider: ((_ container: Container) -> MIDISequence?)?

    public init() {}

    public func build(snapshot: PlaybackGridSnapshot) -> PlaybackGridScene {
        var trackLayouts: [PlaybackGridTrackLayout] = []
        var yOffset: CGFloat = snapshot.showRulerAndSections ? PlaybackGridLayout.trackAreaTop : 0

        for track in snapshot.tracks {
            let baseHeight = snapshot.trackHeights[track.id] ?? snapshot.defaultTrackHeight
            let midiExtraHeight = snapshot.inlineMIDILaneHeights[track.id] ?? 0
            let lanes = automationLanes(for: track)
            let lanePaths = lanes.map(\.targetPath)
            let automationExpanded = snapshot.automationExpandedTrackIDs.contains(track.id) && !lanePaths.isEmpty
            let toolbarHeight = automationExpanded ? snapshot.automationToolbarHeight : 0
            let automationLaneLayouts: [PlaybackGridAutomationLaneLayout]
            if automationExpanded {
                let laneOriginY = yOffset + baseHeight + toolbarHeight
                automationLaneLayouts = lanes.enumerated().map { index, lane in
                    let laneY = laneOriginY + (CGFloat(index) * snapshot.automationSubLaneHeight)
                    return PlaybackGridAutomationLaneLayout(
                        laneID: lane.id,
                        targetPath: lane.targetPath,
                        rect: CGRect(
                            x: 0,
                            y: laneY,
                            width: CGFloat(snapshot.totalBars) * snapshot.pixelsPerBar,
                            height: snapshot.automationSubLaneHeight
                        ),
                        isPreviewed: snapshot.previewedAutomationLaneID == lane.id
                            || snapshot.previewedAutomationPath == lane.targetPath
                    )
                }
            } else {
                automationLaneLayouts = []
            }
            let totalTrackHeight = baseHeight
                + toolbarHeight
                + (CGFloat(automationLaneLayouts.count) * snapshot.automationSubLaneHeight)
                + midiExtraHeight

            var containerLayouts: [PlaybackGridContainerLayout] = []
            for container in track.containers {
                let x = CGFloat(container.startBar - 1.0) * snapshot.pixelsPerBar
                let width = CGFloat(container.lengthBars) * snapshot.pixelsPerBar
                let rect = CGRect(x: x, y: yOffset, width: width, height: baseHeight)
                let peaks = waveformPeaksProvider?(container)
                let extrema = waveformExtremaProvider?(container)
                let rms = waveformRMSProvider?(container)
                let durationBars = audioDurationBarsProvider?(container)
                let notes = resolvedMIDISequenceProvider?(container)?.notes

                containerLayouts.append(PlaybackGridContainerLayout(
                    container: container,
                    rect: rect,
                    waveformPeaks: peaks,
                    waveformExtrema: extrema,
                    waveformRMS: rms,
                    isSelected: snapshot.selectedContainerIDs.contains(container.id),
                    isPreviewed: snapshot.previewedContainerID == container.id,
                    resolvedMIDINotes: notes,
                    enterFade: container.enterFade,
                    exitFade: container.exitFade,
                    audioDurationBars: durationBars
                ))
            }

            trackLayouts.append(PlaybackGridTrackLayout(
                track: track,
                yOrigin: yOffset,
                clipHeight: baseHeight,
                automationToolbarHeight: toolbarHeight,
                automationLaneLayouts: automationLaneLayouts,
                height: totalTrackHeight,
                isPreviewed: snapshot.previewedTrackID == track.id,
                containers: containerLayouts
            ))

            yOffset += totalTrackHeight + PlaybackGridLayout.trackGap
        }

        var sectionLayouts: [PlaybackGridSectionLayout] = []
        for section in snapshot.sections {
            let x = CGFloat(section.startBar - 1) * snapshot.pixelsPerBar
            let width = CGFloat(section.lengthBars) * snapshot.pixelsPerBar
            sectionLayouts.append(PlaybackGridSectionLayout(
                section: section,
                rect: CGRect(x: x, y: PlaybackGridLayout.rulerHeight, width: width, height: PlaybackGridLayout.sectionLaneHeight),
                isSelected: snapshot.selectedSectionID == section.id
            ))
        }

        let sceneMinimumHeight = max(
            snapshot.minimumContentHeight,
            snapshot.showRulerAndSections ? PlaybackGridLayout.trackAreaTop + snapshot.bottomPadding : snapshot.bottomPadding
        )
        let contentHeight = max(yOffset + snapshot.bottomPadding, sceneMinimumHeight)

        return PlaybackGridScene(
            trackLayouts: trackLayouts,
            sectionLayouts: sectionLayouts,
            contentHeight: contentHeight
        )
    }

    private func automationLanes(for track: Track) -> [AutomationLane] {
        var seen = Set<EffectPath>()
        var ordered: [AutomationLane] = []
        for lane in track.trackAutomationLanes {
            if seen.insert(lane.targetPath).inserted {
                ordered.append(lane)
            }
        }
        for container in track.containers {
            for lane in container.automationLanes {
                if seen.insert(lane.targetPath).inserted {
                    ordered.append(lane)
                }
            }
        }
        return ordered
    }
}

extension PlaybackGridScene {
    func asLegacyTrackLayouts() -> [TimelineCanvasView.TrackLayout] {
        trackLayouts.map { trackLayout in
            let legacyContainers = trackLayout.containers.map { cl in
                TimelineCanvasView.ContainerLayout(
                    container: cl.container,
                    rect: cl.rect,
                    waveformPeaks: cl.waveformPeaks,
                    isSelected: cl.isSelected,
                    isClone: cl.container.isClone,
                    resolvedMIDINotes: cl.resolvedMIDINotes,
                    enterFade: cl.enterFade,
                    exitFade: cl.exitFade,
                    audioDurationBars: cl.audioDurationBars
                )
            }

            return TimelineCanvasView.TrackLayout(
                track: trackLayout.track,
                yOrigin: trackLayout.yOrigin,
                height: trackLayout.height,
                containers: legacyContainers
            )
        }
    }

    func asLegacySectionLayouts() -> [TimelineCanvasView.SectionLayout] {
        sectionLayouts.map { layout in
            TimelineCanvasView.SectionLayout(
                section: layout.section,
                rect: layout.rect,
                isSelected: layout.isSelected
            )
        }
    }
}
