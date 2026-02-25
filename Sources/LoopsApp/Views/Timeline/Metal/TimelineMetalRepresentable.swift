import SwiftUI
import LoopsCore

/// SwiftUI bridge for TimelineMetalView.
/// Identical API to TimelineCanvasRepresentable — drop-in replacement
/// controlled by the `useMetalTimeline` feature flag.
public struct TimelineMetalRepresentable: NSViewRepresentable {
    let tracks: [Track]
    @Bindable var viewModel: TimelineViewModel
    @Bindable var projectViewModel: ProjectViewModel
    var selectionState: SelectionState
    let timeSignature: TimeSignature
    let minHeight: CGFloat
    let sections: [SectionRegion]

    var showRulerAndSections: Bool = true

    var onPlayheadPosition: ((Double) -> Void)?
    var onSectionSelect: ((ID<SectionRegion>) -> Void)?
    var onRangeSelect: ((ClosedRange<Int>) -> Void)?
    var onRangeDeselect: (() -> Void)?

    public func makeNSView(context: Context) -> TimelineMetalView {
        let view = TimelineMetalView(frame: .zero)
        view.showRulerAndSections = showRulerAndSections

        view.waveformPeaksProvider = { [projectViewModel] container in
            projectViewModel.waveformPeaks(for: container)
        }
        view.audioDurationBarsProvider = { [projectViewModel] container in
            projectViewModel.recordingDurationBars(for: container)
        }
        view.resolvedMIDISequenceProvider = { [projectViewModel] container in
            projectViewModel.resolvedMIDISequence(container)
        }

        view.onPlayheadPosition = { bar in
            onPlayheadPosition?(bar)
        }
        view.onCursorPosition = { [viewModel] x in
            viewModel.cursorX = x
        }
        view.onSectionSelect = { sectionID in
            onSectionSelect?(sectionID)
        }
        view.onRangeSelect = { range in
            onRangeSelect?(range)
        }
        view.onRangeDeselect = {
            onRangeDeselect?()
        }

        configureView(view)
        return view
    }

    public func updateNSView(_ nsView: TimelineMetalView, context: Context) {
        configureView(nsView)
    }

    private func configureView(_ view: TimelineMetalView) {
        let selectedIDs = selectionState.effectiveSelectedContainerIDs

        view.configure(
            tracks: tracks,
            pixelsPerBar: viewModel.pixelsPerBar,
            totalBars: viewModel.totalBars,
            timeSignature: timeSignature,
            selectedContainerIDs: selectedIDs,
            trackHeights: viewModel.trackHeights,
            defaultTrackHeight: TimelineViewModel.defaultTrackHeight,
            gridMode: viewModel.gridMode,
            selectedRange: viewModel.selectedRange,
            rangeSelection: selectionState.rangeSelection,
            sections: sections,
            selectedSectionID: selectionState.selectedSectionID
        )

        let totalHeight = view.trackLayouts.last.map { $0.yOrigin + $0.height } ?? minHeight
        let displayHeight = max(totalHeight, minHeight)
        view.updatePlayhead(bar: viewModel.playheadBar, height: displayHeight)
        view.updateCursor(x: viewModel.cursorX, height: displayHeight)
    }
}
