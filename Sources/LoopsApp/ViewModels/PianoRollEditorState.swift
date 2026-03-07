import SwiftUI
import LoopsCore

/// Observable state for the active piano roll editing session.
/// Stored on MainContentView so it persists while navigating.
@Observable
@MainActor
public final class PianoRollEditorState {
    /// The container being edited (nil = no piano roll open).
    public var containerID: ID<Container>?
    /// The track that owns the container.
    public var trackID: ID<Track>?
    /// Whether the inline piano roll is expanded below the track.
    public var isExpanded: Bool = false
    /// Whether the piano roll currently has keyboard focus (for arrow key gating).
    public var isFocused: Bool = false
    /// Height of the inline piano roll pane in points (drag-resizable).
    public var inlineHeight: CGFloat = 250
    /// Measured height of the inline toolbar + divider (set by InlinePianoRollView via GeometryReader).
    public var toolbarHeight: CGFloat = 0
    /// Height of the bottom resize handle.
    public static let resizeHandleHeight: CGFloat = 4

    /// Total height of the inline piano roll view including toolbar, divider, and resize handle.
    public var totalInlineViewHeight: CGFloat {
        toolbarHeight + inlineHeight + Self.resizeHandleHeight
    }

    /// Horizontal zoom (beats).
    public var pixelsPerBeat: CGFloat = PianoRollLayout.defaultPixelsPerBeat
    /// Visible pitch range — low end.
    public var lowPitch: UInt8 = PianoRollLayout.defaultLowPitch
    /// Visible pitch range — high end.
    public var highPitch: UInt8 = PianoRollLayout.defaultHighPitch
    /// Vertical zoom — row height in points.
    public var rowHeight: CGFloat = PianoRollLayout.defaultRowHeight
    /// Current MIDI editing tool.
    public var selectedTool: MIDITool = .pointer
    /// Legacy summary for whether any MIDI detail lane is visible.
    public var isExpressionLaneVisible: Bool = true
    /// Active note-expression lane.
    public var selectedExpressionLane: MIDINoteExpressionLane = .velocity
    /// Visible note-expression lanes in stable display order.
    public var visibleExpressionLanes: [MIDINoteExpressionLane] = [.velocity]
    /// Per-lane heights for note-expression editors.
    public var noteExpressionLaneHeights: [MIDINoteExpressionLane: CGFloat] = [:]
    /// Snap grid resolution.
    public var snapResolution: SnapResolution = .sixteenth
    /// Vertical scroll offset tracked from the inline piano roll content (used to sync keyboard labels).
    public var verticalScrollOffset: CGFloat = 0
    /// Currently selected note IDs.
    public var selectedNoteIDs: Set<ID<MIDINoteEvent>> = []

    public init() {}

    public static let minDetailLaneHeight: CGFloat = 56
    public static let maxDetailLaneHeight: CGFloat = 220

    /// Activates the inline piano roll for a given container/track.
    public func open(containerID: ID<Container>, trackID: ID<Track>) {
        self.containerID = containerID
        self.trackID = trackID
        self.isExpanded = true
        self.selectedNoteIDs = []
    }

    /// Closes the inline piano roll.
    public func close() {
        isExpanded = false
        containerID = nil
        trackID = nil
        selectedNoteIDs = []
        isFocused = false
    }

    /// Toggles the inline piano roll for a container.
    public func toggle(containerID: ID<Container>, trackID: ID<Track>) {
        if self.containerID == containerID && isExpanded {
            close()
        } else {
            open(containerID: containerID, trackID: trackID)
        }
    }

    /// Switches the active container within the same track (used for track-wide inline piano roll).
    public func switchContainer(containerID: ID<Container>) {
        self.containerID = containerID
        self.selectedNoteIDs = []
    }

    /// Returns the extra height added by the inline piano roll for a given track, or 0 if not expanded.
    public func extraHeight(forTrackID trackID: ID<Track>) -> CGFloat {
        guard isExpanded, self.trackID == trackID else { return 0 }
        return totalInlineViewHeight
    }

    /// Auto-fits the vertical range to the note content with padding.
    public func fitToNotes(sequence: MIDISequence, padding: UInt8 = 6) {
        guard let low = sequence.lowestPitch, let high = sequence.highestPitch else { return }
        lowPitch = UInt8(max(0, Int(low) - Int(padding)))
        highPitch = UInt8(min(127, Int(high) + Int(padding)))
    }

    public func noteExpressionLaneHeight(for lane: MIDINoteExpressionLane) -> CGFloat {
        noteExpressionLaneHeights[lane] ?? defaultNoteExpressionLaneHeight(for: lane)
    }

    public func setNoteExpressionLaneHeight(_ height: CGFloat, for lane: MIDINoteExpressionLane) {
        noteExpressionLaneHeights[lane] = min(max(height, Self.minDetailLaneHeight), Self.maxDetailLaneHeight)
    }

    public func isExpressionLaneVisible(_ lane: MIDINoteExpressionLane) -> Bool {
        visibleExpressionLanes.contains(lane)
    }

    public func showExpressionLane(_ lane: MIDINoteExpressionLane) {
        guard !visibleExpressionLanes.contains(lane) else { return }
        visibleExpressionLanes.append(lane)
        visibleExpressionLanes.sort { lhs, rhs in
            MIDINoteExpressionLane.allCases.firstIndex(of: lhs)! < MIDINoteExpressionLane.allCases.firstIndex(of: rhs)!
        }
        isExpressionLaneVisible = !visibleExpressionLanes.isEmpty
    }

    public func hideExpressionLane(_ lane: MIDINoteExpressionLane) {
        visibleExpressionLanes.removeAll { $0 == lane }
        if selectedExpressionLane == lane {
            selectedExpressionLane = visibleExpressionLanes.first ?? .velocity
        }
        isExpressionLaneVisible = !visibleExpressionLanes.isEmpty
    }

    public func toggleExpressionLane(_ lane: MIDINoteExpressionLane) {
        if isExpressionLaneVisible(lane) {
            hideExpressionLane(lane)
        } else {
            showExpressionLane(lane)
            selectedExpressionLane = lane
        }
    }

    private func defaultNoteExpressionLaneHeight(for lane: MIDINoteExpressionLane) -> CGFloat {
        switch lane {
        case .velocity:
            return 96
        case .channel:
            return 84
        case .sustain:
            return 72
        case .expression:
            return 96
        }
    }
}
