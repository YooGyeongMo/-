import Data
import Domain
import Foundation
import Observation
import Platform

/// 앱 전체 세션 상태(창 수명). 구현체를 고르는 유일한 곳이 Composition이다(ADR-0016).
@MainActor @Observable
public final class AppSession {
    public private(set) var state: SessionState?
    public private(set) var lastError: DomainError?
    public private(set) var isSigningIn = false

    /// 받은 code(또는 제공자)로 로그인 UseCase를 만든다. S-01의 공식 Apple 버튼은 code를 직접 준다.
    private let makeSignIn: @Sendable (any OAuthCodeProviding) -> SignInUseCase
    private let restoreUseCase: RestoreSessionUseCase
    private let signOutUseCase: SignOutUseCase
    private let unauthorizedEvents: AsyncStream<Void>
    private let resetUnauthorized: @Sendable () async -> Void
    private var listener: Task<Void, Never>?

    public init(
        makeSignIn: @escaping @Sendable (any OAuthCodeProviding) -> SignInUseCase,
        restore: RestoreSessionUseCase,
        signOut: SignOutUseCase,
        unauthorizedEvents: AsyncStream<Void> = AsyncStream { $0.finish() },
        resetUnauthorized: @escaping @Sendable () async -> Void = {}
    ) {
        self.makeSignIn = makeSignIn
        restoreUseCase = restore
        signOutUseCase = signOut
        self.unauthorizedEvents = unauthorizedEvents
        self.resetUnauthorized = resetUnauthorized
    }

    /// 실제 서버·Keychain·Apple 로그인으로 조립한다.
    public static func live(bundle: Bundle = .main) -> AppSession {
        let tokenStore = KeychainTokenStore()
        let api = APIEnvironment(baseURL: APIConfiguration.baseURL(bundle: bundle), tokenStore: tokenStore)
        let repository = api.authRepository()
        return AppSession(
            makeSignIn: { SignInUseCase(codeProvider: $0, repository: repository, tokenStore: tokenStore) },
            restore: RestoreSessionUseCase(repository: repository, tokenStore: tokenStore),
            signOut: SignOutUseCase(tokenStore: tokenStore),
            unauthorizedEvents: api.unauthorizedEvents,
            resetUnauthorized: { await api.resetUnauthorized() }
        )
    }

    /// 앱 시작 시 한 번. 401 신호도 여기서부터 듣는다.
    @discardableResult
    public func start() -> Task<Void, Never> {
        listenForUnauthorized()
        return Task {
            state = await restoreUseCase()
        }
    }

    /// 공식 Apple 버튼이 준 결과로 로그인한다(S-01).
    @discardableResult
    public func signIn(withAppleCode code: String) -> Task<Void, Never> {
        signIn(using: ProvidedCode(code: OAuthCode(provider: .apple, code: code, redirectUri: AppleSignInCodeProvider.nativeRedirectURI)))
    }

    /// 버튼이 실패를 알렸을 때(사용자가 닫은 경우는 부르지 않는다).
    public func appleSignInFailed() {
        lastError = .signInFailed(message: nil)
    }

    /// 버튼 없이 Apple 창을 직접 띄운다(단축어·재로그인 등).
    @discardableResult
    public func signInWithApple() -> Task<Void, Never> {
        signIn(using: AppleSignInCodeProvider())
    }

    private func signIn(using provider: any OAuthCodeProviding) -> Task<Void, Never> {
        let useCase = makeSignIn(provider)
        return Task {
            guard !isSigningIn else { return }
            isSigningIn = true
            defer { isSigningIn = false }
            do {
                let result = try await useCase()
                lastError = nil
                state = .signedIn(result.user)
                await resetUnauthorized()
            } catch let error as DomainError {
                lastError = error == .cancelled ? nil : error
            } catch {
                lastError = .unknown
            }
        }
    }

    @discardableResult
    public func signOut() -> Task<Void, Never> {
        Task {
            try? await signOutUseCase()
            state = .signedOut
        }
    }

    private func listenForUnauthorized() {
        guard listener == nil else { return }
        let events = unauthorizedEvents
        listener = Task { [weak self] in
            for await _ in events {
                await self?.handleUnauthorized()
            }
        }
    }

    private func handleUnauthorized() async {
        try? await signOutUseCase()
        state = .signedOut
    }
}

/// 서버 주소. Info.plist `MWAPIBaseURL`(빌드 설정 `MW_API_BASE_URL`, Debug = 로컬 Caddy 8080).
enum APIConfiguration {
    static let fallback = URL(string: "https://api.mwonmalingyo.kr/api")!

    static func baseURL(bundle: Bundle) -> URL {
        guard let raw = bundle.object(forInfoDictionaryKey: "MWAPIBaseURL") as? String,
              let url = URL(string: raw), url.scheme != nil else { return fallback }
        return url
    }
}

/// 이미 받은 code를 그대로 돌려주는 제공자.
struct ProvidedCode: OAuthCodeProviding {
    let code: OAuthCode
    var provider: OAuthProvider {
        code.provider
    }

    func requestCode() async throws -> OAuthCode {
        code
    }
}
