import Testing
@testable import MwonmalAPI

@Suite struct MwonmalAPIModuleTests {
    @Test func moduleName() {
        #expect(MwonmalAPIModule.name == "MwonmalAPI")
    }
}
