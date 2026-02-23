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

    /// Horizontal zoom (beats).
    public var pixelsPerBeat: CGFloat = PianoRollLayout.defaultPixelsPerBeat
    /// Visible pitch range — low end.
    public var lowPitch: UInt8 = PianoRollLayout.defaultLowPitch
    /// Visible pitch range — high end.
    public var highPitch: UInt8 = PianoRollLayout.defaultHighPitch
    /// Vertical zoom — row height in points.
    public var rowHeight: CGFloat = PianoRollLayout.defaultRowHeight
    /// Snap grid resolution.
    public var snapResolution: SnapResolution = .sixteenth
    /// Currently selected note IDs.
    public var selectedNoteIDs: Set<ID<MIDINoteEvent>> = []

    public init() {}

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

    /// Auto-fits the vertical range to the note content with padding.
    public func fitToNotes(sequence: MIDISequence, padding: UInt8 = 6) {
        guard let low = sequence.lowestPitch, let high = sequence.highestPitch else { return }
        lowPitch = UInt8(max(0, Int(low) - Int(padding)))
        highPitch = UInt8(min(127, Int(high) + Int(padding)))
    }
}
