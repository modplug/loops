import SwiftUI
import LoopsApp

@main
struct LoopsMainApp: App {
    @State private var viewModel = ProjectViewModel()

    var body: some Scene {
        WindowGroup {
            LoopsRootView(viewModel: viewModel)
        }
        .defaultSize(width: 1200, height: 700)
        .commands {
            ProjectCommands(viewModel: viewModel)
        }

        Settings {
            Text("Settings")
                .frame(width: 400, height: 300)
        }
    }
}
