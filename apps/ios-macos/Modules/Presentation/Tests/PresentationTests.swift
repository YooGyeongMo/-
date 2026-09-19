@testable import Presentation
import Testing

struct PresentationModuleTests {
    @Test func moduleName() {
        #expect(PresentationModule.name == "Presentation")
    }
}
