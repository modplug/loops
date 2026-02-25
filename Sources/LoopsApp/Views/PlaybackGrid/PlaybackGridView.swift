import SwiftUI
import UniformTypeIdentifiers
import LoopsCore

public struct PlaybackGridView: View {
    @Bindable var viewModel: TimelineViewModel
    @Bindable var projectViewModel: ProjectViewModel
    var selectionState: SelectionState
    var clipboardState: ClipboardState
    let song: Song
    let tracks: [Track]
    let minHeight: CGFloat
    var pianoRollState: PianoRollEditorState?
    var ghostDropState: GhostTrackDropState?
    var showRulerAndSections: Bool = true
    var bottomPadding: CGFloat = PlaybackGridLayout.bottomPadding
    var onDropFilesToNewTracks: ((_ urls: [URL], _ startBar: Double) -> Void)?
    var onContainerDoubleClick: (() -> Void)?
    var onPlayheadPosition: ((Double) -> Void)?
    var onNotePreview: ((_ pitch: UInt8, _ isNoteOn: Bool) -> Void)?
    var onOpenPianoRollSheet: (() -> Void)?
    var onSectionSelect: ((ID<SectionRegion>) -> Void)?
    var onRangeSelect: ((ClosedRange<Int>) -> Void)?
    var onRangeDeselect: (() -> Void)?
    var debugLabel: String?

    public init(
        viewModel: TimelineViewModel,
        projectViewModel: ProjectViewModel,
        selectionState: SelectionState,
        clipboardState: ClipboardState? = nil,
        song: Song,
        tracks: [Track]? = nil,
        minHeight: CGFloat = 0,
        pianoRollState: PianoRollEditorState? = nil,
        ghostDropState: GhostTrackDropState? = nil,
        showRulerAndSections: Bool = true,
        bottomPadding: CGFloat = PlaybackGridLayout.bottomPadding,
        onDropFilesToNewTracks: ((_ urls: [URL], _ startBar: Double) -> Void)? = nil,
        onContainerDoubleClick: (() -> Void)? = nil,
        onPlayheadPosition: ((Double) -> Void)? = nil,
        onNotePreview: ((_ pitch: UInt8, _ isNoteOn: Bool) -> Void)? = nil,
        onOpenPianoRollSheet: (() -> Void)? = nil,
        onSectionSelect: ((ID<SectionRegion>) -> Void)? = nil,
        onRangeSelect: ((ClosedRange<Int>) -> Void)? = nil,
        onRangeDeselect: (() -> Void)? = nil,
        debugLabel: String? = nil
    ) {
        self.viewModel = viewModel
        self.projectViewModel = projectViewModel
        self.selectionState = selectionState
        self.clipboardState = clipboardState ?? projectViewModel.clipboardState
        self.song = song
        self.tracks = tracks ?? song.tracks
        self.minHeight = minHeight
        self.pianoRollState = pianoRollState
        self.ghostDropState = ghostDropState
        self.showRulerAndSections = showRulerAndSections
        self.bottomPadding = bottomPadding
        self.onDropFilesToNewTracks = onDropFilesToNewTracks
        self.onContainerDoubleClick = onContainerDoubleClick
        self.onPlayheadPosition = onPlayheadPosition
        self.onNotePreview = onNotePreview
        self.onOpenPianoRollSheet = onOpenPianoRollSheet
        self.onSectionSelect = onSectionSelect
        self.onRangeSelect = onRangeSelect
        self.onRangeDeselect = onRangeDeselect
        self.debugLabel = debugLabel
    }

    public var totalContentHeight: CGFloat {
        tracks.reduce(CGFloat(0)) { total, track in
            let base = viewModel.baseTrackHeight(for: track.id)
            let trackHeight = viewModel.trackHeight(for: track, baseHeight: base)
            let pianoRollExtra = pianoRollState?.extraHeight(forTrackID: track.id) ?? 0
            return total + trackHeight + pianoRollExtra
        }
    }

    private var displayHeight: CGFloat {
        let headerHeight = showRulerAndSections ? PlaybackGridLayout.trackAreaTop : CGFloat(0)
        let contentHeight = headerHeight + totalContentHeight + bottomPadding
        return max(contentHeight, minHeight)
    }

    private var displayWidth: CGFloat {
        max(viewModel.totalWidth, 1)
    }

    public var body: some View {
        PlaybackGridRepresentable(
            tracks: tracks,
            viewModel: viewModel,
            projectViewModel: projectViewModel,
            selectionState: selectionState,
            timeSignature: song.timeSignature,
            sections: song.sections,
            showRulerAndSections: showRulerAndSections,
            bottomPadding: bottomPadding,
            minimumContentHeight: displayHeight,
            debugLabel: debugLabel,
            onPlayheadPosition: onPlayheadPosition,
            onSectionSelect: onSectionSelect,
            onRangeSelect: onRangeSelect,
            onRangeDeselect: onRangeDeselect,
            onContainerSelect: { containerID, trackID, modifiers in
                handleContainerSelection(containerID: containerID, trackID: trackID, modifiers: modifiers)
            },
            onContainerOpenEditor: { containerID, _ in
                selectionState.selectedContainerID = containerID
                selectionState.lastSelectedContainerID = containerID
                onContainerDoubleClick?()
            },
            onContainerMove: { containerID, trackID, newStartBar in
                _ = projectViewModel.moveContainer(trackID: trackID, containerID: containerID, newStartBar: newStartBar)
            },
            onContainerClone: { containerID, trackID, newStartBar in
                _ = projectViewModel.cloneContainer(trackID: trackID, containerID: containerID, newStartBar: newStartBar)
            },
            onContainerCopy: { containerID, trackID in
                projectViewModel.copyContainer(trackID: trackID, containerID: containerID)
            },
            onContainerDuplicate: { containerID, trackID in
                _ = projectViewModel.duplicateContainer(trackID: trackID, containerID: containerID)
            },
            onContainerSplitAtPlayhead: { containerID, trackID in
                _ = projectViewModel.splitContainer(
                    trackID: trackID,
                    containerID: containerID,
                    atBar: viewModel.playheadBar
                )
            },
            onContainerDelete: { containerID, trackID in
                projectViewModel.removeContainer(trackID: trackID, containerID: containerID)
            },
            onContainerResizeLeft: { containerID, trackID, newStartBar, newLengthBars in
                _ = projectViewModel.resizeContainer(
                    trackID: trackID,
                    containerID: containerID,
                    newStartBar: newStartBar,
                    newLengthBars: newLengthBars
                )
            },
            onContainerResizeRight: { containerID, trackID, newLengthBars in
                _ = projectViewModel.resizeContainer(
                    trackID: trackID,
                    containerID: containerID,
                    newLengthBars: newLengthBars
                )
            },
            onContainerTrimLeft: { containerID, trackID, newAudioStartOffset, newStartBar, newLengthBars in
                _ = projectViewModel.trimContainerLeft(
                    trackID: trackID,
                    containerID: containerID,
                    newStartBar: newStartBar,
                    newLength: newLengthBars,
                    newAudioStartOffset: newAudioStartOffset
                )
            },
            onContainerTrimRight: { containerID, trackID, newLengthBars in
                _ = projectViewModel.trimContainerRight(
                    trackID: trackID,
                    containerID: containerID,
                    newLength: newLengthBars
                )
            },
            onSetContainerEnterFade: { containerID, fade in
                projectViewModel.setContainerEnterFade(containerID: containerID, fade: fade)
            },
            onSetContainerExitFade: { containerID, fade in
                projectViewModel.setContainerExitFade(containerID: containerID, fade: fade)
            }
        )
        .frame(width: displayWidth, height: displayHeight)
        .onDrop(of: [.fileURL], delegate: PlaybackGridDropDelegate(
            ghostDropState: ghostDropState,
            viewModel: viewModel,
            song: song,
            onPerformDrop: onDropFilesToNewTracks
        ))
        .onKeyPress("+") {
            viewModel.zoomIn()
            return .handled
        }
        .onKeyPress("-") {
            viewModel.zoomOut()
            return .handled
        }
        .onKeyPress(.delete) {
            deleteSelectedContainer()
            return .handled
        }
    }

    private func deleteSelectedContainer() {
        guard let containerID = selectionState.selectedContainerID else { return }
        for track in song.tracks {
            if track.containers.contains(where: { $0.id == containerID }) {
                projectViewModel.removeContainer(trackID: track.id, containerID: containerID)
                return
            }
        }
    }

    private func handleContainerSelection(containerID: ID<Container>, trackID: ID<Track>, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selectionState.selectedContainerIDs.isEmpty,
               let selected = selectionState.selectedContainerID {
                selectionState.selectedContainerIDs = [selected]
                selectionState.selectedContainerID = nil
            }

            if selectionState.selectedContainerIDs.contains(containerID) {
                selectionState.selectedContainerIDs.remove(containerID)
            } else {
                selectionState.selectedContainerIDs.insert(containerID)
            }
            selectionState.lastSelectedContainerID = containerID
        } else if modifiers.contains(.shift),
                  let track = song.tracks.first(where: { $0.id == trackID }) {
            let containers = track.containers.sorted { $0.startBar < $1.startBar }
            let anchorID = selectionState.lastSelectedContainerID ?? selectionState.selectedContainerID
            guard let anchorID,
                  let anchorIndex = containers.firstIndex(where: { $0.id == anchorID }),
                  let clickedIndex = containers.firstIndex(where: { $0.id == containerID }) else {
                selectionState.selectedContainerID = containerID
                selectionState.lastSelectedContainerID = containerID
                return
            }

            let range = min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)
            selectionState.selectedContainerIDs = Set(containers[range].map(\.id))
            selectionState.selectedContainerID = nil
            selectionState.lastSelectedContainerID = containerID
        } else {
            selectionState.selectedContainerID = containerID
            selectionState.lastSelectedContainerID = containerID
        }
    }
}

private struct PlaybackGridDropDelegate: DropDelegate {
    let ghostDropState: GhostTrackDropState?
    let viewModel: TimelineViewModel
    let song: Song
    let onPerformDrop: ((_ urls: [URL], _ startBar: Double) -> Void)?

    private static let supportedAudioExtensions: Set<String> = ["wav", "aiff", "aif", "caf", "mp3", "m4a"]
    private static let supportedMIDIExtensions: Set<String> = ["mid", "midi"]

    func dropEntered(info: DropInfo) {
        guard let ghostDropState else { return }
        if ghostDropState.activate() {
            resolveGhostTracks(from: info, into: ghostDropState)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if let ghostDropState {
            let bar = viewModel.snappedBar(forXPosition: info.location.x, timeSignature: song.timeSignature)
            ghostDropState.dropBar = max(1.0, bar)
        }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        ghostDropState?.deactivate()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let ghostDropState, let onPerformDrop else { return false }
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else {
            ghostDropState.reset()
            return false
        }

        var resolvedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    let ext = url.pathExtension.lowercased()
                    if Self.supportedAudioExtensions.contains(ext) || Self.supportedMIDIExtensions.contains(ext) {
                        resolvedURLs.append(url)
                    }
                }
                group.leave()
            }
        }

        let dropBar = ghostDropState.dropBar
        group.notify(queue: .main) {
            ghostDropState.reset()
            if !resolvedURLs.isEmpty {
                onPerformDrop(resolvedURLs, dropBar)
            }
        }

        return true
    }

    private func resolveGhostTracks(from info: DropInfo, into ghostDropState: GhostTrackDropState) {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return }

        let group = DispatchGroup()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    urls.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let audioFiles = urls.filter { Self.supportedAudioExtensions.contains($0.pathExtension.lowercased()) }
            let midiFiles = urls.filter { Self.supportedMIDIExtensions.contains($0.pathExtension.lowercased()) }
            ghostDropState.ghostTracks = (audioFiles + midiFiles).map {
                GhostTrackInfo(
                    fileName: $0.lastPathComponent,
                    trackKind: Self.supportedMIDIExtensions.contains($0.pathExtension.lowercased()) ? .midi : .audio,
                    url: $0
                )
            }
        }
    }
}
