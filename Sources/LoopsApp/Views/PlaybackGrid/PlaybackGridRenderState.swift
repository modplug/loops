import AppKit
import LoopsCore

public struct PlaybackGridModelState: Equatable {
    public var tracks: [Track]
    public var sections: [SectionRegion]
    public var timeSignature: TimeSignature
    public var trackHeights: [ID<Track>: CGFloat]
    public var inlineMIDILaneHeights: [ID<Track>: CGFloat]
    public var inlineMIDIConfigs: [ID<Track>: PlaybackGridMIDIConfig]
    public var automationExpandedTrackIDs: Set<ID<Track>>
    public var automationSubLaneHeight: CGFloat
    public var automationToolbarHeight: CGFloat
    public var defaultTrackHeight: CGFloat
    public var gridMode: GridMode
    public var selectedAutomationTool: AutomationTool
    public var showRulerAndSections: Bool
    public var bottomPadding: CGFloat
    public var minimumContentHeight: CGFloat

    public init(snapshot: PlaybackGridSnapshot) {
        tracks = snapshot.tracks
        sections = snapshot.sections
        timeSignature = snapshot.timeSignature
        trackHeights = snapshot.trackHeights
        inlineMIDILaneHeights = snapshot.inlineMIDILaneHeights
        inlineMIDIConfigs = snapshot.inlineMIDIConfigs
        automationExpandedTrackIDs = snapshot.automationExpandedTrackIDs
        automationSubLaneHeight = snapshot.automationSubLaneHeight
        automationToolbarHeight = snapshot.automationToolbarHeight
        defaultTrackHeight = snapshot.defaultTrackHeight
        gridMode = snapshot.gridMode
        selectedAutomationTool = snapshot.selectedAutomationTool
        showRulerAndSections = snapshot.showRulerAndSections
        bottomPadding = snapshot.bottomPadding
        minimumContentHeight = snapshot.minimumContentHeight
    }
}

public struct PlaybackGridViewportState: Equatable {
    public var pixelsPerBar: CGFloat
    public var totalBars: Int
    public var visibleRect: CGRect
    public var canvasSize: CGSize

    public init(
        pixelsPerBar: CGFloat,
        totalBars: Int,
        visibleRect: CGRect = .zero,
        canvasSize: CGSize = .zero
    ) {
        self.pixelsPerBar = pixelsPerBar
        self.totalBars = totalBars
        self.visibleRect = visibleRect
        self.canvasSize = canvasSize
    }

    public init(snapshot: PlaybackGridSnapshot, visibleRect: CGRect = .zero, canvasSize: CGSize = .zero) {
        self.init(
            pixelsPerBar: snapshot.pixelsPerBar,
            totalBars: snapshot.totalBars,
            visibleRect: visibleRect,
            canvasSize: canvasSize
        )
    }
}

public struct PlaybackGridOverlayState: Equatable {
    public var selectedContainerIDs: Set<ID<Container>>
    public var selectedMIDINoteIDs: Set<ID<MIDINoteEvent>>
    public var selectedSectionID: ID<SectionRegion>?
    public var selectedRange: ClosedRange<Int>?
    public var rangeSelection: SelectionState.RangeSelection?
    public var isSnapEnabled: Bool
    public var playheadBar: Double
    public var cursorX: CGFloat?

    public init(snapshot: PlaybackGridSnapshot) {
        selectedContainerIDs = snapshot.selectedContainerIDs
        selectedMIDINoteIDs = snapshot.selectedMIDINoteIDs
        selectedSectionID = snapshot.selectedSectionID
        selectedRange = snapshot.selectedRange
        rangeSelection = snapshot.rangeSelection
        isSnapEnabled = snapshot.isSnapEnabled
        playheadBar = snapshot.playheadBar
        cursorX = snapshot.cursorX
    }
}

public struct PlaybackGridInvalidationDomains: OptionSet, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let model = PlaybackGridInvalidationDomains(rawValue: 1 << 0)
    public static let viewport = PlaybackGridInvalidationDomains(rawValue: 1 << 1)
    public static let overlay = PlaybackGridInvalidationDomains(rawValue: 1 << 2)
}
