import Foundation
import AVFoundation
import LoopsCore
import LoopsEngine

@MainActor
public struct CommandPaletteTextInputRequest {
    public let title: String
    public let message: String
    public let initialValue: String
    public let placeholder: String
    public let actionTitle: String

    public init(
        title: String,
        message: String,
        initialValue: String,
        placeholder: String = "",
        actionTitle: String = "Save"
    ) {
        self.title = title
        self.message = message
        self.initialValue = initialValue
        self.placeholder = placeholder
        self.actionTitle = actionTitle
    }
}

@MainActor
public struct CommandPaletteUIActions {
    public var openMixer: () -> Void
    public var openSetlists: () -> Void
    public var openSongs: () -> Void
    public var openSettings: () -> Void
    public var focusTimeline: () -> Void
    public var revealTarget: (PreviewTarget) -> Void
    public var requestTextInput: (CommandPaletteTextInputRequest) -> String?
    public var inspectTrack: (ID<Track>) -> Void
    public var inspectContainer: (ID<Container>) -> Void
    public var openPianoRoll: (ID<Container>) -> Void
    public var presentTrackAutomationPicker: (PendingEffectSelection) -> Void
    public var presentContainerAutomationPicker: (PendingEffectSelection) -> Void

    public init(
        openMixer: @escaping () -> Void,
        openSetlists: @escaping () -> Void,
        openSongs: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        focusTimeline: @escaping () -> Void,
        revealTarget: @escaping (PreviewTarget) -> Void,
        requestTextInput: @escaping (CommandPaletteTextInputRequest) -> String?,
        inspectTrack: @escaping (ID<Track>) -> Void,
        inspectContainer: @escaping (ID<Container>) -> Void,
        openPianoRoll: @escaping (ID<Container>) -> Void,
        presentTrackAutomationPicker: @escaping (PendingEffectSelection) -> Void,
        presentContainerAutomationPicker: @escaping (PendingEffectSelection) -> Void
    ) {
        self.openMixer = openMixer
        self.openSetlists = openSetlists
        self.openSongs = openSongs
        self.openSettings = openSettings
        self.focusTimeline = focusTimeline
        self.revealTarget = revealTarget
        self.requestTextInput = requestTextInput
        self.inspectTrack = inspectTrack
        self.inspectContainer = inspectContainer
        self.openPianoRoll = openPianoRoll
        self.presentTrackAutomationPicker = presentTrackAutomationPicker
        self.presentContainerAutomationPicker = presentContainerAutomationPicker
    }
}

@MainActor
public final class CommandExecutor {
    private let projectViewModel: ProjectViewModel
    private let timelineViewModel: TimelineViewModel
    private let transportViewModel: TransportViewModel?
    private let ui: CommandPaletteUIActions

    public init(
        projectViewModel: ProjectViewModel,
        timelineViewModel: TimelineViewModel,
        transportViewModel: TransportViewModel?,
        ui: CommandPaletteUIActions
    ) {
        self.projectViewModel = projectViewModel
        self.timelineViewModel = timelineViewModel
        self.transportViewModel = transportViewModel
        self.ui = ui
    }

    public func addTrack(kind: TrackKind, to songID: ID<Song>? = nil, count: Int = 1, baseName: String? = nil) {
        if let songID, projectViewModel.currentSongID != songID {
            projectViewModel.selectSong(id: songID)
        }
        guard count > 0 else { return }
        ui.focusTimeline()
        for index in 0..<count {
            let resolvedName: String?
            if let baseName, !baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let trimmedBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
                resolvedName = count == 1 ? trimmedBaseName : "\(trimmedBaseName) \(index + 1)"
            } else {
                resolvedName = nil
            }
            projectViewModel.addTrack(kind: kind, customName: resolvedName)
        }
    }

    public func addCustomTrackCount(kind: TrackKind, to songID: ID<Song>? = nil) {
        guard let rawValue = ui.requestTextInput(
            CommandPaletteTextInputRequest(
                title: "Create \(kind.displayName) Tracks",
                message: "Enter how many \(kind.displayName.lowercased()) tracks to create.",
                initialValue: "1",
                placeholder: "Track count",
                actionTitle: "Create"
            )
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        let count = Int(rawValue),
        count > 0 else { return }

        addTrack(kind: kind, to: songID, count: count)
    }

    public func addCustomNamedTracks(kind: TrackKind, to songID: ID<Song>? = nil, count: Int) {
        let title = count == 1 ? "Name Track" : "Name Tracks"
        let message = count == 1
            ? "Choose a name for the new \(kind.displayName.lowercased()) track."
            : "Choose a base name for the \(count) new \(kind.displayName.lowercased()) tracks."
        let placeholder = count == 1 ? "Track name" : "Base track name"
        guard let baseName = ui.requestTextInput(
            CommandPaletteTextInputRequest(
                title: title,
                message: message,
                initialValue: kind.displayName,
                placeholder: placeholder,
                actionTitle: "Create"
            )
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !baseName.isEmpty else { return }

        addTrack(kind: kind, to: songID, count: count, baseName: baseName)
    }

    public func requestTextInput(_ request: CommandPaletteTextInputRequest) -> String? {
        ui.requestTextInput(request)
    }

    public func addSong() {
        ui.openSongs()
        projectViewModel.addSong()
    }

    public func openMixer() {
        ui.openMixer()
    }

    public func openSetlists() {
        ui.openSetlists()
    }

    public func openCurrentSong() {
        ui.openSongs()
        if let songID = projectViewModel.currentSongID {
            projectViewModel.selectSong(id: songID)
        }
    }

    public func openSettings() {
        ui.openSettings()
    }

    public func undo() {
        projectViewModel.undoManager?.undo()
    }

    public func redo() {
        projectViewModel.undoManager?.redo()
    }

    public func jumpToUndoHistory(index targetIndex: Int) {
        guard let undoManager = projectViewModel.undoManager else { return }
        let currentIndex = projectViewModel.undoState.undoHistoryCursor
        guard targetIndex != currentIndex else { return }

        if targetIndex < currentIndex {
            for _ in targetIndex..<currentIndex {
                guard undoManager.canUndo else { break }
                undoManager.undo()
            }
        } else {
            for _ in currentIndex..<targetIndex {
                guard undoManager.canRedo else { break }
                undoManager.redo()
            }
        }
    }

    public func inspectTrack(_ trackID: ID<Track>) {
        selectSong(containingTrackID: trackID)
        ui.focusTimeline()
        ui.inspectTrack(trackID)
    }

    public func renameSong(_ songID: ID<Song>, currentName: String) {
        guard let name = ui.requestTextInput(
            CommandPaletteTextInputRequest(
                title: "Rename Song",
                message: "Choose a new song name.",
                initialValue: currentName,
                placeholder: "Song name"
            )
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !name.isEmpty,
        name != currentName else { return }
        projectViewModel.renameSong(id: songID, newName: name)
    }

    public func inspectContainer(_ containerID: ID<Container>) {
        selectSong(containingContainerID: containerID)
        ui.focusTimeline()
        ui.inspectContainer(containerID)
    }

    public func reveal(_ target: PreviewTarget) {
        switch target {
        case .track(let trackID):
            selectSong(containingTrackID: trackID)
        case .container(let trackID, _):
            selectSong(containingTrackID: trackID)
        case .pluginInstance(let reference):
            selectSong(containingTrackID: reference.trackID)
        case .automation(let trackID, _, _):
            selectSong(containingTrackID: trackID)
        }
        ui.focusTimeline()
        ui.revealTarget(target)
    }

    public func duplicateTrack(_ trackID: ID<Track>) {
        selectSong(containingTrackID: trackID)
        _ = projectViewModel.duplicateTrack(trackID: trackID)
    }

    public func renameTrack(_ trackID: ID<Track>, currentName: String) {
        selectSong(containingTrackID: trackID)
        guard let name = ui.requestTextInput(
            CommandPaletteTextInputRequest(
                title: "Rename Track",
                message: "Choose a new track name.",
                initialValue: currentName,
                placeholder: "Track name"
            )
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !name.isEmpty,
        name != currentName else { return }
        projectViewModel.renameTrack(id: trackID, newName: name)
    }

    public func deleteTrack(_ trackID: ID<Track>) {
        selectSong(containingTrackID: trackID)
        projectViewModel.removeTrack(id: trackID)
    }

    public func toggleMute(trackID: ID<Track>) {
        selectSong(containingTrackID: trackID)
        projectViewModel.toggleMute(trackID: trackID)
        if let tracks = projectViewModel.currentSong?.tracks {
            transportViewModel?.updateMuteSoloState(tracks: tracks)
        }
    }

    public func toggleSolo(trackID: ID<Track>) {
        selectSong(containingTrackID: trackID)
        projectViewModel.toggleSolo(trackID: trackID)
        if let tracks = projectViewModel.currentSong?.tracks {
            transportViewModel?.updateMuteSoloState(tracks: tracks)
        }
    }

    public func toggleArm(trackID: ID<Track>) {
        selectSong(containingTrackID: trackID)
        guard let track = projectViewModel.project.songs.flatMap(\.tracks).first(where: { $0.id == trackID }) else { return }
        projectViewModel.setTrackRecordArmed(trackID: trackID, armed: !track.isRecordArmed)
    }

    public func addContainer(trackID: ID<Track>) {
        selectSong(containingTrackID: trackID)
        ui.focusTimeline()
        _ = projectViewModel.addContainer(
            trackID: trackID,
            startBar: timelineViewModel.playheadBar,
            lengthBars: 4
        )
    }

    public func duplicateContainer(trackID: ID<Track>, containerID: ID<Container>) {
        selectSong(containingTrackID: trackID)
        _ = projectViewModel.duplicateContainer(trackID: trackID, containerID: containerID)
    }

    public func renameContainer(_ containerID: ID<Container>, currentName: String) {
        selectSong(containingContainerID: containerID)
        guard let name = ui.requestTextInput(
            CommandPaletteTextInputRequest(
                title: "Rename Container",
                message: "Choose a new container name.",
                initialValue: currentName,
                placeholder: "Container name"
            )
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !name.isEmpty,
        name != currentName else { return }
        projectViewModel.updateContainerName(containerID: containerID, name: name)
    }

    public func toggleContainerArm(trackID: ID<Track>, containerID: ID<Container>) {
        selectSong(containingTrackID: trackID)
        projectViewModel.toggleContainerRecordArm(trackID: trackID, containerID: containerID)
    }

    public func addContainerEnterAction(containerID: ID<Container>, action: ContainerAction) {
        selectSong(containingContainerID: containerID)
        projectViewModel.addContainerEnterAction(containerID: containerID, action: action)
    }

    public func removeContainerEnterAction(containerID: ID<Container>, actionID: ID<ContainerAction>) {
        selectSong(containingContainerID: containerID)
        projectViewModel.removeContainerEnterAction(containerID: containerID, actionID: actionID)
    }

    public func addContainerExitAction(containerID: ID<Container>, action: ContainerAction) {
        selectSong(containingContainerID: containerID)
        projectViewModel.addContainerExitAction(containerID: containerID, action: action)
    }

    public func removeContainerExitAction(containerID: ID<Container>, actionID: ID<ContainerAction>) {
        selectSong(containingContainerID: containerID)
        projectViewModel.removeContainerExitAction(containerID: containerID, actionID: actionID)
    }

    public func deleteContainer(trackID: ID<Track>, containerID: ID<Container>) {
        selectSong(containingTrackID: trackID)
        projectViewModel.removeContainer(trackID: trackID, containerID: containerID)
    }

    public func unlinkContainer(trackID: ID<Track>, containerID: ID<Container>) {
        selectSong(containingTrackID: trackID)
        projectViewModel.consolidateContainer(trackID: trackID, containerID: containerID)
    }

    public func addTrackEffect(trackID: ID<Track>, effect: AudioUnitInfo) {
        selectSong(containingTrackID: trackID)
        projectViewModel.addTrackEffect(
            trackID: trackID,
            effect: InsertEffect(component: effect.componentInfo, displayName: effect.name)
        )
    }

    public func addContainerEffect(containerID: ID<Container>, effect: AudioUnitInfo) {
        guard let location = containerLocation(containerID: containerID) else { return }
        selectSong(containingTrackID: location.trackID)
        projectViewModel.addContainerEffect(
            containerID: containerID,
            effect: InsertEffect(component: effect.componentInfo, displayName: effect.name)
        )
    }

    public func setTrackInstrument(trackID: ID<Track>, instrument: AudioUnitInfo) {
        selectSong(containingTrackID: trackID)
        projectViewModel.setTrackInstrument(trackID: trackID, instrument: instrument.componentInfo)
    }

    public func setContainerInstrument(containerID: ID<Container>, instrument: AudioUnitInfo) {
        guard let location = containerLocation(containerID: containerID) else { return }
        selectSong(containingTrackID: location.trackID)
        projectViewModel.setContainerInstrumentOverride(containerID: containerID, override: instrument.componentInfo)
    }

    public func createTrackAndAddEffect(kind: TrackKind, effect: AudioUnitInfo, songID: ID<Song>? = nil) {
        guard let trackID = createTrack(kind: kind, songID: songID) else { return }
        addTrackEffect(trackID: trackID, effect: effect)
    }

    public func createTrackAndSetInstrument(kind: TrackKind = .midi, instrument: AudioUnitInfo, songID: ID<Song>? = nil) {
        guard let trackID = createTrack(kind: kind, songID: songID) else { return }
        setTrackInstrument(trackID: trackID, instrument: instrument)
    }

    public func createContainerAndAddEffect(trackID: ID<Track>, effect: AudioUnitInfo) {
        guard let containerID = createContainer(on: trackID) else { return }
        addContainerEffect(containerID: containerID, effect: effect)
    }

    public func createContainerAndSetInstrument(trackID: ID<Track>, instrument: AudioUnitInfo) {
        guard let containerID = createContainer(on: trackID) else { return }
        setContainerInstrument(containerID: containerID, instrument: instrument)
    }

    public func createTrackWithContainerAndAddEffect(kind: TrackKind, effect: AudioUnitInfo, songID: ID<Song>? = nil) {
        guard let trackID = createTrack(kind: kind, songID: songID),
              let containerID = createContainer(on: trackID) else { return }
        addContainerEffect(containerID: containerID, effect: effect)
    }

    public func createTrackWithContainerAndSetInstrument(kind: TrackKind = .midi, instrument: AudioUnitInfo, songID: ID<Song>? = nil) {
        guard let trackID = createTrack(kind: kind, songID: songID),
              let containerID = createContainer(on: trackID) else { return }
        setContainerInstrument(containerID: containerID, instrument: instrument)
    }

    public func openPluginUI(_ reference: CommandPalettePluginInstanceReference) {
        selectSong(containingTrackID: reference.trackID)
        switch reference.host {
        case .trackEffect:
            guard let effect = findTrackEffect(reference) else { return }
            let activeIndex = activeTrackEffectIndex(reference)
            let liveAU = effect.isBypassed ? nil : transportViewModel?.liveTrackEffectUnit(trackID: reference.trackID, effectIndex: activeIndex)
            PluginWindowManager.shared.open(
                component: effect.component,
                displayName: effect.displayName,
                presetData: effect.presetData,
                liveAudioUnit: liveAU,
                onPresetChanged: { [weak projectViewModel] data in
                    projectViewModel?.updateTrackEffectPreset(trackID: reference.trackID, effectID: effect.id, presetData: data)
                }
            )
        case .containerEffect:
            guard let effect = findContainerEffect(reference) else { return }
            let activeIndex = activeContainerEffectIndex(reference)
            let liveAU = effect.isBypassed ? nil : transportViewModel?.liveEffectUnit(containerID: reference.containerID ?? ID(), effectIndex: activeIndex)
            PluginWindowManager.shared.open(
                component: effect.component,
                displayName: effect.displayName,
                presetData: effect.presetData,
                liveAudioUnit: liveAU,
                onPresetChanged: { [weak projectViewModel] data in
                    guard let containerID = reference.containerID else { return }
                    projectViewModel?.updateContainerEffectPreset(containerID: containerID, effectID: effect.id, presetData: data)
                }
            )
        case .trackInstrument, .containerInstrument:
            PluginWindowManager.shared.open(
                component: reference.component,
                displayName: reference.displayName,
                presetData: nil,
                onPresetChanged: nil
            )
        }
    }

    public func togglePluginBypass(_ reference: CommandPalettePluginInstanceReference) {
        selectSong(containingTrackID: reference.trackID)
        switch reference.host {
        case .trackEffect:
            guard let effectID = reference.insertEffectID else { return }
            projectViewModel.toggleTrackEffectBypass(trackID: reference.trackID, effectID: effectID)
        case .containerEffect:
            guard let effectID = reference.insertEffectID, let containerID = reference.containerID else { return }
            projectViewModel.toggleContainerEffectBypass(containerID: containerID, effectID: effectID)
        case .trackInstrument, .containerInstrument:
            break
        }
    }

    public func deletePlugin(_ reference: CommandPalettePluginInstanceReference) {
        selectSong(containingTrackID: reference.trackID)
        switch reference.host {
        case .trackEffect:
            guard let effectID = reference.insertEffectID else { return }
            projectViewModel.removeTrackEffect(trackID: reference.trackID, effectID: effectID)
        case .containerEffect:
            guard let effectID = reference.insertEffectID, let containerID = reference.containerID else { return }
            projectViewModel.removeContainerEffect(containerID: containerID, effectID: effectID)
        case .trackInstrument:
            projectViewModel.setTrackInstrument(trackID: reference.trackID, instrument: nil)
        case .containerInstrument:
            guard let containerID = reference.containerID else { return }
            projectViewModel.setContainerInstrumentOverride(containerID: containerID, override: nil)
        }
    }

    public func addAutomationLanes(
        for reference: CommandPalettePluginInstanceReference,
        parameters: [LoopsEngine.AudioUnitParameterInfo]
    ) {
        guard !parameters.isEmpty else { return }
        selectSong(containingTrackID: reference.trackID)
        ui.focusTimeline()
        let existingAddresses = existingAutomationAddresses(for: reference)
        let newParameters = parameters.filter { !existingAddresses.contains($0.address) }
        guard !newParameters.isEmpty else { return }

        for parameter in newParameters {
            var lane = AutomationLane(
                targetPath: EffectPath(
                    trackID: reference.trackID,
                    containerID: reference.containerID,
                    effectIndex: reference.effectIndex,
                    parameterAddress: parameter.address
                )
            )
            lane.effectName = reference.parameterEffectName
            lane.parameterName = parameter.displayName
            lane.parameterMin = parameter.minValue
            lane.parameterMax = parameter.maxValue
            lane.parameterUnit = parameter.unit

            if let containerID = reference.containerID {
                projectViewModel.addAutomationLane(containerID: containerID, lane: lane)
            } else {
                projectViewModel.addTrackAutomationLane(trackID: reference.trackID, lane: lane)
            }
        }

        timelineViewModel.automationExpanded.insert(reference.trackID)
    }

    public func revealAutomation(trackID: ID<Track>) {
        reveal(.track(trackID))
    }

    public func addAutomationBreakpoint(lane: AutomationLane) {
        selectSong(containingTrackID: lane.targetPath.trackID)
        if let containerID = lane.targetPath.containerID {
            guard let container = findContainer(containerID) else { return }
            let position = max(0, min(container.lengthBars, timelineViewModel.playheadBar - container.startBar))
            let breakpoint = AutomationBreakpoint(position: position, value: 0.5)
            projectViewModel.addAutomationBreakpoint(containerID: containerID, laneID: lane.id, breakpoint: breakpoint)
        } else {
            let breakpoint = AutomationBreakpoint(position: max(0, timelineViewModel.playheadBar - 1.0), value: 0.5)
            projectViewModel.addTrackAutomationBreakpoint(trackID: lane.targetPath.trackID, laneID: lane.id, breakpoint: breakpoint)
        }
    }

    public func deleteAutomation(trackID: ID<Track>, lane: AutomationLane) {
        selectSong(containingTrackID: trackID)
        if let containerID = lane.targetPath.containerID {
            projectViewModel.removeAutomationLane(containerID: containerID, laneID: lane.id)
        } else {
            projectViewModel.removeTrackAutomationLane(trackID: trackID, laneID: lane.id)
        }
    }

    public func startMIDILearn(path: EffectPath) {
        selectSong(containingTrackID: path.trackID)
        projectViewModel.startMIDIParameterLearn(targetPath: path)
    }

    public func removeMIDIMapping(path: EffectPath) {
        selectSong(containingTrackID: path.trackID)
        projectViewModel.removeMIDIParameterMapping(forTarget: path)
        projectViewModel.onMIDIParameterMappingsChanged?()
    }

    public func assignExpressionPedal(trackID: ID<Track>, cc: UInt8, target: EffectPath?) {
        selectSong(containingTrackID: trackID)
        projectViewModel.assignExpressionPedal(trackID: trackID, cc: cc, target: target)
    }

    public func removeExpressionPedal(trackID: ID<Track>) {
        selectSong(containingTrackID: trackID)
        projectViewModel.removeExpressionPedal(trackID: trackID)
    }

    public func openPianoRoll(containerID: ID<Container>) {
        selectSong(containingContainerID: containerID)
        ui.openPianoRoll(containerID)
    }

    private func selectSong(containingTrackID trackID: ID<Track>) {
        guard let songID = projectViewModel.project.songs.first(where: { song in
            song.tracks.contains(where: { $0.id == trackID })
        })?.id else { return }
        if projectViewModel.currentSongID != songID {
            projectViewModel.selectSong(id: songID)
        }
    }

    private func selectSong(containingContainerID containerID: ID<Container>) {
        for song in projectViewModel.project.songs {
            if song.tracks.contains(where: { $0.containers.contains(where: { $0.id == containerID }) }) {
                if projectViewModel.currentSongID != song.id {
                    projectViewModel.selectSong(id: song.id)
                }
                return
            }
        }
    }

    private func containerLocation(containerID: ID<Container>) -> (trackID: ID<Track>, songID: ID<Song>)? {
        for song in projectViewModel.project.songs {
            for track in song.tracks {
                if track.containers.contains(where: { $0.id == containerID }) {
                    return (track.id, song.id)
                }
            }
        }
        return nil
    }

    private func existingAutomationAddresses(for reference: CommandPalettePluginInstanceReference) -> Set<UInt64> {
        if let containerID = reference.containerID,
           let container = findContainer(containerID) {
            return Set(
                container.automationLanes
                    .filter { $0.targetPath.effectIndex == reference.effectIndex }
                    .map(\.targetPath.parameterAddress)
            )
        }

        guard let track = projectViewModel.project.songs.flatMap(\.tracks).first(where: { $0.id == reference.trackID }) else {
            return []
        }
        return Set(
            track.trackAutomationLanes
                .filter { $0.targetPath.effectIndex == reference.effectIndex }
                .map(\.targetPath.parameterAddress)
        )
    }

    private func findContainer(_ containerID: ID<Container>) -> Container? {
        projectViewModel.project.songs
            .flatMap(\.tracks)
            .flatMap(\.containers)
            .first(where: { $0.id == containerID })
    }

    private func findTrackEffect(_ reference: CommandPalettePluginInstanceReference) -> InsertEffect? {
        projectViewModel.project.songs
            .flatMap(\.tracks)
            .first(where: { $0.id == reference.trackID })?
            .insertEffects
            .first(where: { $0.id == reference.insertEffectID })
    }

    private func findContainerEffect(_ reference: CommandPalettePluginInstanceReference) -> InsertEffect? {
        guard let containerID = reference.containerID else { return nil }
        return projectViewModel.project.songs
            .flatMap(\.tracks)
            .flatMap(\.containers)
            .first(where: { $0.id == containerID })?
            .insertEffects
            .first(where: { $0.id == reference.insertEffectID })
    }

    private func activeTrackEffectIndex(_ reference: CommandPalettePluginInstanceReference) -> Int {
        guard let track = projectViewModel.project.songs.flatMap(\.tracks).first(where: { $0.id == reference.trackID }) else { return reference.effectIndex }
        let sorted = track.insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        guard reference.effectIndex < sorted.count else { return reference.effectIndex }
        return sorted[0..<reference.effectIndex].filter { !$0.isBypassed }.count
    }

    private func activeContainerEffectIndex(_ reference: CommandPalettePluginInstanceReference) -> Int {
        guard let containerID = reference.containerID,
              let container = findContainer(containerID) else { return reference.effectIndex }
        let sorted = container.insertEffects.sorted { $0.orderIndex < $1.orderIndex }
        guard reference.effectIndex < sorted.count else { return reference.effectIndex }
        return sorted[0..<reference.effectIndex].filter { !$0.isBypassed }.count
    }

    private func createTrack(kind: TrackKind, songID: ID<Song>? = nil) -> ID<Track>? {
        if let songID, projectViewModel.currentSongID != songID {
            projectViewModel.selectSong(id: songID)
        }

        let previousTrackIDs = Set(projectViewModel.currentSong?.tracks.map(\.id) ?? [])
        ui.focusTimeline()
        projectViewModel.addTrack(kind: kind)

        return projectViewModel.currentSong?.tracks.first(where: { previousTrackIDs.contains($0.id) == false && $0.kind == kind })?.id
    }

    private func createContainer(on trackID: ID<Track>) -> ID<Container>? {
        selectSong(containingTrackID: trackID)
        let previousContainerIDs = Set(
            projectViewModel.project.songs
                .flatMap(\.tracks)
                .first(where: { $0.id == trackID })?
                .containers
                .map(\.id) ?? []
        )

        ui.focusTimeline()
        guard projectViewModel.addContainer(
            trackID: trackID,
            startBar: timelineViewModel.playheadBar,
            lengthBars: 4
        ) else {
            return nil
        }

        return projectViewModel.project.songs
            .flatMap(\.tracks)
            .first(where: { $0.id == trackID })?
            .containers
            .first(where: { previousContainerIDs.contains($0.id) == false })?
            .id
    }
}

@MainActor
public final class CommandPaletteCatalogBuilder {
    private let projectViewModel: ProjectViewModel
    private let timelineViewModel: TimelineViewModel
    private let transportViewModel: TransportViewModel?
    private let audioUnitProvider: CommandPaletteAudioUnitProvider
    private let parameterCache: CommandPaletteParameterCache
    private let shortcutManager: ShortcutManager
    private let executor: CommandExecutor

    public init(
        projectViewModel: ProjectViewModel,
        timelineViewModel: TimelineViewModel,
        transportViewModel: TransportViewModel?,
        shortcutManager: ShortcutManager,
        audioUnitProvider: CommandPaletteAudioUnitProvider = .live,
        parameterCache: CommandPaletteParameterCache? = nil,
        executor: CommandExecutor
    ) {
        self.projectViewModel = projectViewModel
        self.timelineViewModel = timelineViewModel
        self.transportViewModel = transportViewModel
        self.shortcutManager = shortcutManager
        self.audioUnitProvider = audioUnitProvider
        self.parameterCache = parameterCache ?? .shared
        self.executor = executor
    }

    public func rootNodes() -> [CommandNode] {
        contextNodes()
        + globalActionNodes()
        + songNodes()
        + trackNodes()
        + containerNodes()
        + pluginNodes()
        + pluginInstanceNodes()
        + automationNodes()
    }

    private func contextNodes() -> [CommandNode] {
        var nodes: [CommandNode] = []

        if let selection = selectedContainerContext() {
            nodes.append(
                CommandNode(
                    id: "context-selected-container-\(selection.container.id.rawValue.uuidString)",
                    kind: .container,
                    title: "Selected Container: \(selection.container.name)",
                    subtitle: "\(selection.track.name) · Bars \(formatBar(selection.container.startBar))-\(formatBar(selection.container.endBar))",
                    breadcrumbs: ["Context", selection.song.name],
                    badges: ["Context"] + containerBadges(for: selection.container, track: selection.track),
                    searchableText: [
                        "selected container",
                        "current selection",
                        selection.container.name,
                        selection.track.name,
                        selection.song.name,
                    ],
                    previewTarget: .container(trackID: selection.track.id, containerID: selection.container.id),
                    previewStyle: .pulse,
                    childrenProvider: {
                        self.containerActionNodes(song: selection.song, track: selection.track, container: selection.container)
                    }
                )
            )
        }

        if let selection = selectedTrackContext() {
            nodes.append(
                CommandNode(
                    id: "context-selected-track-\(selection.track.id.rawValue.uuidString)",
                    kind: .track,
                    title: "Selected Track: \(selection.track.name)",
                    subtitle: "\(selection.track.kind.displayName) Track in \(selection.song.name)",
                    breadcrumbs: ["Context", selection.song.name],
                    badges: ["Context"] + trackBadges(for: selection.track),
                    searchableText: [
                        "selected track",
                        "current selection",
                        selection.track.name,
                        selection.song.name,
                        selection.track.kind.displayName,
                    ],
                    previewTarget: .track(selection.track.id),
                    childrenProvider: {
                        self.trackActionNodes(song: selection.song, track: selection.track)
                    }
                )
            )
        }

        if let song = projectViewModel.currentSong {
            nodes.append(
                CommandNode(
                    id: "context-current-song-\(song.id.rawValue.uuidString)",
                    kind: .utility,
                    title: "Current Song: \(song.name)",
                    subtitle: "\(song.tracks.filter { $0.kind != .master }.count) tracks",
                    breadcrumbs: ["Context"],
                    badges: ["Context", "Song"],
                    searchableText: ["current song", "current context", song.name, "tracks"],
                    childrenProvider: {
                        self.currentSongContextNodes(song: song)
                    }
                )
            )
        }

        return nodes
    }

    private func globalActionNodes() -> [CommandNode] {
        return [
            CommandNode(
                id: "global-add-track",
                kind: .globalAction,
                title: "Add Track",
                subtitle: "Create a new track in the current song",
                breadcrumbs: ["Global"],
                badges: ["Track"],
                searchableText: ["new track", "create track", "audio", "midi", "bus", "backing"],
                shortcutDisplay: shortcutManager.displayString(for: .addTrack),
                childrenProvider: {
                    self.trackTypeChoiceNodes(breadcrumbs: ["Global", "Add Track"])
                }
            ),
            CommandNode(
                id: "global-add-song",
                kind: .globalAction,
                title: "Add Song",
                subtitle: "Create a new song",
                breadcrumbs: ["Global"],
                badges: ["Song"],
                searchableText: ["new song", "create song"],
                shortcutDisplay: shortcutManager.displayString(for: .addSong),
                execute: { [executor] in executor.addSong() }
            ),
            CommandNode(
                id: "global-undo",
                kind: .globalAction,
                title: "Undo",
                subtitle: projectViewModel.undoManager?.undoActionName.isEmpty == false
                    ? projectViewModel.undoManager?.undoActionName ?? ""
                    : "Undo the most recent change",
                breadcrumbs: ["Global"],
                badges: ["Undo"],
                searchableText: ["undo", "history", "revert", projectViewModel.undoManager?.undoActionName ?? ""],
                shortcutDisplay: shortcutManager.displayString(for: .undo),
                execute: { [executor] in executor.undo() }
            ),
            CommandNode(
                id: "global-redo",
                kind: .globalAction,
                title: "Redo",
                subtitle: projectViewModel.undoManager?.redoActionName.isEmpty == false
                    ? projectViewModel.undoManager?.redoActionName ?? ""
                    : "Redo the last undone change",
                breadcrumbs: ["Global"],
                badges: ["Redo"],
                searchableText: ["redo", "history", "restore", projectViewModel.undoManager?.redoActionName ?? ""],
                shortcutDisplay: shortcutManager.displayString(for: .redo),
                execute: { [executor] in executor.redo() }
            ),
            CommandNode(
                id: "global-undo-history",
                kind: .globalAction,
                title: "Undo History",
                subtitle: "\(projectViewModel.undoState.undoHistory.count) change\(projectViewModel.undoState.undoHistory.count == 1 ? "" : "s")",
                breadcrumbs: ["Global"],
                badges: ["Undo", "History"],
                searchableText: ["undo history", "redo history", "timeline", "history stack"],
                shortcutDisplay: shortcutManager.displayString(for: .undoHistory),
                childrenProvider: {
                    self.undoHistoryNodes()
                }
            ),
            CommandNode(
                id: "global-open-mixer",
                kind: .globalAction,
                title: "Open Mixer",
                subtitle: "Switch the center view to mixer mode",
                breadcrumbs: ["Global"],
                badges: ["Mixer"],
                searchableText: ["mixer", "mix view"],
                shortcutDisplay: shortcutManager.displayString(for: .openMixer),
                execute: { [executor] in executor.openMixer() }
            ),
            CommandNode(
                id: "global-open-setlists",
                kind: .globalAction,
                title: "Open Setlists",
                subtitle: "Switch the sidebar to setlists",
                breadcrumbs: ["Global"],
                badges: ["Setlists"],
                searchableText: ["setlists", "playlist", "perform"],
                shortcutDisplay: shortcutManager.displayString(for: .openSetlists),
                execute: { [executor] in executor.openSetlists() }
            ),
            CommandNode(
                id: "global-open-current-song",
                kind: .globalAction,
                title: "Go to Current Song",
                subtitle: projectViewModel.currentSong?.name ?? "Current song",
                breadcrumbs: ["Global"],
                badges: ["Song"],
                searchableText: ["current song", "go to song"],
                shortcutDisplay: shortcutManager.displayString(for: .goToCurrentSong),
                execute: { [executor] in executor.openCurrentSong() }
            ),
            CommandNode(
                id: "global-open-settings",
                kind: .globalAction,
                title: "Open Settings",
                subtitle: "Open audio device settings",
                breadcrumbs: ["Global"],
                badges: ["Settings"],
                searchableText: ["settings", "preferences", "audio device", "cmd,"],
                shortcutDisplay: shortcutManager.displayString(for: .openSettings),
                execute: { [executor] in executor.openSettings() }
            ),
        ]
    }

    private func undoHistoryNodes() -> [CommandNode] {
        let history = projectViewModel.undoState.undoHistory
        let cursor = projectViewModel.undoState.undoHistoryCursor

        return history.enumerated().reversed().map { index, entry in
            let isCurrent = index == cursor
            let directionBadge = index > cursor ? "Redo" : "Undo"
            return CommandNode(
                id: "undo-history-\(entry.id.uuidString)",
                kind: .utility,
                title: entry.actionName,
                subtitle: isCurrent
                    ? "Current state · \(entry.relativeTimeString)"
                    : "\(directionBadge) to here · \(entry.relativeTimeString)",
                breadcrumbs: ["Global", "Undo History"],
                badges: isCurrent ? ["History", "Current"] : ["History", directionBadge],
                searchableText: [
                    "undo",
                    "redo",
                    "history",
                    entry.actionName,
                    entry.relativeTimeString,
                ],
                execute: { [executor] in executor.jumpToUndoHistory(index: index) }
            )
        }
    }

    private func currentSongContextNodes(song: Song) -> [CommandNode] {
        var nodes: [CommandNode] = [
            CommandNode(
                id: "context-current-song-open-\(song.id.rawValue.uuidString)",
                kind: .utility,
                title: "Open Song",
                subtitle: "Switch to \(song.name)",
                breadcrumbs: ["Context", song.name],
                badges: ["Song"],
                searchableText: ["open song", "select song", song.name],
                execute: { [projectViewModel] in projectViewModel.selectSong(id: song.id) }
            ),
            CommandNode(
                id: "context-current-song-rename-\(song.id.rawValue.uuidString)",
                kind: .utility,
                title: "Rename Song",
                subtitle: "Update the name of \(song.name)",
                breadcrumbs: ["Context", song.name],
                badges: ["Song"],
                searchableText: ["rename song", song.name],
                execute: { [executor] in executor.renameSong(song.id, currentName: song.name) }
            ),
            CommandNode(
                id: "context-current-song-duplicate-\(song.id.rawValue.uuidString)",
                kind: .utility,
                title: "Duplicate Song",
                subtitle: "Create a copy of \(song.name)",
                breadcrumbs: ["Context", song.name],
                badges: ["Song"],
                searchableText: ["duplicate song", "copy song", song.name],
                execute: { [projectViewModel] in projectViewModel.duplicateSong(id: song.id) }
            ),
            CommandNode(
                id: "context-current-song-delete-\(song.id.rawValue.uuidString)",
                kind: .utility,
                title: "Delete Song",
                subtitle: "Remove \(song.name)",
                breadcrumbs: ["Context", song.name],
                badges: ["Song", "Delete"],
                searchableText: ["delete song", "remove song", song.name],
                confirmation: CommandConfirmation(
                    title: "Delete \(song.name)?",
                    message: "This removes the song from the project."
                ),
                execute: { [projectViewModel] in projectViewModel.removeSong(id: song.id) }
            ),
            CommandNode(
                id: "context-current-song-add-track-\(song.id.rawValue.uuidString)",
                kind: .utility,
                title: "Add Track",
                subtitle: "Create a new track in \(song.name)",
                breadcrumbs: ["Context", song.name],
                badges: ["Track"],
                searchableText: ["add track", "new track", song.name],
                childrenProvider: {
                    self.trackTypeChoiceNodes(breadcrumbs: ["Context", song.name, "Add Track"], songID: song.id)
                }
            ),
            CommandNode(
                id: "context-current-song-open-mixer-\(song.id.rawValue.uuidString)",
                kind: .utility,
                title: "Open Mixer",
                subtitle: "Switch to the mixer for \(song.name)",
                breadcrumbs: ["Context", song.name],
                badges: ["Mixer"],
                searchableText: ["mixer", "current song", song.name],
                execute: { [executor] in executor.openMixer() }
            ),
        ]

        nodes.append(contentsOf: song.tracks.map { track in
            CommandNode(
                id: "context-current-song-track-\(track.id.rawValue.uuidString)",
                kind: .track,
                title: track.name,
                subtitle: "\(track.kind.displayName) Track",
                breadcrumbs: ["Context", song.name],
                badges: trackBadges(for: track),
                searchableText: ["current song", song.name, track.name, track.kind.displayName],
                previewTarget: .track(track.id),
                childrenProvider: {
                    self.trackActionNodes(song: song, track: track)
                }
            )
        })

        return nodes
    }

    private func songNodes() -> [CommandNode] {
        projectViewModel.project.songs.map { song in
            CommandNode(
                id: "song-\(song.id.rawValue.uuidString)",
                kind: .utility,
                title: song.name,
                subtitle: "Song · \(song.tracks.filter { $0.kind != .master }.count) tracks",
                breadcrumbs: ["Songs"],
                badges: ["Song"],
                searchableText: [
                    "song",
                    song.name,
                    "rename",
                    "duplicate",
                    "delete",
                    "add track",
                ],
                childrenProvider: {
                    self.songActionNodes(song: song)
                }
            )
        }
    }

    private func songActionNodes(song: Song) -> [CommandNode] {
        var nodes: [CommandNode] = [
            CommandNode(
                id: "song-open-\(song.id.rawValue.uuidString)",
                kind: .utility,
                title: "Open Song",
                subtitle: "Switch to \(song.name)",
                breadcrumbs: ["Songs", song.name],
                badges: ["Song"],
                searchableText: ["open song", "select song", song.name],
                execute: { [projectViewModel] in projectViewModel.selectSong(id: song.id) }
            ),
            CommandNode(
                id: "song-rename-\(song.id.rawValue.uuidString)",
                kind: .utility,
                title: "Rename Song",
                subtitle: "Update the name of \(song.name)",
                breadcrumbs: ["Songs", song.name],
                badges: ["Song"],
                searchableText: ["rename song", song.name],
                execute: { [executor] in executor.renameSong(song.id, currentName: song.name) }
            ),
            CommandNode(
                id: "song-duplicate-\(song.id.rawValue.uuidString)",
                kind: .utility,
                title: "Duplicate Song",
                subtitle: "Create a copy of \(song.name)",
                breadcrumbs: ["Songs", song.name],
                badges: ["Song"],
                searchableText: ["duplicate song", "copy song", song.name],
                execute: { [projectViewModel] in projectViewModel.duplicateSong(id: song.id) }
            ),
            CommandNode(
                id: "song-delete-\(song.id.rawValue.uuidString)",
                kind: .utility,
                title: "Delete Song",
                subtitle: "Remove \(song.name)",
                breadcrumbs: ["Songs", song.name],
                badges: ["Song", "Delete"],
                searchableText: ["delete song", "remove song", song.name],
                confirmation: CommandConfirmation(
                    title: "Delete \(song.name)?",
                    message: "This removes the song from the project."
                ),
                execute: { [projectViewModel] in projectViewModel.removeSong(id: song.id) }
            ),
            CommandNode(
                id: "song-add-track-\(song.id.rawValue.uuidString)",
                kind: .utility,
                title: "Add Track",
                subtitle: "Create a new track in \(song.name)",
                breadcrumbs: ["Songs", song.name],
                badges: ["Track"],
                searchableText: ["add track", "new track", song.name],
                childrenProvider: {
                    self.trackTypeChoiceNodes(breadcrumbs: ["Songs", song.name, "Add Track"], songID: song.id)
                }
            ),
        ]

        nodes.append(contentsOf: song.tracks.map { track in
            CommandNode(
                id: "song-track-\(song.id.rawValue.uuidString)-\(track.id.rawValue.uuidString)",
                kind: .track,
                title: track.name,
                subtitle: "\(track.kind.displayName) Track",
                breadcrumbs: ["Songs", song.name],
                badges: trackBadges(for: track),
                searchableText: ["track", song.name, track.name, track.kind.displayName],
                previewTarget: .track(track.id),
                childrenProvider: {
                    self.trackActionNodes(song: song, track: track)
                }
            )
        })

        return nodes
    }

    private func trackTypeChoiceNodes(breadcrumbs: [String], songID: ID<Song>? = nil) -> [CommandNode] {
        TrackKind.creatableKinds.map { kind in
            CommandNode(
                id: "track-type-choice-\(kind.rawValue)-\(breadcrumbs.joined(separator: "-"))",
                kind: .destination,
                title: "Add \(kind.displayName) Track",
                subtitle: "Choose how many \(kind.displayName.lowercased()) tracks to create",
                breadcrumbs: breadcrumbs,
                badges: ["Track"],
                searchableText: ["new track", "create track", kind.displayName, "count", "quantity"],
                childrenProvider: {
                    self.trackCountChoiceNodes(kind: kind, breadcrumbs: breadcrumbs + [kind.displayName], songID: songID)
                }
            )
        }
    }

    private func trackCountChoiceNodes(kind: TrackKind, breadcrumbs: [String], songID: ID<Song>? = nil) -> [CommandNode] {
        let presetCounts = [1, 2, 4, 8]
        let presetNodes = presetCounts.map { count in
            CommandNode(
                id: "track-count-\(kind.rawValue)-\(count)-\(breadcrumbs.joined(separator: "-"))",
                kind: .destination,
                title: count == 1 ? "Create 1 Track" : "Create \(count) Tracks",
                subtitle: count == 1
                    ? "Choose the track name"
                    : "Choose names for the \(count) \(kind.displayName.lowercased()) tracks",
                breadcrumbs: breadcrumbs,
                badges: count == 1 ? ["Track", "Default"] : ["Track"],
                searchableText: [
                    "track count",
                    "quantity",
                    "\(count)",
                    kind.displayName,
                    count == 1 ? "default" : "",
                ],
                childEntryBuilder: {
                    self.trackNamingEntry(kind: kind, count: count, breadcrumbs: breadcrumbs + ["\(count)"], songID: songID)
                }
            )
        }

        let customNode = CommandNode(
            id: "track-count-custom-\(kind.rawValue)-\(breadcrumbs.joined(separator: "-"))",
            kind: .destination,
            title: "Custom Count…",
            subtitle: "Enter an exact number, then choose names",
            breadcrumbs: breadcrumbs,
            badges: ["Track", "Input"],
            searchableText: ["custom count", "quantity", "number of tracks", kind.displayName],
            childEntryBuilder: {
                guard let rawValue = self.executorCustomTrackCount(kind: kind),
                      rawValue > 0 else {
                    return CommandNodeChildEntry(
                        title: "Add \(kind.displayName) Track",
                        nodesProvider: { [] }
                    )
                }
                return self.trackNamingEntry(kind: kind, count: rawValue, breadcrumbs: breadcrumbs + ["\(rawValue)"], songID: songID)
            }
        )

        return presetNodes + [customNode]
    }

    private func trackNamingEntry(kind: TrackKind, count: Int, breadcrumbs: [String], songID: ID<Song>? = nil) -> CommandNodeChildEntry {
        CommandNodeChildEntry(
            title: count == 1 ? "Name Track" : "Name Tracks",
            breadcrumbTitle: count == 1 ? "Name" : "Names",
            nodesProvider: {
                self.trackNamingNodes(kind: kind, count: count, breadcrumbs: breadcrumbs, songID: songID)
            }
        )
    }

    private func trackNamingNodes(kind: TrackKind, count: Int, breadcrumbs: [String], songID: ID<Song>? = nil) -> [CommandNode] {
        let previewNames = defaultTrackNames(kind: kind, count: count, songID: songID)
        let defaultTitle = count == 1 ? "Use Default Name" : "Use Default Names"
        let defaultSubtitle = previewNames.joined(separator: count > 3 ? ", " : " · ")

        let defaultNode = CommandNode(
            id: "track-name-default-\(kind.rawValue)-\(count)-\(breadcrumbs.joined(separator: "-"))",
            kind: .destination,
            title: defaultTitle,
            subtitle: defaultSubtitle,
            breadcrumbs: breadcrumbs,
            badges: ["Track", "Default"],
            searchableText: ["default name", "default names", kind.displayName] + previewNames,
            execute: { [executor] in executor.addTrack(kind: kind, to: songID, count: count) }
        )

        let customTitle = count == 1 ? "Custom Name…" : "Custom Base Name…"
        let customSubtitle = count == 1
            ? "Enter a custom track name"
            : "Enter a base name and Loops will number the tracks"
        let customNode = CommandNode(
            id: "track-name-custom-\(kind.rawValue)-\(count)-\(breadcrumbs.joined(separator: "-"))",
            kind: .destination,
            title: customTitle,
            subtitle: customSubtitle,
            breadcrumbs: breadcrumbs,
            badges: ["Track", "Input"],
            searchableText: ["custom track name", "base name", kind.displayName],
            execute: { [executor] in executor.addCustomNamedTracks(kind: kind, to: songID, count: count) }
        )

        return [defaultNode, customNode]
    }

    private func defaultTrackNames(kind: TrackKind, count: Int, songID: ID<Song>? = nil) -> [String] {
        let song = songID.flatMap { targetID in
            projectViewModel.project.songs.first(where: { $0.id == targetID })
        } ?? projectViewModel.currentSong

        let existingCount = song?.tracks.filter { $0.kind == kind }.count ?? 0
        return (0..<count).map { offset in
            "\(kind.displayName) \(existingCount + offset + 1)"
        }
    }

    private func executorCustomTrackCount(kind: TrackKind) -> Int? {
        guard let rawValue = executor.requestTextInput(
            CommandPaletteTextInputRequest(
                title: "Create \(kind.displayName) Tracks",
                message: "Enter how many \(kind.displayName.lowercased()) tracks to create.",
                initialValue: "1",
                placeholder: "Track count",
                actionTitle: "Continue"
            )
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        let count = Int(rawValue),
        count > 0 else {
            return nil
        }
        return count
    }

    private func trackNodes() -> [CommandNode] {
        projectViewModel.project.songs.flatMap { song in
            song.tracks.map { track in
                let breadcrumbs = [song.name]
                return CommandNode(
                    id: "track-\(track.id.rawValue.uuidString)",
                    kind: .track,
                    title: track.name,
                    subtitle: "\(track.kind.displayName) Track",
                    breadcrumbs: breadcrumbs,
                    badges: trackBadges(for: track),
                    searchableText: [
                        "track",
                        song.name,
                        track.kind.displayName,
                        "rename",
                        "duplicate",
                        "delete",
                        "mute",
                        "solo",
                        "arm",
                        "automation",
                        "plugin"
                    ],
                    previewTarget: .track(track.id),
                    childrenProvider: {
                        self.trackActionNodes(song: song, track: track)
                    }
                )
            }
        }
    }

    private func trackActionNodes(song: Song, track: Track) -> [CommandNode] {
        var nodes: [CommandNode] = [
            CommandNode(
                id: "track-inspect-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: "Inspect Track",
                subtitle: "Show \(track.name) in the inspector",
                breadcrumbs: [song.name, track.name],
                badges: ["Track"],
                searchableText: ["inspect", "reveal"],
                previewTarget: .track(track.id),
                execute: { [executor] in executor.inspectTrack(track.id) }
            ),
            CommandNode(
                id: "track-rename-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: "Rename Track",
                subtitle: "Update the name of \(track.name)",
                breadcrumbs: [song.name, track.name],
                badges: ["Track"],
                searchableText: ["rename track", track.name],
                previewTarget: .track(track.id),
                execute: { [executor] in executor.renameTrack(track.id, currentName: track.name) }
            ),
            CommandNode(
                id: "track-reveal-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: "Scroll Into View",
                subtitle: "Center \(track.name) in the timeline",
                breadcrumbs: [song.name, track.name],
                badges: ["Track", "Navigate"],
                searchableText: ["scroll into view", "reveal track", "find track", "navigate"],
                previewTarget: .track(track.id),
                execute: { [executor] in executor.reveal(.track(track.id)) }
            ),
            CommandNode(
                id: "track-duplicate-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: "Duplicate Track",
                subtitle: "Create a copy of \(track.name)",
                breadcrumbs: [song.name, track.name],
                badges: ["Track"],
                searchableText: ["duplicate", "copy track"],
                previewTarget: .track(track.id),
                execute: { [executor] in executor.duplicateTrack(track.id) }
            ),
            CommandNode(
                id: "track-delete-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: "Delete Track",
                subtitle: "Remove \(track.name)",
                breadcrumbs: [song.name, track.name],
                badges: ["Track", "Delete"],
                searchableText: ["delete", "remove"],
                previewTarget: .track(track.id),
                confirmation: CommandConfirmation(
                    title: "Delete \(track.name)?",
                    message: "This removes the track and its containers."
                ),
                execute: { [executor] in executor.deleteTrack(track.id) }
            ),
            CommandNode(
                id: "track-mute-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: track.isMuted ? "Unmute Track" : "Mute Track",
                subtitle: "\(track.name) \(track.isMuted ? "is muted" : "is audible")",
                breadcrumbs: [song.name, track.name],
                badges: ["Track"],
                searchableText: ["mute", "unmute"],
                previewTarget: .track(track.id),
                execute: { [executor] in executor.toggleMute(trackID: track.id) }
            ),
            CommandNode(
                id: "track-solo-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: track.isSoloed ? "Unsolo Track" : "Solo Track",
                subtitle: "Toggle solo for \(track.name)",
                breadcrumbs: [song.name, track.name],
                badges: ["Track"],
                searchableText: ["solo", "unsolo"],
                previewTarget: .track(track.id),
                execute: { [executor] in executor.toggleSolo(trackID: track.id) }
            ),
            CommandNode(
                id: "track-arm-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: track.isRecordArmed ? "Disarm Track" : "Arm Track",
                subtitle: "Toggle recording for \(track.name)",
                breadcrumbs: [song.name, track.name],
                badges: ["Track"],
                searchableText: ["record arm", "arm", "disarm"],
                previewTarget: .track(track.id),
                execute: { [executor] in executor.toggleArm(trackID: track.id) }
            ),
            CommandNode(
                id: "track-add-container-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: "Add Container at Playhead",
                subtitle: "Create a 4-bar container on \(track.name)",
                breadcrumbs: [song.name, track.name],
                badges: ["Container"],
                searchableText: ["add container", "new clip"],
                previewTarget: .track(track.id),
                execute: { [executor] in executor.addContainer(trackID: track.id) }
            ),
            CommandNode(
                id: "track-automation-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: "Show Automation",
                subtitle: "Reveal automation lanes for \(track.name)",
                breadcrumbs: [song.name, track.name],
                badges: ["Automation"],
                searchableText: ["automation", "lanes"],
                previewTarget: .track(track.id),
                execute: { [executor] in executor.revealAutomation(trackID: track.id) }
            ),
            CommandNode(
                id: "track-browse-automation-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: "Browse Automation Lanes",
                subtitle: "See automation on \(track.name) and its containers",
                breadcrumbs: [song.name, track.name],
                badges: ["Automation"],
                searchableText: ["browse automation", "lanes", "automation", track.name],
                previewTarget: .track(track.id),
                childrenProvider: {
                    self.trackAutomationNodes(song: song, track: track)
                }
            ),
            CommandNode(
                id: "track-add-effect-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: "Add Effect",
                subtitle: "Insert a plugin on \(track.name)",
                breadcrumbs: [song.name, track.name],
                badges: ["Plugin"],
                searchableText: ["add effect", "plugin", "insert"],
                previewTarget: .track(track.id),
                childrenProvider: {
                    self.effectDestinationNodes(trackID: track.id)
                }
            ),
            CommandNode(
                id: "track-effects-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: "Effects",
                subtitle: track.insertEffects.isEmpty
                    ? "No track effects on \(track.name)"
                    : "\(track.insertEffects.count) track effect\(track.insertEffects.count == 1 ? "" : "s") on \(track.name)",
                breadcrumbs: [song.name, track.name],
                badges: ["Plugin", "Effect"],
                searchableText: ["effects", "track effects", "browse effects", track.name],
                previewTarget: .track(track.id),
                childrenProvider: {
                    self.pluginInstanceNodes(
                        filterTrackID: track.id,
                        filterHosts: [.trackEffect]
                    )
                }
            ),
            CommandNode(
                id: "track-add-automation-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: "Add Automation",
                subtitle: "Choose parameters from track effects on \(track.name)",
                breadcrumbs: [song.name, track.name],
                badges: ["Automation"],
                searchableText: ["add automation", "effect automation", "track effects", track.name],
                previewTarget: .track(track.id),
                childrenProvider: {
                    self.pluginAutomationInstanceNodes(
                        filterTrackID: track.id,
                        filterHosts: [.trackEffect]
                    )
                }
            ),
            CommandNode(
                id: "track-browse-containers-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: "Browse Containers",
                subtitle: track.containers.isEmpty
                    ? "No containers on \(track.name)"
                    : "\(track.containers.count) container\(track.containers.count == 1 ? "" : "s") on \(track.name)",
                breadcrumbs: [song.name, track.name],
                badges: ["Container"],
                searchableText: ["containers", "clips", "browse containers", track.name],
                previewTarget: .track(track.id),
                childrenProvider: {
                    self.trackContainerNodes(song: song, track: track)
                }
            ),
            CommandNode(
                id: "track-browse-hosted-plugins-\(track.id.rawValue.uuidString)",
                kind: .utility,
                title: "Browse Hosted Plugins",
                subtitle: "See instruments and effects on \(track.name)",
                breadcrumbs: [song.name, track.name],
                badges: ["Plugin"],
                searchableText: ["hosted plugins", "effects", "instrument", "instances"],
                previewTarget: .track(track.id),
                childrenProvider: {
                    self.pluginInstanceNodes(filterTrackID: track.id)
                }
            ),
        ]

        if track.kind == .midi {
            nodes.append(
                CommandNode(
                    id: "track-set-instrument-\(track.id.rawValue.uuidString)",
                    kind: .utility,
                    title: "Set Instrument",
                    subtitle: "Choose an instrument for \(track.name)",
                    breadcrumbs: [song.name, track.name],
                    badges: ["Instrument"],
                    searchableText: ["set instrument", "instrument", "synth"],
                    previewTarget: .track(track.id),
                    childrenProvider: {
                        self.instrumentDestinationNodes(trackID: track.id)
                    }
                )
            )
        }

        return nodes
    }

    private func trackAutomationNodes(song: Song, track: Track) -> [CommandNode] {
        let trackLanes = track.trackAutomationLanes.map { lane in
            automationNode(song: song, track: track, lane: lane, container: nil)
        }
        let containerLanes = track.containers.flatMap { container in
            container.automationLanes.map { lane in
                automationNode(song: song, track: track, lane: lane, container: container)
            }
        }
        return trackLanes + containerLanes
    }

    private func trackContainerNodes(song: Song, track: Track) -> [CommandNode] {
        track.containers.map { container in
            CommandNode(
                id: "track-container-\(track.id.rawValue.uuidString)-\(container.id.rawValue.uuidString)",
                kind: .container,
                title: container.name,
                subtitle: "Bars \(formatBar(container.startBar))-\(formatBar(container.endBar))",
                breadcrumbs: [song.name, track.name],
                badges: containerBadges(for: container, track: track),
                searchableText: [
                    "container",
                    "clip",
                    container.name,
                    track.name,
                    song.name,
                ],
                previewTarget: .container(trackID: track.id, containerID: container.id),
                previewStyle: .pulse,
                childrenProvider: {
                    self.containerActionNodes(song: song, track: track, container: container)
                }
            )
        }
    }

    private func containerNodes() -> [CommandNode] {
        projectViewModel.project.songs.flatMap { song in
            song.tracks.flatMap { track in
                track.containers.map { container in
                    let breadcrumbs = [song.name, track.name]
                    return CommandNode(
                        id: "container-\(container.id.rawValue.uuidString)",
                        kind: .container,
                        title: container.name,
                        subtitle: "Container · Bars \(formatBar(container.startBar))-\(formatBar(container.endBar))",
                        breadcrumbs: breadcrumbs,
                        badges: containerBadges(for: container, track: track),
                        searchableText: [
                            "container",
                            "clip",
                            track.name,
                            song.name,
                            "rename",
                            "duplicate",
                            "delete",
                            "effect",
                            "automation",
                            container.name
                        ],
                        previewTarget: .container(trackID: track.id, containerID: container.id),
                        previewStyle: .pulse,
                        childrenProvider: {
                            self.containerActionNodes(song: song, track: track, container: container)
                        }
                    )
                }
            }
        }
    }

    private func containerActionNodes(song: Song, track: Track, container: Container) -> [CommandNode] {
        var nodes: [CommandNode] = [
            CommandNode(
                id: "container-inspect-\(container.id.rawValue.uuidString)",
                kind: .utility,
                title: "Inspect Container",
                subtitle: "Show \(container.name) in the inspector",
                breadcrumbs: [song.name, track.name, container.name],
                badges: ["Container"],
                searchableText: ["inspect", "reveal"],
                previewTarget: .container(trackID: track.id, containerID: container.id),
                previewStyle: .pulse,
                execute: { [executor] in executor.inspectContainer(container.id) }
            ),
            CommandNode(
                id: "container-rename-\(container.id.rawValue.uuidString)",
                kind: .utility,
                title: "Rename Container",
                subtitle: "Update the name of \(container.name)",
                breadcrumbs: [song.name, track.name, container.name],
                badges: ["Container"],
                searchableText: ["rename container", "rename clip", container.name],
                previewTarget: .container(trackID: track.id, containerID: container.id),
                previewStyle: .pulse,
                execute: { [executor] in executor.renameContainer(container.id, currentName: container.name) }
            ),
            CommandNode(
                id: "container-reveal-\(container.id.rawValue.uuidString)",
                kind: .utility,
                title: "Scroll Into View",
                subtitle: "Center \(container.name) in the timeline",
                breadcrumbs: [song.name, track.name, container.name],
                badges: ["Container", "Navigate"],
                searchableText: ["scroll into view", "reveal container", "find container", "navigate"],
                previewTarget: .container(trackID: track.id, containerID: container.id),
                previewStyle: .pulse,
                execute: { [executor] in
                    executor.reveal(.container(trackID: track.id, containerID: container.id))
                }
            ),
            CommandNode(
                id: "container-arm-\(container.id.rawValue.uuidString)",
                kind: .utility,
                title: container.isRecordArmed ? "Disarm Container" : "Arm Container",
                subtitle: container.isRecordArmed
                    ? "\(container.name) is armed for recording"
                    : "Enable record arm for \(container.name)",
                breadcrumbs: [song.name, track.name, container.name],
                badges: ["Container", "Record"],
                searchableText: ["arm container", "disarm container", "record arm", container.name],
                shortcutDisplay: shortcutManager.displayString(for: .toggleContainerArm),
                previewTarget: .container(trackID: track.id, containerID: container.id),
                previewStyle: .pulse,
                execute: { [executor] in
                    executor.toggleContainerArm(trackID: track.id, containerID: container.id)
                }
            ),
            CommandNode(
                id: "container-duplicate-\(container.id.rawValue.uuidString)",
                kind: .utility,
                title: "Duplicate Container",
                subtitle: "Create a copy of \(container.name)",
                breadcrumbs: [song.name, track.name, container.name],
                badges: ["Container"],
                searchableText: ["duplicate", "copy clip"],
                previewTarget: .container(trackID: track.id, containerID: container.id),
                previewStyle: .pulse,
                execute: { [executor] in executor.duplicateContainer(trackID: track.id, containerID: container.id) }
            ),
            CommandNode(
                id: "container-delete-\(container.id.rawValue.uuidString)",
                kind: .utility,
                title: "Delete Container",
                subtitle: "Remove \(container.name)",
                breadcrumbs: [song.name, track.name, container.name],
                badges: ["Container", "Delete"],
                searchableText: ["delete", "remove clip"],
                previewTarget: .container(trackID: track.id, containerID: container.id),
                previewStyle: .pulse,
                confirmation: CommandConfirmation(
                    title: "Delete \(container.name)?",
                    message: "This removes the container from \(track.name)."
                ),
                execute: { [executor] in executor.deleteContainer(trackID: track.id, containerID: container.id) }
            ),
            CommandNode(
                id: "container-add-effect-\(container.id.rawValue.uuidString)",
                kind: .utility,
                title: "Add Effect",
                subtitle: "Insert a plugin on \(container.name)",
                breadcrumbs: [song.name, track.name, container.name],
                badges: ["Plugin"],
                searchableText: ["add effect", "plugin"],
                previewTarget: .container(trackID: track.id, containerID: container.id),
                previewStyle: .pulse,
                childrenProvider: {
                    self.effectDestinationNodes(containerID: container.id)
                }
            ),
            CommandNode(
                id: "container-enter-actions-\(container.id.rawValue.uuidString)",
                kind: .utility,
                title: "Enter Actions",
                subtitle: container.onEnterActions.isEmpty
                    ? "No enter actions on \(container.name)"
                    : "\(container.onEnterActions.count) enter action\(container.onEnterActions.count == 1 ? "" : "s")",
                breadcrumbs: [song.name, track.name, container.name],
                badges: ["Container", "Enter"],
                searchableText: ["enter actions", "container enter", container.name],
                previewTarget: .container(trackID: track.id, containerID: container.id),
                previewStyle: .pulse,
                childrenProvider: {
                    self.containerLifecycleActionNodes(song: song, track: track, container: container, phase: .enter)
                }
            ),
            CommandNode(
                id: "container-exit-actions-\(container.id.rawValue.uuidString)",
                kind: .utility,
                title: "Exit Actions",
                subtitle: container.onExitActions.isEmpty
                    ? "No exit actions on \(container.name)"
                    : "\(container.onExitActions.count) exit action\(container.onExitActions.count == 1 ? "" : "s")",
                breadcrumbs: [song.name, track.name, container.name],
                badges: ["Container", "Exit"],
                searchableText: ["exit actions", "container exit", container.name],
                previewTarget: .container(trackID: track.id, containerID: container.id),
                previewStyle: .pulse,
                childrenProvider: {
                    self.containerLifecycleActionNodes(song: song, track: track, container: container, phase: .exit)
                }
            ),
            CommandNode(
                id: "container-add-automation-\(container.id.rawValue.uuidString)",
                kind: .utility,
                title: "Add Automation",
                subtitle: "Choose a parameter for \(container.name)",
                breadcrumbs: [song.name, track.name, container.name],
                badges: ["Automation"],
                searchableText: ["add automation", "parameter"],
                previewTarget: .container(trackID: track.id, containerID: container.id),
                previewStyle: .pulse,
                childrenProvider: {
                    self.pluginAutomationInstanceNodes(filterContainerID: container.id)
                }
            ),
            CommandNode(
                id: "container-browse-hosted-plugins-\(container.id.rawValue.uuidString)",
                kind: .utility,
                title: "Browse Hosted Plugins",
                subtitle: "See instruments and effects on \(container.name)",
                breadcrumbs: [song.name, track.name, container.name],
                badges: ["Plugin"],
                searchableText: ["browse hosted plugins", "effects", "instrument", "instances"],
                previewTarget: .container(trackID: track.id, containerID: container.id),
                previewStyle: .pulse,
                childrenProvider: {
                    self.pluginInstanceNodes(filterContainerID: container.id)
                }
            ),
        ]

        if container.isClone {
            nodes.append(
                CommandNode(
                    id: "container-unlink-\(container.id.rawValue.uuidString)",
                    kind: .utility,
                    title: "Unlink Container",
                    subtitle: "Consolidate this clone into an independent container",
                    breadcrumbs: [song.name, track.name, container.name],
                    badges: ["Container"],
                    searchableText: ["unlink", "consolidate clone"],
                    previewTarget: .container(trackID: track.id, containerID: container.id),
                    previewStyle: .pulse,
                    execute: { [executor] in executor.unlinkContainer(trackID: track.id, containerID: container.id) }
                )
            )
        }

        if track.kind == .midi {
            nodes.append(
                CommandNode(
                    id: "container-set-instrument-\(container.id.rawValue.uuidString)",
                    kind: .utility,
                    title: "Set Instrument Override",
                    subtitle: "Choose a container-specific instrument",
                    breadcrumbs: [song.name, track.name, container.name],
                    badges: ["Instrument"],
                    searchableText: ["instrument", "override", "synth"],
                    previewTarget: .container(trackID: track.id, containerID: container.id),
                    previewStyle: .pulse,
                    childrenProvider: {
                        self.instrumentDestinationNodes(containerID: container.id)
                    }
                )
            )
            nodes.append(
                CommandNode(
                    id: "container-piano-roll-\(container.id.rawValue.uuidString)",
                    kind: .utility,
                    title: "Open MIDI Editor",
                    subtitle: "Edit notes for \(container.name)",
                    breadcrumbs: [song.name, track.name, container.name],
                    badges: ["MIDI"],
                    searchableText: ["midi", "piano roll", "notes"],
                    previewTarget: .container(trackID: track.id, containerID: container.id),
                    previewStyle: .pulse,
                    execute: { [executor] in executor.openPianoRoll(containerID: container.id) }
                )
            )
        }

        return nodes
    }

    private enum ContainerLifecyclePhase: String {
        case enter
        case exit

        var title: String {
            switch self {
            case .enter: return "Enter Actions"
            case .exit: return "Exit Actions"
            }
        }
    }

    private func containerLifecycleActionNodes(
        song: Song,
        track: Track,
        container: Container,
        phase: ContainerLifecyclePhase
    ) -> [CommandNode] {
        let actions = phase == .enter ? container.onEnterActions : container.onExitActions
        var nodes: [CommandNode] = [
            CommandNode(
                id: "container-\(phase.rawValue)-inspect-\(container.id.rawValue.uuidString)",
                kind: .utility,
                title: "Inspect Container",
                subtitle: "Manage \(phase.rawValue) actions in the inspector",
                breadcrumbs: [song.name, track.name, container.name, phase.title],
                badges: ["Container"],
                searchableText: ["inspect container", phase.rawValue, "actions"],
                previewTarget: .container(trackID: track.id, containerID: container.id),
                previewStyle: .pulse,
                execute: { [executor] in executor.inspectContainer(container.id) }
            ),
            CommandNode(
                id: "container-\(phase.rawValue)-add-trigger-\(container.id.rawValue.uuidString)",
                kind: .utility,
                title: "Add Trigger Action",
                subtitle: "Start, stop, or arm another container when this one \(phase == .enter ? "starts" : "ends")",
                breadcrumbs: [song.name, track.name, container.name, phase.title],
                badges: ["Trigger"],
                searchableText: ["add trigger action", phase.rawValue, "container action"],
                previewTarget: .container(trackID: track.id, containerID: container.id),
                previewStyle: .pulse,
                childrenProvider: {
                    self.containerTriggerTargetNodes(song: song, sourceTrack: track, sourceContainer: container, phase: phase)
                }
            ),
        ]

        nodes.append(contentsOf: actions.map { action in
            containerLifecycleActionNode(song: song, track: track, container: container, action: action, phase: phase)
        })

        return nodes
    }

    private func containerTriggerTargetNodes(
        song: Song,
        sourceTrack: Track,
        sourceContainer: Container,
        phase: ContainerLifecyclePhase
    ) -> [CommandNode] {
        song.tracks
            .flatMap { track in
                track.containers.filter { $0.id != sourceContainer.id }.map { container in
                    CommandNode(
                        id: "container-\(phase.rawValue)-trigger-target-\(sourceContainer.id.rawValue.uuidString)-\(container.id.rawValue.uuidString)",
                        kind: .container,
                        title: container.name,
                        subtitle: "\(track.name) · Bars \(formatBar(container.startBar))-\(formatBar(container.endBar))",
                        breadcrumbs: [song.name, sourceTrack.name, sourceContainer.name, phase.title, "Add Trigger Action"],
                        badges: ["Container"],
                        searchableText: ["trigger target", container.name, track.name, phase.rawValue],
                        previewTarget: .container(trackID: track.id, containerID: container.id),
                        previewStyle: .pulse,
                        childrenProvider: {
                            self.containerTriggerActionChoiceNodes(
                                song: song,
                                sourceTrack: sourceTrack,
                                sourceContainer: sourceContainer,
                                targetTrack: track,
                                targetContainer: container,
                                phase: phase
                            )
                        }
                    )
                }
            }
    }

    private func containerTriggerActionChoiceNodes(
        song: Song,
        sourceTrack: Track,
        sourceContainer: Container,
        targetTrack: Track,
        targetContainer: Container,
        phase: ContainerLifecyclePhase
    ) -> [CommandNode] {
        let triggerChoices: [(String, TriggerAction, String)] = [
            ("Start", .start, "Start \(targetContainer.name)"),
            ("Stop", .stop, "Stop \(targetContainer.name)"),
            ("Arm Record", .armRecord, "Arm \(targetContainer.name) for recording"),
            ("Disarm Record", .disarmRecord, "Disarm \(targetContainer.name)"),
        ]

        return triggerChoices.map { title, action, subtitle in
            CommandNode(
                id: "container-\(phase.rawValue)-trigger-action-\(sourceContainer.id.rawValue.uuidString)-\(targetContainer.id.rawValue.uuidString)-\(title)",
                kind: .utility,
                title: title,
                subtitle: subtitle,
                breadcrumbs: [song.name, sourceTrack.name, sourceContainer.name, phase.title, targetContainer.name],
                badges: ["Trigger"],
                searchableText: [title, subtitle, phase.rawValue, targetContainer.name, targetTrack.name],
                previewTarget: .container(trackID: targetTrack.id, containerID: targetContainer.id),
                previewStyle: .pulse,
                execute: { [executor] in
                    let containerAction = ContainerAction.makeTriggerContainer(targetID: targetContainer.id, action: action)
                    if phase == .enter {
                        executor.addContainerEnterAction(containerID: sourceContainer.id, action: containerAction)
                    } else {
                        executor.addContainerExitAction(containerID: sourceContainer.id, action: containerAction)
                    }
                }
            )
        }
    }

    private func containerLifecycleActionNode(
        song: Song,
        track: Track,
        container: Container,
        action: ContainerAction,
        phase: ContainerLifecyclePhase
    ) -> CommandNode {
        let descriptor = containerActionDescriptor(action, song: song)
        return CommandNode(
            id: "container-\(phase.rawValue)-action-\(action.id.rawValue.uuidString)",
            kind: .utility,
            title: descriptor.title,
            subtitle: descriptor.subtitle,
            breadcrumbs: [song.name, track.name, container.name, phase.title],
            badges: descriptor.badges,
            searchableText: descriptor.searchTerms,
            previewTarget: descriptor.previewTarget,
            previewStyle: descriptor.previewStyle,
            confirmation: CommandConfirmation(
                title: "Remove \(phase.rawValue) action?",
                message: "This removes the action from \(container.name)."
            ),
            execute: { [executor] in
                if phase == .enter {
                    executor.removeContainerEnterAction(containerID: container.id, actionID: action.id)
                } else {
                    executor.removeContainerExitAction(containerID: container.id, actionID: action.id)
                }
            }
        )
    }

    private func containerActionDescriptor(_ action: ContainerAction, song: Song) -> (
        title: String,
        subtitle: String,
        badges: [String],
        searchTerms: [String],
        previewTarget: PreviewTarget?,
        previewStyle: PreviewHighlightStyle
    ) {
        switch action {
        case .sendMIDI(_, let message, let destination):
            let title = midiActionSummary(message)
            let subtitle = midiDestinationSummary(destination, song: song)
            return (
                title,
                subtitle,
                ["MIDI", "Action"],
                [title, subtitle, "midi action"],
                nil,
                .focus
            )
        case .triggerContainer(_, let targetID, let triggerAction):
            if let target = locateContainer(targetID, in: song) {
                return (
                    triggerActionSummary(triggerAction),
                    "\(target.track.name) · \(target.container.name)",
                    ["Trigger", "Action"],
                    [triggerActionSummary(triggerAction), target.track.name, target.container.name, "trigger action"],
                    .container(trackID: target.track.id, containerID: target.container.id),
                    .pulse
                )
            }
            return (
                triggerActionSummary(triggerAction),
                "Unknown container",
                ["Trigger", "Action"],
                [triggerActionSummary(triggerAction), "trigger action"],
                nil,
                .focus
            )
        case .setParameter(_, let target, let value):
            return (
                "Set Parameter",
                "\(automationPathLabel(target)) → \(String(format: "%.2f", value))",
                ["Parameter", "Action"],
                ["set parameter", automationPathLabel(target), "\(value)"],
                locatePreviewTarget(for: target, song: song),
                .outline
            )
        }
    }

    private func midiActionSummary(_ message: MIDIActionMessage) -> String {
        switch message {
        case .programChange(let channel, let program):
            return "PC \(program) ch \(channel + 1)"
        case .controlChange(let channel, let controller, let value):
            return "CC \(controller) = \(value) ch \(channel + 1)"
        case .noteOn(let channel, let note, let velocity):
            return "Note On \(note) vel \(velocity) ch \(channel + 1)"
        case .noteOff(let channel, let note, _):
            return "Note Off \(note) ch \(channel + 1)"
        }
    }

    private func midiDestinationSummary(_ destination: MIDIDestination, song: Song) -> String {
        switch destination {
        case .externalPort(let name):
            return "Send to \(name)"
        case .internalTrack(let trackID):
            let trackName = song.tracks.first(where: { $0.id == trackID })?.name ?? "Unknown Track"
            return "Send to \(trackName)"
        }
    }

    private func triggerActionSummary(_ action: TriggerAction) -> String {
        switch action {
        case .start: return "Start"
        case .stop: return "Stop"
        case .armRecord: return "Arm Record"
        case .disarmRecord: return "Disarm Record"
        }
    }

    private func locateContainer(_ containerID: ID<Container>, in song: Song) -> (track: Track, container: Container)? {
        for track in song.tracks {
            if let container = track.containers.first(where: { $0.id == containerID }) {
                return (track, container)
            }
        }
        return nil
    }

    private func locatePreviewTarget(for path: EffectPath, song: Song) -> PreviewTarget? {
        if let containerID = path.containerID,
           let target = locateContainer(containerID, in: song) {
            if let lane = target.container.automationLanes.first(where: { $0.targetPath == path }) {
                return .automation(trackID: target.track.id, laneID: lane.id, targetPath: path)
            }
            return .container(trackID: target.track.id, containerID: target.container.id)
        }

        guard let track = song.tracks.first(where: { $0.id == path.trackID }) else { return nil }
        if let lane = track.trackAutomationLanes.first(where: { $0.targetPath == path }) {
            return .automation(trackID: track.id, laneID: lane.id, targetPath: path)
        }
        return .track(track.id)
    }

    private func pluginNodes() -> [CommandNode] {
        let effectNodes = audioUnitProvider.effects().map { info in
            pluginRootNode(info: info, isInstrument: false)
        }
        let instrumentNodes = audioUnitProvider.instruments().map { info in
            pluginRootNode(info: info, isInstrument: true)
        }
        return effectNodes + instrumentNodes
    }

    private func pluginRootNode(info: AudioUnitInfo, isInstrument: Bool) -> CommandNode {
        let kindLabel = isInstrument ? "Installed AU instrument" : "Installed AU effect"
        let addTrackTitle = isInstrument ? "Add \(info.name) to MIDI Track…" : "Add \(info.name) to Track…"
        let addContainerTitle = isInstrument ? "Add \(info.name) to MIDI Container…" : "Add \(info.name) to Container…"

        return CommandNode(
            id: "plugin-\(info.id)",
            kind: .plugin,
            title: info.name,
            subtitle: "Plugin · \(kindLabel)",
            breadcrumbs: [info.manufacturerName],
            badges: isInstrument ? ["Plugin", "Instrument"] : ["Plugin", "Effect"],
            searchableText: [
                info.name,
                info.manufacturerName,
                "plugin",
                isInstrument ? "instrument" : "effect",
                addTrackTitle,
                addContainerTitle,
                "see all instances"
            ],
            childrenProvider: {
                var children: [CommandNode] = []
                children.append(
                    CommandNode(
                        id: "plugin-add-track-\(info.id)",
                        kind: .pluginAction,
                        title: addTrackTitle,
                        subtitle: "Choose a destination track",
                        breadcrumbs: [info.name],
                        badges: ["Plugin"],
                        searchableText: ["add to track", info.name],
                        childrenProvider: {
                            self.destinationTrackNodes(for: info, isInstrument: isInstrument)
                        }
                    )
                )
                children.append(
                    CommandNode(
                        id: "plugin-add-container-\(info.id)",
                        kind: .pluginAction,
                        title: addContainerTitle,
                        subtitle: "Choose a destination container",
                        breadcrumbs: [info.name],
                        badges: ["Plugin"],
                        searchableText: ["add to container", info.name],
                        childrenProvider: {
                            self.destinationContainerNodes(for: info, isInstrument: isInstrument)
                        }
                    )
                )
                children.append(
                    CommandNode(
                        id: "plugin-see-instances-\(info.id)",
                        kind: .pluginAction,
                        title: "See All Instances",
                        subtitle: "Browse every \(info.name) instance",
                        breadcrumbs: [info.name],
                        badges: ["Plugin"],
                        searchableText: ["all instances", "where used"],
                        childrenProvider: {
                            self.pluginInstanceNodes(filterComponent: info.componentInfo)
                        }
                    )
                )
                return children
            }
        )
    }

    private func pluginInstanceNodes(
        filterComponent: AudioComponentInfo? = nil,
        filterTrackID: ID<Track>? = nil,
        filterContainerID: ID<Container>? = nil,
        filterHosts: Set<CommandPalettePluginHost>? = nil
    ) -> [CommandNode] {
        let instances = collectPluginInstances()
            .filter { instance in
                if let filterComponent, instance.component != filterComponent { return false }
                if let filterTrackID, instance.trackID != filterTrackID { return false }
                if let filterContainerID, instance.containerID != filterContainerID { return false }
                if let filterHosts, filterHosts.contains(instance.host) == false { return false }
                return true
            }
            .sorted(by: pluginInstanceSort(lhs:rhs:))

        return instances.map { reference in
            let context = pluginInstanceContext(reference)
            return CommandNode(
                id: "plugin-instance-\(reference.id)",
                kind: .pluginInstance,
                title: reference.displayName,
                subtitle: context.subtitle,
                breadcrumbs: context.breadcrumbs,
                badges: context.badges,
                searchableText: context.searchTerms,
                previewTarget: .pluginInstance(reference),
                childrenProvider: {
                    self.pluginInstanceActionNodes(reference: reference, context: context)
                }
            )
        }
    }

    private func pluginAutomationInstanceNodes(
        filterTrackID: ID<Track>? = nil,
        filterContainerID: ID<Container>? = nil,
        filterHosts: Set<CommandPalettePluginHost>? = nil
    ) -> [CommandNode] {
        let instances = collectPluginInstances()
            .filter { instance in
                if let filterTrackID, instance.trackID != filterTrackID { return false }
                if let filterContainerID, instance.containerID != filterContainerID { return false }
                if let filterHosts, filterHosts.contains(instance.host) == false { return false }
                return true
            }
            .sorted(by: pluginInstanceSort(lhs:rhs:))

        return instances.map { reference in
            let context = pluginInstanceContext(reference)
            return CommandNode(
                id: "plugin-automation-instance-\(reference.id)",
                kind: .pluginInstance,
                title: reference.displayName,
                subtitle: context.subtitle,
                breadcrumbs: context.breadcrumbs,
                badges: context.badges + ["Automation"],
                searchableText: context.searchTerms + ["automation", "parameter"],
                previewTarget: .pluginInstance(reference),
                childEntryBuilder: {
                    self.automationParameterEntry(reference: reference, context: context)
                }
            )
        }
    }

    private func pluginInstanceActionNodes(
        reference: CommandPalettePluginInstanceReference,
        context: PluginContext
    ) -> [CommandNode] {
        var nodes: [CommandNode] = [
            CommandNode(
                id: "plugin-instance-open-\(reference.id)",
                kind: .utility,
                title: "Open UI",
                subtitle: "Open \(reference.displayName)",
                breadcrumbs: context.breadcrumbs,
                badges: ["Plugin"],
                searchableText: ["open plugin", "ui"],
                previewTarget: .pluginInstance(reference),
                execute: { [executor] in executor.openPluginUI(reference) }
            ),
            CommandNode(
                id: "plugin-instance-reveal-\(reference.id)",
                kind: .utility,
                title: "Reveal Host",
                subtitle: context.subtitle,
                breadcrumbs: context.breadcrumbs,
                badges: context.badges,
                searchableText: ["reveal", "show host", "scroll into view", "find host"],
                previewTarget: .pluginInstance(reference),
                execute: { [executor] in executor.reveal(.pluginInstance(reference)) }
            ),
            CommandNode(
                id: "plugin-instance-inspect-\(reference.id)",
                kind: .utility,
                title: "Inspect Host",
                subtitle: "Show the owning host in the inspector",
                breadcrumbs: context.breadcrumbs,
                badges: context.badges,
                searchableText: ["inspect host"],
                previewTarget: .pluginInstance(reference),
                execute: { [executor] in
                    if let containerID = reference.containerID {
                        executor.inspectContainer(containerID)
                    } else {
                        executor.inspectTrack(reference.trackID)
                    }
                }
            ),
            CommandNode(
                id: "plugin-instance-automation-\(reference.id)",
                kind: .utility,
                title: "Add Automation",
                subtitle: "Select one or more parameters from \(reference.displayName)",
                breadcrumbs: context.breadcrumbs,
                badges: ["Automation"],
                searchableText: ["add automation", "parameter"],
                previewTarget: .pluginInstance(reference),
                childEntryBuilder: {
                    self.automationParameterEntry(reference: reference, context: context)
                }
            ),
        ]

        if reference.host == .trackEffect || reference.host == .containerEffect {
            nodes.append(
                CommandNode(
                    id: "plugin-instance-bypass-\(reference.id)",
                    kind: .utility,
                    title: "Toggle Bypass",
                    subtitle: "Enable or bypass \(reference.displayName)",
                    breadcrumbs: context.breadcrumbs,
                    badges: ["Plugin"],
                    searchableText: ["bypass", "enable plugin"],
                    previewTarget: .pluginInstance(reference),
                    execute: { [executor] in executor.togglePluginBypass(reference) }
                )
            )
        }

        let mappingExists = projectViewModel.project.midiParameterMappings.contains { $0.targetPath == reference.effectPath }
        nodes.append(
            CommandNode(
                id: "plugin-instance-midi-\(reference.id)",
                kind: .utility,
                title: mappingExists ? "Show MIDI Mapping" : "Start MIDI Learn",
                subtitle: mappingExists ? "Reveal MIDI mapping for this target" : "Map a MIDI control to this target",
                breadcrumbs: context.breadcrumbs,
                badges: ["MIDI"],
                searchableText: ["midi mapping", "midi learn"],
                previewTarget: .pluginInstance(reference),
                execute: { [executor] in
                    if mappingExists {
                        executor.inspectTrack(reference.trackID)
                    } else {
                        executor.startMIDILearn(path: reference.effectPath)
                    }
                }
            )
        )

        nodes.append(
            CommandNode(
                id: "plugin-instance-expression-\(reference.id)",
                kind: .utility,
                title: "Assign Expression Pedal",
                subtitle: "Choose a CC target for \(reference.displayName)",
                breadcrumbs: context.breadcrumbs,
                badges: ["Expression"],
                searchableText: ["expression pedal", "cc 11", "assign pedal"],
                previewTarget: .pluginInstance(reference),
                childrenProvider: {
                    self.expressionPedalNodes(trackID: reference.trackID, target: reference.effectPath)
                }
            )
        )

        nodes.append(
            CommandNode(
                id: "plugin-instance-delete-\(reference.id)",
                kind: .utility,
                title: "Delete Plugin",
                subtitle: "Remove \(reference.displayName)",
                breadcrumbs: context.breadcrumbs,
                badges: ["Delete", "Plugin"],
                searchableText: ["delete plugin", "remove plugin"],
                previewTarget: .pluginInstance(reference),
                confirmation: CommandConfirmation(
                    title: "Delete \(reference.displayName)?",
                    message: "This removes the plugin from its host."
                ),
                execute: { [executor] in executor.deletePlugin(reference) }
            )
        )

        return nodes
    }

    private func automationNodes() -> [CommandNode] {
        projectViewModel.project.songs.flatMap { song in
            song.tracks.flatMap { track in
                let trackLanes = track.trackAutomationLanes.map { lane in
                    automationNode(song: song, track: track, lane: lane, container: nil)
                }
                let containerLanes = track.containers.flatMap { container in
                    container.automationLanes.map { lane in
                        automationNode(song: song, track: track, lane: lane, container: container)
                    }
                }
                return trackLanes + containerLanes
            }
        }
    }

    private func automationNode(song: Song, track: Track, lane: AutomationLane, container: Container?) -> CommandNode {
        let title = lane.parameterName ?? lane.effectName ?? automationPathLabel(lane.targetPath)
        let subtitle: String
        var breadcrumbs = [song.name, track.name]
        if let container {
            breadcrumbs.append(container.name)
            subtitle = "Automation · Container lane"
        } else {
            subtitle = "Automation · Track lane"
        }
        let previewTarget = PreviewTarget.automation(trackID: track.id, laneID: lane.id, targetPath: lane.targetPath)

        return CommandNode(
            id: "automation-\(lane.id.rawValue.uuidString)",
            kind: .automation,
            title: title,
            subtitle: subtitle,
            breadcrumbs: breadcrumbs,
            badges: ["Automation", container == nil ? "Track" : "Container"],
            searchableText: [
                "automation",
                title,
                lane.effectName ?? "",
                lane.parameterName ?? "",
                track.name,
                container?.name ?? ""
            ],
            previewTarget: previewTarget,
            childrenProvider: {
                self.automationActionNodes(track: track, lane: lane, container: container)
            }
        )
    }

    private func automationActionNodes(track: Track, lane: AutomationLane, container: Container?) -> [CommandNode] {
        let previewTarget = PreviewTarget.automation(trackID: track.id, laneID: lane.id, targetPath: lane.targetPath)
        var nodes: [CommandNode] = [
            CommandNode(
                id: "automation-reveal-\(lane.id.rawValue.uuidString)",
                kind: .utility,
                title: "Reveal Lane",
                subtitle: lane.parameterName ?? automationPathLabel(lane.targetPath),
                breadcrumbs: [track.name],
                badges: ["Automation"],
                searchableText: ["reveal lane", "show automation", "scroll into view", "find automation"],
                previewTarget: previewTarget,
                execute: { [executor] in executor.reveal(previewTarget) }
            ),
            CommandNode(
                id: "automation-breakpoint-\(lane.id.rawValue.uuidString)",
                kind: .utility,
                title: "Add Breakpoint at Playhead",
                subtitle: "Insert a breakpoint at bar \(formatBar(timelineViewModel.playheadBar))",
                breadcrumbs: [track.name],
                badges: ["Automation"],
                searchableText: ["breakpoint", "playhead"],
                previewTarget: previewTarget,
                execute: { [executor] in executor.addAutomationBreakpoint(lane: lane) }
            ),
            CommandNode(
                id: "automation-delete-\(lane.id.rawValue.uuidString)",
                kind: .utility,
                title: "Delete Lane",
                subtitle: "Remove this automation lane",
                breadcrumbs: [track.name],
                badges: ["Automation", "Delete"],
                searchableText: ["delete lane", "remove automation"],
                previewTarget: previewTarget,
                confirmation: CommandConfirmation(
                    title: "Delete automation lane?",
                    message: "This removes all breakpoints in the lane."
                ),
                execute: { [executor] in executor.deleteAutomation(trackID: track.id, lane: lane) }
            ),
            CommandNode(
                id: "automation-midi-learn-\(lane.id.rawValue.uuidString)",
                kind: .utility,
                title: "MIDI Learn",
                subtitle: "Map a MIDI control to this lane target",
                breadcrumbs: [track.name],
                badges: ["MIDI"],
                searchableText: ["midi learn", "map midi"],
                previewTarget: previewTarget,
                execute: { [executor] in executor.startMIDILearn(path: lane.targetPath) }
            ),
        ]

        let mappingExists = projectViewModel.project.midiParameterMappings.contains { $0.targetPath == lane.targetPath }
        if mappingExists {
            nodes.append(
                CommandNode(
                    id: "automation-remove-mapping-\(lane.id.rawValue.uuidString)",
                    kind: .utility,
                    title: "Remove MIDI Mapping",
                    subtitle: "Detach mapped MIDI control",
                    breadcrumbs: [track.name],
                    badges: ["MIDI"],
                    searchableText: ["remove midi mapping", "unmap midi"],
                    previewTarget: previewTarget,
                    execute: { [executor] in executor.removeMIDIMapping(path: lane.targetPath) }
                )
            )
        }

        if container == nil {
            let hasExpression = track.expressionPedalTarget == lane.targetPath
            nodes.append(
                CommandNode(
                    id: "automation-expression-\(lane.id.rawValue.uuidString)",
                    kind: .utility,
                    title: hasExpression ? "Remove Expression Pedal" : "Assign Expression Pedal",
                    subtitle: hasExpression ? "Remove pedal mapping from this target" : "Choose a CC for this target",
                    breadcrumbs: [track.name],
                    badges: ["Expression"],
                    searchableText: ["expression pedal", "cc"],
                    previewTarget: previewTarget,
                    childrenProvider: hasExpression
                        ? nil
                        : { self.expressionPedalNodes(trackID: track.id, target: lane.targetPath) },
                    execute: hasExpression ? { [executor] in executor.removeExpressionPedal(trackID: track.id) } : nil
                )
            )
        }

        return nodes
    }

    private func destinationTrackNodes(for info: AudioUnitInfo, isInstrument: Bool) -> [CommandNode] {
        let currentSongTracks = projectViewModel.currentSong?.tracks ?? []
        let compatibleTracks = currentSongTracks.filter { track in
            if isInstrument {
                return track.kind == .midi
            }
            return track.kind != .master
        }
        let songName = projectViewModel.currentSong?.name ?? ""

        var nodes: [CommandNode] = []
        if isInstrument {
            nodes.append(
                CommandNode(
                    id: "dest-track-create-midi-\(info.id)",
                    kind: .destination,
                    title: "New MIDI Track",
                    subtitle: compatibleTracks.isEmpty
                        ? "Create a MIDI track and load \(info.name)"
                        : "Create another MIDI track with \(info.name)",
                    breadcrumbs: [songName, info.name],
                    badges: ["Track", "Create", "Instrument"],
                    searchableText: ["new midi track", "create midi track", info.name, "instrument"],
                    execute: { [executor] in
                        executor.createTrackAndSetInstrument(instrument: info)
                    }
                )
            )
        } else {
            nodes.append(
                CommandNode(
                    id: "dest-track-create-audio-\(info.id)",
                    kind: .destination,
                    title: "New Audio Track",
                    subtitle: "Create an audio track and add \(info.name)",
                    breadcrumbs: [songName, info.name],
                    badges: ["Track", "Create", "Effect"],
                    searchableText: ["new audio track", "create audio track", info.name, "effect"],
                    execute: { [executor] in
                        executor.createTrackAndAddEffect(kind: .audio, effect: info)
                    }
                )
            )
            nodes.append(
                CommandNode(
                    id: "dest-track-create-midi-\(info.id)",
                    kind: .destination,
                    title: "New MIDI Track",
                    subtitle: "Create a MIDI track and add \(info.name)",
                    breadcrumbs: [songName, info.name],
                    badges: ["Track", "Create", "Effect"],
                    searchableText: ["new midi track", "create midi track", info.name, "effect"],
                    execute: { [executor] in
                        executor.createTrackAndAddEffect(kind: .midi, effect: info)
                    }
                )
            )
        }

        nodes.append(contentsOf: compatibleTracks.map { track in
                CommandNode(
                    id: "dest-track-\(info.id)-\(track.id.rawValue.uuidString)",
                    kind: .destination,
                    title: track.name,
                    subtitle: "\(track.kind.displayName) Track",
                    breadcrumbs: [songName, info.name],
                    badges: ["Track"],
                    searchableText: [track.name, track.kind.displayName, info.name],
                    previewTarget: .track(track.id),
                    execute: { [executor] in
                        if isInstrument {
                            executor.setTrackInstrument(trackID: track.id, instrument: info)
                        } else {
                            executor.addTrackEffect(trackID: track.id, effect: info)
                        }
                    }
                )
            })

        return nodes
    }

    private func destinationContainerNodes(for info: AudioUnitInfo, isInstrument: Bool) -> [CommandNode] {
        guard let song = projectViewModel.currentSong else { return [] }
        let compatibleTracks = song.tracks.filter { track in
            if isInstrument {
                return track.kind == .midi
            }
            return track.kind != .master
        }

        let compatibleContainers = compatibleTracks.flatMap { track in
            track.containers.map { container in
                (track, container)
            }
        }

        var nodes: [CommandNode] = []
        if isInstrument {
            nodes.append(
                CommandNode(
                    id: "dest-container-create-midi-track-\(info.id)",
                    kind: .destination,
                    title: "New MIDI Track + Container",
                    subtitle: compatibleContainers.isEmpty
                        ? "Create a MIDI track, add a container, and load \(info.name)"
                        : "Create another MIDI container with \(info.name)",
                    breadcrumbs: [song.name, info.name],
                    badges: ["Container", "Create", "Instrument"],
                    searchableText: ["new midi container", "new midi track", "create container", info.name],
                    execute: { [executor] in
                        executor.createTrackWithContainerAndSetInstrument(instrument: info)
                    }
                )
            )
            nodes.append(contentsOf: compatibleTracks.map { track in
                CommandNode(
                    id: "dest-container-create-on-track-\(info.id)-\(track.id.rawValue.uuidString)",
                    kind: .destination,
                    title: "New Container on \(track.name)",
                    subtitle: "Create a MIDI container and load \(info.name)",
                    breadcrumbs: [song.name, info.name],
                    badges: ["Container", "Create", "Instrument"],
                    searchableText: ["new container", "create container", track.name, info.name],
                    previewTarget: .track(track.id),
                    execute: { [executor] in
                        executor.createContainerAndSetInstrument(trackID: track.id, instrument: info)
                    }
                )
            })
        } else {
            nodes.append(
                CommandNode(
                    id: "dest-container-create-audio-track-\(info.id)",
                    kind: .destination,
                    title: "New Audio Track + Container",
                    subtitle: "Create an audio track, add a container, and add \(info.name)",
                    breadcrumbs: [song.name, info.name],
                    badges: ["Container", "Create", "Effect"],
                    searchableText: ["new audio container", "new audio track", "create container", info.name],
                    execute: { [executor] in
                        executor.createTrackWithContainerAndAddEffect(kind: .audio, effect: info)
                    }
                )
            )
            nodes.append(
                CommandNode(
                    id: "dest-container-create-midi-track-\(info.id)",
                    kind: .destination,
                    title: "New MIDI Track + Container",
                    subtitle: "Create a MIDI track, add a container, and add \(info.name)",
                    breadcrumbs: [song.name, info.name],
                    badges: ["Container", "Create", "Effect"],
                    searchableText: ["new midi container", "new midi track", "create container", info.name],
                    execute: { [executor] in
                        executor.createTrackWithContainerAndAddEffect(kind: .midi, effect: info)
                    }
                )
            )
            nodes.append(contentsOf: compatibleTracks.map { track in
                CommandNode(
                    id: "dest-container-create-on-track-\(info.id)-\(track.id.rawValue.uuidString)",
                    kind: .destination,
                    title: "New Container on \(track.name)",
                    subtitle: "Create a container and add \(info.name)",
                    breadcrumbs: [song.name, info.name],
                    badges: ["Container", "Create", "Effect"],
                    searchableText: ["new container", "create container", track.name, info.name],
                    previewTarget: .track(track.id),
                    execute: { [executor] in
                        executor.createContainerAndAddEffect(trackID: track.id, effect: info)
                    }
                )
            })
        }

        nodes.append(contentsOf: compatibleContainers.map { track, container in
            CommandNode(
                    id: "dest-container-\(info.id)-\(container.id.rawValue.uuidString)",
                    kind: .destination,
                    title: container.name,
                    subtitle: "\(track.name) · Bars \(formatBar(container.startBar))-\(formatBar(container.endBar))",
                    breadcrumbs: [song.name, track.name, info.name],
                    badges: ["Container"],
                    searchableText: [container.name, track.name, info.name],
                    previewTarget: .container(trackID: track.id, containerID: container.id),
                    previewStyle: .pulse,
                    execute: { [executor] in
                        if isInstrument {
                            executor.setContainerInstrument(containerID: container.id, instrument: info)
                        } else {
                            executor.addContainerEffect(containerID: container.id, effect: info)
                        }
                    }
                )
        })

        return nodes
    }

    private func effectDestinationNodes(trackID: ID<Track>? = nil, containerID: ID<Container>? = nil) -> [CommandNode] {
        audioUnitProvider.effects().map { effect in
            CommandNode(
                id: "effect-choice-\(effect.id)-\(trackID?.rawValue.uuidString ?? containerID?.rawValue.uuidString ?? "none")",
                kind: .destination,
                title: effect.name,
                subtitle: effect.manufacturerName,
                badges: ["Effect"],
                searchableText: [effect.name, effect.manufacturerName, "effect", "plugin"],
                execute: { [executor] in
                    if let trackID {
                        executor.addTrackEffect(trackID: trackID, effect: effect)
                    } else if let containerID {
                        executor.addContainerEffect(containerID: containerID, effect: effect)
                    }
                }
            )
        }
    }

    private func instrumentDestinationNodes(trackID: ID<Track>? = nil, containerID: ID<Container>? = nil) -> [CommandNode] {
        audioUnitProvider.instruments().map { instrument in
            CommandNode(
                id: "instrument-choice-\(instrument.id)-\(trackID?.rawValue.uuidString ?? containerID?.rawValue.uuidString ?? "none")",
                kind: .destination,
                title: instrument.name,
                subtitle: instrument.manufacturerName,
                badges: ["Instrument"],
                searchableText: [instrument.name, instrument.manufacturerName, "instrument", "synth"],
                execute: { [executor] in
                    if let trackID {
                        executor.setTrackInstrument(trackID: trackID, instrument: instrument)
                    } else if let containerID {
                        executor.setContainerInstrument(containerID: containerID, instrument: instrument)
                    }
                }
            )
        }
    }

    private func expressionPedalNodes(trackID: ID<Track>, target: EffectPath?) -> [CommandNode] {
        let choices: [(String, UInt8)] = [
            ("CC #11 (Expression)", 11),
            ("CC #7 (Volume)", 7),
            ("CC #1 (Mod Wheel)", 1),
        ]
        return choices.map { label, cc in
            CommandNode(
                id: "expression-\(trackID.rawValue.uuidString)-\(cc)",
                kind: .destination,
                title: label,
                subtitle: "Assign to this target",
                badges: ["Expression"],
                searchableText: [label, "expression pedal", "cc \(cc)"],
                execute: { [executor] in executor.assignExpressionPedal(trackID: trackID, cc: cc, target: target) }
            )
        }
    }

    private func automationParameterEntry(
        reference: CommandPalettePluginInstanceReference,
        context: PluginContext
    ) -> CommandNodeChildEntry {
        return CommandNodeChildEntry(
            title: "Add Automation",
            breadcrumbTitle: "Parameters",
            nodesProvider: {
                self.automationParameterDefinitions(for: reference).map { $0.node }
            },
            multiSelection: CommandNodeMultiSelection(
                commitTitle: "Add Automation Lanes",
                helperText: "Press Space to select parameters, then Enter to add all selected lanes.",
                allowsSelection: { node in
                    self.automationParameterMap(for: reference)[node.id] != nil && !node.badges.contains("Existing")
                },
                commit: { [executor] nodes in
                    let parameterByID = self.automationParameterMap(for: reference)
                    let selectedParameters = nodes.compactMap { parameterByID[$0.id] }
                    executor.addAutomationLanes(for: reference, parameters: selectedParameters)
                }
            )
        )
    }

    private func automationParameterMap(
        for reference: CommandPalettePluginInstanceReference
    ) -> [String: LoopsEngine.AudioUnitParameterInfo] {
        automationParameterDefinitions(for: reference).reduce(into: [:]) { partialResult, entry in
            if let parameter = entry.parameter {
                partialResult[entry.node.id] = parameter
            }
        }
    }

    private func automationParameterDefinitions(
        for reference: CommandPalettePluginInstanceReference
    ) -> [(node: CommandNode, parameter: LoopsEngine.AudioUnitParameterInfo?)] {
        let context = pluginInstanceContext(reference)
        let breadcrumbs = context.breadcrumbs + [reference.displayName]
        let existingLanes = existingAutomationLanes(for: reference)
        let existingByAddress = Dictionary(uniqueKeysWithValues: existingLanes.map { ($0.targetPath.parameterAddress, $0) })

        if parameterCache.parameters(for: reference.component) == nil,
           let liveAudioUnit = liveAudioUnit(for: reference) {
            parameterCache.prime(
                component: reference.component,
                parameters: parameterInfos(from: liveAudioUnit)
            )
        }

        if let parameters = parameterCache.parameters(for: reference.component) {
            if parameters.isEmpty {
                return [
                    (
                        node: CommandNode(
                            id: "plugin-instance-automation-empty-\(reference.id)",
                            kind: .utility,
                            title: "No Automatable Parameters",
                            subtitle: "\(reference.displayName) does not expose automatable parameters",
                            breadcrumbs: breadcrumbs,
                            badges: ["Automation"]
                        ),
                        parameter: nil
                    )
                ]
            }

            let sorted = parameters.sorted { lhs, rhs in
                if lhs.groupName == rhs.groupName {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                if lhs.groupName.isEmpty { return false }
                if rhs.groupName.isEmpty { return true }
                return lhs.groupName.localizedCaseInsensitiveCompare(rhs.groupName) == .orderedAscending
            }

            return sorted.map { parameter in
                if let lane = existingByAddress[parameter.address] {
                    let previewTarget = PreviewTarget.automation(
                        trackID: reference.trackID,
                        laneID: lane.id,
                        targetPath: lane.targetPath
                    )
                    return (
                        node: CommandNode(
                            id: "plugin-instance-automation-parameter-\(reference.id)-\(parameter.address)",
                            kind: .automation,
                            title: parameter.displayName,
                            subtitle: parameterSubtitle(parameter, isExisting: true),
                            breadcrumbs: breadcrumbs,
                            badges: ["Automation", "Parameter", "Existing"],
                            searchableText: [
                                parameter.displayName,
                                parameter.groupName,
                                parameter.unit,
                                "existing automation",
                                reference.displayName,
                            ],
                            previewTarget: previewTarget,
                            execute: { [executor] in executor.reveal(previewTarget) }
                        ),
                        parameter: parameter
                    )
                }

                return (
                    node: CommandNode(
                        id: "plugin-instance-automation-parameter-\(reference.id)-\(parameter.address)",
                        kind: .automation,
                        title: parameter.displayName,
                        subtitle: parameterSubtitle(parameter, isExisting: false),
                        breadcrumbs: breadcrumbs,
                        badges: ["Automation", "Parameter"],
                        searchableText: [
                            parameter.displayName,
                            parameter.groupName,
                            parameter.unit,
                            "add automation",
                            reference.displayName,
                        ],
                        previewTarget: .pluginInstance(reference),
                        previewStyle: .outline
                    ),
                    parameter: parameter
                )
            }
        }

        parameterCache.ensureLoaded(component: reference.component)
        return [
            (
                node: CommandNode(
                    id: "plugin-instance-automation-loading-\(reference.id)",
                    kind: .utility,
                    title: "Loading Parameters…",
                    subtitle: "Reading automatable parameters from \(reference.displayName)",
                    breadcrumbs: breadcrumbs,
                    badges: ["Automation", "Loading"],
                    searchableText: ["loading parameters", reference.displayName],
                    previewTarget: .pluginInstance(reference)
                ),
                parameter: nil
            )
        ]
    }

    private func parameterSubtitle(_ parameter: LoopsEngine.AudioUnitParameterInfo, isExisting: Bool) -> String {
        var parts: [String] = []
        if !parameter.groupName.isEmpty {
            parts.append(parameter.groupName)
        }
        parts.append(String(format: "%.1f – %.1f", parameter.minValue, parameter.maxValue))
        if !parameter.unit.isEmpty {
            parts.append(parameter.unit)
        }
        if isExisting {
            parts.append("Automation exists")
        }
        return parts.joined(separator: " · ")
    }

    private func existingAutomationLanes(for reference: CommandPalettePluginInstanceReference) -> [AutomationLane] {
        if let containerID = reference.containerID,
           let container = projectViewModel.project.songs
            .flatMap(\.tracks)
            .flatMap(\.containers)
            .first(where: { $0.id == containerID }) {
            return container.automationLanes.filter { $0.targetPath.effectIndex == reference.effectIndex }
        }

        guard let track = projectViewModel.project.songs
            .flatMap(\.tracks)
            .first(where: { $0.id == reference.trackID }) else {
            return []
        }
        return track.trackAutomationLanes.filter { $0.targetPath.effectIndex == reference.effectIndex }
    }

    private func liveAudioUnit(for reference: CommandPalettePluginInstanceReference) -> AVAudioUnit? {
        guard let transportViewModel else { return nil }

        switch reference.host {
        case .trackEffect:
            return transportViewModel.liveTrackEffectUnit(trackID: reference.trackID, effectIndex: reference.effectIndex)
        case .containerEffect:
            guard let containerID = reference.containerID else { return nil }
            return transportViewModel.liveEffectUnit(containerID: containerID, effectIndex: reference.effectIndex)
        case .trackInstrument, .containerInstrument:
            return nil
        }
    }

    private func parameterInfos(from audioUnit: AVAudioUnit) -> [LoopsEngine.AudioUnitParameterInfo] {
        guard let tree = audioUnit.auAudioUnit.parameterTree else { return [] }
        let allParameters = tree.allParameters

        var addressToGroup: [AUParameterAddress: String] = [:]
        func walkGroups(_ group: AUParameterGroup) {
            for child in group.children {
                if let parameter = child as? AUParameter {
                    addressToGroup[parameter.address] = group.displayName
                } else if let subgroup = child as? AUParameterGroup {
                    walkGroups(subgroup)
                }
            }
        }

        for child in tree.children {
            if let group = child as? AUParameterGroup {
                walkGroups(group)
            }
        }

        return allParameters.map { parameter in
            LoopsEngine.AudioUnitParameterInfo(
                address: parameter.address,
                displayName: parameter.displayName,
                groupName: addressToGroup[parameter.address] ?? "",
                minValue: parameter.minValue,
                maxValue: parameter.maxValue,
                defaultValue: parameter.value,
                unit: parameter.unitName ?? ""
            )
        }
    }

    private func collectPluginInstances() -> [CommandPalettePluginInstanceReference] {
        var refs: [CommandPalettePluginInstanceReference] = []
        for song in projectViewModel.project.songs {
            for track in song.tracks {
                let sortedTrackEffects = track.insertEffects.sorted { $0.orderIndex < $1.orderIndex }
                for (index, effect) in sortedTrackEffects.enumerated() {
                    refs.append(
                        CommandPalettePluginInstanceReference(
                            host: .trackEffect,
                            trackID: track.id,
                            effectID: effect.id,
                            effectIndex: index,
                            component: effect.component,
                            displayName: effect.displayName
                        )
                    )
                }
                if track.kind == .midi, let instrument = track.instrumentComponent {
                    refs.append(
                        CommandPalettePluginInstanceReference(
                            host: .trackInstrument,
                            trackID: track.id,
                            effectIndex: EffectPath.instrumentParameterEffectIndex,
                            component: instrument,
                            displayName: "Instrument",
                            parameterEffectName: "Instrument"
                        )
                    )
                }

                for container in track.containers {
                    let sortedContainerEffects = container.insertEffects.sorted { $0.orderIndex < $1.orderIndex }
                    for (index, effect) in sortedContainerEffects.enumerated() {
                        refs.append(
                            CommandPalettePluginInstanceReference(
                                host: .containerEffect,
                                trackID: track.id,
                                containerID: container.id,
                                effectID: effect.id,
                                effectIndex: index,
                                component: effect.component,
                                displayName: effect.displayName
                            )
                        )
                    }
                    if track.kind == .midi, let instrument = container.instrumentOverride {
                        refs.append(
                            CommandPalettePluginInstanceReference(
                                host: .containerInstrument,
                                trackID: track.id,
                                containerID: container.id,
                                effectIndex: EffectPath.instrumentParameterEffectIndex,
                                component: instrument,
                                displayName: "Instrument Override",
                                parameterEffectName: "Instrument"
                            )
                        )
                    }
                }
            }
        }
        return refs
    }

    private func pluginInstanceSort(lhs: CommandPalettePluginInstanceReference, rhs: CommandPalettePluginInstanceReference) -> Bool {
        if lhs.host.sortRank != rhs.host.sortRank {
            return lhs.host.sortRank < rhs.host.sortRank
        }
        let lhsTrackOrder = trackOrderIndex(lhs.trackID)
        let rhsTrackOrder = trackOrderIndex(rhs.trackID)
        if lhsTrackOrder != rhsTrackOrder {
            return lhsTrackOrder < rhsTrackOrder
        }
        let lhsContainerStart = containerStartBar(lhs.containerID) ?? -1
        let rhsContainerStart = containerStartBar(rhs.containerID) ?? -1
        if lhsContainerStart != rhsContainerStart {
            return lhsContainerStart < rhsContainerStart
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private func trackOrderIndex(_ trackID: ID<Track>) -> Int {
        for song in projectViewModel.project.songs {
            if let index = song.tracks.firstIndex(where: { $0.id == trackID }) {
                return index
            }
        }
        return .max
    }

    private func containerStartBar(_ containerID: ID<Container>?) -> Double? {
        guard let containerID else { return nil }
        for song in projectViewModel.project.songs {
            for track in song.tracks {
                if let container = track.containers.first(where: { $0.id == containerID }) {
                    return container.startBar
                }
            }
        }
        return nil
    }

    private func pluginInstanceContext(_ reference: CommandPalettePluginInstanceReference) -> PluginContext {
        for song in projectViewModel.project.songs {
            if let track = song.tracks.first(where: { $0.id == reference.trackID }) {
                var breadcrumbs = [song.name, track.name]
                var subtitle = "\(reference.host.displayName) Host"
                var badges = ["Plugin", reference.host.displayName]
                if let containerID = reference.containerID,
                   let container = track.containers.first(where: { $0.id == containerID }) {
                    breadcrumbs.append(container.name)
                    subtitle = "\(reference.host.displayName) · Bars \(formatBar(container.startBar))-\(formatBar(container.endBar))"
                    badges.append("Container")
                } else {
                    badges.append("Track")
                }

                if let mapping = projectViewModel.midiParameterMapping(forTarget: reference.effectPath) {
                    badges.append("MIDI")
                    subtitle += " · \(mapping.trigger.displayString)"
                }

                let searchTerms = breadcrumbs + badges + [
                    reference.displayName,
                    reference.parameterEffectName,
                    subtitle,
                    reference.host.displayName
                ]
                return PluginContext(breadcrumbs: breadcrumbs, subtitle: subtitle, badges: badges, searchTerms: searchTerms)
            }
        }
        return PluginContext(
            breadcrumbs: [],
            subtitle: reference.host.displayName,
            badges: ["Plugin"],
            searchTerms: [reference.displayName, reference.host.displayName]
        )
    }

    private func trackBadges(for track: Track) -> [String] {
        var badges = [track.kind.displayName, "Track"]
        if track.isMuted { badges.append("Muted") }
        if track.isSoloed { badges.append("Solo") }
        if track.isRecordArmed { badges.append("Armed") }
        if track.kind == .midi { badges.append("MIDI") }
        if track.instrumentComponent != nil { badges.append("Instrument") }
        if !track.insertEffects.isEmpty { badges.append("Plugins") }
        return badges
    }

    private func containerBadges(for container: Container, track: Track) -> [String] {
        var badges = ["Container"]
        if track.kind == .midi { badges.append("MIDI") }
        if container.isClone { badges.append("Clone") }
        if container.instrumentOverride != nil { badges.append("Instrument") }
        if !container.insertEffects.isEmpty { badges.append("Plugins") }
        if !container.automationLanes.isEmpty { badges.append("Automation") }
        return badges
    }

    private func automationPathLabel(_ path: EffectPath) -> String {
        if path.isTrackVolume { return "Volume" }
        if path.isTrackPan { return "Pan" }
        if path.isTrackInstrumentParameter { return "Instrument" }
        return "FX \(path.effectIndex + 1)"
    }

    private func selectedTrackContext() -> (song: Song, track: Track)? {
        guard let selectedTrackID = projectViewModel.selectedTrackID else { return nil }
        for song in projectViewModel.project.songs {
            if let track = song.tracks.first(where: { $0.id == selectedTrackID }) {
                return (song, track)
            }
        }
        return nil
    }

    private func selectedContainerContext() -> (song: Song, track: Track, container: Container)? {
        guard let selectedContainerID = projectViewModel.selectedContainerID else { return nil }
        for song in projectViewModel.project.songs {
            for track in song.tracks {
                if let container = track.containers.first(where: { $0.id == selectedContainerID }) {
                    return (song, track, container)
                }
            }
        }
        return nil
    }
}

private struct PluginContext {
    let breadcrumbs: [String]
    let subtitle: String
    let badges: [String]
    let searchTerms: [String]
}

private func formatBar(_ value: Double) -> String {
    if value.rounded() == value {
        return String(Int(value))
    }
    return String(format: "%.2f", value)
}
