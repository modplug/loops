import SwiftUI
import LoopsCore

/// Inspector panel for configuring a setlist entry's transition and fade-in.
public struct SetlistEntryInspectorView: View {
    let entry: SetlistEntry
    let songName: String

    var onUpdateTransition: ((TransitionMode) -> Void)?
    var onUpdateFadeIn: ((FadeSettings?) -> Void)?

    @State private var transitionMode: TransitionModeKind = .manualAdvance
    @State private var gapDuration: Double = 2.0
    @State private var fadeInEnabled: Bool = false
    @State private var fadeInDuration: Double = 1.0
    @State private var fadeInCurve: CurveType = .linear

    public var body: some View {
        Form {
            songInfoSection
            transitionSection
            fadeInSection
        }
        .formStyle(.grouped)
        .onAppear { loadFromEntry() }
        .onChange(of: entry.id) { _, _ in loadFromEntry() }
    }

    // MARK: - Song Info

    @ViewBuilder
    private var songInfoSection: some View {
        Section("Song") {
            LabeledContent("Name", value: songName)
        }
    }

    // MARK: - Transition

    @ViewBuilder
    private var transitionSection: some View {
        Section("Transition to Next") {
            Picker("Mode", selection: $transitionMode) {
                ForEach(TransitionModeKind.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .onChange(of: transitionMode) { _, _ in commitTransition() }

            if transitionMode == .automaticWithDelay {
                HStack {
                    Text("Delay")
                    Slider(value: $gapDuration, in: 0.5...30.0, step: 0.5)
                    Text("\(gapDuration, specifier: "%.1f")s")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                .onChange(of: gapDuration) { _, _ in commitTransition() }
            }
        }
    }

    // MARK: - Fade In

    @ViewBuilder
    private var fadeInSection: some View {
        Section("Fade In") {
            Toggle("Enable Fade In", isOn: $fadeInEnabled)
                .onChange(of: fadeInEnabled) { _, enabled in
                    commitFadeIn(enabled: enabled)
                }

            if fadeInEnabled {
                HStack {
                    Text("Duration")
                    Slider(value: $fadeInDuration, in: 0.25...16.0, step: 0.25)
                    Text("\(fadeInDuration, specifier: "%.2g") bar(s)")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }
                .onChange(of: fadeInDuration) { _, _ in
                    commitFadeIn(enabled: true)
                }

                Picker("Curve", selection: $fadeInCurve) {
                    ForEach(CurveType.allCases, id: \.self) { curve in
                        Text(curve.displayName).tag(curve)
                    }
                }
                .onChange(of: fadeInCurve) { _, _ in
                    commitFadeIn(enabled: true)
                }

                FadeCurvePreview(curve: fadeInCurve, isFadeIn: true)
                    .frame(height: 80)
            }
        }
    }

    // MARK: - Private

    private func loadFromEntry() {
        switch entry.transitionToNext {
        case .seamless:
            transitionMode = .automatic
            gapDuration = 2.0
        case .gap(let duration):
            transitionMode = .automaticWithDelay
            gapDuration = duration
        case .manualAdvance:
            transitionMode = .manualAdvance
            gapDuration = 2.0
        }

        if let fade = entry.fadeIn {
            fadeInEnabled = true
            fadeInDuration = fade.duration
            fadeInCurve = fade.curve
        } else {
            fadeInEnabled = false
            fadeInDuration = 1.0
            fadeInCurve = .linear
        }
    }

    private func commitTransition() {
        let mode: TransitionMode
        switch transitionMode {
        case .manualAdvance:
            mode = .manualAdvance
        case .automatic:
            mode = .seamless
        case .automaticWithDelay:
            mode = .gap(durationSeconds: gapDuration)
        }
        onUpdateTransition?(mode)
    }

    private func commitFadeIn(enabled: Bool) {
        if enabled {
            onUpdateFadeIn?(FadeSettings(duration: fadeInDuration, curve: fadeInCurve))
        } else {
            onUpdateFadeIn?(nil)
        }
    }
}

/// UI-friendly enum for the transition mode picker.
enum TransitionModeKind: CaseIterable {
    case manualAdvance
    case automatic
    case automaticWithDelay

    var displayName: String {
        switch self {
        case .manualAdvance: return "Manual"
        case .automatic: return "Automatic"
        case .automaticWithDelay: return "Automatic with Delay"
        }
    }
}
