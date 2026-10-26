@testable import AuthFeature
import Testing

struct AuthFeatureModuleTests {
    @Test("모듈 이름") func moduleName() {
        #expect(AuthFeatureModule.name == "AuthFeature")
    }
}
