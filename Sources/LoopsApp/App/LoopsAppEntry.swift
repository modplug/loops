import SwiftUI
import LoopsCore
import LoopsEngine

/// The root view of the Loops application.
public struct LoopsRootView: View {
    @Bindable var viewModel: ProjectViewModel
    @Bindable var transportViewModel: TransportViewModel
    @State private var timelineViewModel = TimelineViewModel()
    @State private var setlistViewModel: SetlistViewModel?

    public init(viewModel: ProjectViewModel, transportViewModel: TransportViewModel) {
        self.viewModel = viewModel
        self.transportViewModel = transportViewModel
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ToolbarView(viewModel: transportViewModel)
                Divider()
                MainContentView(
                    projectViewModel: viewModel,
                    timelineViewModel: timelineViewModel,
                    setlistViewModel: setlistViewModel
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
