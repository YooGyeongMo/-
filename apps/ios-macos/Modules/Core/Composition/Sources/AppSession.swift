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

    private let signInUseCase: SignInUseCase
    private let restoreUseCase: RestoreSessionUseCase
    private let signOutUseCase: SignOutUseCase
    private let unauthorizedEvents: AsyncStream<Void>
    private let resetUnauthorized: @Sendable () async -> Void
    private var listener: Task<Void, Never>?

    public init(
        signIn: SignInUseCase,
        restore: RestoreSessionUseCase,
        signOut: SignOutUseCase,
        unauthorizedEvents: AsyncStream<Void> = AsyncStream { $0.finish() },
        resetUnauthorized: @escaping @Sendable () async -> Void = {}
    ) {
        signInUseCase = signIn
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
            signIn: SignInUseCase(codeProvider: AppleSignInCodeProvider(), repository: repository, tokenStore: tokenStore),
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

    @discardableResult
    public func signIn() -> Task<Void, Never> {
        Task {
            guard !isSigningIn else { return }
            isSigningIn = true
            defer { isSigningIn = false }
            do {
                let result = try await signInUseCase()
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
