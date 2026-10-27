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

    /// 해석·할 일·용어 서버 저장소와 AI 동의 저장소(기능 화면이 쓴다).
    public let translations: any TranslationRepository
    public let consent: any AIConsentStore
    private let refreshProfile: @Sendable () async throws -> UserProfile
    /// Debug 빌드 + 실행 인자 `-MWDevLogin <이름>`일 때만 있다(로컬 서버 E2E, ADR-0020).
    private let devCodeProvider: (any OAuthCodeProviding)?
    /// Debug + 실행 인자 `-MWResetSession`: 시작할 때 저장된 로그인을 지운다(E2E가 늘 로그인 화면에서 시작).
    var resetOnLaunch = false

    public init(
        makeSignIn: @escaping @Sendable (any OAuthCodeProviding) -> SignInUseCase,
        restore: RestoreSessionUseCase,
        signOut: SignOutUseCase,
        unauthorizedEvents: AsyncStream<Void> = AsyncStream { $0.finish() },
        resetUnauthorized: @escaping @Sendable () async -> Void = {},
        translations: any TranslationRepository = UnavailableTranslationRepository(),
        consent: any AIConsentStore = NoConsentStore(),
        refreshProfile: @escaping @Sendable () async throws -> UserProfile = { throw DomainError.unknown },
        devCodeProvider: (any OAuthCodeProviding)? = nil
    ) {
        self.translations = translations
        self.consent = consent
        self.refreshProfile = refreshProfile
        self.devCodeProvider = devCodeProvider
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
        var devLogin: (any OAuthCodeProviding)?
        #if DEBUG
            devLogin = DevCodeProvider.fromLaunchArguments()
        #endif
        let session = AppSession(
            makeSignIn: { SignInUseCase(codeProvider: $0, repository: repository, tokenStore: tokenStore) },
            restore: RestoreSessionUseCase(repository: repository, tokenStore: tokenStore),
            signOut: SignOutUseCase(tokenStore: tokenStore),
            unauthorizedEvents: api.unauthorizedEvents,
            resetUnauthorized: { await api.resetUnauthorized() },
            translations: api.translationRepository(),
            consent: UserDefaultsAIConsentStore(),
            refreshProfile: { try await repository.me() },
            devCodeProvider: devLogin
        )
        #if DEBUG
            session.resetOnLaunch = ProcessInfo.processInfo.arguments.contains("-MWResetSession")
        #endif
        return session
    }

    /// 앱 시작 시 한 번. 401 신호도 여기서부터 듣는다.
    @discardableResult
    public func start() -> Task<Void, Never> {
        listenForUnauthorized()
        return Task {
            if resetOnLaunch {
                try? await signOutUseCase()
                await consent.setGranted(false)
            }
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

    /// 버튼 없이 Apple 창을 직접 띄운다(단축어·재로그인 등). 로컬 E2E 실행 인자가 있으면 개발용 로그인.
    @discardableResult
    public func signInWithApple() -> Task<Void, Never> {
        signIn(using: devCodeProvider ?? AppleSignInCodeProvider())
    }

    /// 사용자 정보(등급·연속·현재 프로젝트)를 다시 읽는다. 실패하면 그대로 둔다.
    public func reloadProfile() async {
        // 오프라인으로 시작(unverified)했어도 다시 닿으면 회복한다.
        switch state {
        case .signedIn, .unverified: break
        default: return
        }
        guard let profile = try? await refreshProfile() else { return }
        state = .signedIn(profile)
    }

    public var user: UserProfile? {
        if case let .signedIn(user) = state {
            return user
        }
        return nil
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

    /// 로그아웃: 토큰과 AI 동의를 지운다(#25 "로그아웃 시 초기화").
    @discardableResult
    public func signOut() -> Task<Void, Never> {
        // 상태를 먼저 바꾼다: 토큰을 지우는 사이 화면이 보낸 요청의 401 이 "로그인이 풀렸어요"로 보이지 않게.
        state = .signedOut
        lastError = nil
        return Task {
            try? await signOutUseCase()
            await consent.setGranted(false)
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
        // 이미 로그아웃 중이면(직접 로그아웃) 무시한다.
        switch state {
        case .signedIn, .unverified: break
        default: return
        }
        state = .signedOut // 먼저 바꿔 동시에 온 401 은 위 guard 에서 멈춘다
        lastError = .unauthorized
        try? await signOutUseCase()
        await consent.setGranted(false) // #25: 로그인이 풀리면 AI 동의도 꺼진다
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

/// 저장소를 넣지 않은 테스트용 기본값. 부르면 항상 실패한다.
public struct UnavailableTranslationRepository: TranslationRepository {
    public init() {}
    public func translate(
        _: String,
        direction _: TranslationDirection,
        projectId _: Int64?,
        aiConsent _: Bool
    ) async throws -> Domain.Translation {
        throw DomainError.unknown
    }

    public func translations(projectId _: Int64?, page _: Int, size _: Int) async throws -> Page<TranslationSummary> {
        throw DomainError.unknown
    }

    public func translation(id _: Int64) async throws -> Domain.Translation {
        throw DomainError.unknown
    }

    public func deleteTranslation(id _: Int64) async throws {
        throw DomainError.unknown
    }

    public func setAction(translationId _: Int64, actionId _: Int64, isChecked _: Bool?, alertEnabled _: Bool?) async throws -> ActionItem {
        throw DomainError.unknown
    }

    public func actions(checked _: Bool, page _: Int, size _: Int) async throws -> Page<UpcomingAction> {
        throw DomainError.unknown
    }

    public func term(id _: Int64) async throws -> TermDetail {
        throw DomainError.unknown
    }

    public func projects() async throws -> [ProjectSummary] {
        throw DomainError.unknown
    }
}

/// 동의 저장소 기본값(항상 꺼짐).
public struct NoConsentStore: AIConsentStore {
    public init() {}
    public func isGranted() async -> Bool {
        false
    }

    public func setGranted(_: Bool) async {}
}
