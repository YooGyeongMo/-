@testable import Routing
import Testing

@MainActor
struct AppRouterTests {
    @Test("탭은 Figma 순서(홈·프로젝트·복습·MY)") func tabOrder() {
        #expect(AppTab.allCases == [.home, .project, .review, .my])
    }

    @Test("push는 선택된 탭의 경로에만 쌓인다") func pushAppendsToSelectedTab() {
        let router = AppRouter()
        router.push(.result(translationId: 7))
        #expect(router.path(for: .home) == [.result(translationId: 7)])
        #expect(router.path(for: .my).isEmpty)
    }

    @Test("탭을 바꿔도 다른 탭의 경로는 보존된다") func tabSwitchPreservesPaths() {
        let router = AppRouter()
        router.push(.result(translationId: 1))
        router.select(.my)
        router.select(.home)
        #expect(router.path(for: .home) == [.result(translationId: 1)])
    }

    @Test("빈 경로에서 pop은 아무것도 안 한다") func popOnEmptyIsNoop() {
        let router = AppRouter()
        router.pop()
        #expect(router.path(for: .home).isEmpty)
    }

    @Test("popToRoot는 현재 탭만 비운다") func popToRootClearsCurrentTabOnly() {
        let router = AppRouter()
        router.select(.my)
        router.push(.result(translationId: 2))
        router.select(.home)
        router.push(.result(translationId: 1))
        router.popToRoot()
        #expect(router.path(for: .home).isEmpty)
        #expect(router.path(for: .my) == [.result(translationId: 2)])
    }

    @Test("붙여넣기 → 결과는 같은 자리에서 바뀐다") func composeReplacedByResult() {
        let router = AppRouter()
        router.present(.compose)
        router.present(.result(translationId: 9))
        #expect(router.sheet == .result(translationId: 9))
        #expect(router.sheetOverSheet == nil)
    }

    @Test("용어 시트는 결과 시트 위에 뜨고, 닫으면 결과로 돌아간다") func termOverResult() {
        let router = AppRouter()
        router.present(.result(translationId: 9))
        router.present(.term(termId: 3))
        #expect(router.sheet == .result(translationId: 9))
        #expect(router.sheetOverSheet == .term(termId: 3))
        router.dismissSheet()
        #expect(router.sheetOverSheet == nil)
        #expect(router.sheet == .result(translationId: 9))
        router.dismissSheet()
        #expect(router.sheet == nil)
    }

    @Test("reset은 시트·경로·탭을 처음으로") func resetClearsAll() {
        let router = AppRouter()
        router.select(.project)
        router.push(.result(translationId: 1))
        router.present(.settings)
        router.reset()
        #expect(router.selectedTab == .home && router.sheet == nil && router.path(for: .project).isEmpty)
    }

    @Test("dataChanged는 버전을 올린다") func dataVersionBumps() {
        let router = AppRouter()
        router.dataChanged()
        router.dataChanged()
        #expect(router.dataVersion == 2)
    }
}
