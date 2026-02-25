import AppKit
import LoopsCore

public final class PlaybackGridInteractionController {
    public private(set) var state: PlaybackGridInteractionState = .idle

    private weak var sink: PlaybackGridCommandSink?

    public init(sink: PlaybackGridCommandSink?) {
        self.sink = sink
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
            sink?.setPlayhead(bar: snappedBarForX(point.x, snapshot: snapshot))
            state = .idle

        case .midiNote:
            guard let containerID = pick.containerID,
                  let trackID = pick.trackID,
                  let noteID = pick.midiNoteID else {
                state = .idle
                return
            }

            if event.modifierFlags.contains(.option) {
                sink?.removeMIDINote(containerID, noteID: noteID)
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
                containerID: containerID,
                trackID: trackID,
                noteID: noteID,
                startPoint: point,
                originalNote: note,
                containerStartBar: container.startBar,
                containerLengthBars: container.lengthBars
            ))

        case .automationBreakpoint:
            guard let containerID = pick.containerID,
                  let trackID = pick.trackID,
                  let laneID = pick.automationLaneID,
                  let breakpointID = pick.automationBreakpointID else {
                state = .idle
                return
            }

            if event.modifierFlags.contains(.option) {
                sink?.removeAutomationBreakpoint(containerID, laneID: laneID, breakpointID: breakpointID)
                state = .idle
                return
            }

            sink?.selectContainer(containerID, trackID: trackID, modifiers: event.modifierFlags)
            state = .draggingAutomationBreakpoint(context: PlaybackGridAutomationBreakpointDragContext(
                containerID: containerID,
                trackID: trackID,
                laneID: laneID,
                breakpointID: breakpointID,
                startPoint: point
            ))

        case .none:
            // Allow setting playhead anywhere in the main grid surface, even when no
            // specific pick object is hit (e.g. blank timeline area).
            let gridTop = snapshot.showRulerAndSections ? PlaybackGridLayout.trackAreaTop : 0
            if point.y >= CGFloat(gridTop) {
                sink?.setPlayhead(bar: snappedBarForX(point.x, snapshot: snapshot))
            }
            state = .idle

        default:
            state = .idle
        }
    }

    public func handleMouseDragged(
        point: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) {
        switch state {
        case .scrubbingRuler:
            sink?.setPlayhead(bar: snappedBarForX(point.x, snapshot: snapshot))

        case let .draggingContainer(context):
            handleContainerDrag(context: context, point: point, snapshot: snapshot)

        case let .draggingMIDINote(context):
            handleMIDINoteDrag(context: context, point: point, snapshot: snapshot)

        case let .draggingAutomationBreakpoint(context):
            handleAutomationBreakpointDrag(context: context, point: point, snapshot: snapshot)

        case .selectingRange:
            break

        case .idle:
            break
        }
    }

    public func handleMouseUp(
        point: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) {
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

        case .draggingMIDINote:
            break

        case .draggingAutomationBreakpoint:
            break

        case .idle:
            break
        }

        state = .idle
    }

    private func barForX(_ x: CGFloat, pixelsPerBar: CGFloat, totalBars: Int) -> Int {
        max(1, min(Int(x / max(pixelsPerBar, 1)) + 1, totalBars))
    }

    private func snapToGrid(_ bar: Double, snapshot: PlaybackGridSnapshot) -> Double {
        guard snapshot.isSnapEnabled else { return max(bar, 1.0) }

        let resolution = effectiveSnapResolution(snapshot: snapshot)
        let beatsPerBar = Double(snapshot.timeSignature.beatsPerBar)
        let totalBeats = (bar - 1.0) * beatsPerBar
        let snappedBeats = resolution.snap(totalBeats)
        return max((snappedBeats / beatsPerBar) + 1.0, 1.0)
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

    private func containerRect(
        containerID: ID<Container>,
        trackID: ID<Track>,
        snapshot: PlaybackGridSnapshot
    ) -> CGRect? {
        var yOffset: CGFloat = snapshot.showRulerAndSections ? PlaybackGridLayout.trackAreaTop : 0
        for track in snapshot.tracks {
            let height = snapshot.trackHeights[track.id] ?? snapshot.defaultTrackHeight
            defer { yOffset += height }
            guard track.id == trackID else { continue }
            guard let container = track.containers.first(where: { $0.id == containerID }) else { return nil }
            let x = CGFloat(container.startBar - 1.0) * snapshot.pixelsPerBar
            let width = CGFloat(container.lengthBars) * snapshot.pixelsPerBar
            return CGRect(x: x, y: yOffset, width: width, height: height)
        }
        return nil
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

    private func handleMIDINoteDrag(
        context: PlaybackGridMIDINoteDragContext,
        point: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) {
        let beatsPerBar = Double(snapshot.timeSignature.beatsPerBar)
        let deltaX = point.x - context.startPoint.x
        let deltaBars = Double(deltaX / snapshot.pixelsPerBar)
        let deltaBeatsRaw = deltaBars * beatsPerBar

        let deltaBeats: Double
        if snapshot.isSnapEnabled {
            let unit = effectiveSnapResolution(snapshot: snapshot).beatsPerUnit
            deltaBeats = (deltaBeatsRaw / unit).rounded() * unit
        } else {
            deltaBeats = deltaBeatsRaw
        }

        let maxStartBeat = max(0, context.containerLengthBars * beatsPerBar - context.originalNote.duration)
        var updated = context.originalNote
        updated.startBeat = max(0, min(maxStartBeat, context.originalNote.startBeat + deltaBeats))

        let deltaYPixels = context.startPoint.y - point.y
        let pitchDelta = Int((deltaYPixels / 8).rounded())
        let newPitch = max(0, min(127, Int(context.originalNote.pitch) + pitchDelta))
        updated.pitch = UInt8(newPitch)

        sink?.updateMIDINote(context.containerID, note: updated)
    }

    private func handleAutomationBreakpointDrag(
        context: PlaybackGridAutomationBreakpointDragContext,
        point: CGPoint,
        snapshot: PlaybackGridSnapshot
    ) {
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
        let lane = container.automationLanes.first(where: { $0.id == context.laneID }),
        let existing = lane.breakpoints.first(where: { $0.id == context.breakpointID }) else {
            return
        }

        let rawBarOffset = Double((point.x - rect.minX) / snapshot.pixelsPerBar)
        let clampedRawOffset = max(0, min(container.lengthBars, rawBarOffset))
        let snappedAbsBar = snapToGrid(container.startBar + clampedRawOffset, snapshot: snapshot)
        let snappedOffset = max(0, min(container.lengthBars, snappedAbsBar - container.startBar))

        let rawValue = 1.0 - ((point.y - rect.minY) / max(rect.height, 1))
        let value = Float(max(0, min(1, rawValue)))

        var updated = existing
        updated.position = snappedOffset
        updated.value = value
        sink?.updateAutomationBreakpoint(context.containerID, laneID: context.laneID, breakpoint: updated)
    }
}
