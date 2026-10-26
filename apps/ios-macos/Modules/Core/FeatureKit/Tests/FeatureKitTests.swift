@testable import FeatureKit
import Testing

struct PhaseTests {
    @Test("loaded만 값을 준다") func valueOnlyWhenLoaded() {
        #expect(Phase<Int>.loaded(3).value == 3)
        #expect(Phase<Int>.loading.value == nil)
        #expect(Phase<Int>.failed(code: "X").value == nil)
    }

    @Test("isLoading") func isLoadingOnlyForLoading() {
        #expect(Phase<Int>.loading.isLoading)
        #expect(!Phase<Int>.idle.isLoading)
    }
}
