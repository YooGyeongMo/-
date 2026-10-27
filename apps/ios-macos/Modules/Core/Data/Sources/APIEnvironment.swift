import Domain
import Foundation
import MwonmalAPI

/// 서버 연결 한 벌(클라이언트 + 401 신호). Composition은 MwonmalAPI를 모르고 이것만 본다(ADR-0016).
public final class APIEnvironment: Sendable {
    private let client: Client
    private let signal: UnauthorizedSignal

    public init(baseURL: URL, tokenStore: any TokenStore, session: URLSession = .shared) {
        let signal = UnauthorizedSignal()
        self.signal = signal
        client = MwonmalAPIClientFactory.make(
            serverURL: baseURL,
            accessToken: { await tokenStore.read() },
            unauthorized: signal,
            session: session
        )
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
