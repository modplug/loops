import SwiftUI
import LoopsCore
import LoopsEngine

/// Pending effect selection awaiting parameter pick.
struct PendingEffectSelection: Equatable, Identifiable {
    let trackID: ID<Track>
    let containerID: ID<Container>?
    let effectIndex: Int
    let component: AudioComponentInfo
    let effectName: String

    var id: String {
        "\(trackID.rawValue)-\(containerID?.rawValue.uuidString ?? "track")-\(effectIndex)"
    }
}

/// Sheet that loads and displays an AU's parameters for the user to pick one.
struct ParameterPickerView: View {
    let pending: PendingEffectSelection
    var onPick: ((EffectPath) -> Void)?
    var onCancel: (() -> Void)?

    @State private var parameters: [AudioUnitParameterInfo] = []
    @State private var isLoading = true
    @State private var searchText = ""

    private var filteredParameters: [AudioUnitParameterInfo] {
        if searchText.isEmpty { return parameters }
        return parameters.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pick Parameter — \(pending.effectName)")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel?() }
            }
            .padding()

            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading parameters...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if parameters.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("This effect has no automatable parameters")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextField("Search parameters...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                List(filteredParameters) { param in
                    Button {
                        let path = EffectPath(
                            trackID: pending.trackID,
                            containerID: pending.containerID,
                            effectIndex: pending.effectIndex,
                            parameterAddress: param.address
                        )
                        onPick?(path)
                    } label: {
                        HStack {
                            Text(param.displayName)
                            Spacer()
                            Text("\(param.minValue, specifier: "%.1f") – \(param.maxValue, specifier: "%.1f")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !param.unit.isEmpty {
                                Text(param.unit)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 500, minHeight: 300, idealHeight: 400)
        .task {
            let discovery = AudioUnitDiscovery()
            let params = await discovery.parameters(for: pending.component)
            self.parameters = params
            self.isLoading = false
        }
    }
}
