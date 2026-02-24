import Foundation
import LoopsCore
import SwiftUI

/// Information about a single ghost track preview during a file drop.
public struct GhostTrackInfo: Identifiable {
    public let id: UUID
    public let fileName: String
    public var lengthBars: Double?
    public let trackKind: TrackKind
    public let url: URL?

    public init(
        id: UUID = UUID(),
        fileName: String,
        lengthBars: Double? = nil,
        trackKind: TrackKind,
        url: URL? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.lengthBars = lengthBars
        self.trackKind = trackKind
        self.url = url
    }

    public var trackColor: Color {
        switch trackKind {
        case .audio: return .blue
        case .midi: return .purple
        case .bus: return .green
        case .backing: return .orange
        case .master: return .gray
        }
    }
}

/// Observable state that tracks ghost track previews when files are dragged over empty space.
@Observable
public final class GhostTrackDropState {
    public var isActive = false
    public var ghostTracks: [GhostTrackInfo] = []
    public var dropBar: Double = 1.0
    /// Tracks how many drop delegates currently consider this drag active.
    /// Only reset when all delegates have exited.
    private var activeDelegateCount = 0
    /// Whether ghost track metadata has already been resolved for this drag session.
    private var hasResolved = false

    public init() {}

    public static let ghostTrackHeight: CGFloat = 80

    public var totalGhostHeight: CGFloat {
        CGFloat(ghostTracks.count) * Self.ghostTrackHeight
    }

    /// Called by a delegate when a drag enters its zone. Returns true if this is the
    /// first activation (caller should resolve ghost tracks).
    public func activate() -> Bool {
        activeDelegateCount += 1
        isActive = true
        if hasResolved { return false }
        hasResolved = true
        return true
    }

    /// Called by a delegate when a drag exits its zone.
    /// Only resets when all delegates have exited.
    public func deactivate() {
        activeDelegateCount = max(0, activeDelegateCount - 1)
        if activeDelegateCount == 0 {
            reset()
        }
    }

    /// Force-reset after a drop is performed.
    public func reset() {
        isActive = false
        ghostTracks = []
        dropBar = 1.0
        activeDelegateCount = 0
        hasResolved = false
    }
}
