import Testing
@testable import Data

@Suite struct DataModuleTests {
    @Test func moduleName() {
        #expect(DataModule.name == "Data")
    }
}
