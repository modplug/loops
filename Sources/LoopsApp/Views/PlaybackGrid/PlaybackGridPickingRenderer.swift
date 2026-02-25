import AppKit
import LoopsCore

/// Picking renderer for playback-grid interaction.
///
/// Current implementation uses deterministic CPU hit testing against the
/// scene graph while preserving the same object-ID surface required by
/// the interaction controller. The API is intentionally shaped so the
/// internal implementation can be swapped to a GPU ID pass without
/// changing the caller contract.
public final class PlaybackGridPickingRenderer {
    public init() {}

    public func pick(
        at point: CGPoint,
        scene: PlaybackGridScene,
        snapshot: PlaybackGridSnapshot,
        visibleRect: CGRect,
        canvasWidth: CGFloat
    ) -> GridPickObject {
        if snapshot.showRulerAndSections {
            let vpTop = visibleRect.minY
            if point.y < vpTop + PlaybackGridLayout.rulerHeight {
                return GridPickObject(
                    id: makeID(kind: .ruler),
                    kind: .ruler
                )
            }
            if point.y < vpTop + PlaybackGridLayout.trackAreaTop {
                for section in scene.sectionLayouts.reversed() {
                    let pinnedRect = CGRect(
                        x: section.rect.minX,
                        y: vpTop + PlaybackGridLayout.rulerHeight + 1,
                        width: section.rect.width,
                        height: PlaybackGridLayout.sectionLaneHeight - 2
                    )
                    if pinnedRect.contains(point) {
                        return GridPickObject(
                            id: makeID(kind: .section, sectionID: section.section.id),
                            kind: .section,
                            sectionID: section.section.id
                        )
                    }
                }
                return GridPickObject(
                    id: makeID(kind: .ruler),
                    kind: .ruler
                )
            }
        }

        for trackLayout in scene.trackLayouts.reversed() {
            for containerLayout in trackLayout.containers.reversed() {
                if containerLayout.rect.contains(point) {
                    if let midiHit = detectMIDINoteHit(
                        point: point,
                        containerLayout: containerLayout,
                        timeSignature: snapshot.timeSignature
                    ) {
                        return GridPickObject(
                            id: makeID(
                                kind: .midiNote,
                                containerID: containerLayout.container.id,
                                trackID: trackLayout.track.id,
                                midiNoteID: midiHit.id
                            ),
                            kind: .midiNote,
                            containerID: containerLayout.container.id,
                            trackID: trackLayout.track.id,
                            midiNoteID: midiHit.id
                        )
                    }

                    if let automationHit = detectAutomationBreakpointHit(
                        point: point,
                        containerLayout: containerLayout
                    ) {
                        return GridPickObject(
                            id: makeID(
                                kind: .automationBreakpoint,
                                containerID: containerLayout.container.id,
                                trackID: trackLayout.track.id,
                                automationLaneID: automationHit.laneID,
                                automationBreakpointID: automationHit.breakpoint.id
                            ),
                            kind: .automationBreakpoint,
                            containerID: containerLayout.container.id,
                            trackID: trackLayout.track.id,
                            automationLaneID: automationHit.laneID,
                            automationBreakpointID: automationHit.breakpoint.id
                        )
                    }

                    let zone = detectZone(point: point, rect: containerLayout.rect)
                    return GridPickObject(
                        id: makeID(
                            kind: .containerZone,
                            containerID: containerLayout.container.id,
                            trackID: trackLayout.track.id,
                            zone: zone
                        ),
                        kind: .containerZone,
                        containerID: containerLayout.container.id,
                        trackID: trackLayout.track.id,
                        zone: zone
                    )
                }
            }

            let trackRect = CGRect(
                x: 0,
                y: trackLayout.yOrigin,
                width: canvasWidth,
                height: trackLayout.height
            )
            if trackRect.contains(point) {
                return GridPickObject(
                    id: makeID(kind: .trackBackground, trackID: trackLayout.track.id),
                    kind: .trackBackground,
                    trackID: trackLayout.track.id
                )
            }
        }

        let gridTop = snapshot.showRulerAndSections ? PlaybackGridLayout.trackAreaTop : 0
        if point.y >= CGFloat(gridTop), point.y <= scene.contentHeight {
            return GridPickObject(
                id: makeID(kind: .trackBackground),
                kind: .trackBackground
            )
        }

        return .none
    }

    private func detectZone(point: CGPoint, rect: CGRect) -> GridContainerZone {
        let localX = point.x - rect.minX
        let localY = point.y - rect.minY
        let edge: CGFloat = 12

        let isLeftEdge = localX < edge
        let isRightEdge = localX > rect.width - edge
        let relativeY = localY / max(rect.height, 1)

        if relativeY < (1.0 / 3.0) {
            if isLeftEdge { return .fadeLeft }
            if isRightEdge { return .fadeRight }
            return .selector
        } else if relativeY < (2.0 / 3.0) {
            if isLeftEdge { return .resizeLeft }
            if isRightEdge { return .resizeRight }
            return .move
        } else {
            if isLeftEdge { return .trimLeft }
            if isRightEdge { return .trimRight }
            return .move
        }
    }

    private func detectMIDINoteHit(
        point: CGPoint,
        containerLayout: PlaybackGridContainerLayout,
        timeSignature: TimeSignature
    ) -> MIDINoteEvent? {
        guard let notes = containerLayout.resolvedMIDINotes, !notes.isEmpty else {
            return nil
        }

        var minPitch: UInt8 = 127
        var maxPitch: UInt8 = 0
        for note in notes {
            if note.pitch < minPitch { minPitch = note.pitch }
            if note.pitch > maxPitch { maxPitch = note.pitch }
        }
        let pitchRange = max(CGFloat(maxPitch - minPitch), 12)
        let beatsPerBar = CGFloat(timeSignature.beatsPerBar)
        let totalBeats = max(CGFloat(containerLayout.container.lengthBars) * beatsPerBar, 0.0001)
        let heightMinusPad = containerLayout.rect.height - 4
        let noteH = max(2, heightMinusPad / pitchRange)

        for note in notes.reversed() {
            let xFraction = CGFloat(note.startBeat) / totalBeats
            let widthFraction = CGFloat(note.duration) / totalBeats
            let noteX = containerLayout.rect.minX + xFraction * containerLayout.rect.width
            let noteW = max(2, widthFraction * containerLayout.rect.width)
            let yFraction = 1.0 - (CGFloat(note.pitch - minPitch) / pitchRange)
            let noteY = containerLayout.rect.minY + yFraction * heightMinusPad + 2
            let centerX = noteX + noteW / 2
            let centerY = noteY + noteH / 2
            let halfSize = min(noteW, noteH, 8) / 2
            let hitRect = CGRect(
                x: centerX - halfSize - 3,
                y: centerY - halfSize - 3,
                width: (halfSize + 3) * 2,
                height: (halfSize + 3) * 2
            )
            if hitRect.contains(point) {
                return note
            }
        }
        return nil
    }

    private func detectAutomationBreakpointHit(
        point: CGPoint,
        containerLayout: PlaybackGridContainerLayout
    ) -> (laneID: ID<AutomationLane>, breakpoint: AutomationBreakpoint)? {
        let hitRadius: CGFloat = 7
        for lane in containerLayout.container.automationLanes.reversed() {
            for breakpoint in lane.breakpoints.reversed() {
                let x = containerLayout.rect.minX + CGFloat(breakpoint.position) * (containerLayout.rect.width / max(CGFloat(containerLayout.container.lengthBars), 0.0001))
                let y = containerLayout.rect.maxY - (CGFloat(breakpoint.value) * containerLayout.rect.height)
                let dx = point.x - x
                let dy = point.y - y
                if dx * dx + dy * dy <= hitRadius * hitRadius {
                    return (laneID: lane.id, breakpoint: breakpoint)
                }
            }
        }
        return nil
    }

    private func makeID(
        kind: GridPickObjectKind,
        containerID: ID<Container>? = nil,
        trackID: ID<Track>? = nil,
        sectionID: ID<SectionRegion>? = nil,
        automationLaneID: ID<AutomationLane>? = nil,
        automationBreakpointID: ID<AutomationBreakpoint>? = nil,
        midiNoteID: ID<MIDINoteEvent>? = nil,
        zone: GridContainerZone? = nil
    ) -> GridPickID {
        var hasher = Hasher()
        hasher.combine(kind)
        hasher.combine(containerID?.rawValue)
        hasher.combine(trackID?.rawValue)
        hasher.combine(sectionID?.rawValue)
        hasher.combine(automationLaneID?.rawValue)
        hasher.combine(automationBreakpointID?.rawValue)
        hasher.combine(midiNoteID?.rawValue)
        hasher.combine(zone?.rawValue)
        let value = UInt32(bitPattern: Int32(truncatingIfNeeded: hasher.finalize()))
        return value == 0 ? 1 : value
    }
}
