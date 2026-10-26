/// 제공자 인증 화면을 띄워 code를 받는다. Platform이 구현한다(Apple: AuthenticationServices).
public protocol OAuthCodeProviding: Sendable {
    var provider: OAuthProvider { get }
    /// 사용자가 닫으면 `DomainError.cancelled`.
    func requestCode() async throws -> OAuthCode
}

/// 우리 서버 토큰 보관소. Platform은 Keychain, 테스트는 메모리(D-11).
public protocol TokenStore: Sendable {
    func read() async -> String?
    func save(_ token: String) async throws
    func clear() async throws
}
