import SwiftUI
import AppKit
import LoopsCore

public struct PlaybackGridRepresentable: NSViewRepresentable {
    let tracks: [Track]
    @Bindable var viewModel: TimelineViewModel
    @Bindable var projectViewModel: ProjectViewModel
    var selectionState: SelectionState
    let timeSignature: TimeSignature
    let sections: [SectionRegion]
    var showRulerAndSections: Bool = true
    var bottomPadding: CGFloat = PlaybackGridLayout.bottomPadding
    var minimumContentHeight: CGFloat = 0
    var debugLabel: String?

    var onPlayheadPosition: ((Double) -> Void)?
    var onSectionSelect: ((ID<SectionRegion>) -> Void)?
    var onRangeSelect: ((ClosedRange<Int>) -> Void)?
    var onRangeDeselect: (() -> Void)?
    var onContainerSelect: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ modifiers: NSEvent.ModifierFlags) -> Void)?
    var onContainerOpenEditor: ((_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void)?
    var onContainerMove: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newStartBar: Double) -> Void)?
    var onContainerClone: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newStartBar: Double) -> Void)?
    var onContainerCopy: ((_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void)?
    var onContainerDuplicate: ((_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void)?
    var onContainerSplitAtPlayhead: ((_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void)?
    var onContainerDelete: ((_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void)?
    var onContainerResizeLeft: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newStartBar: Double, _ newLengthBars: Double) -> Void)?
    var onContainerResizeRight: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newLengthBars: Double) -> Void)?
    var onContainerTrimLeft: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newAudioStartOffset: Double, _ newStartBar: Double, _ newLengthBars: Double) -> Void)?
    var onContainerTrimRight: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newLengthBars: Double) -> Void)?
    var onSetContainerEnterFade: ((_ containerID: ID<Container>, _ fade: FadeSettings?) -> Void)?
    var onSetContainerExitFade: ((_ containerID: ID<Container>, _ fade: FadeSettings?) -> Void)?

    public func makeNSView(context: Context) -> PlaybackGridNSView {
        let view = PlaybackGridNSView(frame: .zero)
        view.debugLabel = debugLabel ?? "grid"

        view.waveformPeaksProvider = { [projectViewModel] container in
            projectViewModel.waveformPeaks(for: container)
        }
        view.audioDurationBarsProvider = { [projectViewModel] container in
            projectViewModel.recordingDurationBars(for: container)
        }
        view.resolvedMIDISequenceProvider = { [projectViewModel] container in
            projectViewModel.resolvedMIDISequence(container)
        }

        view.onCursorPosition = { [viewModel] x in
            viewModel.cursorX = x
        }

        configure(view)
        return view
    }

    public func updateNSView(_ nsView: PlaybackGridNSView, context: Context) {
        nsView.debugLabel = debugLabel ?? "grid"
        configure(nsView)
    }

    private func configure(_ view: PlaybackGridNSView) {
        let adapter = CommandAdapter(
            onPlayheadPosition: onPlayheadPosition,
            onSectionSelect: onSectionSelect,
            onRangeSelect: onRangeSelect,
            onRangeDeselect: onRangeDeselect,
            onContainerSelect: onContainerSelect,
            onContainerOpenEditor: onContainerOpenEditor,
            onContainerMove: onContainerMove,
            onContainerClone: onContainerClone,
            onContainerCopy: onContainerCopy,
            onContainerDuplicate: onContainerDuplicate,
            onContainerSplitAtPlayhead: onContainerSplitAtPlayhead,
            onContainerDelete: onContainerDelete,
            onContainerResizeLeft: onContainerResizeLeft,
            onContainerResizeRight: onContainerResizeRight,
            onContainerTrimLeft: onContainerTrimLeft,
            onContainerTrimRight: onContainerTrimRight,
            onSetContainerEnterFade: onSetContainerEnterFade,
            onSetContainerExitFade: onSetContainerExitFade
        )
        view.setCommandSink(adapter)

        // Store adapter on coordinator to retain it for the view lifetime.
        PlaybackGridRepresentableStorage.shared.store(adapter: adapter, for: ObjectIdentifier(view))

        view.configure(snapshot: PlaybackGridSnapshot(
            tracks: tracks,
            sections: sections,
            timeSignature: timeSignature,
            pixelsPerBar: viewModel.pixelsPerBar,
            totalBars: viewModel.totalBars,
            trackHeights: viewModel.trackHeights,
            defaultTrackHeight: TimelineViewModel.defaultTrackHeight,
            gridMode: viewModel.gridMode,
            selectedContainerIDs: selectionState.effectiveSelectedContainerIDs,
            selectedSectionID: selectionState.selectedSectionID,
            selectedRange: viewModel.selectedRange,
            rangeSelection: selectionState.rangeSelection,
            showRulerAndSections: showRulerAndSections,
            playheadBar: viewModel.playheadBar,
            cursorX: viewModel.cursorX,
            bottomPadding: bottomPadding,
            minimumContentHeight: minimumContentHeight
        ))
    }
}

private final class CommandAdapter: PlaybackGridCommandSink {
    private let onPlayheadPosition: ((Double) -> Void)?
    private let onSectionSelect: ((ID<SectionRegion>) -> Void)?
    private let onRangeSelect: ((ClosedRange<Int>) -> Void)?
    private let onRangeDeselect: (() -> Void)?
    private let onContainerSelect: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ modifiers: NSEvent.ModifierFlags) -> Void)?
    private let onContainerOpenEditor: ((_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void)?
    private let onContainerMove: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newStartBar: Double) -> Void)?
    private let onContainerClone: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newStartBar: Double) -> Void)?
    private let onContainerCopy: ((_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void)?
    private let onContainerDuplicate: ((_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void)?
    private let onContainerSplitAtPlayhead: ((_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void)?
    private let onContainerDelete: ((_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void)?
    private let onContainerResizeLeft: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newStartBar: Double, _ newLengthBars: Double) -> Void)?
    private let onContainerResizeRight: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newLengthBars: Double) -> Void)?
    private let onContainerTrimLeft: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newAudioStartOffset: Double, _ newStartBar: Double, _ newLengthBars: Double) -> Void)?
    private let onContainerTrimRight: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newLengthBars: Double) -> Void)?
    private let onSetContainerEnterFade: ((_ containerID: ID<Container>, _ fade: FadeSettings?) -> Void)?
    private let onSetContainerExitFade: ((_ containerID: ID<Container>, _ fade: FadeSettings?) -> Void)?

    init(
        onPlayheadPosition: ((Double) -> Void)?,
        onSectionSelect: ((ID<SectionRegion>) -> Void)?,
        onRangeSelect: ((ClosedRange<Int>) -> Void)?,
        onRangeDeselect: (() -> Void)?,
        onContainerSelect: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ modifiers: NSEvent.ModifierFlags) -> Void)?,
        onContainerOpenEditor: ((_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void)?,
        onContainerMove: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newStartBar: Double) -> Void)?,
        onContainerClone: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newStartBar: Double) -> Void)?,
        onContainerCopy: ((_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void)?,
        onContainerDuplicate: ((_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void)?,
        onContainerSplitAtPlayhead: ((_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void)?,
        onContainerDelete: ((_ containerID: ID<Container>, _ trackID: ID<Track>) -> Void)?,
        onContainerResizeLeft: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newStartBar: Double, _ newLengthBars: Double) -> Void)?,
        onContainerResizeRight: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newLengthBars: Double) -> Void)?,
        onContainerTrimLeft: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newAudioStartOffset: Double, _ newStartBar: Double, _ newLengthBars: Double) -> Void)?,
        onContainerTrimRight: ((_ containerID: ID<Container>, _ trackID: ID<Track>, _ newLengthBars: Double) -> Void)?,
        onSetContainerEnterFade: ((_ containerID: ID<Container>, _ fade: FadeSettings?) -> Void)?,
        onSetContainerExitFade: ((_ containerID: ID<Container>, _ fade: FadeSettings?) -> Void)?
    ) {
        self.onPlayheadPosition = onPlayheadPosition
        self.onSectionSelect = onSectionSelect
        self.onRangeSelect = onRangeSelect
        self.onRangeDeselect = onRangeDeselect
        self.onContainerSelect = onContainerSelect
        self.onContainerOpenEditor = onContainerOpenEditor
        self.onContainerMove = onContainerMove
        self.onContainerClone = onContainerClone
        self.onContainerCopy = onContainerCopy
        self.onContainerDuplicate = onContainerDuplicate
        self.onContainerSplitAtPlayhead = onContainerSplitAtPlayhead
        self.onContainerDelete = onContainerDelete
        self.onContainerResizeLeft = onContainerResizeLeft
        self.onContainerResizeRight = onContainerResizeRight
        self.onContainerTrimLeft = onContainerTrimLeft
        self.onContainerTrimRight = onContainerTrimRight
        self.onSetContainerEnterFade = onSetContainerEnterFade
        self.onSetContainerExitFade = onSetContainerExitFade
    }

    func setPlayhead(bar: Double) {
        onPlayheadPosition?(bar)
    }

    func selectSection(_ sectionID: ID<SectionRegion>) {
        onSectionSelect?(sectionID)
    }

    func selectRange(_ range: ClosedRange<Int>) {
        onRangeSelect?(range)
    }

    func clearRangeSelection() {
        onRangeDeselect?()
    }

    func selectContainer(_ containerID: ID<Container>, trackID: ID<Track>, modifiers: NSEvent.ModifierFlags) {
        onContainerSelect?(containerID, trackID, modifiers)
    }

    func openContainerEditor(_ containerID: ID<Container>, trackID: ID<Track>) {
        onContainerOpenEditor?(containerID, trackID)
    }

    func moveContainer(_ containerID: ID<Container>, trackID: ID<Track>, newStartBar: Double) {
        onContainerMove?(containerID, trackID, newStartBar)
    }

    func cloneContainer(_ containerID: ID<Container>, trackID: ID<Track>, newStartBar: Double) {
        onContainerClone?(containerID, trackID, newStartBar)
    }

    func copyContainer(_ containerID: ID<Container>, trackID: ID<Track>) {
        onContainerCopy?(containerID, trackID)
    }

    func duplicateContainer(_ containerID: ID<Container>, trackID: ID<Track>) {
        onContainerDuplicate?(containerID, trackID)
    }

    func splitContainerAtPlayhead(_ containerID: ID<Container>, trackID: ID<Track>) {
        onContainerSplitAtPlayhead?(containerID, trackID)
    }

    func deleteContainer(_ containerID: ID<Container>, trackID: ID<Track>) {
        onContainerDelete?(containerID, trackID)
    }

    func resizeContainerLeft(_ containerID: ID<Container>, trackID: ID<Track>, newStartBar: Double, newLengthBars: Double) {
        onContainerResizeLeft?(containerID, trackID, newStartBar, newLengthBars)
    }

    func resizeContainerRight(_ containerID: ID<Container>, trackID: ID<Track>, newLengthBars: Double) {
        onContainerResizeRight?(containerID, trackID, newLengthBars)
    }

    func trimContainerLeft(_ containerID: ID<Container>, trackID: ID<Track>, newAudioStartOffset: Double, newStartBar: Double, newLengthBars: Double) {
        onContainerTrimLeft?(containerID, trackID, newAudioStartOffset, newStartBar, newLengthBars)
    }

    func trimContainerRight(_ containerID: ID<Container>, trackID: ID<Track>, newLengthBars: Double) {
        onContainerTrimRight?(containerID, trackID, newLengthBars)
    }

    func setContainerEnterFade(_ containerID: ID<Container>, fade: FadeSettings?) {
        onSetContainerEnterFade?(containerID, fade)
    }

    func setContainerExitFade(_ containerID: ID<Container>, fade: FadeSettings?) {
        onSetContainerExitFade?(containerID, fade)
    }
}

private final class PlaybackGridRepresentableStorage {
    static let shared = PlaybackGridRepresentableStorage()

    private var adapters: [ObjectIdentifier: CommandAdapter] = [:]
    private let lock = NSLock()

    func store(adapter: CommandAdapter, for key: ObjectIdentifier) {
        lock.lock()
        adapters[key] = adapter
        lock.unlock()
    }
}
