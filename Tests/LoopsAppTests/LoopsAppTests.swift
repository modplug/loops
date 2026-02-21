import Testing
@testable import LoopsApp

@Suite("LoopsApp Module Tests")
struct LoopsAppModuleTests {
    @Test("LoopsRootView can be created")
    @MainActor
    func rootViewCreation() {
        let viewModel = ProjectViewModel()
        let _ = LoopsRootView(viewModel: viewModel)
    }
}
