import SwiftUI
import LoopsCore

/// SwiftUI bridge for TimelineCanvasView.
/// Reads from TimelineViewModel and ProjectViewModel, pushes updates to the NSView.
///
/// Usage: Drop this into the view hierarchy wherever the SwiftUI TimelineView was.
/// The feature flag `useNSViewTimeline` controls which path is active.
public struct TimelineCanvasRepresentable: NSViewRepresentable {
    let tracks: [Track]
    @Bindable var viewModel: TimelineViewModel
    @Bindable var projectViewModel: ProjectViewModel
    var selectionState: SelectionState
    let timeSignature: TimeSignature
    let minHeight: CGFloat
    let sections: [SectionRegion]

    /// When false, the canvas skips ruler and section lane drawing.
    /// Used for the docked master track which shares the main timeline's ruler.
    var showRulerAndSections: Bool = true

    /// Callbacks matching existing SwiftUI TimelineView API.
    var onPlayheadPosition: ((Double) -> Void)?
    var onSectionSelect: ((ID<SectionRegion>) -> Void)?
    var onRangeSelect: ((ClosedRange<Int>) -> Void)?
    var onRangeDeselect: (() -> Void)?

    public func makeNSView(context: Context) -> TimelineCanvasView {
        let view = TimelineCanvasView(frame: .zero)
        view.showRulerAndSections = showRulerAndSections

        // Wire up data providers
        view.waveformPeaksProvider = { [projectViewModel] container in
            projectViewModel.waveformPeaks(for: container)
        }
        view.audioDurationBarsProvider = { [projectViewModel] container in
            projectViewModel.recordingDurationBars(for: container)
        }
        view.resolvedMIDISequenceProvider = { [projectViewModel] container in
            projectViewModel.resolvedMIDISequence(container)
        }

        // Wire up callbacks
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

    public func updateNSView(_ nsView: TimelineCanvasView, context: Context) {
        configureView(nsView)
    }

    private func configureView(_ view: TimelineCanvasView) {
        let selectedIDs = selectionState.effectiveSelectedContainerIDs

        // configure() has internal change detection — it only redraws when data changed.
        // This is safe to call on every SwiftUI update cycle (scroll, playhead, etc).
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

        // Overlay layers bypass draw() — always update cheaply via CATransaction.
        let totalHeight = view.trackLayouts.last.map { $0.yOrigin + $0.height } ?? minHeight
        let displayHeight = max(totalHeight, minHeight)
        view.updatePlayhead(bar: viewModel.playheadBar, height: displayHeight)
        view.updateCursor(x: viewModel.cursorX, height: displayHeight)

        // Do NOT set view.frame here — SwiftUI sizes the NSView via the .frame() modifier
        // on the parent. Setting frame inside updateNSView fights with SwiftUI's layout
        // engine and causes infinite layout loops during zoom.
    }
}
