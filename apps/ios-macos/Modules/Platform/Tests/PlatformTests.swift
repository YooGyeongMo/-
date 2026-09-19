@testable import Platform
import Testing

struct PlatformModuleTests {
    @Test func moduleName() {
        #expect(PlatformModule.name == "Platform")
    }
}
