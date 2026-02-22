import SwiftUI
import AVFoundation
import LoopsCore
import LoopsEngine

/// Wraps an AUAudioUnit's native NSViewController as a SwiftUI view.
struct AudioUnitNSViewControllerRepresentable: NSViewControllerRepresentable {
    let viewController: NSViewController

    func makeNSViewController(context: Context) -> NSViewController {
        viewController
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}

/// Sheet that loads and displays an Audio Unit's native plugin UI.
/// Shows a loading spinner while the AU is being instantiated.
struct AudioUnitPluginView: View {
    let component: AudioComponentInfo
    let displayName: String
    let presetData: Data?
    var onPresetChanged: ((Data?) -> Void)?
    var onDismiss: (() -> Void)?

    @State private var auViewController: NSViewController?
    @State private var avAudioUnit: AVAudioUnit?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(displayName)
                    .font(.headline)
                Spacer()
                Button("Save & Close") {
                    savePresetAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            // Plugin UI content
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading plugin...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.yellow)
                        Text(error)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let vc = auViewController {
                    AudioUnitNSViewControllerRepresentable(viewController: vc)
                        .frame(minWidth: 400, minHeight: 300)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("This plugin has no custom UI")
                            .foregroundStyle(.secondary)
                        if let au = avAudioUnit {
                            genericParameterList(au: au)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 700, minHeight: 400, idealHeight: 500)
        .task {
            await loadPlugin()
        }
    }

    @ViewBuilder
    private func genericParameterList(au: AVAudioUnit) -> some View {
        let params = au.auAudioUnit.parameterTree?.allParameters ?? []
        if params.isEmpty {
            Text("No parameters available")
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(params.enumerated()), id: \.offset) { _, param in
                        GenericParameterRow(parameter: param)
                    }
                }
                .padding()
            }
        }
    }

    private func loadPlugin() async {
        let description = AudioComponentDescription(
            componentType: component.componentType,
            componentSubType: component.componentSubType,
            componentManufacturer: component.componentManufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        do {
            let au = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAudioUnit, Error>) in
                AVAudioUnit.instantiate(with: description, options: []) { audioUnit, error in
                    if let audioUnit = audioUnit {
                        continuation.resume(returning: audioUnit)
                    } else {
                        continuation.resume(throwing: error ?? LoopsError.audioUnitLoadFailed(component: "\(component.componentType)"))
                    }
                }
            }

            // Restore preset if we have one
            if let data = presetData {
                let host = AudioUnitHost(engine: AVAudioEngine())
                try? host.restoreState(audioUnit: au, data: data)
            }

            self.avAudioUnit = au

            // Request the plugin's custom view controller
            let vc = await AudioUnitUIHost.requestViewController(for: au.auAudioUnit)
            self.auViewController = vc
            self.isLoading = false
        } catch {
            self.errorMessage = "Failed to load plugin: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    private func savePresetAndDismiss() {
        if let au = avAudioUnit {
            let host = AudioUnitHost(engine: AVAudioEngine())
            let data = host.saveState(audioUnit: au)
            onPresetChanged?(data)
        }
        onDismiss?()
    }
}

/// A generic slider row for AU parameters when no custom UI is available.
struct GenericParameterRow: View {
    let parameter: AUParameter
    @State private var value: Float = 0

    var body: some View {
        HStack {
            Text(parameter.displayName)
                .frame(width: 150, alignment: .leading)
                .font(.callout)
                .lineLimit(1)
            Slider(
                value: $value,
                in: parameter.minValue...max(parameter.minValue + 0.001, parameter.maxValue)
            )
            .onChange(of: value) { _, newValue in
                parameter.value = newValue
            }
            Text("\(value, specifier: "%.2f")")
                .font(.caption.monospacedDigit())
                .frame(width: 50, alignment: .trailing)
        }
        .onAppear {
            value = parameter.value
        }
    }
}
