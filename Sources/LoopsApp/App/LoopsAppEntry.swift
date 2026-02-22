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
    @State private var mixerViewModel = MixerViewModel()
    @State private var setlistViewModel: SetlistViewModel?
    @State private var midiActivityMonitor = MIDIActivityMonitor()

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
                    settingsViewModel: settingsViewModel,
                    mixerViewModel: mixerViewModel,
                    midiActivityMonitor: midiActivityMonitor
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
        // Note: playheadBar sync uses a direct callback (onPlayheadChanged)
        // rather than .onChange to avoid re-evaluating this view's body at 60fps.
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
        .onChange(of: viewModel.currentSong?.tracks) { _, newValue in
            midiActivityMonitor.updateTracks(newValue ?? [])
        }
        .onChange(of: setlistViewModel?.isPerformMode) { _, newValue in
            transportViewModel.isPerformMode = newValue ?? false
        }
        .onAppear {
            transportViewModel.songProvider = { [weak viewModel] in
                guard let vm = viewModel, let song = vm.currentSong else { return nil }
                return (song: song, recordings: vm.project.sourceRecordings, audioDir: vm.audioDirectory)
            }
            // Bridge playhead updates directly, bypassing SwiftUI observation
            transportViewModel.onPlayheadChanged = { [weak timelineViewModel, weak viewModel, weak setlistViewModel] bar in
                timelineViewModel?.playheadBar = bar
                if let slVM = setlistViewModel, slVM.isPerformMode,
                   let song = viewModel?.currentSong {
                    let containerMax = song.tracks.flatMap(\.containers).map(\.endBar).max() ?? 1
                    let sectionMax = song.sections.map(\.endBar).max() ?? 1
                    let songLength = max(containerMax, sectionMax, 1)
                    slVM.updateSongProgress(playheadBar: bar, songLengthBars: songLength)
                }
            }
            // Wire song change handler: reset playhead and restart playback
            viewModel.onSongChanged = { [weak transportViewModel] in
                transportViewModel?.handleSongChanged()
            }
            // Sync count-in bars from the current song
            transportViewModel.countInBars = viewModel.currentSong?.countInBars ?? 0
            // Sync time signature from the current song
            transportViewModel.timeSignature = viewModel.currentSong?.timeSignature ?? TimeSignature()
            // Sync metronome config from the current song
            let config = viewModel.currentSong?.metronomeConfig ?? MetronomeConfig()
            transportViewModel.applyMetronomeConfig(config)

            // Wire container recording callbacks
            transportViewModel.onRecordingPeaksUpdated = { [weak viewModel] containerID, peaks in
                viewModel?.updateRecordingPeaks(containerID: containerID, peaks: peaks)
            }
            transportViewModel.onRecordingComplete = { [weak viewModel] trackID, containerID, recording in
                viewModel?.setContainerRecording(trackID: trackID, containerID: containerID, recording: recording)
            }

            // Set up master level metering
            engineManager?.onMasterLevelUpdate = { [weak mixerViewModel] peak in
                Task { @MainActor in
                    mixerViewModel?.updateMasterLevel(peak)
                }
            }
            engineManager?.installMasterLevelTap()

            // Wire MIDI parameter learn: when learning, intercept MIDI events
            setupMIDIParameterDispatch()
        }
        .sheet(isPresented: $viewModel.isExportSheetPresented) {
            ExportAudioView(viewModel: viewModel)
        }
    }

    /// Wires MIDI CC events to parameter mapping dispatch and learn flow.
    private func setupMIDIParameterDispatch() {
        guard let midiManager = engineManager?.midiManager else { return }

        let paramDispatcher = MIDIDispatcher()
        paramDispatcher.updateParameterMappings(viewModel.project.midiParameterMappings)

        // When a CC arrives with a value, scale and apply to the target parameter
        paramDispatcher.onParameterValue = { [weak transportViewModel] path, value in
            Task { @MainActor [weak transportViewModel] in
                transportViewModel?.setParameter(at: path, value: value)
            }
        }

        midiManager.onMIDICCWithValue = { trigger, ccValue in
            paramDispatcher.dispatch(trigger, ccValue: ccValue)
        }

        // Wire MIDI learn: when ProjectViewModel is in learn mode, intercept events
        midiManager.onMIDIEvent = { [weak viewModel] trigger in
            guard let vm = viewModel, vm.isMIDIParameterLearning else { return }
            Task { @MainActor [weak vm] in
                vm?.completeMIDIParameterLearn(trigger: trigger)
                // Rebuild the parameter dispatcher mappings
                paramDispatcher.updateParameterMappings(vm?.project.midiParameterMappings ?? [])
            }
        }

        // When mappings change (add/remove), rebuild the dispatcher
        viewModel.onMIDIParameterMappingsChanged = { [weak viewModel] in
            paramDispatcher.updateParameterMappings(viewModel?.project.midiParameterMappings ?? [])
        }

        // Wire MIDI activity monitor: raw message callback
        let monitor = midiActivityMonitor
        midiActivityMonitor.updateTracks(viewModel.currentSong?.tracks ?? [])
        midiActivityMonitor.updateDeviceNames(midiManager.availableInputDevices())

        midiManager.onRawMIDIMessage = { [weak monitor] word, deviceID in
            Task { @MainActor [weak monitor] in
                monitor?.recordMessage(word: word, deviceID: deviceID)
            }
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
