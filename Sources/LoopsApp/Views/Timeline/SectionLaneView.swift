import SwiftUI
import LoopsCore

/// Renders section regions as colored bands on a lane above the track area.
struct SectionLaneView: View {
    let sections: [SectionRegion]
    let pixelsPerBar: CGFloat
    let totalBars: Int
    let selectedSectionID: ID<SectionRegion>?
    let onSectionSelect: (ID<SectionRegion>) -> Void
    let onSectionCreate: (Int, Int) -> Void
    let onSectionMove: (ID<SectionRegion>, Int) -> Void
    let onSectionResizeLeft: (ID<SectionRegion>, Int, Int) -> Void
    let onSectionResizeRight: (ID<SectionRegion>, Int) -> Void
    let onSectionDoubleClick: (ID<SectionRegion>) -> Void
    let onSectionNavigate: (Int) -> Void
    var onSectionDelete: ((ID<SectionRegion>) -> Void)?
    var onSectionRecolor: ((ID<SectionRegion>, String) -> Void)?
    var onSectionCopy: ((ID<SectionRegion>) -> Void)?
    var onSectionSplit: ((ID<SectionRegion>) -> Void)?

    private let laneHeight: CGFloat = 24

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background — drag to create
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: CGFloat(totalBars) * pixelsPerBar, height: laneHeight)
                .gesture(createDragGesture)

            // Section bands
            ForEach(sections) { section in
                SectionBandView(
                    section: section,
                    pixelsPerBar: pixelsPerBar,
                    isSelected: selectedSectionID == section.id,
                    onSelect: { onSectionSelect(section.id) },
                    onMove: { newStartBar in onSectionMove(section.id, newStartBar) },
                    onResizeLeft: { newStart, newLength in onSectionResizeLeft(section.id, newStart, newLength) },
                    onResizeRight: { newLength in onSectionResizeRight(section.id, newLength) },
                    onDoubleClick: { onSectionDoubleClick(section.id) },
                    onNavigate: { onSectionNavigate(section.startBar) },
                    onDelete: { onSectionDelete?(section.id) },
                    onRecolor: { color in onSectionRecolor?(section.id, color) },
                    onCopy: { onSectionCopy?(section.id) },
                    onSplit: {
                        onSectionSplit?(section.id)
                    }
                )
            }
        }
        .frame(width: CGFloat(totalBars) * pixelsPerBar, height: laneHeight)
        .clipped()
    }

    // MARK: - Create by dragging on empty area

    @GestureState private var dragCreateState: (startX: CGFloat, currentX: CGFloat)? = nil

    private var createDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($dragCreateState) { value, state, _ in
                state = (startX: value.startLocation.x, currentX: value.location.x)
            }
            .onEnded { value in
                let minX = min(value.startLocation.x, value.location.x)
                let maxX = max(value.startLocation.x, value.location.x)
                let startBar = max(Int(minX / pixelsPerBar) + 1, 1)
                let endBar = max(Int(ceil(maxX / pixelsPerBar)) + 1, startBar + 1)
                let lengthBars = endBar - startBar
                if lengthBars >= 1 {
                    onSectionCreate(startBar, lengthBars)
                }
            }
    }
}

/// A single section band rendered on the section lane.
private struct SectionBandView: View {
    let section: SectionRegion
    let pixelsPerBar: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let onMove: (Int) -> Void
    let onResizeLeft: (Int, Int) -> Void
    let onResizeRight: (Int) -> Void
    let onDoubleClick: () -> Void
    let onNavigate: () -> Void
    var onDelete: (() -> Void)?
    var onRecolor: ((String) -> Void)?
    var onCopy: (() -> Void)?
    var onSplit: (() -> Void)?

    private static let sectionColors: [(String, String)] = [
        ("Red", "#E74C3C"),
        ("Orange", "#E67E22"),
        ("Yellow", "#F1C40F"),
        ("Green", "#2ECC71"),
        ("Teal", "#1ABC9C"),
        ("Blue", "#3498DB"),
        ("Purple", "#9B59B6"),
        ("Pink", "#E91E90"),
    ]

    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0

    private var xPosition: CGFloat {
        CGFloat(section.startBar - 1) * pixelsPerBar + (isDragging ? dragOffset : 0)
    }

    private var width: CGFloat {
        CGFloat(section.lengthBars) * pixelsPerBar
    }

    private let resizeHandleWidth: CGFloat = 6

    var body: some View {
        ZStack {
            // Background fill
            RoundedRectangle(cornerRadius: 3)
                .fill(colorFromHex(section.color).opacity(0.4))

            // Border
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(
                    isSelected ? Color.accentColor : colorFromHex(section.color).opacity(0.7),
                    lineWidth: isSelected ? 1.5 : 0.5
                )

            // Name label
            Text(section.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(colorFromHex(section.color))
                .lineLimit(1)
                .padding(.horizontal, 6)

            // Resize handles overlay
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: resizeHandleWidth)
                    .contentShape(Rectangle())
                    .gesture(leftResizeGesture)

                Spacer(minLength: 0)

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: resizeHandleWidth)
                    .contentShape(Rectangle())
                    .gesture(rightResizeGesture)
            }
        }
        .frame(width: max(width, pixelsPerBar * 0.5), height: 22)
        .offset(x: xPosition, y: 1)
        .onTapGesture(count: 2) { onDoubleClick() }
        .onTapGesture(count: 1) {
            onSelect()
            onNavigate()
        }
        .gesture(moveDragGesture)
        .contextMenu {
            Button("Rename...") { onDoubleClick() }
            Menu("Recolor") {
                ForEach(Self.sectionColors, id: \.1) { name, hex in
                    Button(name) { onRecolor?(hex) }
                }
            }
            Divider()
            Button("Copy Section") { onCopy?() }
            Button("Split at Playhead") { onSplit?() }
            Divider()
            Button("Delete", role: .destructive) { onDelete?() }
        }
    }

    // MARK: - Move Gesture

    private var moveDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                isDragging = true
                dragOffset = value.translation.width
            }
            .onEnded { value in
                isDragging = false
                dragOffset = 0
                let barDelta = Int(round(value.translation.width / pixelsPerBar))
                let newStartBar = max(section.startBar + barDelta, 1)
                if newStartBar != section.startBar {
                    onMove(newStartBar)
                }
            }
    }

    // MARK: - Left Resize Gesture

    private var leftResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onEnded { value in
                let barDelta = Int(round(value.translation.width / pixelsPerBar))
                let newStart = max(section.startBar + barDelta, 1)
                let newLength = section.lengthBars - (newStart - section.startBar)
                if newLength >= 1 {
                    onResizeLeft(newStart, newLength)
                }
            }
    }

    // MARK: - Right Resize Gesture

    private var rightResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onEnded { value in
                let barDelta = Int(round(value.translation.width / pixelsPerBar))
                let newLength = max(section.lengthBars + barDelta, 1)
                onResizeRight(newLength)
            }
    }

    // MARK: - Helpers

    private func colorFromHex(_ hex: String) -> Color {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let rgb = Int(trimmed, radix: 16) else { return .gray }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
