@testable import SettingsFeature
import Testing

struct SettingsFeatureModuleTests {
    @Test("모듈 이름") func moduleName() {
        #expect(SettingsFeatureModule.name == "SettingsFeature")
    }
}
