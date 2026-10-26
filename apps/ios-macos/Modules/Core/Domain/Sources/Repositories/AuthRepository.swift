/// 로그인·내 정보. 구현은 Data(RemoteAuthRepository), 테스트는 DomainTesting Fake.
public protocol AuthRepository: Sendable {
    /// `POST /api/auth/oauth/{provider}` → 서버 토큰 + 사용자.
    func signIn(with code: OAuthCode) async throws -> (accessToken: String, result: SignInResult)
    /// `GET /api/users/me`
    func me() async throws -> UserProfile
}
