@testable import DomainTesting
import Testing

struct DomainTestingModuleTests {
    @Test("디버그 빌드에서 모듈이 보인다") func visibleInDebug() {
        #expect(DomainTestingModule.name == "DomainTesting")
        #expect(DomainTestingModule.domain == "Domain")
    }
}
