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
                    originAudioStartOffset: container.audioStartOffset
                ))
            } else {
                state = .idle
            }

        case .trackBackground:
            sink?.setPlayhead(bar: snappedBarForX(point.x, snapshot: snapshot))
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

        case .idle:
            break
        }

        state = .idle
    }

    private func barForX(_ x: CGFloat, pixelsPerBar: CGFloat, totalBars: Int) -> Int {
        max(1, min(Int(x / max(pixelsPerBar, 1)) + 1, totalBars))
    }

    private func snapToGrid(_ bar: Double, snapshot: PlaybackGridSnapshot) -> Double {
        // Reuse the same adaptive behavior currently used in timeline interaction.
        let pixelsPerBeat = snapshot.pixelsPerBar / CGFloat(snapshot.timeSignature.beatsPerBar)
        if pixelsPerBeat >= 40 {
            let beatsPerBar = Double(snapshot.timeSignature.beatsPerBar)
            let totalBeats = (bar - 1.0) * beatsPerBar
            let snappedBeats = totalBeats.rounded()
            return max((snappedBeats / beatsPerBar) + 1.0, 1.0)
        }
        return max(bar.rounded(), 1.0)
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
            let fadeBars = max(0.0, min(context.originLengthBars, (point.x / snapshot.pixelsPerBar) - (context.originStartBar - 1.0)))
            let fade = fadeBars < 0.01 ? nil : FadeSettings(duration: fadeBars, curve: .linear)
            sink?.setContainerEnterFade(context.containerID, fade: fade)

        case .fadeRight:
            let endBar = context.originStartBar + context.originLengthBars
            let cursorBar = (point.x / snapshot.pixelsPerBar) + 1.0
            let fadeBars = max(0.0, min(context.originLengthBars, endBar - cursorBar))
            let fade = fadeBars < 0.01 ? nil : FadeSettings(duration: fadeBars, curve: .linear)
            sink?.setContainerExitFade(context.containerID, fade: fade)
        }
    }
}
