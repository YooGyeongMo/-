@testable import FeatureKit
import Observation
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

@MainActor
struct ViewModelStateTests {
    @Observable final class Counter {
        nonisolated(unsafe) static var made = 0
        var text = ""
        init() {
            Self.made += 1
        }
    }

    @Test("만드는 식은 처음 읽을 때 한 번만 돈다(@State 초기화 함정)") func makesOnce() {
        Counter.made = 0
        let state = ViewModelState(wrappedValue: Counter())
        #expect(Counter.made == 0) // 만들기만 하고 읽지 않으면 0
        let first = state.wrappedValue
        let second = state.wrappedValue
        #expect(first === second)
        #expect(Counter.made == 1)
    }

    @Test("$model 바인딩이 같은 모델을 바꾼다") func bindable() {
        let state = ViewModelState(wrappedValue: Counter())
        state.projectedValue.text.wrappedValue = "a"
        #expect(state.wrappedValue.text == "a")
    }
}
