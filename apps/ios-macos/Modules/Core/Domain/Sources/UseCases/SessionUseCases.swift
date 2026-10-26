/// 로그인: 제공자 code → 서버 교환 → 토큰 저장. 실패하면 아무것도 저장하지 않는다.
public struct SignInUseCase: Sendable {
    private let codeProvider: any OAuthCodeProviding
    private let repository: any AuthRepository
    private let tokenStore: any TokenStore

    public init(codeProvider: any OAuthCodeProviding, repository: any AuthRepository, tokenStore: any TokenStore) {
        self.codeProvider = codeProvider
        self.repository = repository
        self.tokenStore = tokenStore
    }

    public func callAsFunction() async throws -> SignInResult {
        let code = try await codeProvider.requestCode()
        let (token, result) = try await repository.signIn(with: code)
        try await tokenStore.save(token)
        return result
    }
}

/// 앱 시작: 저장된 토큰으로 내 정보를 확인한다.
/// - 토큰 없음 → signedOut
/// - 401 → 토큰을 지우고 signedOut
/// - 오프라인 등 → 토큰을 지우지 않고 unverified(다음 기회에 다시 확인)
public struct RestoreSessionUseCase: Sendable {
    private let repository: any AuthRepository
    private let tokenStore: any TokenStore

    public init(repository: any AuthRepository, tokenStore: any TokenStore) {
        self.repository = repository
        self.tokenStore = tokenStore
    }

    public func callAsFunction() async -> SessionState {
        guard await tokenStore.read() != nil else { return .signedOut }
        do {
            return try await .signedIn(repository.me())
        } catch DomainError.unauthorized {
            try? await tokenStore.clear()
            return .signedOut
        } catch {
            return .unverified
        }
    }
}

/// 로그아웃: v1.0은 토큰 삭제만(기기 해제·서버 토큰 폐기는 v1.1 계약).
public struct SignOutUseCase: Sendable {
    private let tokenStore: any TokenStore

    public init(tokenStore: any TokenStore) {
        self.tokenStore = tokenStore
    }

    public func callAsFunction() async throws {
        try await tokenStore.clear()
    }
}
