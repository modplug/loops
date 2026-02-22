import SwiftUI

/// An auto-dismissing toast overlay that shows undo/redo action feedback.
public struct UndoToastView: View {
    let message: UndoToastMessage

    public var body: some View {
        Text(message.text)
            .font(.system(.callout, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
