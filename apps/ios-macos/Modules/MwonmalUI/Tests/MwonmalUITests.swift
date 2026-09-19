import Testing
@testable import MwonmalUI

@Suite struct MwonmalUIModuleTests {
    @Test func moduleName() {
        #expect(MwonmalUIModule.name == "MwonmalUI")
    }
}
