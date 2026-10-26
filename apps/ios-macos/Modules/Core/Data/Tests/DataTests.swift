@testable import Data
import Testing

struct DataModuleTests {
    @Test func moduleName() {
        #expect(DataModule.name == "Data")
    }

    @Test("생성 클라이언트 모듈이 링크된다") func linksGeneratedClient() {
        #expect(DataModule.apiModuleName == "MwonmalAPI")
    }
}
