import Testing
@testable import Composition

@Suite struct CompositionModuleTests {
    @Test func moduleName() {
        #expect(CompositionModule.name == "Composition")
    }
}
