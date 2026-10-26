@testable import Composition
import Testing

struct CompositionModuleTests {
    @Test func moduleName() {
        #expect(CompositionModule.name == "Composition")
    }
}
