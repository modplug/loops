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
        selectedSectionID = nil
        rangeSelection = nil
    }

    public struct RangeSelection: Equatable {
        public let containerID: ID<Container>
        public let startBar: Double
        public let endBar: Double
    }

    public init() {}
}
