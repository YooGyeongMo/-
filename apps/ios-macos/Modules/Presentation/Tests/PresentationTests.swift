import Testing
@testable import Presentation

@Suite struct PresentationModuleTests {
    @Test func moduleName() {
        #expect(PresentationModule.name == "Presentation")
    }
}
