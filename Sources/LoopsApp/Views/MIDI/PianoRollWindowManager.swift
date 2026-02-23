import SwiftUI
import LoopsCore

/// Manages a floating NSPanel for the pop-out piano roll editor.
/// Each track's piano roll remembers its window position/size via `setFrameAutosaveName`.
@MainActor
final class PianoRollWindowManager {
    static let shared = PianoRollWindowManager()

    private var window: NSPanel?
    private var currentTrackID: ID<Track>?

    var isOpen: Bool {
        window?.isVisible ?? false
    }

    func open<Content: View>(content: Content, title: String, trackID: ID<Track>) {
        // If a window is already showing for the same track, bring it to front
        if let existing = window, existing.isVisible, currentTrackID == trackID {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        // Close any existing window before opening a new one
        close()

        let hostingView = NSHostingView(rootView: content)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
        panel.minSize = NSSize(width: 400, height: 300)
        panel.setFrameAutosaveName("PianoRoll-\(trackID.rawValue)")
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = true

        // Center only if no saved frame (first open for this track)
        if !panel.setFrameUsingName(panel.frameAutosaveName) {
            panel.center()
        }

        panel.makeKeyAndOrderFront(nil)
        window = panel
        currentTrackID = trackID
    }

    func close() {
        window?.orderOut(nil)
        window = nil
        currentTrackID = nil
    }
}
