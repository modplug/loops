import SwiftUI
import LoopsCore

/// An entry in the container clipboard, storing a copied container and its source track ID.
public struct ClipboardContainerEntry: Equatable, Sendable {
    public let container: Container
    public let trackID: ID<Track>
}

/// Dedicated observable for clipboard state, extracted from ProjectViewModel.
/// Isolates clipboard changes so only views that read clipboard (paste availability)
/// re-evaluate when clipboard contents change.
@Observable
@MainActor
public final class ClipboardState {

    /// Clipboard for container copy/paste operations.
    public var clipboard: [ClipboardContainerEntry] = []

    /// The leftmost start bar of copied containers, used for offset calculation on paste.
    public var clipboardBaseBar: Int = 1

    /// Section region metadata copied with section copy operations.
    public var clipboardSectionRegion: SectionRegion?

    /// Whether the clipboard has any content (containers or section metadata).
    public var hasContent: Bool {
        !clipboard.isEmpty || clipboardSectionRegion != nil
    }

    public init() {}
}
