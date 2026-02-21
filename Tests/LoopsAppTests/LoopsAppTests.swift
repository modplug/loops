import Testing
@testable import LoopsApp
@testable import LoopsEngine

@Suite("LoopsApp Module Tests")
struct LoopsAppModuleTests {
    @Test("LoopsRootView can be created")
    @MainActor
    func rootViewCreation() {
        let viewModel = ProjectViewModel()
        let transport = TransportManager()
        let transportVM = TransportViewModel(transport: transport)
        let _ = LoopsRootView(viewModel: viewModel, transportViewModel: transportVM)
    }
}
