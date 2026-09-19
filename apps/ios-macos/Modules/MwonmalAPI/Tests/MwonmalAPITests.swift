@testable import MwonmalAPI
import Testing

struct MwonmalAPIModuleTests {
    @Test func moduleName() {
        #expect(MwonmalAPIModule.name == "MwonmalAPI")
    }
}
