@testable import Navigation
import Testing

struct NavigationModuleTests {
    @Test func moduleName() {
        #expect(NavigationModule.name == "Navigation")
    }
}
