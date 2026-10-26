import AuthenticationServices
import Domain

/// Sign in with Apple 네이티브 창을 띄워 authorization code를 받는다(ADR-0014).
/// 이메일·이름 범위는 요청하지 않는다: 서버는 id_token의 sub로 신원을 정하고, 없으면 `{sub}@apple.invalid`.
public struct AppleSignInCodeProvider: OAuthCodeProviding {
    /// 계약 v1.0 필수 필드. 네이티브 흐름이라 서버는 Apple에 보내지 않는다.
    public static let nativeRedirectURI = "https://api.mwonmalingyo.kr/auth/apple/native"

    public let provider: OAuthProvider = .apple

    public init() {}

    public func requestCode() async throws -> OAuthCode {
        let code = try await AppleAuthorizationRunner.run()
        return OAuthCode(provider: .apple, code: code, redirectUri: Self.nativeRedirectURI)
    }
}

/// ASAuthorizationController는 메인 스레드·델리게이트 기반이라 continuation으로 감싼다.
@MainActor
final class AppleAuthorizationRunner: NSObject {
    private var continuation: CheckedContinuation<String, any Error>?
    /// 컨트롤러가 끝날 때까지 자신을 붙잡아 둔다(델리게이트는 weak).
    private var retainSelf: AppleAuthorizationRunner?

    static func run() async throws -> String {
        let runner = AppleAuthorizationRunner()
        return try await runner.start()
    }

    private func start() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            retainSelf = self
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = []
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: ASAuthorizationControllerDelegate

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.authorizationCode,
              let code = String(data: data, encoding: .utf8), !code.isEmpty
        else {
            finish(.failure(DomainError.signInFailed(message: nil)))
            return
        }
        finish(.success(code))
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithError error: any Error) {
        finish(.failure(Self.map(error)))
    }

    nonisolated static func map(_ error: any Error) -> DomainError {
        guard let auth = error as? ASAuthorizationError else { return .signInFailed(message: nil) }
        switch auth.code {
        case .canceled: return .cancelled
        default: return .signInFailed(message: nil)
        }
    }

    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        Self.currentAnchor()
    }

    private func finish(_ result: Result<String, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
        retainSelf = nil
    }

    private static func currentAnchor() -> ASPresentationAnchor {
        #if os(iOS)
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            return active?.keyWindow ?? active?.windows.first ?? ASPresentationAnchor()
        #else
            return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        #endif
    }
}

extension AppleAuthorizationRunner: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {}
