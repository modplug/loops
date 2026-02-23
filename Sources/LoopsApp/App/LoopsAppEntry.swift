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
    @State private var isVirtualKeyboardVisible = false

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
                    onUndo: { viewModel.undoManager?.undo() },
                    onRedo: { viewModel.undoManager?.redo() },
                    canUndo: viewModel.undoManager?.canUndo ?? false,
                    canRedo: viewModel.undoManager?.canRedo ?? false,
                    undoActionName: viewModel.undoManager?.undoActionName ?? "",
                    redoActionName: viewModel.undoManager?.redoActionName ?? "",
                    undoState: viewModel.undoState,
                    availableOutputPorts: engineManager?.deviceManager.outputDevices().flatMap { device in
                        engineManager?.deviceManager.outputPorts(for: device) ?? []
                    } ?? [],
                    isVirtualKeyboardVisible: $isVirtualKeyboardVisible
                )
                Divider()
                mainContentView
            }

            if let setlistVM = setlistViewModel, setlistVM.isPerformMode {
                PerformModeView(viewModel: setlistVM)
            }

            // Undo/redo toast notification
            VStack {
                Spacer()
                if let toast = viewModel.undoState.undoToastMessage {
                    UndoToastView(message: toast)
                        .padding(.bottom, 24)
                        .id(toast.id)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.undoState.undoToastMessage)
        }
        .frame(minWidth: 800, minHeight: 500)
        .onChange(of: viewModel.undoState.undoToastMessage) { _, newValue in
            guard newValue != nil else { return }
            // Auto-dismiss toast after 2 seconds
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                // Only dismiss if the toast hasn't been replaced
                if viewModel.undoState.undoToastMessage?.id == newValue?.id {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.undoState.undoToastMessage = nil
                    }
                }
            }
        }
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

            // Wire recording propagation: register audio file and schedule linked containers
            viewModel.onRecordingPropagated = { [weak transportViewModel] recordingID, filename, linkedContainers in
                transportViewModel?.registerAndScheduleLinkedContainers(
                    recordingID: recordingID,
                    filename: filename,
                    linkedContainers: linkedContainers
                )
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

    private var mainContentView: some View {
        MainContentView(
            projectViewModel: viewModel,
            timelineViewModel: timelineViewModel,
            selectionState: viewModel.selectionState,
            transportViewModel: transportViewModel,
            setlistViewModel: setlistViewModel,
            engineManager: engineManager,
            settingsViewModel: settingsViewModel,
            mixerViewModel: mixerViewModel,
            midiActivityMonitor: midiActivityMonitor,
            isVirtualKeyboardVisible: $isVirtualKeyboardVisible
        )
    }

    /// Wires MIDI CC events to control mapping dispatch, parameter mapping dispatch, and learn flow.
    private func setupMIDIParameterDispatch() {
        guard let midiManager = engineManager?.midiManager else { return }

        // Parameter dispatcher for effect/AU parameter CC mappings
        let paramDispatcher = MIDIDispatcher()
        paramDispatcher.updateParameterMappings(viewModel.project.midiParameterMappings)

        paramDispatcher.onParameterValue = { [weak transportViewModel] path, value in
            Task { @MainActor [weak transportViewModel] in
                transportViewModel?.setParameter(at: path, value: value)
            }
        }

        // Control dispatcher for transport + mixer + navigation MIDI mappings
        let controlDispatcher = MIDIDispatcher()
        controlDispatcher.updateMappings(viewModel.project.midiMappings)
        let slVM = setlistViewModel

        controlDispatcher.onControlTriggered = { [weak viewModel, weak transportViewModel, weak slVM] control in
            Task { @MainActor [weak viewModel, weak transportViewModel, weak slVM] in
                guard let vm = viewModel else { return }
                let regularTracks = vm.currentSong?.tracks.filter { $0.kind != .master } ?? []
                switch control {
                case .playPause: transportViewModel?.togglePlayPause()
                case .stop: transportViewModel?.stop()
                case .recordArm:
                    if let trackID = vm.selectionState.selectedTrackID {
                        let track = vm.currentSong?.tracks.first(where: { $0.id == trackID })
                        vm.setTrackRecordArmed(trackID: trackID, armed: !(track?.isRecordArmed ?? false))
                    }
                case .nextSong:
                    if let slVM = setlistViewModel, slVM.isPerformMode {
                        slVM.advanceToNextSong()
                    } else {
                        let nextIdx = vm.currentSongIndex + 1
                        if nextIdx < vm.project.songs.count {
                            vm.selectSong(id: vm.project.songs[nextIdx].id)
                        }
                    }
                case .previousSong:
                    if let slVM = setlistViewModel, slVM.isPerformMode {
                        slVM.goToPreviousSong()
                    } else {
                        let prevIdx = vm.currentSongIndex - 1
                        if prevIdx >= 0 {
                            vm.selectSong(id: vm.project.songs[prevIdx].id)
                        }
                    }
                case .metronomeToggle: transportViewModel?.toggleMetronome()
                case .trackMute(let idx):
                    if idx < regularTracks.count {
                        vm.toggleMute(trackID: regularTracks[idx].id)
                    }
                case .trackSolo(let idx):
                    if idx < regularTracks.count {
                        vm.toggleSolo(trackID: regularTracks[idx].id)
                    }
                case .trackSelect(let idx):
                    if idx < regularTracks.count {
                        vm.selectionState.selectedTrackID = regularTracks[idx].id
                    }
                case .songSelect(let idx):
                    if idx < vm.project.songs.count {
                        vm.selectSong(id: vm.project.songs[idx].id)
                    }
                case .trackVolume, .trackPan, .trackSend:
                    break // Handled by onContinuousControlTriggered
                }
            }
        }

        controlDispatcher.onContinuousControlTriggered = { [weak viewModel] control, value in
            Task { @MainActor [weak viewModel] in
                guard let vm = viewModel else { return }
                let regularTracks = vm.currentSong?.tracks.filter { $0.kind != .master } ?? []
                switch control {
                case .trackVolume(let idx):
                    if idx < regularTracks.count {
                        vm.setTrackVolume(trackID: regularTracks[idx].id, volume: value)
                    }
                case .trackPan(let idx):
                    if idx < regularTracks.count {
                        vm.setTrackPan(trackID: regularTracks[idx].id, pan: value)
                    }
                case .trackSend(let trackIdx, let sendIdx):
                    if trackIdx < regularTracks.count, sendIdx < regularTracks[trackIdx].sendLevels.count {
                        vm.setTrackSendLevel(trackID: regularTracks[trackIdx].id, sendIndex: sendIdx, level: value)
                    }
                default: break
                }
            }
        }

        midiManager.onMIDICCWithValue = { trigger, ccValue in
            controlDispatcher.dispatch(trigger, ccValue: ccValue)
            paramDispatcher.dispatch(trigger, ccValue: ccValue)
        }

        // Also dispatch note events to the control dispatcher (for toggle controls)
        let previousOnMIDIEvent = midiManager.onMIDIEvent
        midiManager.onMIDIEvent = { [weak viewModel] trigger in
            // Learn mode takes priority
            if let vm = viewModel, vm.midiLearnState.isMIDIParameterLearning {
                Task { @MainActor [weak vm] in
                    vm?.completeMIDIParameterLearn(trigger: trigger)
                    paramDispatcher.updateParameterMappings(vm?.project.midiParameterMappings ?? [])
                }
                return
            }
            controlDispatcher.dispatch(trigger)
            previousOnMIDIEvent?(trigger)
        }

        // When parameter mappings change, rebuild the parameter dispatcher
        viewModel.onMIDIParameterMappingsChanged = { [weak viewModel] in
            paramDispatcher.updateParameterMappings(viewModel?.project.midiParameterMappings ?? [])
        }

        // When control mappings change, rebuild the control dispatcher
        viewModel.onMIDIMappingsChanged = { [weak viewModel] in
            controlDispatcher.updateMappings(viewModel?.project.midiMappings ?? [])
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
