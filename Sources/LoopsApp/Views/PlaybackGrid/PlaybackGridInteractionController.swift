import AppKit
import QuartzCore
import LoopsCore

public final class PlaybackGridInteractionController {
    private struct ContainerAutomationPendingKey: Hashable {
        let containerID: ID<Container>
        let laneID: ID<AutomationLane>
        let breakpointID: ID<AutomationBreakpoint>
    }

    private struct TrackAutomationPendingKey: Hashable {
        let trackID: ID<Track>
        let laneID: ID<AutomationLane>
        let breakpointID: ID<AutomationBreakpoint>
    }

    public private(set) var state: PlaybackGridInteractionState = .idle
    private static let debugLogsEnabled: Bool = {
        ProcessInfo.processInfo.environment["LOOPS_GRID_DEBUG"] == "1"
        || UserDefaults.standard.bool(forKey: "PlaybackGridDebugLogs")
    }()

    private weak var sink: PlaybackGridCommandSink?
    private var lastLogTimeByCategory: [String: CFTimeInterval] = [:]
    private var previewedMIDIPitch: UInt8?
    private var pendingMIDINoteUpdates: [ID<MIDINoteEvent>: (containerID: ID<Container>, note: MIDINoteEvent)] = [:]
    private var pendingAutomationBreakpointUpdates: [ContainerAutomationPendingKey: AutomationBreakpoint] = [:]
    private var pendingTrackAutomationBreakpointUpdates: [TrackAutomationPendingKey: AutomationBreakpoint] = [:]
    private var automationDidEmitDuringDrag: Set<ContainerAutomationPendingKey> = []
    private var trackAutomationDidEmitDuringDrag: Set<TrackAutomationPendingKey> = []
    private var midiGhostOverlay: PlaybackGridMIDINoteOverlay?
    private var midiLiveOverlay: PlaybackGridMIDINoteOverlay?
    private var automationGhostOverlay: PlaybackGridAutomationBreakpointOverlay?
    private var automationLiveOverlay: PlaybackGridAutomationBreakpointOverlay?
    private var automationShapeGhostOverlay: PlaybackGridAutomationShapeOverlay?
    private var automationShapeLiveOverlay: PlaybackGridAutomationShapeOverlay?

    public var activeMIDINoteOverlays: [PlaybackGridMIDINoteOverlay] {
        var overlays: [PlaybackGridMIDINoteOverlay] = []
        if let ghost = midiGhostOverlay { overlays.append(ghost) }
        if let live = midiLiveOverlay { overlays.append(live) }
        return overlays
    }

    public var activeAutomationBreakpointOverlays: [PlaybackGridAutomationBreakpointOverlay] {
        var overlays: [PlaybackGridAutomationBreakpointOverlay] = []
        if let ghost = automationGhostOverlay { overlays.append(ghost) }
        if let live = automationLiveOverlay { overlays.append(live) }
        return overlays
    }

    public var activeAutomationShapeOverlays: [PlaybackGridAutomationShapeOverlay] {
        var overlays: [PlaybackGridAutomationShapeOverlay] = []
        if let ghost = automationShapeGhostOverlay { overlays.append(ghost) }
        if let live = automationShapeLiveOverlay { overlays.append(live) }
        return overlays
    }

    public var activeAutomationSuppressedLanes: Set<PlaybackGridAutomationSuppression> {
        var suppressed: Set<PlaybackGridAutomationSuppression> = []
        switch state {
        case let .draggingAutomationBreakpoint(context):
            suppressed.insert(.init(
                trackID: context.trackID,
                containerID: context.containerID,
                laneID: context.laneID
            ))
        case let .draggingTrackAutomationBreakpoint(context):
            suppressed.insert(.init(
                trackID: context.trackID,
                containerID: nil,
                laneID: context.laneID
            ))
        case let .drawingAutomationShape(context):
            suppressed.insert(.init(
                trackID: context.trackID,
                containerID: context.containerID,
                laneID: context.laneID
            ))
        case let .drawingTrackAutomationShape(context):
            suppressed.insert(.init(
                trackID: context.trackID,
                containerID: nil,
                laneID: context.laneID
            ))
        default:
            break
        }
        return suppressed
    }

    public init(sink: PlaybackGridCommandSink?) {
        self.sink = sink
    }

    public var isInteractionActive: Bool {
        if case .idle = state { return false }
        return true
    }

    public func setCommandSink(_ sink: PlaybackGridCommandSink?) {
        self.sink = sink
    }

    public func handleMouseDown(
        event: NSEvent,
        point: CGPoint,
        pick: GridPickObject,
        snapshot: PlaybackGridSnapshot
    ) {
        PlaybackGridPerfLogger.bump("interaction.mouseDown")
        stopMIDIPreviewIfNeeded()
        switch pick.kind {
        case .ruler:
            if event.modifierFlags.contains(.shift) {
                let startBar = barForX(point.x, pixelsPerBar: snapshot.pixelsPerBar, totalBars: snapshot.totalBars)
                state = .selectingRange(startBar: startBar, startPoint: point)
            } else {
                state = .scrubbingRuler
                sink?.clearRangeSelection()
                sink?.setPlayhead(bar: snappedBarForX(point.x, snapshot: snapshot))
            }

        case .section:
            if let sectionID = pick.sectionID {
                sink?.selectSection(sectionID)
            }
            state = .idle

        case .containerZone:
            guard let containerID = pick.containerID, let trackID = pick.trackID else {
                state = .idle
                return
            }
            sink?.selectContainer(containerID, trackID: trackID, modifiers: event.modifierFlags)
            if event.clickCount >= 2 {
                sink?.openContainerEditor(containerID, trackID: trackID)
                state = .idle
                return
            }

            guard let container = container(containerID: containerID, in: snapshot.tracks) else {
                state = .idle
                return
            }
            guard let track = track(trackID: trackID, in: snapshot.tracks) else {
                state = .idle
                return
            }

            if shouldBeginMIDINoteCreate(
                event: event,
                zone: pick.zone,
                track: track,
                containerID: containerID,
                trackID: trackID,
                point: point,
                snapshot: snapshot
            ),
            let baseRect = containerRect(containerID: containerID, trackID: trackID, snapshot: snapshot) {
                let pitchRect = midiPitchRect(
                    baseRect: baseRect,
                    trackID: trackID,
                    snapshot: snapshot
                )
                let startBeat = beatOffsetForPointX(
                    point.x,
                    container: container,
                    snapshot: snapshot,
                    snapMode: .nearest
                )
                let pitch = midiPitchForPointY(
                    point.y,
                    rect: pitchRect,
                    container: container,
                    trackID: trackID,
                    snapshot: snapshot
                )
                state = .creatingMIDINote(context: PlaybackGridMIDINoteCreateContext(
                    containerID: containerID,
                    trackID: trackID,
                    startPoint: point,
                    startBeat: startBeat,
                    pitch: pitch,
                    provisionalNoteID: nil
                ))
                previewMIDIPitchIfNeeded(pitch)
                log("midi create armed container=\(containerID.rawValue) startBeat=\(format(startBeat)) pitch=\(pitch)")
                return
            }

            let dragKind: PlaybackGridContainerDragKind? =
                event.modifierFlags.contains(.option)
                ? .clone
                : dragKindForZone(pick.zone)
            if let dragKind {
                state = .draggingContainer(context: PlaybackGridContainerDragContext(
                    kind: dragKind,
                    containerID: containerID,
                    trackID: trackID,
                    startPoint: point,
                    originStartBar: container.startBar,
                    originLengthBars: container.lengthBars,
                    originAudioStartOffset: container.audioStartOffset,
                    originEnterFadeDuration: container.enterFade?.duration ?? 0,
                    originEnterFadeCurve: container.enterFade?.curve ?? .linear,
                    originExitFadeDuration: container.exitFade?.duration ?? 0,
                    originExitFadeCurve: container.exitFade?.curve ?? .linear
                ))
            } else {
                state = .idle
            }

        case .trackBackground:
            if beginInlineMIDILaneResizeIfNeeded(
                event: event,
                point: point,
                snapshot: snapshot,
                preferredTrackID: pick.trackID
            ) {
                return
            }

            let clickedBar = snappedBarForX(point.x, snapshot: snapshot)
            sink?.setPlayhead(bar: clickedBar)

            if beginMIDINoteCreateFromTrackBackground(
                event: event,
                point: point,
                snapshot: snapshot,
                preferredTrackID: pick.trackID
            ) {
                return
            }

            if let trackID = pick.trackID,
               isPointInInlineMIDILane(point, trackID: trackID, snapshot: snapshot) {
                // Do not fall through to clip creation when the user is interacting in
                // an expanded inline MIDI lane but not over an existing clip.
                state = .idle
                return
            }

            guard let trackID = pick.trackID,
                  let track = track(trackID: trackID, in: snapshot.tracks),
                  track.kind != .master,
                  let segment = freeSegment(containing: clickedBar, in: track, totalBars: snapshot.totalBars) else {
                state = .idle
                return
            }

            if event.clickCount >= 2 {
                createDoubleClickContainer(
                    trackID: trackID,
                    clickedBar: clickedBar,
                    segment: segment
                )
                state = .idle
                return
            }

            state = .creatingContainer(context: PlaybackGridContainerCreateContext(
                trackID: trackID,
                startPoint: point,
                anchorBar: clickedBar,
                segmentStartBar: segment.start,
                segmentEndBar: segment.end,
                didDrag: false
            ))
            log("container create armed track=\(trackID.rawValue) anchor=\(format(clickedBar)) segment=\(format(segment.start))-\(format(segment.end))")

        case .midiNote:
            guard let containerID = pick.containerID,
                  let trackID = pick.trackID,
                  let noteID = pick.midiNoteID else {
                state = .idle
                return
            }

            if event.modifierFlags.contains(.option) {
                sink?.removeMIDINote(containerID, noteID: noteID)
                pendingMIDINoteUpdates.removeValue(forKey: noteID)
                log("midi remove note container=\(containerID.rawValue) note=\(noteID.rawValue)")
                state = .idle
                return
            }

            guard let (_, container) = containerAndTrack(containerID: containerID, trackID: trackID, in: snapshot.tracks),
                  let note = container.midiSequence?.notes.first(where: { $0.id == noteID }) ?? container.resolved(using: { id in
                      snapshot.tracks
                          .flatMap(\.containers)
                          .first(where: { $0.id == id })
                  }).midiSequence?.notes.first(where: { $0.id == noteID }) else {
                state = .idle
                return
            }

            sink?.selectContainer(containerID, trackID: trackID, modifiers: event.modifierFlags)
            if event.clickCount >= 2 {
                sink?.openContainerEditor(containerID, trackID: trackID)
                state = .idle
                return
            }

            state = .draggingMIDINote(context: PlaybackGridMIDINoteDragContext(
                kind: midiDragKind(for: pick.zone),
                containerID: containerID,
                trackID: trackID,
                noteID: noteID,
                startPoint: point,
                originalNote: note,
                containerStartBar: container.startBar,
                containerLengthBars: container.lengthBars
            ))
            midiGhostOverlay = PlaybackGridMIDINoteOverlay(
                containerID: containerID,
                trackID: trackID,
                note: note,
                isGhost: true
            )
            midiLiveOverlay = PlaybackGridMIDINoteOverlay(
                containerID: containerID,
                trackID: trackID,
                note: note,
                isGhost: false
            )
            pendingMIDINoteUpdates[note.id] = (containerID: containerID, note: note)
            previewMIDIPitchIfNeeded(note.pitch)
            log("midi drag begin container=\(containerID.rawValue) note=\(noteID.rawValue)")

        case .automationBreakpoint:
            guard let trackID = pick.trackID,
                  let laneID = pick.automationLaneID,
                  let breakpointID = pick.automationBreakpointID else {
                state = .idle
                return
            }

            if let containerID = pick.containerID {
                if event.modifierFlags.contains(.option) {
                    sink?.removeAutomationBreakpoint(containerID, laneID: laneID, breakpointID: breakpointID)
                    log("automation remove breakpoint container=\(containerID.rawValue) lane=\(laneID.rawValue) breakpoint=\(breakpointID.rawValue)")
                    state = .idle
                    return
                }

                guard let (_, container) = containerAndTrack(
                    containerID: containerID,
                    trackID: trackID,
                    in: snapshot.tracks
                ),
                let lane = container.automationLanes.first(where: { $0.id == laneID }),
                let breakpoint = lane.breakpoints.first(where: { $0.id == breakpointID }) else {
                    state = .idle
                    return
                }

                sink?.selectContainer(containerID, trackID: trackID, modifiers: event.modifierFlags)
                let laneRect: CGRect
                if let rect = containerRect(containerID: containerID, trackID: trackID, snapshot: snapshot) {
                    laneRect = automationLaneRect(
                        container: container,
                        trackID: trackID,
                        laneID: laneID,
                        containerRect: rect,
                        snapshot: snapshot
                    )
                } else {
                    laneRect = .zero
                }
                state = .draggingAutomationBreakpoint(context: PlaybackGridAutomationBreakpointDragContext(
                    containerID: containerID,
                    trackID: trackID,
                    laneID: laneID,
                    breakpointID: breakpointID,
                    startPoint: point,
                    originPosition: breakpoint.position,
                    originValue: breakpoint.value
                ))
                let pendingKey = ContainerAutomationPendingKey(
                    containerID: containerID,
                    laneID: laneID,
                    breakpointID: breakpointID
                )
                automationDidEmitDuringDrag.remove(pendingKey)
                pendingAutomationBreakpointUpdates[pendingKey] = breakpoint
                automationGhostOverlay = PlaybackGridAutomationBreakpointOverlay(
                    trackID: trackID,
                    containerID: containerID,
                    laneID: laneID,
                    breakpoint: breakpoint,
                    laneRect: laneRect,
                    isGhost: true
                )
                automationLiveOverlay = PlaybackGridAutomationBreakpointOverlay(
                    trackID: trackID,
                    containerID: containerID,
                    laneID: laneID,
                    breakpoint: breakpoint,
                    laneRect: laneRect,
                    isGhost: false
                )
                log("automation drag begin container=\(containerID.rawValue) lane=\(laneID.rawValue) breakpoint=\(breakpointID.rawValue)")
            } else {
                if event.modifierFlags.contains(.option) {
                    sink?.removeTrackAutomationBreakpoint(trackID: trackID, laneID: laneID, breakpointID: breakpointID)
                    log("automation remove breakpoint track=\(trackID.rawValue) lane=\(laneID.rawValue) breakpoint=\(breakpointID.rawValue)")
                    state = .idle
                    return
                }

                guard let track = track(trackID: trackID, in: snapshot.tracks),
                      let lane = track.trackAutomationLanes.first(where: { $0.id == laneID }),
                      let breakpoint = lane.breakpoints.first(where: { $0.id == breakpointID }) else {
                    state = .idle
                    return
                }

                state = .draggingTrackAutomationBreakpoint(context: PlaybackGridTrackAutomationBreakpointDragContext(
                    trackID: trackID,
                    laneID: laneID,
                    breakpointID: breakpointID,
                    startPoint: point,
                    originPosition: breakpoint.position,
                    originValue: breakpoint.value
                ))
                let laneRect = trackAutomationLaneRect(
                    trackID: trackID,
                    laneID: laneID,
                    snapshot: snapshot
                ) ?? .zero
                let pendingKey = TrackAutomationPendingKey(
                    trackID: trackID,
                    laneID: laneID,
                    breakpointID: breakpointID
                )
                trackAutomationDidEmitDuringDrag.remove(pendingKey)
                pendingTrackAutomationBreakpointUpdates[pendingKey] = breakpoint
                automationGhostOverlay = PlaybackGridAutomationBreakpointOverlay(
                    trackID: trackID,
                    containerID: nil,
                    laneID: laneID,
                    breakpoint: breakpoint,
                    laneRect: laneRect,
                    isGhost: true
                )
                automationLiveOverlay = PlaybackGridAutomationBreakpointOverlay(
                    trackID: trackID,
                    containerID: nil,
                    laneID: laneID,
                    breakpoint: breakpoint,
                    laneRect: laneRect,
                    isGhost: false
                )
                log("automation drag begin track=\(trackID.rawValue) lane=\(laneID.rawValue) breakpoint=\(breakpointID.rawValue)")
            }

        case .automationSegment:
            guard let trackID = pick.trackID,
                  let laneID = pick.automationLaneID else {
                state = .idle
                return
            }

            if let containerID = pick.containerID {
                sink?.selectContainer(containerID, trackID: trackID, modifiers: event.modifierFlags)
                if snapshot.selectedAutomationTool == .pointer {
                    guard let breakpoint = makeAutomationBreakpoint(
                        containerID: containerID,
                        trackID: trackID,
                        laneID: laneID,
                        point: point,
                        snapshot: snapshot
                    ) else {
                        state = .idle
                        return
                    }
                    sink?.addAutomationBreakpoint(containerID, laneID: laneID, breakpoint: breakpoint)
                    log("automation add breakpoint container=\(containerID.rawValue) lane=\(laneID.rawValue) pos=\(format(breakpoint.position)) value=\(format(Double(breakpoint.value)))")
                    let laneRect: CGRect
                    if let (_, container) = containerAndTrack(
                        containerID: containerID,
                        trackID: trackID,
                        in: snapshot.tracks
                    ),
                    let rect = containerRect(containerID: containerID, trackID: trackID, snapshot: snapshot) {
                        laneRect = automationLaneRect(
                            container: container,
                            trackID: trackID,
                            laneID: laneID,
                            containerRect: rect,
                            snapshot: snapshot
                        )
                    } else {
                        laneRect = .zero
                    }
                    state = .draggingAutomationBreakpoint(context: PlaybackGridAutomationBreakpointDragContext(
                        containerID: containerID,
                        trackID: trackID,
                        laneID: laneID,
                        breakpointID: breakpoint.id,
                        startPoint: point,
                        originPosition: breakpoint.position,
                        originValue: breakpoint.value
                    ))
                    let pendingKey = ContainerAutomationPendingKey(
                        containerID: containerID,
                        laneID: laneID,
                        breakpointID: breakpoint.id
                    )
                    automationDidEmitDuringDrag.remove(pendingKey)
                    pendingAutomationBreakpointUpdates[pendingKey] = breakpoint
                    automationGhostOverlay = PlaybackGridAutomationBreakpointOverlay(
                        trackID: trackID,
                        containerID: containerID,
                        laneID: laneID,
                        breakpoint: breakpoint,
                        laneRect: laneRect,
                        isGhost: true
                    )
                    automationLiveOverlay = PlaybackGridAutomationBreakpointOverlay(
                        trackID: trackID,
                        containerID: containerID,
                        laneID: laneID,
                        breakpoint: breakpoint,
                        laneRect: laneRect,
                        isGhost: false
                    )
                } else {
                    state = .drawingAutomationShape(context: PlaybackGridAutomationShapeDrawContext(
                        containerID: containerID,
                        trackID: trackID,
                        laneID: laneID,
                        startPoint: point
                    ))
                    if let (_, container) = containerAndTrack(
                        containerID: containerID,
                        trackID: trackID,
                        in: snapshot.tracks
                    ),
                    let rect = containerRect(containerID: containerID, trackID: trackID, snapshot: snapshot),
                    let lane = container.automationLanes.first(where: { $0.id == laneID }) {
                        let laneRect = automationLaneRect(
                            container: container,
                            trackID: trackID,
                            laneID: laneID,
                            containerRect: rect,
                            snapshot: snapshot
                        )
                        let sorted = lane.breakpoints.sorted { $0.position < $1.position }
                        automationShapeGhostOverlay = PlaybackGridAutomationShapeOverlay(
                            trackID: trackID,
                            containerID: containerID,
                            laneID: laneID,
                            breakpoints: sorted,
                            laneRect: laneRect,
                            isGhost: true
                        )
                        automationShapeLiveOverlay = PlaybackGridAutomationShapeOverlay(
                            trackID: trackID,
                            containerID: containerID,
                            laneID: laneID,
                            breakpoints: sorted,
                            laneRect: laneRect,
                            isGhost: false
                        )
                    }
                    log("automation shape begin container=\(containerID.rawValue) lane=\(laneID.rawValue) tool=\(snapshot.selectedAutomationTool)")
                }
            } else {
                if snapshot.selectedAutomationTool == .pointer {
                    guard let breakpoint = makeTrackAutomationBreakpoint(
                        trackID: trackID,
                        laneID: laneID,
                        point: point,
                        snapshot: snapshot
                    ) else {
                        state = .idle
                        return
                    }
                    sink?.addTrackAutomationBreakpoint(trackID: trackID, laneID: laneID, breakpoint: breakpoint)
                    state = .draggingTrackAutomationBreakpoint(context: PlaybackGridTrackAutomationBreakpointDragContext(
                        trackID: trackID,
                        laneID: laneID,
                        breakpointID: breakpoint.id,
                        startPoint: point,
                        originPosition: breakpoint.position,
                        originValue: breakpoint.value
                    ))
                    let laneRect = trackAutomationLaneRect(
                        trackID: trackID,
                        laneID: laneID,
                        snapshot: snapshot
                    ) ?? .zero
                    let pendingKey = TrackAutomationPendingKey(
                        trackID: trackID,
                        laneID: laneID,
                        breakpointID: breakpoint.id
                    )
                    trackAutomationDidEmitDuringDrag.remove(pendingKey)
                    pendingTrackAutomationBreakpointUpdates[pendingKey] = breakpoint
                    automationGhostOverlay = PlaybackGridAutomationBreakpointOverlay(
                        trackID: trackID,
                        containerID: nil,
                        laneID: laneID,
                        breakpoint: breakpoint,
                        laneRect: laneRect,
                        isGhost: true
                    )
                    automationLiveOverlay = PlaybackGridAutomationBreakpointOverlay(
                        trackID: trackID,
                        containerID: nil,
                        laneID: laneID,
                        breakpoint: breakpoint,
                        laneRect: laneRect,
                        isGhost: false
                    )
                    log("automation add breakpoint track=\(trackID.rawValue) lane=\(laneID.rawValue) pos=\(format(breakpoint.position)) value=\(format(Double(breakpoint.value)))")
                } else {
                    state = .drawingTrackAutomationShape(context: PlaybackGridTrackAutomationShapeDrawContext(
                        trackID: trackID,
                        laneID: laneID,
                        startPoint: point
                    ))
                    if let track = track(trackID: trackID, in: snapshot.tracks),
                       let lane = track.trackAutomationLanes.first(where: { $0.id == laneID }),
                       let laneRect = trackAutomationLaneRect(
                           trackID: trackID,
                           laneID: laneID,
                           snapshot: snapshot
                       ) {
                        let sorted = lane.breakpoints.sorted { $0.position < $1.position }
                        automationShapeGhostOverlay = PlaybackGridAutomationShapeOverlay(
                            trackID: trackID,
                            containerID: nil,
                            laneID: laneID,
                            breakpoints: sorted,
                            laneRect: laneRect,
                            isGhost: true
                        )
                        automationShapeLiveOverlay = PlaybackGridAutomationShapeOverlay(
                            trackID: trackID,
                            containerID: nil,
                            laneID: laneID,
                            breakpoints: sorted,
                            laneRect: laneRect,
                            isGhost: false
                        )
                    }
                    log("automation shape begin track=\(trackID.rawValue) lane=\(laneID.rawValue) tool=\(snapshot.selectedAutomationTool)")
                }
            }

        case .none:
            // Allow setting playhead anywhere in the main grid surface, even when no
            // specific pick object is hit (e.g. blank timeline area).
            let gridTop = snapshot.showRulerAndSections ? PlaybackGridLayout.trackAreaTop : 0
            if point.y >= CGFloat(gridTop) {
                if beginInlineMIDILaneResizeIfNeeded(
                    event: event,
                    point: point,
                    snapshot: snapshot,
                    preferredTrackID: nil
                ) {
                    return
                }
                sink?.setPlayhead(bar: snappedBarForX(point.x, snapshot: snapshot))
                if beginMIDINoteCreateFromTrackBackground(
                    event: event,
                    point: point,
                    snapshot: snapshot,
                    preferredTrackID: nil
                ) {
                    return
                }
            }
            state = .idle

        default:
            state = .idle
        }
    }

    @discardableResult
    public func handleMouseDragged(
        point: CGPoint,
        snapshot: PlaybackGridSnapshot,
        modifiers: NSEvent.ModifierFlags = []
    ) -> Bool {
        PlaybackGridPerfLogger.bump("interaction.mouseDragged")
        switch state {
        case .scrubbingRuler:
            sink?.setPlayhead(bar: snappedBarForX(point.x, snapshot: snapshot))
            return false

        case let .draggingContainer(context):
            handleContainerDrag(context: context, point: point, snapshot: snapshot)
            return false

        case let .creatingContainer(context):
            var updated = context
            if !updated.didDrag {
                let distance = hypot(point.x - updated.startPoint.x, point.y - updated.startPoint.y)
                if distance >= 6 {
                    updated.didDrag = true
                    log("container create drag start track=\(updated.trackID.rawValue) anchor=\(format(updated.anchorBar))")
                    state = .creatingContainer(context: updated)
                    return false
                }
            }
            state = .creatingContainer(context: updated)
            return false

        case let .resizingMIDILane(context):
            let deltaY = point.y - context.startPoint.y
            let proposed = context.originHeight + deltaY
            let clamped = min(max(proposed, 120), 640)
            sink?.setInlineMIDILaneHeight(trackID: context.trackID, height: clamped)
            return false

        case let .creatingMIDINote(context):
            previewMIDINoteCreation(context: context, point: point, snapshot: snapshot)
            return true

        case let .draggingMIDINote(context):
            return handleMIDINoteDrag(
                context: context,
                point: point,
                snapshot: snapshot,
                modifiers: modifiers
            )

        case let .draggingAutomationBreakpoint(context):
            return handleAutomationBreakpointDrag(
                context: context,
                point: point,
                snapshot: snapshot,
                modifiers: modifiers
            )

        case let .draggingTrackAutomationBreakpoint(context):
            return handleTrackAutomationBreakpointDrag(
                context: context,
                point: point,
                snapshot: snapshot,
                modifiers: modifiers
            )

        case let .drawingAutomationShape(context):
            return previewAutomationShape(
                context: context,
                endPoint: point,
                snapshot: snapshot
            )

        case let .drawingTrackAutomationShape(context):
            return previewTrackAutomationShape(
                context: context,
                endPoint: point,
                snapshot: snapshot
            )

        case .selectingRange:
            return false

        case .idle:
            return false
        }
    }

    public func handleMouseUp(
        point: CGPoint,
        snapshot: PlaybackGridSnapshot,
        modifiers: NSEvent.ModifierFlags = []
    ) {
        PlaybackGridPerfLogger.bump("interaction.mouseUp")
        switch state {
        case let .selectingRange(startBar, startPoint):
            let endBar = barForX(point.x, pixelsPerBar: snapshot.pixelsPerBar, totalBars: snapshot.totalBars)
            let dragDistance = abs(point.x - startPoint.x)
            if dragDistance < 3 {
                sink?.clearRangeSelection()
                sink?.setPlayhead(bar: snappedBarForX(point.x, snapshot: snapshot))
            } else if startBar != endBar {
                sink?.selectRange(min(startBar, endBar)...max(startBar, endBar))
            }

        case .scrubbingRuler:
            sink?.setPlayhead(bar: snappedBarForX(point.x, snapshot: snapshot))

        case .draggingContainer:
            if case let .draggingContainer(context) = state,
               context.kind == .clone {
                let deltaX = point.x - context.startPoint.x
                let deltaBars = Double(deltaX / snapshot.pixelsPerBar)
                let target = max(1.0, context.originStartBar + deltaBars)
                let snapped = snapToGrid(target, snapshot: snapshot)
                sink?.cloneContainer(context.containerID, trackID: context.trackID, newStartBar: snapped)
            }

        case let .draggingMIDINote(context):
            handleMIDINoteDrag(
                context: context,
                point: point,
                snapshot: snapshot,
                modifiers: modifiers,
                forceEmit: true
            )
            log("midi drag end")
            stopMIDIPreviewIfNeeded()
            break

        case let .resizingMIDILane(context):
            let deltaY = point.y - context.startPoint.y
            let proposed = context.originHeight + deltaY
            let clamped = min(max(proposed, 120), 640)
            sink?.setInlineMIDILaneHeight(trackID: context.trackID, height: clamped)

        case let .draggingAutomationBreakpoint(context):
            _ = handleAutomationBreakpointDrag(
                context: context,
                point: point,
                snapshot: snapshot,
                modifiers: modifiers,
                forceEmit: true
            )
            log("automation drag end")
            break

        case let .draggingTrackAutomationBreakpoint(context):
            _ = handleTrackAutomationBreakpointDrag(
                context: context,
                point: point,
                snapshot: snapshot,
                modifiers: modifiers,
                forceEmit: true
            )
            log("automation track drag end")
            break

        case let .creatingContainer(context):
            if context.didDrag {
                commitDraggedContainerCreation(context: context, point: point, snapshot: snapshot)
            }

        case let .creatingMIDINote(context):
            commitMIDINoteCreation(context: context, point: point, snapshot: snapshot)
            stopMIDIPreviewIfNeeded()

        case let .drawingAutomationShape(context):
            applyAutomationShape(context: context, endPoint: point, snapshot: snapshot)

        case let .drawingTrackAutomationShape(context):
            applyTrackAutomationShape(context: context, endPoint: point, snapshot: snapshot)

        case .idle:
            break
        }

        pendingMIDINoteUpdates.removeAll(keepingCapacity: true)
        pendingAutomationBreakpointUpdates.removeAll(keepingCapacity: true)
        pendingTrackAutomationBreakpointUpdates.removeAll(keepingCapacity: true)
        automationDidEmitDuringDrag.removeAll(keepingCapacity: true)
        trackAutomationDidEmitDuringDrag.removeAll(keepingCapacity: true)
        midiGhostOverlay = nil
        midiLiveOverlay = nil
        automationGhostOverlay = nil
        automationLiveOverlay = nil
        automationShapeGhostOverlay = nil
        automationShapeLiveOverlay = nil
        state = .idle
    }

    private func barForX(_ x: CGFloat, pixelsPerBar: CGFloat, totalBars: Int) -> Int {
        max(1, min(Int(x / max(pixelsPerBar, 1)) + 1, totalBars))
    }

    private func snapToGrid(_ bar: Double, snapshot: PlaybackGridSnapshot) -> Double {
        guard snapshot.isSnapEnabled else {
            let clamped = max(bar, 1.0)
            log(
                "snap disabled inBar=\(format(bar)) outBar=\(format(clamped))",
                category: "snap",
                minInterval: 0.35
            )
            return clamped
        }

        let resolution = effectiveSnapResolution(snapshot: snapshot)
        let beatsPerBar = Double(snapshot.timeSignature.beatsPerBar)
        let totalBeats = (bar - 1.0) * beatsPerBar
        let snappedBeats = resolution.snap(totalBeats)
        let snappedBar = max((snappedBeats / beatsPerBar) + 1.0, 1.0)
        log(
            "snap resolution=\(resolution) inBar=\(format(bar)) outBar=\(format(snappedBar))",
            category: "snap",
            minInterval: 0.35
        )
        return snappedBar
    }

    private func effectiveSnapResolution(snapshot: PlaybackGridSnapshot) -> SnapResolution {
        switch snapshot.gridMode {
        case .fixed(let resolution):
            return resolution
        case .adaptive:
            let ppBeat = snapshot.pixelsPerBar / CGFloat(snapshot.timeSignature.beatsPerBar)
            if ppBeat >= 150 { return .thirtySecond }
            if ppBeat >= 80 { return .sixteenth }
            if ppBeat >= 40 { return .quarter }
            return .whole
        }
    }

    private func snapFadeDuration(_ durationBars: Double, snapshot: PlaybackGridSnapshot) -> Double {
        guard snapshot.isSnapEnabled else { return max(durationBars, 0) }

        let resolution = effectiveSnapResolution(snapshot: snapshot)
        let beatsPerBar = Double(snapshot.timeSignature.beatsPerBar)
        let snappedBeats = resolution.snap(durationBars * beatsPerBar)
        return max(snappedBeats / beatsPerBar, 0)
    }

    private func snappedBarForX(_ x: CGFloat, snapshot: PlaybackGridSnapshot) -> Double {
        let rawBar = (Double(max(0, x)) / Double(snapshot.pixelsPerBar)) + 1.0
        return snapToGrid(rawBar, snapshot: snapshot)
    }

    private func container(containerID: ID<Container>, in tracks: [Track]) -> Container? {
        for track in tracks {
            if let container = track.containers.first(where: { $0.id == containerID }) {
                return container
            }
        }
        return nil
    }

    private func containerAndTrack(
        containerID: ID<Container>,
        trackID: ID<Track>,
        in tracks: [Track]
    ) -> (Track, Container)? {
        guard let track = tracks.first(where: { $0.id == trackID }),
              let container = track.containers.first(where: { $0.id == containerID }) else {
            return nil
        }
        return (track, container)
    }

    private func track(trackID: ID<Track>, in tracks: [Track]) -> Track? {
        tracks.first(where: { $0.id == trackID })
    }

    private func freeSegment(
        containing bar: Double,
        in track: Track,
        totalBars: Int
    ) -> (start: Double, end: Double)? {
        let sorted = track.containers.sorted { $0.startBar < $1.startBar }

        var previousEnd = 1.0
        for container in sorted {
            if bar < container.startBar {
                return (start: previousEnd, end: container.startBar)
            }
            if bar >= container.startBar && bar < container.endBar {
                return nil
            }
            previousEnd = max(previousEnd, container.endBar)
        }

        let timelineEnd = max(Double(totalBars) + 1.0, previousEnd + 1.0)
        return (start: previousEnd, end: timelineEnd)
    }

    private func shouldBeginMIDINoteCreate(
        event: NSEvent,
        zone: GridContainerZone?,
        track: Track,
        containerID: ID<Container>,
        trackID: ID<Track>,
        point: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) -> Bool {
        guard track.kind == .midi else { return false }
        guard event.clickCount == 1 else { return false }
        guard zone == .move else { return false }
        let blockedMods: NSEvent.ModifierFlags = [.option, .command, .control]
        guard event.modifierFlags.intersection(blockedMods).isEmpty else { return false }
        guard let baseRect = containerRect(containerID: containerID, trackID: trackID, snapshot: snapshot) else {
            return false
        }
        let pitchRect = midiPitchRect(baseRect: baseRect, trackID: trackID, snapshot: snapshot)
        if pitchRect.maxY > baseRect.maxY {
            // Inline MIDI lane enabled: use the dedicated lane below the clip.
            return point.y >= baseRect.maxY && point.y <= pitchRect.maxY
        }

        // No inline lane: keep top portion available for container-level gestures.
        let drawThresholdY = baseRect.minY + baseRect.height * 0.45
        return point.y >= drawThresholdY && point.y <= baseRect.maxY
    }

    private func beginInlineMIDILaneResizeIfNeeded(
        event: NSEvent,
        point: CGPoint,
        snapshot: PlaybackGridSnapshot,
        preferredTrackID: ID<Track>?
    ) -> Bool {
        guard event.clickCount == 1 else { return false }
        let blockedMods: NSEvent.ModifierFlags = [.option, .command, .control]
        guard event.modifierFlags.intersection(blockedMods).isEmpty else { return false }
        guard let hit = inlineMIDILaneResizeHit(
            point: point,
            snapshot: snapshot,
            preferredTrackID: preferredTrackID
        ) else { return false }

        state = .resizingMIDILane(context: PlaybackGridMIDILaneResizeContext(
            trackID: hit.trackID,
            startPoint: point,
            originHeight: hit.height
        ))
        return true
    }

    private func inlineMIDILaneResizeHit(
        point: CGPoint,
        snapshot: PlaybackGridSnapshot,
        preferredTrackID: ID<Track>?
    ) -> (trackID: ID<Track>, height: CGFloat)? {
        var yOffset: CGFloat = snapshot.showRulerAndSections ? PlaybackGridLayout.trackAreaTop : 0
        let hitPadding: CGFloat = 10

        for track in snapshot.tracks {
            let baseHeight = snapshot.trackHeights[track.id] ?? snapshot.defaultTrackHeight
            let automationExtra = automationTrackExtraHeight(track: track, snapshot: snapshot)
            let inlineHeight = snapshot.inlineMIDILaneHeights[track.id] ?? 0
            defer { yOffset += baseHeight + automationExtra + inlineHeight }
            guard track.kind == .midi, inlineHeight > 0 else { continue }
            if let preferredTrackID, preferredTrackID != track.id { continue }

            let laneBottomY = yOffset + baseHeight + automationExtra + inlineHeight
            if point.y >= laneBottomY - hitPadding && point.y <= laneBottomY + hitPadding {
                return (trackID: track.id, height: inlineHeight)
            }
        }
        return nil
    }

    private func containerRect(
        containerID: ID<Container>,
        trackID: ID<Track>,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect? {
        var yOffset: CGFloat = snapshot.showRulerAndSections ? PlaybackGridLayout.trackAreaTop : 0
        for track in snapshot.tracks {
            let baseHeight = snapshot.trackHeights[track.id] ?? snapshot.defaultTrackHeight
            let automationExtra = automationTrackExtraHeight(track: track, snapshot: snapshot)
            let inlineMIDILaneHeight = snapshot.inlineMIDILaneHeights[track.id] ?? 0
            defer { yOffset += baseHeight + automationExtra + inlineMIDILaneHeight }
            guard track.id == trackID else { continue }
            guard let container = track.containers.first(where: { $0.id == containerID }) else { return nil }
            let x = CGFloat(container.startBar - 1.0) * snapshot.pixelsPerBar
            let width = CGFloat(container.lengthBars) * snapshot.pixelsPerBar
            return CGRect(x: x, y: yOffset, width: width, height: baseHeight)
        }
        return nil
    }

    private func beginMIDINoteCreateFromTrackBackground(
        event: NSEvent,
        point: CGPoint,
        snapshot: PlaybackGridSnapshot,
        preferredTrackID: ID<Track>?
    ) -> Bool {
        guard event.clickCount == 1 else { return false }
        let blockedMods: NSEvent.ModifierFlags = [.option, .command, .control]
        guard event.modifierFlags.intersection(blockedMods).isEmpty else { return false }
        guard let target = resolveMIDINoteCreateTarget(
            point: point,
            snapshot: snapshot,
            preferredTrackID: preferredTrackID
        ),
        let baseRect = containerRect(
            containerID: target.container.id,
            trackID: target.track.id,
            snapshot: snapshot
        ) else {
            log("midi create skipped source=track-bg reason=no-target", category: "midi", minInterval: 0.2)
            return false
        }

        let pitchRect = midiPitchRect(
            baseRect: baseRect,
            trackID: target.track.id,
            snapshot: snapshot
        )
        let startBeat = beatOffsetForPointX(
            point.x,
            container: target.container,
            snapshot: snapshot,
            snapMode: .nearest
        )
        let pitch = midiPitchForPointY(
            point.y,
            rect: pitchRect,
            container: target.container,
            trackID: target.track.id,
            snapshot: snapshot
        )
        state = .creatingMIDINote(context: PlaybackGridMIDINoteCreateContext(
            containerID: target.container.id,
            trackID: target.track.id,
            startPoint: point,
            startBeat: startBeat,
            pitch: pitch,
            provisionalNoteID: nil
        ))
        previewMIDIPitchIfNeeded(pitch)
        log("midi create armed container=\(target.container.id.rawValue) startBeat=\(format(startBeat)) pitch=\(pitch) source=track-bg")
        return true
    }

    private func resolveMIDINoteCreateTarget(
        point: CGPoint,
        snapshot: PlaybackGridSnapshot,
        preferredTrackID: ID<Track>?
    ) -> (track: Track, container: Container)? {
        let bar = (Double(max(0, point.x)) / Double(snapshot.pixelsPerBar)) + 1.0

        func containerForTrack(_ track: Track) -> Container? {
            guard track.kind == .midi else { return nil }
            let candidates = track.containers.filter { container in
                bar >= container.startBar && bar <= container.endBar
            }
            let laneCandidates = candidates.filter { container in
                guard let baseRect = containerRect(
                    containerID: container.id,
                    trackID: track.id,
                    snapshot: snapshot
                ) else { return false }
                let pitchRect = midiPitchRect(baseRect: baseRect, trackID: track.id, snapshot: snapshot)
                return pitchRect.contains(point)
            }
            guard !laneCandidates.isEmpty else { return nil }
            if let selected = laneCandidates.first(where: { snapshot.selectedContainerIDs.contains($0.id) }) {
                return selected
            }
            return laneCandidates.first
        }

        if let preferredTrackID,
           let preferredTrack = track(trackID: preferredTrackID, in: snapshot.tracks),
           let preferredContainer = containerForTrack(preferredTrack) {
            return (preferredTrack, preferredContainer)
        }

        for track in snapshot.tracks where track.kind == .midi {
            if let container = containerForTrack(track) {
                return (track, container)
            }
        }
        return nil
    }

    private func midiPitchRect(
        baseRect: CGRect,
        trackID: ID<Track>,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect {
        let inlineHeight = snapshot.inlineMIDILaneHeights[trackID] ?? 0
        guard inlineHeight > 0 else { return baseRect }
        let automationExtra = automationTrackExtraHeight(trackID: trackID, snapshot: snapshot)
        return CGRect(
            x: baseRect.minX,
            y: baseRect.maxY + automationExtra,
            width: baseRect.width,
            height: inlineHeight
        )
    }

    private func isPointInInlineMIDILane(
        _ point: CGPoint,
        trackID: ID<Track>,
        snapshot: PlaybackGridSnapshot
    ) -> Bool {
        guard let laneRect = inlineMIDILaneRect(trackID: trackID, snapshot: snapshot) else {
            return false
        }
        return laneRect.contains(point)
    }

    private func inlineMIDILaneRect(
        trackID: ID<Track>,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect? {
        var yOffset: CGFloat = snapshot.showRulerAndSections ? PlaybackGridLayout.trackAreaTop : 0
        for track in snapshot.tracks {
            let baseHeight = snapshot.trackHeights[track.id] ?? snapshot.defaultTrackHeight
            let automationExtra = automationTrackExtraHeight(track: track, snapshot: snapshot)
            let inlineHeight = snapshot.inlineMIDILaneHeights[track.id] ?? 0
            defer { yOffset += baseHeight + automationExtra + inlineHeight }
            guard track.id == trackID else { continue }
            guard inlineHeight > 0 else { return nil }
            return CGRect(
                x: 0,
                y: yOffset + baseHeight + automationExtra,
                width: CGFloat(snapshot.totalBars) * snapshot.pixelsPerBar,
                height: inlineHeight
            )
        }
        return nil
    }

    private func automationTrackExtraHeight(trackID: ID<Track>, snapshot: PlaybackGridSnapshot) -> CGFloat {
        guard let track = track(trackID: trackID, in: snapshot.tracks) else { return 0 }
        return automationTrackExtraHeight(track: track, snapshot: snapshot)
    }

    private func automationTrackExtraHeight(track: Track, snapshot: PlaybackGridSnapshot) -> CGFloat {
        guard snapshot.automationExpandedTrackIDs.contains(track.id) else { return 0 }
        let laneCount = automationLanePaths(for: track).count
        guard laneCount > 0 else { return 0 }
        return snapshot.automationToolbarHeight + (CGFloat(laneCount) * snapshot.automationSubLaneHeight)
    }

    private func automationLanePaths(for track: Track) -> [EffectPath] {
        var seen = Set<EffectPath>()
        var ordered: [EffectPath] = []
        for lane in track.trackAutomationLanes {
            if seen.insert(lane.targetPath).inserted {
                ordered.append(lane.targetPath)
            }
        }
        for container in track.containers {
            for lane in container.automationLanes {
                if seen.insert(lane.targetPath).inserted {
                    ordered.append(lane.targetPath)
                }
            }
        }
        return ordered
    }

    private func dragKindForZone(_ zone: GridContainerZone?) -> PlaybackGridContainerDragKind? {
        switch zone {
        case .move, .selector:
            return .move
        case .resizeLeft:
            return .resizeLeft
        case .resizeRight:
            return .resizeRight
        case .trimLeft:
            return .trimLeft
        case .trimRight:
            return .trimRight
        case .fadeLeft:
            return .fadeLeft
        case .fadeRight:
            return .fadeRight
        case .none:
            return nil
        }
    }

    private func handleContainerDrag(
        context: PlaybackGridContainerDragContext,
        point: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) {
        let deltaX = point.x - context.startPoint.x
        let deltaBars = Double(deltaX / snapshot.pixelsPerBar)

        switch context.kind {
        case .move:
            let target = max(1.0, context.originStartBar + deltaBars)
            let snapped = snapToGrid(target, snapshot: snapshot)
            sink?.moveContainer(context.containerID, trackID: context.trackID, newStartBar: snapped)

        case .clone:
            break

        case .resizeLeft:
            var newStart = context.originStartBar + deltaBars
            var newLength = context.originLengthBars - deltaBars
            if newLength < 1.0 {
                newLength = 1.0
                newStart = context.originStartBar + (context.originLengthBars - 1.0)
            }
            newStart = max(1.0, newStart)
            newStart = snapToGrid(newStart, snapshot: snapshot)
            newLength = max(1.0, (context.originStartBar + context.originLengthBars) - newStart)
            sink?.resizeContainerLeft(context.containerID, trackID: context.trackID, newStartBar: newStart, newLengthBars: newLength)

        case .resizeRight:
            var newLength = context.originLengthBars + deltaBars
            newLength = max(1.0, newLength)
            let snappedEnd = snapToGrid(context.originStartBar + newLength, snapshot: snapshot)
            newLength = max(1.0, snappedEnd - context.originStartBar)
            sink?.resizeContainerRight(context.containerID, trackID: context.trackID, newLengthBars: newLength)

        case .trimLeft:
            var newStart = context.originStartBar + deltaBars
            var newLength = context.originLengthBars - deltaBars
            var newOffset = context.originAudioStartOffset + deltaBars

            if newLength < 1.0 {
                let adjust = 1.0 - newLength
                newLength = 1.0
                newStart -= adjust
                newOffset += adjust
            }

            if newStart < 1.0 {
                let adjust = 1.0 - newStart
                newStart = 1.0
                newLength -= adjust
                newOffset -= adjust
            }

            newOffset = max(0.0, newOffset)
            newStart = snapToGrid(newStart, snapshot: snapshot)
            newLength = max(1.0, (context.originStartBar + context.originLengthBars) - newStart)

            sink?.trimContainerLeft(
                context.containerID,
                trackID: context.trackID,
                newAudioStartOffset: newOffset,
                newStartBar: newStart,
                newLengthBars: newLength
            )

        case .trimRight:
            var newLength = context.originLengthBars + deltaBars
            newLength = max(1.0, newLength)
            let snappedEnd = snapToGrid(context.originStartBar + newLength, snapshot: snapshot)
            newLength = max(1.0, snappedEnd - context.originStartBar)
            sink?.trimContainerRight(context.containerID, trackID: context.trackID, newLengthBars: newLength)

        case .fadeLeft:
            let rawDuration = context.originEnterFadeDuration + deltaBars
            let clamped = max(0.0, min(context.originLengthBars, rawDuration))
            let snapped = snapFadeDuration(clamped, snapshot: snapshot)
            let fade = snapped < 0.125 ? nil : FadeSettings(duration: snapped, curve: context.originEnterFadeCurve)
            sink?.setContainerEnterFade(context.containerID, fade: fade)

        case .fadeRight:
            let rawDuration = context.originExitFadeDuration - deltaBars
            let clamped = max(0.0, min(context.originLengthBars, rawDuration))
            let snapped = snapFadeDuration(clamped, snapshot: snapshot)
            let fade = snapped < 0.125 ? nil : FadeSettings(duration: snapped, curve: context.originExitFadeCurve)
            sink?.setContainerExitFade(context.containerID, fade: fade)
        }
    }

    @discardableResult
    private func handleMIDINoteDrag(
        context: PlaybackGridMIDINoteDragContext,
        point: CGPoint,
        snapshot: PlaybackGridSnapshot,
        modifiers: NSEvent.ModifierFlags,
        forceEmit: Bool = false
    ) -> Bool {
        let previousLive = midiLiveOverlay
        let beatsPerBar = Double(snapshot.timeSignature.beatsPerBar)
        let deltaX = point.x - context.startPoint.x
        let deltaBars = Double(deltaX / snapshot.pixelsPerBar)
        let deltaBeatsRaw = deltaBars * beatsPerBar

        let shouldSnap = snapshot.isSnapEnabled != modifiers.contains(.command)
        let deltaBeats: Double
        if shouldSnap {
            let unit = effectiveSnapResolution(snapshot: snapshot).beatsPerUnit
            deltaBeats = (deltaBeatsRaw / unit).rounded() * unit
        } else {
            deltaBeats = deltaBeatsRaw
        }

        var updated = context.originalNote
        let minimumDuration = shouldSnap
            ? effectiveSnapResolution(snapshot: snapshot).beatsPerUnit
            : (1.0 / 64.0)
        let containerTotalBeats = context.containerLengthBars * beatsPerBar

        switch context.kind {
        case .move:
            let maxStartBeat = max(0, containerTotalBeats - context.originalNote.duration)
            updated.startBeat = max(0, min(maxStartBeat, context.originalNote.startBeat + deltaBeats))

            let pitchStep = max(1, midiPitchStepHeight(
                containerID: context.containerID,
                trackID: context.trackID,
                snapshot: snapshot
            ))
            let deltaYPixels = context.startPoint.y - point.y
            let pitchDelta = Int((deltaYPixels / pitchStep).rounded())
            let unclampedPitch = Int(context.originalNote.pitch) + pitchDelta
            let pitchRange = midiPitchClampRange(
                containerID: context.containerID,
                trackID: context.trackID,
                snapshot: snapshot
            )
            let newPitch = max(pitchRange.low, min(pitchRange.high, unclampedPitch))
            updated.pitch = UInt8(clamping: newPitch)
            previewMIDIPitchIfNeeded(updated.pitch)

        case .resizeRight:
            let originalEnd = context.originalNote.startBeat + context.originalNote.duration
            var newEnd = originalEnd + deltaBeats
            newEnd = max(context.originalNote.startBeat + minimumDuration, newEnd)
            newEnd = min(containerTotalBeats, newEnd)
            updated.duration = max(minimumDuration, newEnd - context.originalNote.startBeat)

        case .resizeLeft:
            let originalEnd = context.originalNote.startBeat + context.originalNote.duration
            var newStart = context.originalNote.startBeat + deltaBeats
            newStart = min(newStart, originalEnd - minimumDuration)
            newStart = max(0, newStart)
            updated.startBeat = newStart
            updated.duration = max(minimumDuration, originalEnd - newStart)
        }

        pendingMIDINoteUpdates[context.noteID] = (
            containerID: context.containerID,
            note: updated
        )
        if forceEmit {
            flushPendingMIDINoteUpdate(
                noteID: context.noteID,
                originalNote: context.originalNote
            )
        } else {
            PlaybackGridPerfLogger.bump("interaction.midiEmit.bufferedUntilMouseUp")
        }
        midiLiveOverlay = PlaybackGridMIDINoteOverlay(
            containerID: context.containerID,
            trackID: context.trackID,
            note: updated,
            isGhost: false
        )
        let didChangeVisual = previousLive?.note != updated || previousLive?.trackID != context.trackID || previousLive?.containerID != context.containerID
        if !didChangeVisual {
            PlaybackGridPerfLogger.bump("interaction.midiVisual.unchanged")
        }
        return didChangeVisual || forceEmit
    }

    private func beatOffsetForPointX(
        _ x: CGFloat,
        container: Container,
        snapshot: PlaybackGridSnapshot,
        snapMode: BeatSnapMode = .nearest
    ) -> Double {
        let beatsPerBar = Double(snapshot.timeSignature.beatsPerBar)
        let rawOffsetBars = Double(x / snapshot.pixelsPerBar) - (container.startBar - 1.0)
        let rawOffsetBeats = max(0, min(container.lengthBars * beatsPerBar, rawOffsetBars * beatsPerBar))

        guard snapshot.isSnapEnabled, snapMode != .none else {
            return rawOffsetBeats
        }

        let unit = effectiveSnapResolution(snapshot: snapshot).beatsPerUnit
        let snappedBeats: Double
        switch snapMode {
        case .none:
            snappedBeats = rawOffsetBeats
        case .nearest:
            snappedBeats = (rawOffsetBeats / unit).rounded() * unit
        case .floor:
            snappedBeats = floor(rawOffsetBeats / unit) * unit
        case .ceil:
            snappedBeats = ceil(rawOffsetBeats / unit) * unit
        }
        return max(0, min(container.lengthBars * beatsPerBar, snappedBeats))
    }

    private func midiPitchForPointY(
        _ y: CGFloat,
        rect: CGRect,
        container: Container,
        trackID: ID<Track>,
        snapshot: PlaybackGridSnapshot
    ) -> UInt8 {
        _ = container
        let resolved = resolvedMIDILayout(
            trackID: trackID,
            laneHeight: rect.height,
            snapshot: snapshot
        )
        let low = Int(resolved.lowPitch)
        let high = Int(resolved.highPitch)
        let rows = max(resolved.rows, 1)
        let rowHeight = max(resolved.rowHeight, 1)
        let clampedY = max(rect.minY, min(rect.maxY - 0.001, y))
        let rowFromTop = Int(floor((clampedY - rect.minY) / rowHeight))
        let clampedRow = max(0, min(rows - 1, rowFromTop))
        let pitch = high - clampedRow
        return UInt8(clamping: max(low, min(high, pitch)))
    }

    private func previewMIDINoteCreation(
        context: PlaybackGridMIDINoteCreateContext,
        point: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) {
        guard let (_, container) = containerAndTrack(
            containerID: context.containerID,
            trackID: context.trackID,
            in: snapshot.tracks
        ) else {
            return
        }
        var updatedContext = context
        var note = midiNoteDraft(context: updatedContext, point: point, snapshot: snapshot, container: container)
        if let provisionalID = updatedContext.provisionalNoteID {
            note.id = provisionalID
        } else {
            updatedContext.provisionalNoteID = note.id
            log("midi create preview container=\(updatedContext.containerID.rawValue) note=\(note.id.rawValue)", category: "midi", minInterval: 0.2)
        }
        PlaybackGridPerfLogger.bump("interaction.midiCreate.preview")
        midiLiveOverlay = PlaybackGridMIDINoteOverlay(
            containerID: updatedContext.containerID,
            trackID: updatedContext.trackID,
            note: note,
            isGhost: false
        )
        state = .creatingMIDINote(context: updatedContext)
    }

    private func midiNoteDraft(
        context: PlaybackGridMIDINoteCreateContext,
        point: CGPoint,
        snapshot: PlaybackGridSnapshot,
        container: Container
    ) -> MIDINoteEvent {
        let endSnapMode: BeatSnapMode = point.x >= context.startPoint.x ? .ceil : .floor
        let endBeat = beatOffsetForPointX(
            point.x,
            container: container,
            snapshot: snapshot,
            snapMode: endSnapMode
        )
        let minBeat = min(context.startBeat, endBeat)
        let maxBeat = max(context.startBeat, endBeat)
        let minimumDuration = snapshot.isSnapEnabled
            ? effectiveSnapResolution(snapshot: snapshot).beatsPerUnit
            : (1.0 / 64.0)
        let duration = max(minimumDuration, maxBeat - minBeat)
        let totalBeats = container.lengthBars * Double(snapshot.timeSignature.beatsPerBar)
        let clampedStart = max(0, min(totalBeats - minimumDuration, minBeat))
        let clampedDuration = max(minimumDuration, min(duration, totalBeats - clampedStart))

        return MIDINoteEvent(
            pitch: context.pitch,
            velocity: 100,
            startBeat: clampedStart,
            duration: clampedDuration
        )
    }

    private func midiPitchStepHeight(
        containerID: ID<Container>,
        trackID: ID<Track>,
        snapshot: PlaybackGridSnapshot
    ) -> CGFloat {
        if let config = snapshot.inlineMIDIConfigs[trackID], let rowHeight = config.rowHeight, rowHeight > 0 {
            return rowHeight
        }
        guard let baseRect = containerRect(containerID: containerID, trackID: trackID, snapshot: snapshot) else {
            return 8
        }
        let pitchRect = midiPitchRect(baseRect: baseRect, trackID: trackID, snapshot: snapshot)
        let resolved = resolvedMIDILayout(
            trackID: trackID,
            laneHeight: pitchRect.height,
            snapshot: snapshot
        )
        return max(2, resolved.rowHeight)
    }

    private func midiPitchClampRange(
        containerID: ID<Container>,
        trackID: ID<Track>,
        snapshot: PlaybackGridSnapshot
    ) -> (low: Int, high: Int) {
        guard let baseRect = containerRect(containerID: containerID, trackID: trackID, snapshot: snapshot) else {
            return (low: 0, high: 127)
        }
        let pitchRect = midiPitchRect(baseRect: baseRect, trackID: trackID, snapshot: snapshot)
        let resolved = resolvedMIDILayout(
            trackID: trackID,
            laneHeight: pitchRect.height,
            snapshot: snapshot
        )
        return (low: Int(resolved.lowPitch), high: Int(resolved.highPitch))
    }

    private func resolvedMIDILayout(
        trackID: ID<Track>,
        laneHeight: CGFloat,
        snapshot: PlaybackGridSnapshot
    ) -> PlaybackGridMIDIResolvedLayout {
        guard let track = track(trackID: trackID, in: snapshot.tracks) else {
            return PlaybackGridMIDIViewResolver.resolveLayout(
                notes: [],
                trackID: trackID,
                laneHeight: laneHeight,
                snapshot: snapshot
            )
        }
        return PlaybackGridMIDIViewResolver.resolveTrackLayout(
            track: track,
            laneHeight: laneHeight,
            snapshot: snapshot
        )
    }

    private func midiDragKind(for zone: GridContainerZone?) -> PlaybackGridMIDINoteDragKind {
        switch zone {
        case .resizeLeft: return .resizeLeft
        case .resizeRight: return .resizeRight
        default: return .move
        }
    }

    private enum BeatSnapMode {
        case none
        case nearest
        case floor
        case ceil
    }

    private func commitMIDINoteCreation(
        context: PlaybackGridMIDINoteCreateContext,
        point: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) {
        guard let (_, container) = containerAndTrack(
            containerID: context.containerID,
            trackID: context.trackID,
            in: snapshot.tracks
        ) else {
            return
        }

        var note = midiNoteDraft(context: context, point: point, snapshot: snapshot, container: container)
        if let provisionalID = context.provisionalNoteID {
            note.id = provisionalID
        }
        sink?.addMIDINote(context.containerID, note: note)
        PlaybackGridPerfLogger.bump("interaction.midiCreate.committed")
        midiLiveOverlay = PlaybackGridMIDINoteOverlay(
            containerID: context.containerID,
            trackID: context.trackID,
            note: note,
            isGhost: false
        )
        log("midi create commit container=\(context.containerID.rawValue) startBeat=\(format(note.startBeat)) duration=\(format(note.duration)) pitch=\(note.pitch)")
    }

    private func flushPendingMIDINoteUpdate(
        noteID: ID<MIDINoteEvent>,
        originalNote: MIDINoteEvent
    ) {
        PlaybackGridPerfLogger.bump("interaction.midiEmit.attempt")
        guard let pending = pendingMIDINoteUpdates[noteID] else {
            PlaybackGridPerfLogger.bump("interaction.midiEmit.missingPending")
            return
        }
        defer { pendingMIDINoteUpdates.removeValue(forKey: noteID) }
        if pending.note == originalNote {
            PlaybackGridPerfLogger.bump("interaction.midiEmit.unchanged")
            return
        }
        let sinkUpdateStart = PlaybackGridPerfLogger.begin()
        sink?.updateMIDINote(pending.containerID, note: pending.note)
        PlaybackGridPerfLogger.end("interaction.midiEmit.sinkUpdate.ms", sinkUpdateStart)
        PlaybackGridPerfLogger.bump("interaction.midiEmit.sent")
    }

    private func flushPendingAutomationBreakpointUpdate(
        key: ContainerAutomationPendingKey,
        originalBreakpoint: AutomationBreakpoint
    ) {
        PlaybackGridPerfLogger.bump("interaction.automationEmit.attempt")
        guard let pending = pendingAutomationBreakpointUpdates[key] else {
            PlaybackGridPerfLogger.bump("interaction.automationEmit.missingPending")
            return
        }
        defer { pendingAutomationBreakpointUpdates.removeValue(forKey: key) }
        if pending == originalBreakpoint {
            PlaybackGridPerfLogger.bump("interaction.automationEmit.unchanged")
            return
        }
        let sinkUpdateStart = PlaybackGridPerfLogger.begin()
        sink?.updateAutomationBreakpoint(key.containerID, laneID: key.laneID, breakpoint: pending)
        PlaybackGridPerfLogger.end("interaction.automationEmit.sinkUpdate.ms", sinkUpdateStart)
        PlaybackGridPerfLogger.bump("interaction.automationEmit.sent")
    }

    private func flushPendingTrackAutomationBreakpointUpdate(
        key: TrackAutomationPendingKey,
        originalBreakpoint: AutomationBreakpoint
    ) {
        PlaybackGridPerfLogger.bump("interaction.automationEmit.attempt")
        guard let pending = pendingTrackAutomationBreakpointUpdates[key] else {
            PlaybackGridPerfLogger.bump("interaction.automationEmit.missingPending")
            return
        }
        defer { pendingTrackAutomationBreakpointUpdates.removeValue(forKey: key) }
        if pending == originalBreakpoint {
            PlaybackGridPerfLogger.bump("interaction.automationEmit.unchanged")
            return
        }
        let sinkUpdateStart = PlaybackGridPerfLogger.begin()
        sink?.updateTrackAutomationBreakpoint(trackID: key.trackID, laneID: key.laneID, breakpoint: pending)
        PlaybackGridPerfLogger.end("interaction.automationEmit.sinkUpdate.ms", sinkUpdateStart)
        PlaybackGridPerfLogger.bump("interaction.automationEmit.sent")
    }

    private func handleAutomationBreakpointDrag(
        context: PlaybackGridAutomationBreakpointDragContext,
        point: CGPoint,
        snapshot: PlaybackGridSnapshot,
        modifiers: NSEvent.ModifierFlags,
        forceEmit: Bool = false
    ) -> Bool {
        let previousLive = automationLiveOverlay
        guard let (_, container) = containerAndTrack(
            containerID: context.containerID,
            trackID: context.trackID,
            in: snapshot.tracks
        ),
        let rect = containerRect(
            containerID: context.containerID,
            trackID: context.trackID,
            snapshot: snapshot
        ),
        let lane = container.automationLanes.first(where: { $0.id == context.laneID }) else {
            return false
        }
        let existing = lane.breakpoints.first(where: { $0.id == context.breakpointID })
        let laneRect = automationLaneRect(
            container: container,
            trackID: context.trackID,
            laneID: context.laneID,
            containerRect: rect,
            snapshot: snapshot
        )

        let deltaXBars = Double((point.x - context.startPoint.x) / snapshot.pixelsPerBar)
        let effectiveDeltaBars = modifiers.contains(.shift) ? (deltaXBars * 0.2) : deltaXBars
        let rawBarOffset = context.originPosition + effectiveDeltaBars
        let clampedRawOffset = max(0, min(container.lengthBars, rawBarOffset))
        let shouldSnap = snapshot.isSnapEnabled != modifiers.contains(.command)
        let snappedOffset: Double
        if shouldSnap {
            let snappedAbsBar = snapToGrid(container.startBar + clampedRawOffset, snapshot: snapshot)
            snappedOffset = max(0, min(container.lengthBars, snappedAbsBar - container.startBar))
        } else {
            snappedOffset = clampedRawOffset
        }

        let deltaValue = Float((context.startPoint.y - point.y) / max(laneRect.height, 1))
        let scaledDeltaValue = modifiers.contains(.shift) ? (deltaValue * 0.2) : deltaValue
        let value = max(0, min(1, context.originValue + scaledDeltaValue))

        var updated = existing
            ?? AutomationBreakpoint(
                id: context.breakpointID,
                position: context.originPosition,
                value: context.originValue
            )
        updated.position = snappedOffset
        updated.value = value

        let pendingKey = ContainerAutomationPendingKey(
            containerID: context.containerID,
            laneID: context.laneID,
            breakpointID: context.breakpointID
        )
        pendingAutomationBreakpointUpdates[pendingKey] = updated
        if forceEmit {
            flushPendingAutomationBreakpointUpdate(
                key: pendingKey,
                originalBreakpoint: AutomationBreakpoint(
                    id: context.breakpointID,
                    position: context.originPosition,
                    value: context.originValue
                )
            )
            automationDidEmitDuringDrag.remove(pendingKey)
        } else {
            let shouldEmitImmediately = modifiers.contains(.shift) || !automationDidEmitDuringDrag.contains(pendingKey)
            if shouldEmitImmediately {
                automationDidEmitDuringDrag.insert(pendingKey)
                flushPendingAutomationBreakpointUpdate(
                    key: pendingKey,
                    originalBreakpoint: AutomationBreakpoint(
                        id: context.breakpointID,
                        position: context.originPosition,
                        value: context.originValue
                    )
                )
            } else {
                PlaybackGridPerfLogger.bump("interaction.automationEmit.bufferedUntilMouseUp")
            }
        }
        automationLiveOverlay = PlaybackGridAutomationBreakpointOverlay(
            trackID: context.trackID,
            containerID: context.containerID,
            laneID: context.laneID,
            breakpoint: updated,
            laneRect: laneRect,
            isGhost: false
        )
        let didChangeVisual = previousLive?.breakpoint != updated
            || previousLive?.trackID != context.trackID
            || previousLive?.containerID != context.containerID
            || previousLive?.laneID != context.laneID
        if !didChangeVisual {
            PlaybackGridPerfLogger.bump("interaction.automationVisual.unchanged")
        }
        return didChangeVisual || forceEmit
    }

    private func handleTrackAutomationBreakpointDrag(
        context: PlaybackGridTrackAutomationBreakpointDragContext,
        point: CGPoint,
        snapshot: PlaybackGridSnapshot,
        modifiers: NSEvent.ModifierFlags,
        forceEmit: Bool = false
    ) -> Bool {
        let previousLive = automationLiveOverlay
        guard let track = track(trackID: context.trackID, in: snapshot.tracks),
              let lane = track.trackAutomationLanes.first(where: { $0.id == context.laneID }),
              let laneRect = trackAutomationLaneRect(
                trackID: context.trackID,
                laneID: context.laneID,
                snapshot: snapshot
              ) else {
            return false
        }
        let existing = lane.breakpoints.first(where: { $0.id == context.breakpointID })

        let deltaXBars = Double((point.x - context.startPoint.x) / snapshot.pixelsPerBar)
        let effectiveDeltaBars = modifiers.contains(.shift) ? (deltaXBars * 0.2) : deltaXBars
        let rawPosition = context.originPosition + effectiveDeltaBars
        let clampedRawPosition = max(0, min(Double(snapshot.totalBars), rawPosition))
        let shouldSnap = snapshot.isSnapEnabled != modifiers.contains(.command)
        let snappedPosition: Double
        if shouldSnap {
            let snappedBar = snapToGrid(clampedRawPosition + 1.0, snapshot: snapshot)
            snappedPosition = max(0, min(Double(snapshot.totalBars), snappedBar - 1.0))
        } else {
            snappedPosition = clampedRawPosition
        }

        let deltaValue = Float((context.startPoint.y - point.y) / max(laneRect.height, 1))
        let scaledDeltaValue = modifiers.contains(.shift) ? (deltaValue * 0.2) : deltaValue
        let value = max(0, min(1, context.originValue + scaledDeltaValue))

        var updated = existing
            ?? AutomationBreakpoint(
                id: context.breakpointID,
                position: context.originPosition,
                value: context.originValue
            )
        updated.position = snappedPosition
        updated.value = value
        let pendingKey = TrackAutomationPendingKey(
            trackID: context.trackID,
            laneID: context.laneID,
            breakpointID: context.breakpointID
        )
        pendingTrackAutomationBreakpointUpdates[pendingKey] = updated
        if forceEmit {
            flushPendingTrackAutomationBreakpointUpdate(
                key: pendingKey,
                originalBreakpoint: AutomationBreakpoint(
                    id: context.breakpointID,
                    position: context.originPosition,
                    value: context.originValue
                )
            )
            trackAutomationDidEmitDuringDrag.remove(pendingKey)
        } else {
            let shouldEmitImmediately = modifiers.contains(.shift) || !trackAutomationDidEmitDuringDrag.contains(pendingKey)
            if shouldEmitImmediately {
                trackAutomationDidEmitDuringDrag.insert(pendingKey)
                flushPendingTrackAutomationBreakpointUpdate(
                    key: pendingKey,
                    originalBreakpoint: AutomationBreakpoint(
                        id: context.breakpointID,
                        position: context.originPosition,
                        value: context.originValue
                    )
                )
            } else {
                PlaybackGridPerfLogger.bump("interaction.automationEmit.bufferedUntilMouseUp")
            }
        }
        automationLiveOverlay = PlaybackGridAutomationBreakpointOverlay(
            trackID: context.trackID,
            containerID: nil,
            laneID: context.laneID,
            breakpoint: updated,
            laneRect: laneRect,
            isGhost: false
        )
        let didChangeVisual = previousLive?.breakpoint != updated
            || previousLive?.trackID != context.trackID
            || previousLive?.containerID != nil
            || previousLive?.laneID != context.laneID
        if !didChangeVisual {
            PlaybackGridPerfLogger.bump("interaction.automationVisual.unchanged")
        }
        return didChangeVisual || forceEmit
    }

    private func makeAutomationBreakpoint(
        containerID: ID<Container>,
        trackID: ID<Track>,
        laneID: ID<AutomationLane>,
        point: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) -> AutomationBreakpoint? {
        guard let (_, container) = containerAndTrack(containerID: containerID, trackID: trackID, in: snapshot.tracks),
              let rect = containerRect(containerID: containerID, trackID: trackID, snapshot: snapshot) else {
            return nil
        }
        let laneRect = automationLaneRect(
            container: container,
            trackID: trackID,
            laneID: laneID,
            containerRect: rect,
            snapshot: snapshot
        )

        let rawBarOffset = Double((point.x - rect.minX) / snapshot.pixelsPerBar)
        let clampedOffset = max(0, min(container.lengthBars, rawBarOffset))
        let snappedBar = snapToGrid(container.startBar + clampedOffset, snapshot: snapshot)
        let snappedOffset = max(0, min(container.lengthBars, snappedBar - container.startBar))

        let rawValue = 1.0 - ((point.y - laneRect.minY) / max(laneRect.height, 1))
        let value = Float(max(0, min(1, rawValue)))
        return AutomationBreakpoint(position: snappedOffset, value: value)
    }

    private func makeTrackAutomationBreakpoint(
        trackID: ID<Track>,
        laneID: ID<AutomationLane>,
        point: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) -> AutomationBreakpoint? {
        guard track(trackID: trackID, in: snapshot.tracks) != nil,
              let laneRect = trackAutomationLaneRect(
                trackID: trackID,
                laneID: laneID,
                snapshot: snapshot
              ) else {
            return nil
        }

        let rawPosition = Double((point.x - laneRect.minX) / snapshot.pixelsPerBar)
        let clampedPosition = max(0, min(Double(snapshot.totalBars), rawPosition))
        let snappedBar = snapToGrid(clampedPosition + 1.0, snapshot: snapshot)
        let snappedPosition = max(0, min(Double(snapshot.totalBars), snappedBar - 1.0))

        let rawValue = 1.0 - ((point.y - laneRect.minY) / max(laneRect.height, 1))
        let value = Float(max(0, min(1, rawValue)))
        return AutomationBreakpoint(position: snappedPosition, value: value)
    }

    private struct AutomationShapePreviewData {
        var existing: [AutomationBreakpoint]
        var minPosition: Double
        var maxPosition: Double
        var replacements: [AutomationBreakpoint]
        var fallbackBreakpoint: AutomationBreakpoint?
        var laneRect: CGRect
    }

    private func buildContainerAutomationShapeData(
        context: PlaybackGridAutomationShapeDrawContext,
        endPoint: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) -> AutomationShapePreviewData? {
        guard snapshot.selectedAutomationTool != .pointer,
              let (_, container) = containerAndTrack(containerID: context.containerID, trackID: context.trackID, in: snapshot.tracks),
              let lane = container.automationLanes.first(where: { $0.id == context.laneID }),
              let rect = containerRect(containerID: context.containerID, trackID: context.trackID, snapshot: snapshot) else {
            return nil
        }

        let laneRect = automationLaneRect(
            container: container,
            trackID: context.trackID,
            laneID: context.laneID,
            containerRect: rect,
            snapshot: snapshot
        )
        let startOffset = max(0, min(container.lengthBars, Double((context.startPoint.x - rect.minX) / snapshot.pixelsPerBar)))
        let endOffset = max(0, min(container.lengthBars, Double((endPoint.x - rect.minX) / snapshot.pixelsPerBar)))
        let minPosition = min(startOffset, endOffset)
        let maxPosition = max(startOffset, endOffset)
        let span = maxPosition - minPosition
        let existing = lane.breakpoints.sorted { $0.position < $1.position }

        if span <= 0.001 {
            return AutomationShapePreviewData(
                existing: existing,
                minPosition: minPosition,
                maxPosition: maxPosition,
                replacements: [],
                fallbackBreakpoint: makeAutomationBreakpoint(
                    containerID: context.containerID,
                    trackID: context.trackID,
                    laneID: context.laneID,
                    point: endPoint,
                    snapshot: snapshot
                ),
                laneRect: laneRect
            )
        }

        let startValue = Float(max(0, min(1, 1.0 - ((context.startPoint.y - laneRect.minY) / max(laneRect.height, 1)))))
        let endValue = Float(max(0, min(1, 1.0 - ((endPoint.y - laneRect.minY) / max(laneRect.height, 1)))))
        let gridSpacingBars = effectiveSnapResolution(snapshot: snapshot).beatsPerUnit / Double(snapshot.timeSignature.beatsPerBar)
        let replacements = AutomationShapeGenerator.generate(
            tool: snapshot.selectedAutomationTool,
            startPosition: minPosition,
            endPosition: maxPosition,
            startValue: startOffset <= endOffset ? startValue : endValue,
            endValue: startOffset <= endOffset ? endValue : startValue,
            gridSpacing: max(gridSpacingBars, 1.0 / Double(snapshot.timeSignature.beatsPerBar * 32))
        )
        return AutomationShapePreviewData(
            existing: existing,
            minPosition: minPosition,
            maxPosition: maxPosition,
            replacements: replacements,
            fallbackBreakpoint: nil,
            laneRect: laneRect
        )
    }

    private func buildTrackAutomationShapeData(
        context: PlaybackGridTrackAutomationShapeDrawContext,
        endPoint: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) -> AutomationShapePreviewData? {
        guard snapshot.selectedAutomationTool != .pointer,
              let track = track(trackID: context.trackID, in: snapshot.tracks),
              let lane = track.trackAutomationLanes.first(where: { $0.id == context.laneID }),
              let laneRect = trackAutomationLaneRect(
                trackID: context.trackID,
                laneID: context.laneID,
                snapshot: snapshot
              ) else {
            return nil
        }

        let timelineBars = Double(snapshot.totalBars)
        let startPosition = max(0, min(timelineBars, Double((context.startPoint.x - laneRect.minX) / snapshot.pixelsPerBar)))
        let endPosition = max(0, min(timelineBars, Double((endPoint.x - laneRect.minX) / snapshot.pixelsPerBar)))
        let minPosition = min(startPosition, endPosition)
        let maxPosition = max(startPosition, endPosition)
        let span = maxPosition - minPosition
        let existing = lane.breakpoints.sorted { $0.position < $1.position }

        if span <= 0.001 {
            return AutomationShapePreviewData(
                existing: existing,
                minPosition: minPosition,
                maxPosition: maxPosition,
                replacements: [],
                fallbackBreakpoint: makeTrackAutomationBreakpoint(
                    trackID: context.trackID,
                    laneID: context.laneID,
                    point: endPoint,
                    snapshot: snapshot
                ),
                laneRect: laneRect
            )
        }

        let startValue = Float(max(0, min(1, 1.0 - ((context.startPoint.y - laneRect.minY) / max(laneRect.height, 1)))))
        let endValue = Float(max(0, min(1, 1.0 - ((endPoint.y - laneRect.minY) / max(laneRect.height, 1)))))
        let gridSpacingBars = effectiveSnapResolution(snapshot: snapshot).beatsPerUnit / Double(snapshot.timeSignature.beatsPerBar)
        let replacements = AutomationShapeGenerator.generate(
            tool: snapshot.selectedAutomationTool,
            startPosition: minPosition,
            endPosition: maxPosition,
            startValue: startPosition <= endPosition ? startValue : endValue,
            endValue: startPosition <= endPosition ? endValue : startValue,
            gridSpacing: max(gridSpacingBars, 1.0 / Double(snapshot.timeSignature.beatsPerBar * 32))
        )
        return AutomationShapePreviewData(
            existing: existing,
            minPosition: minPosition,
            maxPosition: maxPosition,
            replacements: replacements,
            fallbackBreakpoint: nil,
            laneRect: laneRect
        )
    }

    private func mergeAutomationBreakpoints(
        existing: [AutomationBreakpoint],
        range: ClosedRange<Double>,
        replacements: [AutomationBreakpoint]
    ) -> [AutomationBreakpoint] {
        var merged = existing.filter { !$0.position.isFinite || $0.position < range.lowerBound || $0.position > range.upperBound }
        merged.append(contentsOf: replacements)
        merged.sort { $0.position < $1.position }
        return merged
    }

    private func previewAutomationShape(
        context: PlaybackGridAutomationShapeDrawContext,
        endPoint: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) -> Bool {
        guard let data = buildContainerAutomationShapeData(
            context: context,
            endPoint: endPoint,
            snapshot: snapshot
        ) else {
            return false
        }

        var liveBreakpoints = data.existing
        if !data.replacements.isEmpty {
            liveBreakpoints = mergeAutomationBreakpoints(
                existing: data.existing,
                range: data.minPosition...data.maxPosition,
                replacements: data.replacements
            )
        } else if let fallback = data.fallbackBreakpoint {
            liveBreakpoints.append(fallback)
            liveBreakpoints.sort { $0.position < $1.position }
        }

        let previousLive = automationShapeLiveOverlay
        let ghost = PlaybackGridAutomationShapeOverlay(
            trackID: context.trackID,
            containerID: context.containerID,
            laneID: context.laneID,
            breakpoints: data.existing,
            laneRect: data.laneRect,
            isGhost: true
        )
        let live = PlaybackGridAutomationShapeOverlay(
            trackID: context.trackID,
            containerID: context.containerID,
            laneID: context.laneID,
            breakpoints: liveBreakpoints,
            laneRect: data.laneRect,
            isGhost: false
        )
        automationShapeGhostOverlay = ghost
        automationShapeLiveOverlay = live
        return previousLive != live
    }

    private func previewTrackAutomationShape(
        context: PlaybackGridTrackAutomationShapeDrawContext,
        endPoint: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) -> Bool {
        guard let data = buildTrackAutomationShapeData(
            context: context,
            endPoint: endPoint,
            snapshot: snapshot
        ) else {
            return false
        }

        var liveBreakpoints = data.existing
        if !data.replacements.isEmpty {
            liveBreakpoints = mergeAutomationBreakpoints(
                existing: data.existing,
                range: data.minPosition...data.maxPosition,
                replacements: data.replacements
            )
        } else if let fallback = data.fallbackBreakpoint {
            liveBreakpoints.append(fallback)
            liveBreakpoints.sort { $0.position < $1.position }
        }

        let previousLive = automationShapeLiveOverlay
        let ghost = PlaybackGridAutomationShapeOverlay(
            trackID: context.trackID,
            containerID: nil,
            laneID: context.laneID,
            breakpoints: data.existing,
            laneRect: data.laneRect,
            isGhost: true
        )
        let live = PlaybackGridAutomationShapeOverlay(
            trackID: context.trackID,
            containerID: nil,
            laneID: context.laneID,
            breakpoints: liveBreakpoints,
            laneRect: data.laneRect,
            isGhost: false
        )
        automationShapeGhostOverlay = ghost
        automationShapeLiveOverlay = live
        return previousLive != live
    }

    private func applyAutomationShape(
        context: PlaybackGridAutomationShapeDrawContext,
        endPoint: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) {
        guard let data = buildContainerAutomationShapeData(
            context: context,
            endPoint: endPoint,
            snapshot: snapshot
        ) else {
            return
        }

        if let fallback = data.fallbackBreakpoint {
            sink?.addAutomationBreakpoint(context.containerID, laneID: context.laneID, breakpoint: fallback)
            return
        }
        guard !data.replacements.isEmpty else {
            return
        }
        sink?.replaceAutomationBreakpoints(
            context.containerID,
            laneID: context.laneID,
            startPosition: data.minPosition,
            endPosition: data.maxPosition,
            breakpoints: data.replacements
        )
        log("automation shape apply container=\(context.containerID.rawValue) lane=\(context.laneID.rawValue) tool=\(snapshot.selectedAutomationTool) points=\(data.replacements.count) range=\(format(data.minPosition))-\(format(data.maxPosition))")
    }

    private func applyTrackAutomationShape(
        context: PlaybackGridTrackAutomationShapeDrawContext,
        endPoint: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) {
        guard let data = buildTrackAutomationShapeData(
            context: context,
            endPoint: endPoint,
            snapshot: snapshot
        ) else {
            return
        }

        if let fallback = data.fallbackBreakpoint {
            sink?.addTrackAutomationBreakpoint(trackID: context.trackID, laneID: context.laneID, breakpoint: fallback)
            return
        }
        guard !data.replacements.isEmpty else {
            return
        }
        sink?.replaceTrackAutomationBreakpoints(
            trackID: context.trackID,
            laneID: context.laneID,
            startPosition: data.minPosition,
            endPosition: data.maxPosition,
            breakpoints: data.replacements
        )
        log("automation shape apply track=\(context.trackID.rawValue) lane=\(context.laneID.rawValue) tool=\(snapshot.selectedAutomationTool) points=\(data.replacements.count) range=\(format(data.minPosition))-\(format(data.maxPosition))")
    }

    private func createDoubleClickContainer(
        trackID: ID<Track>,
        clickedBar: Double,
        segment: (start: Double, end: Double)
    ) {
        let start = max(segment.start, min(clickedBar, segment.end - 0.0001))
        let remaining = segment.end - start
        guard remaining > 0 else {
            log("container create skipped track=\(trackID.rawValue) reason=no-space")
            return
        }

        let length = min(4.0, remaining)
        let created = sink?.createContainer(trackID: trackID, startBar: start, lengthBars: length) ?? false
        log("container create double-click track=\(trackID.rawValue) start=\(format(start)) length=\(format(length)) success=\(created)")
    }

    private func commitDraggedContainerCreation(
        context: PlaybackGridContainerCreateContext,
        point: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) {
        let unclamped = snappedBarForX(point.x, snapshot: snapshot)
        let clamped = min(max(unclamped, context.segmentStartBar), context.segmentEndBar)
        var startBar = min(context.anchorBar, clamped)
        var endBar = max(context.anchorBar, clamped)

        if endBar - startBar < 1.0 {
            if clamped >= context.anchorBar {
                endBar = min(context.segmentEndBar, startBar + 1.0)
            } else {
                startBar = max(context.segmentStartBar, endBar - 1.0)
            }
        }

        let length = endBar - startBar
        guard length >= 1.0 else {
            log("container create drag skipped track=\(context.trackID.rawValue) reason=length<1 segment=\(format(context.segmentStartBar))-\(format(context.segmentEndBar))")
            return
        }

        let created = sink?.createContainer(trackID: context.trackID, startBar: startBar, lengthBars: length) ?? false
        log("container create drag commit track=\(context.trackID.rawValue) start=\(format(startBar)) length=\(format(length)) success=\(created)")
    }

    private func automationLaneRect(
        container: Container,
        trackID: ID<Track>? = nil,
        laneID: ID<AutomationLane>,
        containerRect: CGRect,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect {
        if let trackID,
           snapshot.automationExpandedTrackIDs.contains(trackID),
           let track = track(trackID: trackID, in: snapshot.tracks) {
            let targetPath = track.trackAutomationLanes.first(where: { $0.id == laneID })?.targetPath
                ?? container.automationLanes.first(where: { $0.id == laneID })?.targetPath
            if let targetPath,
               let laneIndex = automationLanePaths(for: track).firstIndex(of: targetPath) {
                return CGRect(
                    x: containerRect.minX,
                    y: containerRect.maxY
                        + snapshot.automationToolbarHeight
                        + (CGFloat(laneIndex) * snapshot.automationSubLaneHeight),
                    width: containerRect.width,
                    height: snapshot.automationSubLaneHeight
                )
            }
        }

        let lanes = container.automationLanes
        guard !lanes.isEmpty else { return containerRect }

        let automationBandHeight: CGFloat
        if snapshot.selectedAutomationTool == .pointer {
            automationBandHeight = min(containerRect.height, max(24, containerRect.height * 0.42))
        } else {
            automationBandHeight = containerRect.height
        }

        let bandRect = CGRect(
            x: containerRect.minX,
            y: containerRect.minY,
            width: containerRect.width,
            height: automationBandHeight
        )
        guard lanes.count > 1 else { return bandRect }

        let laneHeight = max(automationBandHeight / CGFloat(lanes.count), 1)
        let index = lanes.firstIndex(where: { $0.id == laneID }) ?? 0
        return CGRect(
            x: bandRect.minX,
            y: bandRect.minY + (CGFloat(index) * laneHeight),
            width: bandRect.width,
            height: laneHeight
        )
    }

    private func trackAutomationLaneRect(
        trackID: ID<Track>,
        laneID: ID<AutomationLane>,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect? {
        guard snapshot.automationExpandedTrackIDs.contains(trackID) else { return nil }

        var yOffset: CGFloat = snapshot.showRulerAndSections ? PlaybackGridLayout.trackAreaTop : 0
        let timelineWidth = CGFloat(snapshot.totalBars) * snapshot.pixelsPerBar

        for track in snapshot.tracks {
            let baseHeight = snapshot.trackHeights[track.id] ?? snapshot.defaultTrackHeight
            let automationExtra = automationTrackExtraHeight(track: track, snapshot: snapshot)
            let inlineHeight = snapshot.inlineMIDILaneHeights[track.id] ?? 0

            defer { yOffset += baseHeight + automationExtra + inlineHeight }
            guard track.id == trackID else { continue }

            let lanePaths = automationLanePaths(for: track)
            guard !lanePaths.isEmpty else { return nil }
            guard let targetPath = track.trackAutomationLanes.first(where: { $0.id == laneID })?.targetPath,
                  let laneIndex = lanePaths.firstIndex(of: targetPath) else {
                return nil
            }

            let laneY = yOffset
                + baseHeight
                + snapshot.automationToolbarHeight
                + (CGFloat(laneIndex) * snapshot.automationSubLaneHeight)
            return CGRect(
                x: 0,
                y: laneY,
                width: timelineWidth,
                height: snapshot.automationSubLaneHeight
            )
        }

        return nil
    }

    private func previewMIDIPitchIfNeeded(_ pitch: UInt8) {
        if let current = previewedMIDIPitch, current == pitch { return }
        if let current = previewedMIDIPitch {
            sink?.previewMIDINote(pitch: current, isNoteOn: false)
        }
        sink?.previewMIDINote(pitch: pitch, isNoteOn: true)
        previewedMIDIPitch = pitch
    }

    private func stopMIDIPreviewIfNeeded() {
        guard let pitch = previewedMIDIPitch else { return }
        sink?.previewMIDINote(pitch: pitch, isNoteOn: false)
        previewedMIDIPitch = nil
    }

    private func log(
        _ message: String,
        category explicitCategory: String? = nil,
        minInterval: CFTimeInterval = 0.1
    ) {
        guard Self.debugLogsEnabled else { return }
        let category: String
        if let explicitCategory {
            category = explicitCategory
        } else if let first = message.split(separator: " ").first, !first.isEmpty {
            category = String(first)
        } else {
            category = "general"
        }

        let now = CACurrentMediaTime()
        let last = lastLogTimeByCategory[category] ?? 0
        guard now - last >= minInterval else { return }
        lastLogTimeByCategory[category] = now
        print("[GRIDINT][\(category)] \(message)")
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
