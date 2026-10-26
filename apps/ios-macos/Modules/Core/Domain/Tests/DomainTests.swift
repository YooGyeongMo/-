@testable import Domain
import Testing

struct DomainModuleTests {
    @Test func moduleName() {
        #expect(DomainModule.name == "Domain")
    }
}
