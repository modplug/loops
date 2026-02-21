/// LoopsApp — SwiftUI views, view models, and app entry point.
/// Depends on LoopsCore and LoopsEngine.
import SwiftUI
import LoopsCore
import LoopsEngine

/// The root view of the Loops application.
public struct LoopsRootView: View {
    public init() {}

    public var body: some View {
        Text("Loops")
            .font(.largeTitle)
            .frame(minWidth: 800, minHeight: 500)
    }
}
