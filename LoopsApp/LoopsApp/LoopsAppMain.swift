import SwiftUI
import LoopsApp

@main
struct LoopsMainApp: App {
    var body: some Scene {
        WindowGroup {
            LoopsRootView()
        }
        .defaultSize(width: 1200, height: 700)

        Settings {
            Text("Settings")
                .frame(width: 400, height: 300)
        }
    }
}
