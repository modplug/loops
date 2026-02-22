import SwiftUI
import LoopsCore
import LoopsEngine

/// The root view of the Loops application.
public struct LoopsRootView: View {
    @Bindable var viewModel: ProjectViewModel
    @Bindable var transportViewModel: TransportViewModel
    let engineManager: AudioEngineManager?
    var settingsViewModel: SettingsViewModel?
    @State private var timelineViewModel = TimelineViewModel()
    @State private var setlistViewModel: SetlistViewModel?

    public init(viewModel: ProjectViewModel, transportViewModel: TransportViewModel, engineManager: AudioEngineManager? = nil, settingsViewModel: SettingsViewModel? = nil) {
        self.viewModel = viewModel
        self.transportViewModel = transportViewModel
        self.engineManager = engineManager
        self.settingsViewModel = settingsViewModel
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ToolbarView(
                    viewModel: transportViewModel,
                    onTimeSignatureChange: { beatsPerBar, beatUnit in
                        if let songID = viewModel.currentSongID {
                            viewModel.setTimeSignature(songID: songID, beatsPerBar: beatsPerBar, beatUnit: beatUnit)
                        }
                    },
                    onMetronomeConfigChange: { config in
                        if let songID = viewModel.currentSongID {
                            viewModel.setMetronomeConfig(songID: songID, config: config)
                        }
                    },
                    availableOutputPorts: engineManager?.deviceManager.outputDevices().flatMap { device in
                        engineManager?.deviceManager.outputPorts(for: device) ?? []
                    } ?? []
                )
                Divider()
                MainContentView(
                    projectViewModel: viewModel,
                    timelineViewModel: timelineViewModel,
                    transportViewModel: transportViewModel,
                    setlistViewModel: setlistViewModel,
                    engineManager: engineManager,
                    settingsViewModel: settingsViewModel
                )
            }

            if let setlistVM = setlistViewModel, setlistVM.isPerformMode {
                PerformModeView(viewModel: setlistVM)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear {
            if setlistViewModel == nil {
                setlistViewModel = SetlistViewModel(project: viewModel)
            }
        }
        .onChange(of: transportViewModel.playheadBar) { _, newValue in
            timelineViewModel.playheadBar = newValue
        }
        .onChange(of: viewModel.currentSong?.countInBars) { _, newValue in
            transportViewModel.countInBars = newValue ?? 0
        }
        .onChange(of: transportViewModel.countInBars) { _, newValue in
            if let songID = viewModel.currentSongID {
                viewModel.setCountInBars(songID: songID, bars: newValue)
            }
        }
        .onChange(of: viewModel.currentSong?.timeSignature) { _, newValue in
            transportViewModel.timeSignature = newValue ?? TimeSignature()
        }
        .onChange(of: viewModel.currentSong?.metronomeConfig) { _, newValue in
            let config = newValue ?? MetronomeConfig()
            transportViewModel.applyMetronomeConfig(config)
        }
        .onAppear {
            transportViewModel.songProvider = { [weak viewModel] in
                guard let vm = viewModel, let song = vm.currentSong else { return nil }
                return (song: song, recordings: vm.project.sourceRecordings, audioDir: vm.audioDirectory)
            }
            // Sync count-in bars from the current song
            transportViewModel.countInBars = viewModel.currentSong?.countInBars ?? 0
            // Sync time signature from the current song
            transportViewModel.timeSignature = viewModel.currentSong?.timeSignature ?? TimeSignature()
            // Sync metronome config from the current song
            let config = viewModel.currentSong?.metronomeConfig ?? MetronomeConfig()
            transportViewModel.applyMetronomeConfig(config)
        }
        .sheet(isPresented: $viewModel.isExportSheetPresented) {
            ExportAudioView(viewModel: viewModel)
        }
    }
}

/// File menu commands for project management.
public struct ProjectCommands: Commands {
    @Bindable var viewModel: ProjectViewModel

    public init(viewModel: ProjectViewModel) {
        self.viewModel = viewModel
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project") {
                viewModel.newProject()
            }
            .keyboardShortcut("n")

            Divider()

            Button("Open Project...") {
                openProject()
            }
            .keyboardShortcut("o")

            Divider()

            Button("Save Project") {
                do {
                    let saved = try viewModel.save()
                    if !saved {
                        saveProjectAs()
                    }
                } catch {
                    presentError(error)
                }
            }
            .keyboardShortcut("s")

            Button("Save Project As...") {
                saveProjectAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button("Export Audio...") {
                viewModel.isExportSheetPresented = true
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }

    private func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Select a .loops project bundle"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try viewModel.open(from: url)
            } catch {
                presentError(error)
            }
        }
    }

    private func saveProjectAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.folder]
        panel.nameFieldStringValue = viewModel.project.name + ".loops"
        panel.message = "Choose a location to save your project"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try viewModel.save(to: url)
            } catch {
                presentError(error)
            }
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

/// Edit menu commands for undo/redo.
public struct EditCommands: Commands {
    @Bindable var viewModel: ProjectViewModel

    public init(viewModel: ProjectViewModel) {
        self.viewModel = viewModel
    }

    public var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(undoTitle) {
                viewModel.undoManager?.undo()
            }
            .keyboardShortcut("z")
            .disabled(!(viewModel.undoManager?.canUndo ?? false))

            Button(redoTitle) {
                viewModel.undoManager?.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!(viewModel.undoManager?.canRedo ?? false))
        }
    }

    private var undoTitle: String {
        if let actionName = viewModel.undoManager?.undoActionName, !actionName.isEmpty {
            return "Undo \(actionName)"
        }
        return "Undo"
    }

    private var redoTitle: String {
        if let actionName = viewModel.undoManager?.redoActionName, !actionName.isEmpty {
            return "Redo \(actionName)"
        }
        return "Redo"
    }
}
