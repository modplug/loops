import Testing
@testable import LoopsCore

@Suite("LoopsCore Module Tests")
struct LoopsCoreModuleTests {
    @Test("Module version is set")
    func moduleVersion() {
        #expect(loopsCoreVersion == "0.1.0")
    }
}
