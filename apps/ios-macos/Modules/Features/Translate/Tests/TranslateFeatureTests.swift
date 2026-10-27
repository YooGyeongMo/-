import Domain
import DomainTesting
import MwonmalUI
import Testing
@testable import TranslateFeature

struct TranslateFeatureModuleTests {
    @Test("모듈 이름") func moduleName() {
        #expect(TranslateFeatureModule.name == "TranslateFeature")
    }
}

@MainActor
struct ComposeViewModelTests {
    private func model(_ repo: FakeTranslationRepository = FakeTranslationRepository(), consent: Bool = false) -> ComposeViewModel {
        ComposeViewModel(dependencies: TranslateDependencies(repository: repo, consent: InMemoryAIConsentStore(granted: consent)))
    }

    @Test("빈 칸·공백만이면 보낼 수 없다") func emptyCannotSubmit() {
        let compose = model()
        compose.text = "  \n "
        #expect(compose.canSubmit == false)
    }

    @Test("500자(스칼라) 넘으면 보낼 수 없다") func tooLong() {
        let compose = model()
        compose.text = String(repeating: "가", count: 501)
        #expect(compose.canSubmit == false)
        compose.text = String(repeating: "가", count: 500)
        #expect(compose.canSubmit)
    }

    @Test("동의 상태가 저장소까지 간다") func consentPassedThrough() async {
        let repo = FakeTranslationRepository()
        let compose = model(repo, consent: true)
        compose.text = "얼라인 부탁"
        _ = await compose.submit()
        #expect(await repo.translateCalls.map(\.consent) == [true])
    }

    @Test("503 이면 바쁨 + 초") func busy() async {
        let repo = FakeTranslationRepository()
        await repo.setTranslateResult(.failure(.aiUnavailable(retryAfter: 5, message: nil)))
        let compose = model(repo)
        compose.text = "얼라인"
        #expect(await compose.submit() == nil)
        #expect(compose.state == .failed(.busy(seconds: 5)))
    }

    @Test("해석 중에 다시 눌러도 요청은 하나") func doubleSubmit() async {
        let repo = FakeTranslationRepository()
        await repo.setTranslateDelay(.milliseconds(200))
        let compose = model(repo)
        compose.text = "얼라인"
        async let first = compose.submit()
        try? await Task.sleep(for: .milliseconds(20))
        let second = await compose.submit()
        let firstResult = await first
        #expect(second == nil)
        #expect(firstResult != nil)
        #expect(await repo.translateCalls.count == 1)
    }

    @Test("취소하면 편집 상태로") func cancel() async {
        let repo = FakeTranslationRepository()
        await repo.setTranslateDelay(.seconds(5))
        let compose = model(repo)
        compose.text = "얼라인"
        let task = Task { await compose.submit() }
        try? await Task.sleep(for: .milliseconds(30))
        compose.cancel()
        _ = await task.value
        #expect(compose.state == .editing)
    }
}

struct JargonTextTests {
    @Test("스칼라 위치로 형광펜·링크, 겹치거나 넘치는 범위는 건너뜀") func attributed() {
        let text = "👍 얼라인 R&R"
        let highlights = [
            JargonText.Highlight(start: 2, end: 5, termId: 3, meaning: "얼라인"),
            JargonText.Highlight(start: 4, end: 7, termId: 9, meaning: "겹침"),
            JargonText.Highlight(start: 6, end: 9, termId: nil, meaning: "R&R"),
            JargonText.Highlight(start: 8, end: 99, termId: 1, meaning: "넘침"),
        ]
        let result = JargonText.attributed(text, highlights)
        let linked = result.runs.compactMap { run in run.link.map { (String(result[run.range].characters), $0) } }
        #expect(linked.map(\.0) == ["얼라인"])
        #expect(linked.first?.1.absoluteString == "mw-term://3")
        let lit = result.runs.filter { $0.backgroundColor != nil }.map { String(result[$0.range].characters) }
        #expect(lit == ["얼라인", "R&R"])
    }
}
