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
        var midiLayoutsByTrack: [ID<Track>: PlaybackGridMIDIResolvedLayout] = [:]
        for trackLayout in scene.trackLayouts where trackLayout.track.kind == .midi {
            let inlineMIDILaneHeight = snapshot.inlineMIDILaneHeights[trackLayout.track.id] ?? 0
            let laneHeight = inlineMIDILaneHeight > 0
                ? inlineMIDILaneHeight
                : (snapshot.trackHeights[trackLayout.track.id] ?? snapshot.defaultTrackHeight)
            midiLayoutsByTrack[trackLayout.track.id] = PlaybackGridMIDIViewResolver.resolveTrackLayout(
                trackLayout: trackLayout,
                laneHeight: laneHeight,
                snapshot: snapshot
            )
        }

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
            if !trackLayout.automationLaneLayouts.isEmpty {
                if let automationHit = detectExpandedAutomationBreakpointHit(
                    point: point,
                    trackLayout: trackLayout,
                    snapshot: snapshot
                ) {
                    return GridPickObject(
                        id: makeID(
                            kind: .automationBreakpoint,
                            containerID: automationHit.containerID,
                            trackID: trackLayout.track.id,
                            automationLaneID: automationHit.laneID,
                            automationBreakpointID: automationHit.breakpoint.id
                        ),
                        kind: .automationBreakpoint,
                        containerID: automationHit.containerID,
                        trackID: trackLayout.track.id,
                        automationLaneID: automationHit.laneID,
                        automationBreakpointID: automationHit.breakpoint.id
                    )
                }

                if let automationSegment = detectExpandedAutomationSegmentHit(
                    point: point,
                    trackLayout: trackLayout,
                    snapshot: snapshot
                ) {
                    return GridPickObject(
                        id: makeID(
                            kind: .automationSegment,
                            containerID: automationSegment.containerID,
                            trackID: trackLayout.track.id,
                            automationLaneID: automationSegment.laneID
                        ),
                        kind: .automationSegment,
                        containerID: automationSegment.containerID,
                        trackID: trackLayout.track.id,
                        automationLaneID: automationSegment.laneID
                    )
                }
            }

            for containerLayout in trackLayout.containers.reversed() {
                let midiRect = midiEditorRect(
                    trackLayout: trackLayout,
                    for: containerLayout,
                    snapshot: snapshot
                )
                let isInContainer = containerLayout.rect.contains(point)
                let isInMidiRect = midiRect.contains(point)
                if isInContainer || isInMidiRect {
                    if let midiHit = detectMIDINoteHit(
                        point: point,
                        containerLayout: containerLayout,
                        midiRect: midiRect,
                        timeSignature: snapshot.timeSignature,
                        resolved: midiLayoutsByTrack[trackLayout.track.id]
                    ) {
                        return GridPickObject(
                            id: makeID(
                                kind: .midiNote,
                                containerID: containerLayout.container.id,
                                trackID: trackLayout.track.id,
                                midiNoteID: midiHit.note.id,
                                zone: midiHit.zone
                            ),
                            kind: .midiNote,
                            containerID: containerLayout.container.id,
                            trackID: trackLayout.track.id,
                            midiNoteID: midiHit.note.id,
                            zone: midiHit.zone
                        )
                    }

                    if isInContainer {
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

                        if let automationLaneID = detectAutomationSegmentHit(
                            point: point,
                            containerLayout: containerLayout,
                            snapshot: snapshot
                        ) {
                            return GridPickObject(
                                id: makeID(
                                    kind: .automationSegment,
                                    containerID: containerLayout.container.id,
                                    trackID: trackLayout.track.id,
                                    automationLaneID: automationLaneID
                                ),
                                kind: .automationSegment,
                                containerID: containerLayout.container.id,
                                trackID: trackLayout.track.id,
                                automationLaneID: automationLaneID
                            )
                        }
                    }

                    let zone = detectZone(point: point, rect: containerLayout.rect)
                    let effectiveZone: GridContainerZone = isInContainer ? zone : .move
                    return GridPickObject(
                        id: makeID(
                            kind: .containerZone,
                            containerID: containerLayout.container.id,
                            trackID: trackLayout.track.id,
                            zone: effectiveZone
                        ),
                        kind: .containerZone,
                        containerID: containerLayout.container.id,
                        trackID: trackLayout.track.id,
                        zone: effectiveZone
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

    private struct MIDINoteHit {
        let note: MIDINoteEvent
        let zone: GridContainerZone
    }

    private func detectMIDINoteHit(
        point: CGPoint,
        containerLayout: PlaybackGridContainerLayout,
        midiRect: CGRect,
        timeSignature: TimeSignature,
        resolved: PlaybackGridMIDIResolvedLayout?
    ) -> MIDINoteHit? {
        guard let notes = containerLayout.resolvedMIDINotes, !notes.isEmpty else {
            return nil
        }
        guard let resolved else { return nil }

        for note in notes.reversed() {
            guard let noteRect = PlaybackGridMIDIViewResolver.noteRect(
                note: note,
                containerLengthBars: containerLayout.container.lengthBars,
                laneRect: midiRect,
                timeSignature: timeSignature,
                resolved: resolved
            ) else { continue }
            // Larger hit target improves edge-resize ergonomics on short notes.
            let hitRect = noteRect.insetBy(dx: -5, dy: -4)
            if hitRect.contains(point) {
                let zone = midiNoteZone(point: point, noteRect: noteRect)
                return MIDINoteHit(note: note, zone: zone)
            }
        }
        return nil
    }

    private func detectExpandedAutomationBreakpointHit(
        point: CGPoint,
        trackLayout: PlaybackGridTrackLayout,
        snapshot: PlaybackGridSnapshot
    ) -> (containerID: ID<Container>?, laneID: ID<AutomationLane>, breakpoint: AutomationBreakpoint)? {
        let hitRadius: CGFloat = 7
        let ppb = snapshot.pixelsPerBar

        for laneLayout in trackLayout.automationLaneLayouts.reversed() {
            guard laneLayout.rect.contains(point) else { continue }

            if let trackLane = trackLayout.track.trackAutomationLanes.first(where: { $0.targetPath == laneLayout.targetPath }) {
                for breakpoint in trackLane.breakpoints.reversed() {
                    let x = CGFloat(breakpoint.position) * ppb
                    let y = laneLayout.rect.maxY - (CGFloat(breakpoint.value) * laneLayout.rect.height)
                    let dx = point.x - x
                    let dy = point.y - y
                    if dx * dx + dy * dy <= hitRadius * hitRadius {
                        return (containerID: nil, laneID: trackLane.id, breakpoint: breakpoint)
                    }
                }
            }

            for containerLayout in trackLayout.containers.reversed() {
                guard containerLayout.rect.minX <= point.x, containerLayout.rect.maxX >= point.x else { continue }
                guard let lane = containerLayout.container.automationLanes.first(where: { $0.targetPath == laneLayout.targetPath }) else { continue }
                let barsToPixels = containerLayout.rect.width / max(CGFloat(containerLayout.container.lengthBars), 0.0001)
                for breakpoint in lane.breakpoints.reversed() {
                    let x = containerLayout.rect.minX + (CGFloat(breakpoint.position) * barsToPixels)
                    let y = laneLayout.rect.maxY - (CGFloat(breakpoint.value) * laneLayout.rect.height)
                    let dx = point.x - x
                    let dy = point.y - y
                    if dx * dx + dy * dy <= hitRadius * hitRadius {
                        return (containerID: containerLayout.container.id, laneID: lane.id, breakpoint: breakpoint)
                    }
                }
            }
        }
        return nil
    }

    private func detectExpandedAutomationSegmentHit(
        point: CGPoint,
        trackLayout: PlaybackGridTrackLayout,
        snapshot: PlaybackGridSnapshot
    ) -> (containerID: ID<Container>?, laneID: ID<AutomationLane>)? {
        for laneLayout in trackLayout.automationLaneLayouts {
            guard laneLayout.rect.contains(point) else { continue }

            for containerLayout in trackLayout.containers.reversed() {
                guard containerLayout.rect.minX <= point.x, containerLayout.rect.maxX >= point.x else { continue }
                if let lane = containerLayout.container.automationLanes.first(where: { $0.targetPath == laneLayout.targetPath }) {
                    return (containerID: containerLayout.container.id, laneID: lane.id)
                }
            }

            if let trackLane = trackLayout.track.trackAutomationLanes.first(where: { $0.targetPath == laneLayout.targetPath }) {
                return (containerID: nil, laneID: trackLane.id)
            }
        }
        return nil
    }

    private func midiNoteZone(point: CGPoint, noteRect: CGRect) -> GridContainerZone {
        let threshold = midiEdgeThreshold(noteWidth: noteRect.width)
        guard threshold > 0 else { return .move }
        let localX = point.x - noteRect.minX
        if (threshold * 2) >= (noteRect.width - 0.5) {
            return localX < (noteRect.width * 0.5) ? .resizeLeft : .resizeRight
        }
        if localX < threshold { return .resizeLeft }
        if localX > noteRect.width - threshold { return .resizeRight }
        return .move
    }

    private func midiEdgeThreshold(noteWidth: CGFloat) -> CGFloat {
        guard noteWidth >= 3 else { return 0 }
        if noteWidth <= 24 { return max(5.0, noteWidth * 0.48) }
        if noteWidth <= 64 { return max(8.0, min(20.0, noteWidth * 0.32)) }
        return max(11.0, min(24.0, noteWidth * 0.24))
    }

    private func midiEditorRect(
        trackLayout: PlaybackGridTrackLayout,
        for containerLayout: PlaybackGridContainerLayout,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect {
        let inlineHeight = snapshot.inlineMIDILaneHeights[trackLayout.track.id] ?? 0
        guard inlineHeight > 0 else { return containerLayout.rect }
        let automationHeight = trackLayout.automationToolbarHeight
            + (CGFloat(trackLayout.automationLaneLayouts.count) * snapshot.automationSubLaneHeight)
        return CGRect(
            x: containerLayout.rect.minX,
            y: trackLayout.yOrigin + trackLayout.clipHeight + automationHeight,
            width: containerLayout.rect.width,
            height: inlineHeight
        )
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

    private func detectAutomationSegmentHit(
        point: CGPoint,
        containerLayout: PlaybackGridContainerLayout,
        snapshot: PlaybackGridSnapshot
    ) -> ID<AutomationLane>? {
        let lanes = containerLayout.container.automationLanes
        guard !lanes.isEmpty else { return nil }
        let automationBandHeight: CGFloat
        if snapshot.selectedAutomationTool == .pointer {
            automationBandHeight = min(containerLayout.rect.height, max(24, containerLayout.rect.height * 0.42))
        } else {
            automationBandHeight = containerLayout.rect.height
        }
        let bandRect = CGRect(
            x: containerLayout.rect.minX,
            y: containerLayout.rect.minY,
            width: containerLayout.rect.width,
            height: automationBandHeight
        )
        guard bandRect.contains(point) else { return nil }
        guard lanes.count > 1 else { return lanes[0].id }
        let y = point.y - bandRect.minY
        let laneHeight = max(automationBandHeight / CGFloat(lanes.count), 1)
        let index = min(max(Int(y / laneHeight), 0), lanes.count - 1)
        return lanes[index].id
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
