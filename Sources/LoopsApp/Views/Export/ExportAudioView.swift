import SwiftUI
import LoopsCore
import LoopsEngine

/// Dialog for configuring and initiating audio export.
struct ExportAudioView: View {
    @Bindable var viewModel: ProjectViewModel

    @State private var selectedFormat: ExportFormat = .wav24
    @State private var selectedSampleRate: ExportSampleRate = .rate44100
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportError: String?
    @State private var exportComplete = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Export Audio")
                .font(.headline)

            Form {
                Picker("Format", selection: $selectedFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }

                Picker("Sample Rate", selection: $selectedSampleRate) {
                    ForEach(ExportSampleRate.allCases, id: \.self) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
            }
            .padding(.horizontal)

            if isExporting {
                ProgressView(value: exportProgress)
                    .padding(.horizontal)
                Text("Exporting... \(Int(exportProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = exportError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if exportComplete {
                Text("Export complete!")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Export...") {
                    startExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isExporting)
            }
            .padding(.horizontal)
        }
        .padding(20)
        .frame(width: 380)
    }

    private func startExport() {
        let panel = NSSavePanel()
        let songName = viewModel.currentSong?.name ?? viewModel.project.name
        panel.nameFieldStringValue = songName + "." + selectedFormat.fileExtension
        panel.message = "Choose where to save the exported audio"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        exportError = nil
        exportComplete = false
        exportProgress = 0

        guard let song = viewModel.currentSong else {
            exportError = "No song selected"
            return
        }
        let recordings = viewModel.project.sourceRecordings
        let format = selectedFormat
        let sampleRate = selectedSampleRate
        let audioDir = viewModel.projectURL?.appendingPathComponent("audio")
            ?? FileManager.default.temporaryDirectory

        let config = ExportConfiguration(
            format: format,
            sampleRate: sampleRate,
            destinationURL: url
        )

        Task.detached {
            do {
                let renderer = OfflineRenderer(audioDirURL: audioDir)
                try renderer.render(
                    song: song,
                    sourceRecordings: recordings,
                    config: config
                ) { progress in
                    Task { @MainActor in
                        exportProgress = progress
                    }
                }
                await MainActor.run {
                    isExporting = false
                    exportComplete = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                }
            }
        }
    }
}
