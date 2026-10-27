import Domain
import Foundation
import MwonmalAPI

/// 서버 연결 한 벌(클라이언트 + 401 신호). Composition은 MwonmalAPI를 모르고 이것만 본다(ADR-0016).
public final class APIEnvironment: Sendable {
    private let client: Client
    private let signal: UnauthorizedSignal

    public init(baseURL: URL, tokenStore: any TokenStore, session: URLSession = APIEnvironment.makeSession()) {
        let signal = UnauthorizedSignal()
        self.signal = signal
        client = MwonmalAPIClientFactory.make(
            serverURL: baseURL,
            accessToken: { await tokenStore.read() },
            unauthorized: signal,
            session: session
        )
    }

    /// 앱 전용 URLSession(앱에 하나). `.shared`를 쓰지 않는 이유:
    /// - 응답에 개인 데이터(원문·할 일)가 있다 → 디스크·메모리 URL 캐시를 아예 두지 않는다(서버 `no-store`와 이중 방어).
    /// - 쿠키를 쓰지 않는다(인증은 Bearer 토큰) → 쿠키 저장소도 끈다.
    /// - 오프라인이면 기다리지 않고 바로 실패해야 화면이 "연결 없음"을 보여 준다(`waitsForConnectivity = false`).
    /// - 요청 시간 20초 = 서버 AI 타임아웃 12초 + 사전 바닥 + 왕복 여유. 자원 전체 60초.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }

    /// 401 재로그인 신호(동시 401은 한 번). 다시 로그인한 뒤 `resetUnauthorized()`.
    public var unauthorizedEvents: AsyncStream<Void> {
        signal.events
    }

    public func resetUnauthorized() async {
        await signal.reset()
    }

    public func authRepository() -> any AuthRepository {
        RemoteAuthRepository(client: client)
    }

    public func translationRepository() -> any TranslationRepository {
        RemoteTranslationRepository(client: client)
    }
}
