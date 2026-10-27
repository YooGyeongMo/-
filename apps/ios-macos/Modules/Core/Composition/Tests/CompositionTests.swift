@testable import Composition
import Domain
import DomainTesting
import Testing

@MainActor
struct AppSessionTests {
    private func session(repo: FakeAuthRepository = FakeAuthRepository(), store: InMemoryTokenStore = InMemoryTokenStore()) -> AppSession {
        AppSession(
            makeSignIn: { SignInUseCase(codeProvider: $0, repository: repo, tokenStore: store) },
            restore: RestoreSessionUseCase(repository: repo, tokenStore: store),
            signOut: SignOutUseCase(tokenStore: store)
        )
    }

    @Test("모듈 이름") func moduleName() {
        #expect(CompositionModule.name == "Composition")
    }

    @Test("버튼이 준 code로 로그인하면 signedIn, 서버에 그 code가 간다") func signInWithButtonCode() async {
        let repo = FakeAuthRepository()
        let store = InMemoryTokenStore()
        let app = session(repo: repo, store: store)
        await app.signIn(withAppleCode: "button-code").value
        #expect(app.state == .signedIn(.sample))
        #expect(await repo.signInCodes.map(\.code) == ["button-code"])
        #expect(await store.token == "server-token")
        #expect(app.lastError == nil)
    }

    @Test("서버 거절이면 오류 문구를 남기고 로그인 화면 유지") func serverRejection() async {
        let repo = FakeAuthRepository(signIn: .failure(.signInFailed(message: "로그인에 실패했어요. 다시 시도해 주세요.")))
        let app = session(repo: repo)
        await app.start().value
        await app.signIn(withAppleCode: "c").value
        #expect(app.state == .signedOut)
        #expect(app.lastError == .signInFailed(message: "로그인에 실패했어요. 다시 시도해 주세요."))
    }

    @Test("토큰이 없으면 시작 시 signedOut") func startSignedOut() async {
        let app = session()
        await app.start().value
        #expect(app.state == .signedOut)
    }

    @Test("로그아웃하면 토큰을 지우고 signedOut") func signOutClears() async {
        let store = InMemoryTokenStore(token: "t")
        let app = session(store: store)
        await app.signOut().value
        #expect(app.state == .signedOut)
        #expect(await store.token == nil)
    }

    @Test("직접 로그아웃은 세션 만료 문구를 남기지 않고 AI 동의를 끈다") func signOutClearsErrorAndConsent() async {
        let consent = InMemoryAIConsentStore(granted: true)
        let store = InMemoryTokenStore(token: "t")
        let repo = FakeAuthRepository()
        let app = AppSession(
            makeSignIn: { SignInUseCase(codeProvider: $0, repository: repo, tokenStore: store) },
            restore: RestoreSessionUseCase(repository: repo, tokenStore: store),
            signOut: SignOutUseCase(tokenStore: store),
            consent: consent
        )
        await app.start().value
        await app.signOut().value
        #expect(app.state == .signedOut)
        #expect(app.lastError == nil)
        #expect(await consent.granted == false)
    }

    @Test("401 신호면 로그아웃 + 만료 안내 + AI 동의 끔(#25)") func unauthorizedClearsConsent() async throws {
        let consent = InMemoryAIConsentStore(granted: true)
        let store = InMemoryTokenStore(token: "t")
        let repo = FakeAuthRepository()
        let (events, continuation) = AsyncStream.makeStream(of: Void.self)
        let app = AppSession(
            makeSignIn: { SignInUseCase(codeProvider: $0, repository: repo, tokenStore: store) },
            restore: RestoreSessionUseCase(repository: repo, tokenStore: store),
            signOut: SignOutUseCase(tokenStore: store),
            unauthorizedEvents: events,
            consent: consent
        )
        await app.start().value
        #expect(app.state == .signedIn(.sample))
        continuation.yield()
        for _ in 0 ..< 50 where app.state != .signedOut {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(app.state == .signedOut)
        #expect(app.lastError == .unauthorized)
        #expect(await consent.granted == false)
    }
}
