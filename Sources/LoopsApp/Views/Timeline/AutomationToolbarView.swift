import SwiftUI
import LoopsCore

/// Toolbar displayed above expanded automation sub-lanes, styled consistently with the piano roll toolbar.
/// Shows the lane name, parameter info, and shape drawing tools.
struct AutomationToolbarView: View {
    let laneName: String
    let parameterInfo: String
    let laneColor: Color
    @Binding var selectedTool: AutomationTool

    var body: some View {
        HStack(spacing: 8) {
            // Lane name + parameter info
            Text("Automation")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(laneName)
                .font(.caption.bold())
                .foregroundStyle(laneColor)

            if !parameterInfo.isEmpty {
                Text(parameterInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Shape tools
            ForEach(AutomationTool.allCases, id: \.self) { tool in
                Button(action: { selectedTool = tool }) {
                    Image(systemName: tool.iconName)
                        .font(.system(size: 10))
                        .foregroundStyle(selectedTool == tool ? .white : .secondary)
                        .frame(width: 20, height: 20)
                        .background(selectedTool == tool ? laneColor.opacity(0.8) : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .help(tool.label)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
