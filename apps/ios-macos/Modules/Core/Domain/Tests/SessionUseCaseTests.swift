@testable import Domain
import Testing

/// DomainTests는 DomainTesting에 기대지 않는다(Domain이 가장 아래). 여기서만 쓰는 작은 Fake를 둔다.
private actor Store: TokenStore {
    var token: String?
    var failSave = false
    init(token: String? = nil, failSave: Bool = false) {
        self.token = token
        self.failSave = failSave
    }

    func read() async -> String? {
        token
    }

    func save(_ token: String) async throws {
        if failSave {
            throw DomainError.unknown
        }
        self.token = token
    }

    func clear() async throws {
        token = nil
    }
}

private struct Codes: OAuthCodeProviding {
    let provider: OAuthProvider = .apple
    let result: Result<OAuthCode, DomainError>
    func requestCode() async throws -> OAuthCode {
        try result.get()
    }
}

private actor Repo: AuthRepository {
    let signInResult: Result<(accessToken: String, result: SignInResult), DomainError>
    let meResult: Result<UserProfile, DomainError>
    private(set) var signInCalls = 0
    init(
        signIn: Result<(accessToken: String, result: SignInResult), DomainError> = .success(("tok", Repo.result)),
        profile: Result<UserProfile, DomainError> = .success(Repo.user)
    ) {
        signInResult = signIn
        meResult = profile
    }

    static let user = UserProfile(id: 1, nickname: "n", email: nil, jobGroup: nil)
    static let result = SignInResult(user: user, isNewUser: true, needsOnboarding: true)

    func signIn(with _: OAuthCode) async throws -> (accessToken: String, result: SignInResult) {
        signInCalls += 1
        return try signInResult.get()
    }

    func me() async throws -> UserProfile {
        try meResult.get()
    }
}

private let code = OAuthCode(provider: .apple, code: "c", redirectUri: "https://example.invalid/cb")

struct SignInUseCaseTests {
    @Test("성공하면 토큰을 저장하고 결과를 돌려준다") func savesTokenOnSuccess() async throws {
        let store = Store()
        let result = try await SignInUseCase(codeProvider: Codes(result: .success(code)), repository: Repo(), tokenStore: store)()
        #expect(result == Repo.result)
        #expect(await store.token == "tok")
    }

    @Test("사용자가 닫으면 서버를 부르지 않고 cancelled") func cancelSkipsServer() async {
        let repo = Repo()
        let store = Store()
        await #expect(throws: DomainError.cancelled) {
            try await SignInUseCase(codeProvider: Codes(result: .failure(.cancelled)), repository: repo, tokenStore: store)()
        }
        #expect(await repo.signInCalls == 0)
        #expect(await store.token == nil)
    }

    @Test("서버가 거절하면 토큰을 저장하지 않는다") func serverFailureSavesNothing() async {
        let store = Store()
        let repo = Repo(signIn: .failure(.signInFailed(message: "로그인에 실패했어요. 다시 시도해 주세요.")))
        await #expect(throws: DomainError.signInFailed(message: "로그인에 실패했어요. 다시 시도해 주세요.")) {
            try await SignInUseCase(codeProvider: Codes(result: .success(code)), repository: repo, tokenStore: store)()
        }
        #expect(await store.token == nil)
    }

    @Test("토큰 저장이 실패하면 로그인도 실패") func saveFailurePropagates() async {
        let store = Store(failSave: true)
        await #expect(throws: DomainError.self) {
            try await SignInUseCase(codeProvider: Codes(result: .success(code)), repository: Repo(), tokenStore: store)()
        }
    }
}

struct RestoreSessionUseCaseTests {
    @Test("토큰이 없으면 서버를 부르지 않고 signedOut") func noTokenSignedOut() async {
        #expect(await RestoreSessionUseCase(repository: Repo(profile: .failure(.unknown)), tokenStore: Store())() == .signedOut)
    }

    @Test("토큰이 유효하면 signedIn") func validTokenSignedIn() async {
        #expect(await RestoreSessionUseCase(repository: Repo(), tokenStore: Store(token: "t"))() == .signedIn(Repo.user))
    }

    @Test("401이면 토큰을 지우고 signedOut") func unauthorizedClearsToken() async {
        let store = Store(token: "t")
        #expect(await RestoreSessionUseCase(repository: Repo(profile: .failure(.unauthorized)), tokenStore: store)() == .signedOut)
        #expect(await store.token == nil)
    }

    @Test("오프라인이면 토큰을 지우지 않고 unverified") func offlineKeepsToken() async {
        let store = Store(token: "t")
        #expect(await RestoreSessionUseCase(repository: Repo(profile: .failure(.offline)), tokenStore: store)() == .unverified)
        #expect(await store.token == "t")
    }
}

struct SignOutUseCaseTests {
    @Test("로그아웃은 토큰을 지운다") func clearsToken() async throws {
        let store = Store(token: "t")
        try await SignOutUseCase(tokenStore: store)()
        #expect(await store.token == nil)
    }
}
