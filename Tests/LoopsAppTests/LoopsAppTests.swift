import Testing
@testable import LoopsApp

@Suite("LoopsApp Module Tests")
struct LoopsAppModuleTests {
    @Test("LoopsRootView can be created")
    func rootViewCreation() {
        let _ = LoopsRootView()
    }
}
