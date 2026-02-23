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
    public var selectedTrackID: ID<Track>? {
        didSet {
            if selectedTrackID != nil {
                selectedContainerID = nil
                selectedContainerIDs = []
            }
        }
    }

    /// Set of all selected container IDs (populated by select-all; cleared on single-select or deselect).
    public var selectedContainerIDs: Set<ID<Container>> = []

    /// The currently selected container ID.
    /// Setting this clears selectedTrackID for mutual exclusion.
    public var selectedContainerID: ID<Container>? {
        didSet {
            if selectedContainerID != nil {
                selectedTrackID = nil
            }
        }
    }

    /// The currently selected section ID.
    public var selectedSectionID: ID<SectionRegion>?

    /// Clears all selection state (container, track, section, multi-select).
    public func deselectAll() {
        selectedContainerID = nil
        selectedContainerIDs = []
        selectedTrackID = nil
        selectedSectionID = nil
    }

    public init() {}
}
