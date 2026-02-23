import SwiftUI

/// Dedicated observable for export sheet state, extracted from ProjectViewModel.
/// Isolates export sheet presentation so toggling the export dialog doesn't
/// invalidate unrelated parts of the view tree (timeline, mixer, inspector).
@Observable
@MainActor
public final class ExportState {

    /// Whether the export audio sheet is currently presented.
    public var isExportSheetPresented: Bool = false

    public init() {}
}
