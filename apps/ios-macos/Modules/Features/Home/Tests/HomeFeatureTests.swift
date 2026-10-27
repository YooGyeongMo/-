import Domain
import DomainTesting
@testable import HomeFeature
import Testing

struct HomeFeatureModuleTests {
    @Test("모듈 이름") func moduleName() {
        #expect(HomeFeatureModule.name == "HomeFeature")
    }
}

@MainActor
struct HomeViewModelTests {
    static func upcoming(checked: Bool = false) -> UpcomingAction {
        UpcomingAction(
            action: ActionItem(
                id: 5001,
                sortOrder: 1,
                text: "역할 정리 문서 만들기",
                dueHint: nil,
                dueAt: nil,
                isChecked: checked,
                alertEnabled: true
            ),
            translationId: 1024, projectName: "루나", meetingTitle: nil, inputSource: nil, createdAt: .now
        )
    }

    @Test("불러오면 할 일과 전체 수") func load() async {
        let repo = FakeTranslationRepository()
        await repo.setActionsResult(.success(Page(items: [Self.upcoming()], page: 1, totalElements: 4, totalPages: 1)))
        let model = HomeViewModel(repository: repo)
        await model.load()
        #expect(model.actions.value?.count == 1)
        #expect(model.totalOpen == 4)
    }

    @Test("체크 실패하면 체크와 전체 수가 둘 다 원래대로") func toggleRollback() async {
        let repo = FakeTranslationRepository()
        await repo.setActionsResult(.success(Page(items: [Self.upcoming()], page: 1, totalElements: 4, totalPages: 1)))
        await repo.setSetActionResult(.failure(.offline))
        let model = HomeViewModel(repository: repo)
        await model.load()
        await model.toggle(Self.upcoming())
        #expect(model.actions.value?.first?.action.isChecked == false)
        #expect(model.totalOpen == 4)
        #expect(model.notice != nil)
    }

    @Test("체크 성공하면 남은 수가 하나 준다") func toggleSuccess() async {
        let repo = FakeTranslationRepository()
        await repo.setActionsResult(.success(Page(items: [Self.upcoming()], page: 1, totalElements: 4, totalPages: 1)))
        let model = HomeViewModel(repository: repo)
        await model.load()
        await model.toggle(Self.upcoming())
        #expect(model.actions.value?.first?.action.isChecked == true)
        #expect(model.totalOpen == 3)
    }

    @Test("판교 등급: 코드 우선, 없으면 점수", arguments: [
        (nil as String?, 0, 1), (nil, 25, 2), ("SETTLER", 0, 3), (nil, 100, 5),
    ])
    func level(code: String?, score: Int, number: Int) {
        #expect(PangyoLevel.of(code: code, score: score).number == number)
    }
}
