import SwiftUI
import LoopsCore

/// Dedicated observable for selection state, extracted from ProjectViewModel.
/// Isolates selection changes so only views that depend on selection (inspector,
/// highlighting) re-evaluate when selection changes.
@Observable
@MainActor
public final class SelectionState {

    /// The currently selected single track ID (for keyboard operations like record arm).
    /// Setting this clears selectedContainerID for mutual exclusion.
    /// Guards avoid unnecessary @Observable mutation notifications when values are already nil/empty.
    public var selectedTrackID: ID<Track>? {
        didSet {
            if selectedTrackID != nil {
                if selectedContainerID != nil { selectedContainerID = nil }
                if !selectedContainerIDs.isEmpty { selectedContainerIDs = [] }
                // Sync multi-select set with single selection
                if !selectedTrackIDs.isEmpty { selectedTrackIDs = [] }
            }
        }
    }

    /// Set of all selected track IDs for multi-selection (Cmd+Click, Shift+Click).
    /// Cleared when single-selecting a track or selecting containers.
    public var selectedTrackIDs: Set<ID<Track>> = [] {
        didSet {
            if !selectedTrackIDs.isEmpty {
                if selectedContainerID != nil { selectedContainerID = nil }
                if !selectedContainerIDs.isEmpty { selectedContainerIDs = [] }
                // Clear single track selection when multi-selecting
                if selectedTrackID != nil { selectedTrackID = nil }
            }
        }
    }

    /// Set of all selected container IDs (populated by multi-select, select-all; cleared on single-select or deselect).
    public var selectedContainerIDs: Set<ID<Container>> = []

    /// The last container that was clicked (anchor for shift+click range selection).
    public var lastSelectedContainerID: ID<Container>?

    /// The currently selected container ID.
    /// Setting this clears selectedTrackID and selectedContainerIDs for mutual exclusion.
    /// Guards avoid unnecessary @Observable mutation notifications when values are already nil.
    public var selectedContainerID: ID<Container>? {
        didSet {
            if selectedContainerID != nil {
                if selectedTrackID != nil { selectedTrackID = nil }
                if !selectedContainerIDs.isEmpty { selectedContainerIDs = [] }
                lastSelectedContainerID = selectedContainerID
            }
        }
    }

    /// The currently selected section ID.
    public var selectedSectionID: ID<SectionRegion>?

    /// Range selection within a container (selector tool drag).
    /// Bar values are absolute timeline positions.
    public var rangeSelection: RangeSelection?

    /// Returns true if the container is part of the current selection (single or multi).
    public func isContainerSelected(_ id: ID<Container>) -> Bool {
        selectedContainerID == id || selectedContainerIDs.contains(id)
    }

    /// All effectively selected container IDs (union of single and multi-select).
    public var effectiveSelectedContainerIDs: Set<ID<Container>> {
        if !selectedContainerIDs.isEmpty {
            return selectedContainerIDs
        }
        if let single = selectedContainerID {
            return [single]
        }
        return []
    }

    /// Clears all selection state (container, track, section, multi-select).
    public func deselectAll() {
        selectedContainerID = nil
        selectedContainerIDs = []
        lastSelectedContainerID = nil
        selectedTrackID = nil
        selectedTrackIDs = []
        selectedSectionID = nil
        rangeSelection = nil
    }

    /// Returns whether a track is selected (either single or multi-selected).
    public func isTrackSelected(_ trackID: ID<Track>) -> Bool {
        selectedTrackID == trackID || selectedTrackIDs.contains(trackID)
    }

    /// All effectively selected track IDs (union of single + multi).
    public var allSelectedTrackIDs: Set<ID<Track>> {
        if !selectedTrackIDs.isEmpty { return selectedTrackIDs }
        if let single = selectedTrackID { return [single] }
        return []
    }

    /// Handles Cmd+Click: toggles the track in/out of multi-selection.
    /// If currently single-selecting, promotes to multi-select including the existing selection.
    public func toggleTrackInMultiSelect(_ trackID: ID<Track>) {
        if selectedTrackIDs.contains(trackID) {
            selectedTrackIDs.remove(trackID)
            // If only one left, demote to single-select
            if selectedTrackIDs.count == 1, let remaining = selectedTrackIDs.first {
                selectedTrackIDs = []
                selectedTrackID = remaining
            }
        } else {
            // Promote existing single selection to multi-select
            var newSet = selectedTrackIDs
            if let existing = selectedTrackID {
                newSet.insert(existing)
            }
            newSet.insert(trackID)
            selectedTrackIDs = newSet
        }
    }

    /// Handles Shift+Click: selects a contiguous range of tracks.
    /// `orderedTrackIDs` should be the track IDs in visual order.
    public func selectTrackRange(to targetID: ID<Track>, orderedTrackIDs: [ID<Track>]) {
        // Find the anchor — use last single selection or first multi-selected track
        let anchorID: ID<Track>?
        if let single = selectedTrackID {
            anchorID = single
        } else if let first = orderedTrackIDs.first(where: { selectedTrackIDs.contains($0) }) {
            anchorID = first
        } else {
            anchorID = nil
        }

        guard let anchor = anchorID,
              let anchorIndex = orderedTrackIDs.firstIndex(of: anchor),
              let targetIndex = orderedTrackIDs.firstIndex(of: targetID) else {
            // No anchor — just single-select the target
            selectedTrackID = targetID
            return
        }

        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedTrackIDs = Set(orderedTrackIDs[range])
    }

    public struct RangeSelection: Equatable {
        public let containerID: ID<Container>
        public let startBar: Double
        public let endBar: Double
    }

    public init() {}
}
