import SwiftUI
import UniformTypeIdentifiers
import LoopsCore

/// Renders a single track's horizontal lane on the timeline.
/// Supports container rendering and click-drag to create new containers.
public struct TrackLaneView: View {
    let track: Track
    let pixelsPerBar: CGFloat
    let totalBars: Int
    let height: CGFloat
    let selectedContainerID: ID<Container>?
    /// Closure to look up waveform peaks for a container.
    var waveformPeaksForContainer: ((_ container: Container) -> [Float]?)?
    var onContainerSelect: ((_ containerID: ID<Container>) -> Void)?
    var onContainerDelete: ((_ containerID: ID<Container>) -> Void)?
    var onContainerMove: ((_ containerID: ID<Container>, _ newStartBar: Int) -> Bool)?
    var onContainerResizeLeft: ((_ containerID: ID<Container>, _ newStartBar: Int, _ newLength: Int) -> Bool)?
    var onContainerResizeRight: ((_ containerID: ID<Container>, _ newLength: Int) -> Bool)?
    var onCreateContainer: ((_ startBar: Int, _ lengthBars: Int) -> Void)?
    var onDropAudioFile: ((_ url: URL, _ startBar: Int) -> Void)?
    var onContainerDoubleClick: ((_ containerID: ID<Container>) -> Void)?
    var onCloneContainer: ((_ containerID: ID<Container>, _ newStartBar: Int) -> Void)?

    @State private var dragStartX: CGFloat?
    @State private var dragCurrentX: CGFloat?
    @State private var isCreatingContainer = false

    public init(
        track: Track,
        pixelsPerBar: CGFloat,
        totalBars: Int,
        height: CGFloat = 80,
        selectedContainerID: ID<Container>? = nil,
        waveformPeaksForContainer: ((_ container: Container) -> [Float]?)? = nil,
        onContainerSelect: ((_ containerID: ID<Container>) -> Void)? = nil,
        onContainerDelete: ((_ containerID: ID<Container>) -> Void)? = nil,
        onContainerMove: ((_ containerID: ID<Container>, _ newStartBar: Int) -> Bool)? = nil,
        onContainerResizeLeft: ((_ containerID: ID<Container>, _ newStartBar: Int, _ newLength: Int) -> Bool)? = nil,
        onContainerResizeRight: ((_ containerID: ID<Container>, _ newLength: Int) -> Bool)? = nil,
        onCreateContainer: ((_ startBar: Int, _ lengthBars: Int) -> Void)? = nil,
        onDropAudioFile: ((_ url: URL, _ startBar: Int) -> Void)? = nil,
        onContainerDoubleClick: ((_ containerID: ID<Container>) -> Void)? = nil,
        onCloneContainer: ((_ containerID: ID<Container>, _ newStartBar: Int) -> Void)? = nil
    ) {
        self.track = track
        self.pixelsPerBar = pixelsPerBar
        self.totalBars = totalBars
        self.height = height
        self.selectedContainerID = selectedContainerID
        self.waveformPeaksForContainer = waveformPeaksForContainer
        self.onContainerSelect = onContainerSelect
        self.onContainerDelete = onContainerDelete
        self.onContainerMove = onContainerMove
        self.onContainerResizeLeft = onContainerResizeLeft
        self.onContainerResizeRight = onContainerResizeRight
        self.onCreateContainer = onCreateContainer
        self.onDropAudioFile = onDropAudioFile
        self.onContainerDoubleClick = onContainerDoubleClick
        self.onCloneContainer = onCloneContainer
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Track background — also handles drag-to-create
            Rectangle()
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.3))
                .contentShape(Rectangle())
                .gesture(createContainerGesture)

            // Draw-to-create preview
            if isCreatingContainer, let startX = dragStartX, let currentX = dragCurrentX {
                let minX = min(startX, currentX)
                let maxX = max(startX, currentX)
                RoundedRectangle(cornerRadius: 4)
                    .fill(trackColor.opacity(0.2))
                    .strokeBorder(trackColor.opacity(0.5), lineWidth: 1, antialiased: true)
                    .frame(width: maxX - minX, height: height - 4)
                    .offset(x: minX, y: 2)
            }

            // Existing containers
            ForEach(track.containers) { container in
                ContainerView(
                    container: container,
                    pixelsPerBar: pixelsPerBar,
                    height: height - 4,
                    isSelected: container.id == selectedContainerID,
                    trackColor: trackColor,
                    waveformPeaks: waveformPeaksForContainer?(container),
                    isClone: container.parentContainerID != nil,
                    overriddenFields: container.overriddenFields,
                    onSelect: { onContainerSelect?(container.id) },
                    onDelete: { onContainerDelete?(container.id) },
                    onMove: { newStart in onContainerMove?(container.id, newStart) ?? false },
                    onResizeLeft: { start, len in onContainerResizeLeft?(container.id, start, len) ?? false },
                    onResizeRight: { len in onContainerResizeRight?(container.id, len) ?? false },
                    onDoubleClick: { onContainerDoubleClick?(container.id) },
                    onClone: { newStart in onCloneContainer?(container.id, newStart) }
                )
                .offset(x: CGFloat(container.startBar - 1) * pixelsPerBar, y: 2)
            }
        }
        .frame(width: CGFloat(totalBars) * pixelsPerBar, height: height)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers, location in
            guard let onDrop = onDropAudioFile else { return false }
            guard let provider = providers.first else { return false }
            let barAtDrop = max(Int(location.x / pixelsPerBar) + 1, 1)
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let ext = url.pathExtension.lowercased()
                let supported: Set<String> = ["wav", "aiff", "aif", "caf", "mp3", "m4a"]
                guard supported.contains(ext) else { return }
                DispatchQueue.main.async {
                    onDrop(url, barAtDrop)
                }
            }
            return true
        }
    }

    private var createContainerGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if !isCreatingContainer {
                    isCreatingContainer = true
                    // Snap start to bar boundary
                    let snappedStart = round(value.startLocation.x / pixelsPerBar) * pixelsPerBar
                    dragStartX = snappedStart
                }
                // Snap current to bar boundary
                let snappedCurrent = round(value.location.x / pixelsPerBar) * pixelsPerBar
                dragCurrentX = snappedCurrent
            }
            .onEnded { value in
                defer {
                    isCreatingContainer = false
                    dragStartX = nil
                    dragCurrentX = nil
                }

                guard let startX = dragStartX, let currentX = dragCurrentX else { return }

                let minX = min(startX, currentX)
                let maxX = max(startX, currentX)
                let startBar = Int(minX / pixelsPerBar) + 1
                let lengthBars = max(Int(round((maxX - minX) / pixelsPerBar)), 1)

                onCreateContainer?(startBar, lengthBars)
            }
    }

    private var trackColor: Color {
        switch track.kind {
        case .audio: return .blue
        case .midi: return .purple
        case .bus: return .green
        case .backing: return .orange
        }
    }
}
