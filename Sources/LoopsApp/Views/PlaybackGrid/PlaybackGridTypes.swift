import AppKit
import Metal
import simd
import LoopsCore

public typealias GridPickID = UInt32

public enum GridPickObjectKind: Hashable {
    case none
    case ruler
    case section
    case trackBackground
    case container
    case containerZone
    case automationBreakpoint
    case automationSegment
    case midiNote
}

public enum GridContainerZone: UInt8, Equatable {
    case selector
    case move
    case resizeLeft
    case resizeRight
    case trimLeft
    case trimRight
    case fadeLeft
    case fadeRight
}

public struct GridPickObject: Equatable {
    public var id: GridPickID
    public var kind: GridPickObjectKind
    public var containerID: ID<Container>?
    public var trackID: ID<Track>?
    public var sectionID: ID<SectionRegion>?
    public var zone: GridContainerZone?

    public init(
        id: GridPickID = 0,
        kind: GridPickObjectKind = .none,
        containerID: ID<Container>? = nil,
        trackID: ID<Track>? = nil,
        sectionID: ID<SectionRegion>? = nil,
        zone: GridContainerZone? = nil
    ) {
        self.id = id
        self.kind = kind
        self.containerID = containerID
        self.trackID = trackID
        self.sectionID = sectionID
        self.zone = zone
    }

    public static let none = GridPickObject()
}

public enum PlaybackGridInteractionState: Equatable {
    case idle
    case scrubbingRuler
    case selectingRange(startBar: Int, startPoint: CGPoint)
    case draggingContainer(context: PlaybackGridContainerDragContext)
}

public enum PlaybackGridContainerDragKind: Equatable {
    case move
    case clone
    case resizeLeft
    case resizeRight
    case trimLeft
    case trimRight
    case fadeLeft
    case fadeRight
}

public struct PlaybackGridContainerDragContext: Equatable {
    public var kind: PlaybackGridContainerDragKind
    public var containerID: ID<Container>
    public var trackID: ID<Track>
    public var startPoint: CGPoint
    public var originStartBar: Double
    public var originLengthBars: Double
    public var originAudioStartOffset: Double
}

public protocol PlaybackGridCommandSink: AnyObject {
    func setPlayhead(bar: Double)
    func selectSection(_ sectionID: ID<SectionRegion>)
    func selectRange(_ range: ClosedRange<Int>)
    func clearRangeSelection()
    func selectContainer(_ containerID: ID<Container>, trackID: ID<Track>, modifiers: NSEvent.ModifierFlags)
    func openContainerEditor(_ containerID: ID<Container>, trackID: ID<Track>)
    func moveContainer(_ containerID: ID<Container>, trackID: ID<Track>, newStartBar: Double)
    func cloneContainer(_ containerID: ID<Container>, trackID: ID<Track>, newStartBar: Double)
    func copyContainer(_ containerID: ID<Container>, trackID: ID<Track>)
    func duplicateContainer(_ containerID: ID<Container>, trackID: ID<Track>)
    func splitContainerAtPlayhead(_ containerID: ID<Container>, trackID: ID<Track>)
    func deleteContainer(_ containerID: ID<Container>, trackID: ID<Track>)
    func resizeContainerLeft(_ containerID: ID<Container>, trackID: ID<Track>, newStartBar: Double, newLengthBars: Double)
    func resizeContainerRight(_ containerID: ID<Container>, trackID: ID<Track>, newLengthBars: Double)
    func trimContainerLeft(_ containerID: ID<Container>, trackID: ID<Track>, newAudioStartOffset: Double, newStartBar: Double, newLengthBars: Double)
    func trimContainerRight(_ containerID: ID<Container>, trackID: ID<Track>, newLengthBars: Double)
    func setContainerEnterFade(_ containerID: ID<Container>, fade: FadeSettings?)
    func setContainerExitFade(_ containerID: ID<Container>, fade: FadeSettings?)
}

public extension PlaybackGridCommandSink {
    func setPlayhead(bar: Double) {}
    func selectSection(_ sectionID: ID<SectionRegion>) {}
    func selectRange(_ range: ClosedRange<Int>) {}
    func clearRangeSelection() {}
    func selectContainer(_ containerID: ID<Container>, trackID: ID<Track>, modifiers: NSEvent.ModifierFlags) {}
    func openContainerEditor(_ containerID: ID<Container>, trackID: ID<Track>) {}
    func moveContainer(_ containerID: ID<Container>, trackID: ID<Track>, newStartBar: Double) {}
    func cloneContainer(_ containerID: ID<Container>, trackID: ID<Track>, newStartBar: Double) {}
    func copyContainer(_ containerID: ID<Container>, trackID: ID<Track>) {}
    func duplicateContainer(_ containerID: ID<Container>, trackID: ID<Track>) {}
    func splitContainerAtPlayhead(_ containerID: ID<Container>, trackID: ID<Track>) {}
    func deleteContainer(_ containerID: ID<Container>, trackID: ID<Track>) {}
    func resizeContainerLeft(_ containerID: ID<Container>, trackID: ID<Track>, newStartBar: Double, newLengthBars: Double) {}
    func resizeContainerRight(_ containerID: ID<Container>, trackID: ID<Track>, newLengthBars: Double) {}
    func trimContainerLeft(_ containerID: ID<Container>, trackID: ID<Track>, newAudioStartOffset: Double, newStartBar: Double, newLengthBars: Double) {}
    func trimContainerRight(_ containerID: ID<Container>, trackID: ID<Track>, newLengthBars: Double) {}
    func setContainerEnterFade(_ containerID: ID<Container>, fade: FadeSettings?) {}
    func setContainerExitFade(_ containerID: ID<Container>, fade: FadeSettings?) {}
}

public enum PlaybackGridLayout {
    public static let rulerHeight: CGFloat = 20
    public static let sectionLaneHeight: CGFloat = 24
    public static let trackAreaTop: CGFloat = rulerHeight + sectionLaneHeight
    public static let bottomPadding: CGFloat = 200
}

public struct PlaybackGridSnapshot: Equatable {
    public var tracks: [Track]
    public var sections: [SectionRegion]
    public var timeSignature: TimeSignature
    public var pixelsPerBar: CGFloat
    public var totalBars: Int
    public var trackHeights: [ID<Track>: CGFloat]
    public var defaultTrackHeight: CGFloat
    public var gridMode: GridMode
    public var selectedContainerIDs: Set<ID<Container>>
    public var selectedSectionID: ID<SectionRegion>?
    public var selectedRange: ClosedRange<Int>?
    public var rangeSelection: SelectionState.RangeSelection?
    public var showRulerAndSections: Bool
    public var playheadBar: Double
    public var cursorX: CGFloat?
    public var bottomPadding: CGFloat
    public var minimumContentHeight: CGFloat

    public init(
        tracks: [Track],
        sections: [SectionRegion],
        timeSignature: TimeSignature,
        pixelsPerBar: CGFloat,
        totalBars: Int,
        trackHeights: [ID<Track>: CGFloat],
        defaultTrackHeight: CGFloat,
        gridMode: GridMode,
        selectedContainerIDs: Set<ID<Container>>,
        selectedSectionID: ID<SectionRegion>?,
        selectedRange: ClosedRange<Int>?,
        rangeSelection: SelectionState.RangeSelection?,
        showRulerAndSections: Bool,
        playheadBar: Double,
        cursorX: CGFloat?,
        bottomPadding: CGFloat = PlaybackGridLayout.bottomPadding,
        minimumContentHeight: CGFloat = 0
    ) {
        self.tracks = tracks
        self.sections = sections
        self.timeSignature = timeSignature
        self.pixelsPerBar = pixelsPerBar
        self.totalBars = totalBars
        self.trackHeights = trackHeights
        self.defaultTrackHeight = defaultTrackHeight
        self.gridMode = gridMode
        self.selectedContainerIDs = selectedContainerIDs
        self.selectedSectionID = selectedSectionID
        self.selectedRange = selectedRange
        self.rangeSelection = rangeSelection
        self.showRulerAndSections = showRulerAndSections
        self.playheadBar = playheadBar
        self.cursorX = cursorX
        self.bottomPadding = bottomPadding
        self.minimumContentHeight = minimumContentHeight
    }
}

public struct PlaybackGridContainerLayout: Equatable {
    public var container: Container
    public var rect: CGRect
    public var waveformPeaks: [Float]?
    public var isSelected: Bool
    public var resolvedMIDINotes: [MIDINoteEvent]?
    public var enterFade: FadeSettings?
    public var exitFade: FadeSettings?
    public var audioDurationBars: Double?
}

public struct PlaybackGridTrackLayout: Equatable {
    public var track: Track
    public var yOrigin: CGFloat
    public var height: CGFloat
    public var containers: [PlaybackGridContainerLayout]
}

public struct PlaybackGridSectionLayout: Equatable {
    public var section: SectionRegion
    public var rect: CGRect
    public var isSelected: Bool
}

public struct PlaybackGridScene: Equatable {
    public var trackLayouts: [PlaybackGridTrackLayout]
    public var sectionLayouts: [PlaybackGridSectionLayout]
    public var contentHeight: CGFloat
}

public struct PlaybackGridRectInstance {
    public var origin: SIMD2<Float>
    public var size: SIMD2<Float>
    public var color: SIMD4<Float>
    public var cornerRadius: Float

    public init(origin: SIMD2<Float>, size: SIMD2<Float>, color: SIMD4<Float>, cornerRadius: Float = 0) {
        self.origin = origin
        self.size = size
        self.color = color
        self.cornerRadius = cornerRadius
    }
}

public struct PlaybackGridLineInstance {
    public var start: SIMD2<Float>
    public var end: SIMD2<Float>
    public var color: SIMD4<Float>
    public var width: Float
}

public struct PlaybackGridWaveformParams {
    public var containerOrigin: SIMD2<Float>
    public var containerSize: SIMD2<Float>
    public var fillColor: SIMD4<Float>
    public var peakOffset: UInt32
    public var peakCount: UInt32
    public var amplitude: Float
}

public struct PlaybackGridMIDINoteInstance {
    public var center: SIMD2<Float>
    public var halfSize: Float
    public var color: SIMD4<Float>
}

public struct PlaybackGridFadeVertex {
    public var position: SIMD2<Float>
    public var color: SIMD4<Float>
}

public struct PlaybackGridUniforms {
    public var projectionMatrix: simd_float4x4
    public var pixelsPerBar: Float
    public var canvasHeight: Float
    public var viewportMinX: Float
    public var viewportMaxX: Float

    public init(
        projectionMatrix: simd_float4x4,
        pixelsPerBar: Float,
        canvasHeight: Float,
        viewportMinX: Float,
        viewportMaxX: Float
    ) {
        self.projectionMatrix = projectionMatrix
        self.pixelsPerBar = pixelsPerBar
        self.canvasHeight = canvasHeight
        self.viewportMinX = viewportMinX
        self.viewportMaxX = viewportMaxX
    }

    public static func orthographic(
        left: Float,
        right: Float,
        top: Float,
        bottom: Float
    ) -> simd_float4x4 {
        let sx = 2 / (right - left)
        let sy = 2 / (top - bottom)
        let tx = -(right + left) / (right - left)
        let ty = -(top + bottom) / (top - bottom)

        return simd_float4x4(
            SIMD4<Float>(sx, 0, 0, 0),
            SIMD4<Float>(0, sy, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(tx, ty, 0, 1)
        )
    }
}

public struct PlaybackGridDebugStats {
    public var rectCount: Int = 0
    public var lineCount: Int = 0
    public var waveformCount: Int = 0
    public var midiCount: Int = 0
    public var fadeVertexCount: Int = 0
    public var borderCount: Int = 0
}
