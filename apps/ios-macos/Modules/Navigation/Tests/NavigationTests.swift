import Testing
@testable import Navigation

@Suite struct NavigationModuleTests {
    @Test func moduleName() {
        #expect(NavigationModule.name == "Navigation")
    }
}
