import SwiftUI
import AppKit

/// Displays a thin vertical cursor line at the current mouse position.
/// Isolated from the parent view tree so 60fps cursor movement doesn't re-render track lanes.
struct CursorOverlayView: View {
    let viewModel: TimelineViewModel
    let height: CGFloat

    var body: some View {
        if let x = viewModel.cursorX {
            Rectangle()
                .fill(Color.primary.opacity(0.3))
                .frame(width: 0.5, height: height)
                .offset(x: x)
                .allowsHitTesting(false)
        }
    }
}

/// Tracks pointer position using NSTrackingArea without intercepting any mouse events.
/// Works even when SwiftUI child views have their own onContinuousHover handlers,
/// because NSTrackingArea fires based on rect membership, not hit testing.
struct PointerTrackingOverlay: NSViewRepresentable {
    let onPositionChange: (CGFloat?) -> Void

    func makeNSView(context: Context) -> PointerTrackingNSView {
        let view = PointerTrackingNSView()
        view.onPositionChange = onPositionChange
        return view
    }

    func updateNSView(_ nsView: PointerTrackingNSView, context: Context) {
        nsView.onPositionChange = onPositionChange
    }

    final class PointerTrackingNSView: NSView {
        var onPositionChange: ((CGFloat?) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self
            ))
        }

        override func mouseMoved(with event: NSEvent) {
            let local = convert(event.locationInWindow, from: nil)
            onPositionChange?(local.x)
        }

        override func mouseExited(with event: NSEvent) {
            onPositionChange?(nil)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
