import SwiftUI
import LoopsCore

/// Full-screen perform mode displaying the current setlist position and controls.
public struct PerformModeView: View {
    @Bindable var viewModel: SetlistViewModel

    public init(viewModel: SetlistViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                if let setlist = viewModel.selectedSetlist {
                    Text(setlist.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                Spacer()
                Button("Exit Perform Mode") {
                    viewModel.exitPerformMode()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Main content
            VStack(spacing: 40) {
                Spacer()

                // Current song
                if let entry = viewModel.currentPerformEntry,
                   let song = viewModel.song(for: entry) {
                    VStack(spacing: 12) {
                        Text("NOW PLAYING")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(2)

                        Text(song.name)
                            .font(.system(size: 48, weight: .bold))

                        HStack(spacing: 20) {
                            Label("\(Int(song.tempo.bpm)) BPM", systemImage: "metronome")
                            Label("\(song.timeSignature.beatsPerBar)/\(song.timeSignature.beatUnit)", systemImage: "music.note")
                            Label("\(song.tracks.count) tracks", systemImage: "slider.horizontal.3")
                        }
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    }

                    // Progress
                    if let setlist = viewModel.selectedSetlist {
                        Text("Song \(viewModel.currentEntryIndex + 1) of \(setlist.entries.count)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    // Transition info
                    transitionInfo(for: entry)
                } else {
                    Text("No song loaded")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Next song preview
                if let nextEntry = viewModel.nextPerformEntry {
                    VStack(spacing: 8) {
                        Text("UP NEXT")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(2)

                        Text(viewModel.songName(for: nextEntry))
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }

                Spacer()

                // Controls
                HStack(spacing: 30) {
                    Button(action: { viewModel.goToPreviousSong() }) {
                        Label("Previous", systemImage: "backward.fill")
                            .font(.title2)
                    }
                    .disabled(viewModel.currentEntryIndex == 0)

                    Button(action: { viewModel.advanceToNextSong() }) {
                        Label("Next Song", systemImage: "forward.fill")
                            .font(.title)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(viewModel.nextPerformEntry == nil)
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder
    private func transitionInfo(for entry: SetlistEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right.circle")
            switch entry.transitionToNext {
            case .seamless:
                Text("Seamless transition to next song")
            case .gap(let duration):
                Text("Gap of \(String(format: "%.1f", duration))s before next song")
            case .manualAdvance:
                Text("Press Space or Next to advance")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }
}
