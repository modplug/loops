import AppKit
import LoopsCore

public final class PlaybackGridSceneBuilder {
    public var waveformPeaksProvider: ((_ container: Container) -> [Float]?)?
    public var audioDurationBarsProvider: ((_ container: Container) -> Double?)?
    public var resolvedMIDISequenceProvider: ((_ container: Container) -> MIDISequence?)?

    public init() {}

    public func build(snapshot: PlaybackGridSnapshot) -> PlaybackGridScene {
        var trackLayouts: [PlaybackGridTrackLayout] = []
        var yOffset: CGFloat = snapshot.showRulerAndSections ? PlaybackGridLayout.trackAreaTop : 0

        for track in snapshot.tracks {
            let height = snapshot.trackHeights[track.id] ?? snapshot.defaultTrackHeight

            var containerLayouts: [PlaybackGridContainerLayout] = []
            for container in track.containers {
                let x = CGFloat(container.startBar - 1.0) * snapshot.pixelsPerBar
                let width = CGFloat(container.lengthBars) * snapshot.pixelsPerBar
                let rect = CGRect(x: x, y: yOffset, width: width, height: height)
                let peaks = waveformPeaksProvider?(container)
                let durationBars = audioDurationBarsProvider?(container)
                let notes = resolvedMIDISequenceProvider?(container)?.notes

                containerLayouts.append(PlaybackGridContainerLayout(
                    container: container,
                    rect: rect,
                    waveformPeaks: peaks,
                    isSelected: snapshot.selectedContainerIDs.contains(container.id),
                    resolvedMIDINotes: notes,
                    enterFade: container.enterFade,
                    exitFade: container.exitFade,
                    audioDurationBars: durationBars
                ))
            }

            trackLayouts.append(PlaybackGridTrackLayout(
                track: track,
                yOrigin: yOffset,
                height: height,
                containers: containerLayouts
            ))

            yOffset += height
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
