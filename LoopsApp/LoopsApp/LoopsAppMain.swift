import SwiftUI
import LoopsApp
import LoopsEngine

@main
struct LoopsMainApp: App {
    @State private var viewModel = ProjectViewModel()
    @State private var engineManager = AudioEngineManager()
    @State private var settingsViewModel: SettingsViewModel?

    var body: some Scene {
        WindowGroup {
            LoopsRootView(viewModel: viewModel)
                .onAppear {
                    startEngine()
                }
        }
        .defaultSize(width: 1200, height: 700)
        .commands {
            ProjectCommands(viewModel: viewModel)
        }

        Settings {
            if let settingsVM = settingsViewModel {
                AudioDeviceView(viewModel: settingsVM)
            } else {
                Text("Loading settings...")
                    .frame(width: 400, height: 300)
                    .onAppear { initSettingsViewModel() }
            }
        }
    }

    private func startEngine() {
        do {
            try engineManager.start()
        } catch {
            // Engine start failure is non-fatal at launch;
            // user can fix via Settings > Audio Device
        }
        initSettingsViewModel()
    }

    private func initSettingsViewModel() {
        if settingsViewModel == nil {
            settingsViewModel = SettingsViewModel(engineManager: engineManager)
        }
    }
}
