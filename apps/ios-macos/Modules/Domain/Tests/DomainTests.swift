import Testing
@testable import Domain

@Suite struct DomainModuleTests {
    @Test func moduleName() {
        #expect(DomainModule.name == "Domain")
    }
}
