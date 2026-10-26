import Testing
@testable import TranslateFeature

struct TranslateFeatureModuleTests {
    @Test("모듈 이름") func moduleName() {
        #expect(TranslateFeatureModule.name == "TranslateFeature")
    }
}
