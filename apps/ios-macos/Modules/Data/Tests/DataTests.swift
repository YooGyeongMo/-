@testable import Data
import Testing

struct DataModuleTests {
    @Test func moduleName() {
        #expect(DataModule.name == "Data")
    }
}
