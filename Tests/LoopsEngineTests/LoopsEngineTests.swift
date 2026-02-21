import Testing
@testable import LoopsEngine

@Suite("LoopsEngine Module Tests")
struct LoopsEngineModuleTests {
    @Test("Module version matches core")
    func moduleVersion() {
        #expect(LoopsEngine.version == "0.1.0")
    }
}
