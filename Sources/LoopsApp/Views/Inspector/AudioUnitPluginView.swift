import SwiftUI
import AVFoundation
import LoopsCore
import LoopsEngine

/// Manages floating NSWindows for Audio Unit plugin UIs.
/// Each plugin gets its own resizable window that fits the plugin's preferred content size.
@MainActor
final class PluginWindowManager {
    static let shared = PluginWindowManager()

    private var windows: [String: NSWindow] = [:]

    /// Returns the window for the given component key, if one is open.
    func window(for component: AudioComponentInfo) -> NSWindow? {
        let key = "\(component.componentType)-\(component.componentSubType)-\(component.componentManufacturer)"
        return windows[key]
    }

    /// Opens (or brings to front) a plugin window for the given component.
    /// When `liveAudioUnit` is provided (from the engine's active effect chain), the window
    /// displays that instance directly so parameter changes affect live audio immediately.
    /// When nil, a standalone instance is created (fallback for when playback is not prepared).
    func open(
        component: AudioComponentInfo,
        displayName: String,
        presetData: Data?,
        liveAudioUnit: AVAudioUnit? = nil,
        onPresetChanged: ((Data?) -> Void)?
    ) {
        let key = "\(component.componentType)-\(component.componentSubType)-\(component.componentManufacturer)"

        // If a window for this component is already open, bring it to front
        if let existing = windows[key], existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = PluginWindow(
            component: component,
            displayName: displayName,
            presetData: presetData,
            liveAudioUnit: liveAudioUnit,
            onPresetChanged: onPresetChanged,
            onClose: { [weak self] in
                self?.windows.removeValue(forKey: key)
            }
        )
        windows[key] = window
        window.makeKeyAndOrderFront(nil)
    }
}

/// A resizable NSWindow that hosts an Audio Unit's native plugin UI.
/// When a live AU instance (from the engine) is provided, parameter changes in the
/// plugin UI immediately affect audio output. Otherwise a standalone instance is created.
@MainActor
private final class PluginWindow: NSWindow, NSWindowDelegate {
    private var avAudioUnit: AVAudioUnit?
    private var onPresetChanged: ((Data?) -> Void)?
    private var onClose: (() -> Void)?
    private var sizeObservation: NSKeyValueObservation?

    convenience init(
        component: AudioComponentInfo,
        displayName: String,
        presetData: Data?,
        liveAudioUnit: AVAudioUnit?,
        onPresetChanged: ((Data?) -> Void)?,
        onClose: (() -> Void)?
    ) {
        let loadingRect = NSRect(x: 0, y: 0, width: 400, height: 300)
        self.init(
            contentRect: loadingRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.onPresetChanged = onPresetChanged
        self.onClose = onClose
        self.title = displayName
        self.isReleasedWhenClosed = false
        self.delegate = self
        self.center()

        // Show a loading spinner while the AU view loads
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        let loadingView = NSView(frame: loadingRect)
        loadingView.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor),
        ])
        self.contentView = loadingView

        if let liveAudioUnit {
            // Use the engine's live AU instance directly — parameter changes
            // will affect audio output in real-time.
            self.avAudioUnit = liveAudioUnit
            Task { @MainActor in
                await self.presentAudioUnit(liveAudioUnit, displayName: displayName)
            }
        } else {
            // No live instance available — create a standalone AU (fallback)
            Task { @MainActor in
                await self.loadStandalonePlugin(component: component, presetData: presetData, displayName: displayName)
            }
        }
    }

    /// Presents the UI for an already-loaded AVAudioUnit instance.
    private func presentAudioUnit(_ au: AVAudioUnit, displayName: String) async {
        let vc = await AudioUnitUIHost.requestViewController(for: au.auAudioUnit)

        if let vc {
            self.contentViewController = vc

            if self.applyPreferredSize(from: vc) {
                self.center()
            } else {
                // Plugin hasn't reported its preferred size yet — observe for
                // async updates (common with AU effect plugins).
                self.sizeObservation = vc.observe(
                    \.preferredContentSize,
                    options: [.new]
                ) { [weak self] viewController, _ in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if self.applyPreferredSize(from: viewController) {
                            self.center()
                            self.sizeObservation = nil
                        }
                    }
                }
            }
        } else {
            // No custom UI — show generic parameter sliders in SwiftUI
            let params = au.auAudioUnit.parameterTree?.allParameters ?? []
            let hostingView = NSHostingView(rootView: GenericParameterListView(
                parameters: params,
                displayName: displayName
            ))
            self.contentView = hostingView
            self.setContentSize(NSSize(width: 450, height: min(CGFloat(params.count * 32 + 80), 600)))
            self.center()
        }
    }

    /// Creates a standalone AU instance (not connected to engine) and presents its UI.
    private func loadStandalonePlugin(component: AudioComponentInfo, presetData: Data?, displayName: String) async {
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

            await presentAudioUnit(au, displayName: displayName)
        } catch {
            let hostingView = NSHostingView(rootView: PluginErrorView(message: error.localizedDescription))
            self.contentView = hostingView
            self.setContentSize(NSSize(width: 350, height: 150))
            self.center()
        }
    }

    /// Attempts to size the window to the view controller's preferred or fitting size.
    /// Returns true if a valid size was applied.
    @discardableResult
    private func applyPreferredSize(from vc: NSViewController) -> Bool {
        let preferred = vc.preferredContentSize
        if preferred.width > 0 && preferred.height > 0 {
            self.setContentSize(preferred)
            return true
        }
        let viewSize = vc.view.fittingSize
        if viewSize.width > 0 && viewSize.height > 0 {
            self.setContentSize(viewSize)
            return true
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        sizeObservation = nil
        // Save preset before closing
        if let au = avAudioUnit {
            let host = AudioUnitHost(engine: AVAudioEngine())
            let data = host.saveState(audioUnit: au)
            onPresetChanged?(data)
        }
        onClose?()
    }
}


/// Generic parameter sliders shown when a plugin has no custom UI.
private struct GenericParameterListView: View {
    let parameters: [AUParameter]
    let displayName: String

    var body: some View {
        VStack(spacing: 0) {
            if parameters.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No parameters available")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(parameters.enumerated()), id: \.offset) { _, param in
                            GenericParameterRow(parameter: param)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

/// Error view shown when plugin loading fails.
private struct PluginErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text("Failed to load plugin")
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
