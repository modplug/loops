import SwiftUI
import AppKit
import LoopsApp
import LoopsEngine

@main
struct LoopsMainApp: App {
    @State private var viewModel = ProjectViewModel()
    @State private var engineManager = AudioEngineManager()
    @State private var transportManager = TransportManager()
    @State private var transportViewModel: TransportViewModel?
    @State private var settingsViewModel: SettingsViewModel?
    @State private var shortcutManager = ShortcutManager()

    init() {
        // SPM executables don't have a proper .app bundle, so macOS
        // won't activate the menu bar by default. Setting the policy
        // to .regular makes it behave like a normal app.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            if let transportVM = transportViewModel {
                LoopsRootView(
                    viewModel: viewModel,
                    transportViewModel: transportVM,
                    shortcutManager: shortcutManager,
                    engineManager: engineManager,
                    settingsViewModel: settingsViewModel
                )
            } else {
                Text("Loading...")
                    .frame(minWidth: 800, minHeight: 500)
                    .onAppear { initialize() }
            }
        }
        .defaultSize(width: 1200, height: 700)
        .commands {
            ProjectCommands(viewModel: viewModel, shortcutManager: shortcutManager)
            CreateCommands(viewModel: viewModel, shortcutManager: shortcutManager)
            EditCommands(viewModel: viewModel, shortcutManager: shortcutManager)
            NavigationCommands(shortcutManager: shortcutManager)
            ViewCommands(shortcutManager: shortcutManager)
            AppPreferencesCommands(shortcutManager: shortcutManager)
        }

        Settings {
            if let settingsVM = settingsViewModel {
                AudioDeviceView(viewModel: settingsVM, shortcutManager: shortcutManager)
            } else {
                Text("Loading settings...")
                    .frame(width: 400, height: 300)
                    .onAppear { initialize() }
            }
        }
    }

    private func initialize() {
        // Audio engine start is deferred — it will start when
        // the user first plays or records. Starting at launch can
        // crash with an unrecoverable ObjC exception if the process
        // lacks audio entitlements (e.g. SPM executable without codesigning).
        if settingsViewModel == nil {
            settingsViewModel = SettingsViewModel(engineManager: engineManager)
        }
        if transportViewModel == nil {
            transportViewModel = TransportViewModel(transport: transportManager, engineManager: engineManager)
        }
    }
}
