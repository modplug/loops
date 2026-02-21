import SwiftUI
import LoopsApp
import LoopsEngine

@main
struct LoopsMainApp: App {
    @State private var viewModel = ProjectViewModel()
    @State private var engineManager = AudioEngineManager()
    @State private var transportManager = TransportManager()
    @State private var transportViewModel: TransportViewModel?
    @State private var settingsViewModel: SettingsViewModel?

    var body: some Scene {
        WindowGroup {
            if let transportVM = transportViewModel {
                LoopsRootView(viewModel: viewModel, transportViewModel: transportVM)
            } else {
                Text("Loading...")
                    .frame(minWidth: 800, minHeight: 500)
                    .onAppear { initialize() }
            }
        }
        .defaultSize(width: 1200, height: 700)
        .commands {
            ProjectCommands(viewModel: viewModel)
            EditCommands(viewModel: viewModel)
        }

        Settings {
            if let settingsVM = settingsViewModel {
                AudioDeviceView(viewModel: settingsVM)
            } else {
                Text("Loading settings...")
                    .frame(width: 400, height: 300)
                    .onAppear { initialize() }
            }
        }
    }

    private func initialize() {
        do {
            try engineManager.start()
        } catch {
            // Engine start failure is non-fatal at launch
        }
        if settingsViewModel == nil {
            settingsViewModel = SettingsViewModel(engineManager: engineManager)
        }
        if transportViewModel == nil {
            transportViewModel = TransportViewModel(transport: transportManager)
        }
    }
}
