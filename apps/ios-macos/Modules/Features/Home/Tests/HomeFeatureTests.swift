@testable import HomeFeature
import Testing

struct HomeFeatureModuleTests {
    @Test("모듈 이름") func moduleName() {
        #expect(HomeFeatureModule.name == "HomeFeature")
    }
}
