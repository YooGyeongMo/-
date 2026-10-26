@testable import Routing
import Testing

@MainActor
struct AppRouterTests {
    @Test("push는 선택된 탭의 경로에만 쌓인다") func pushAppendsToSelectedTab() {
        let router = AppRouter()
        router.push(.compose)
        router.push(.result(translationId: 7))
        #expect(router.path(for: .home) == [.compose, .result(translationId: 7)])
        #expect(router.path(for: .settings).isEmpty)
    }

    @Test("탭을 바꿔도 다른 탭의 경로는 보존된다") func tabSwitchPreservesPaths() {
        let router = AppRouter()
        router.push(.compose)
        router.select(.settings)
        router.select(.home)
        #expect(router.path(for: .home) == [.compose])
    }

    @Test("빈 경로에서 pop은 아무것도 안 한다") func popOnEmptyIsNoop() {
        let router = AppRouter()
        router.pop()
        #expect(router.path(for: .home).isEmpty)
    }

    @Test("popToRoot는 현재 탭만 비운다") func popToRootClearsCurrentTabOnly() {
        let router = AppRouter()
        router.select(.settings)
        router.push(.compose)
        router.select(.home)
        router.push(.result(translationId: 1))
        router.popToRoot()
        #expect(router.path(for: .home).isEmpty)
        #expect(router.path(for: .settings) == [.compose])
    }
}
