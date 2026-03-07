import SwiftUI
import LoopsCore
import LoopsEngine

/// Pending effect selection awaiting parameter pick.
public struct PendingEffectSelection: Equatable, Identifiable {
    public let trackID: ID<Track>
    public let containerID: ID<Container>?
    public let effectIndex: Int
    public let component: AudioComponentInfo
    public let effectName: String

    public init(
        trackID: ID<Track>,
        containerID: ID<Container>?,
        effectIndex: Int,
        component: AudioComponentInfo,
        effectName: String
    ) {
        self.trackID = trackID
        self.containerID = containerID
        self.effectIndex = effectIndex
        self.component = component
        self.effectName = effectName
    }

    public var id: String {
        "\(trackID.rawValue)-\(containerID?.rawValue.uuidString ?? "track")-\(effectIndex)"
    }
}

/// Sheet that loads and displays an AU's parameters for the user to pick one.
struct ParameterPickerView: View {
    let pending: PendingEffectSelection
    var onPick: ((EffectPath, AudioUnitParameterInfo) -> Void)?
    var onCancel: (() -> Void)?

    @State private var parameters: [AudioUnitParameterInfo] = []
    @State private var isLoading = true
    @State private var searchText = ""

    private var filteredParameters: [AudioUnitParameterInfo] {
        if searchText.isEmpty { return parameters }
        return parameters.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
            || $0.groupName.localizedCaseInsensitiveContains(searchText)
        }
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
                        onPick?(path, param)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(param.displayName)
                                if !param.groupName.isEmpty {
                                    Text(param.groupName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
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
