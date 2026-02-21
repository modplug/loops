import Testing
@testable import LoopsCore

@Suite("LoopsCore Module Tests")
struct LoopsCoreModuleTests {
    @Test("Module version is set")
    func moduleVersion() {
        #expect(LoopsCore.version == "0.1.0")
    }
}
