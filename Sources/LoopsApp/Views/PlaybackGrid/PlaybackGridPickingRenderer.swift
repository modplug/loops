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

    private func makeID(
        kind: GridPickObjectKind,
        containerID: ID<Container>? = nil,
        trackID: ID<Track>? = nil,
        sectionID: ID<SectionRegion>? = nil,
        zone: GridContainerZone? = nil
    ) -> GridPickID {
        var hasher = Hasher()
        hasher.combine(kind)
        hasher.combine(containerID?.rawValue)
        hasher.combine(trackID?.rawValue)
        hasher.combine(sectionID?.rawValue)
        hasher.combine(zone?.rawValue)
        let value = UInt32(bitPattern: Int32(truncatingIfNeeded: hasher.finalize()))
        return value == 0 ? 1 : value
    }
}
