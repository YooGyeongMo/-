import Testing
@testable import Platform

@Suite struct PlatformModuleTests {
    @Test func moduleName() {
        #expect(PlatformModule.name == "Platform")
    }
}
