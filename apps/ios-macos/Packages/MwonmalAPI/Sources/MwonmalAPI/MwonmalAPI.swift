import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// MwonmalAPI 모듈. 역할과 의존 방향은 docs/design/12_앱_아키텍처_설계.md §0, §4 참고.
/// 계약 v1.0(contracts/openapi.yml)에서 빌드 플러그인이 `Client`와 `Components`를 만든다.
public enum MwonmalAPIModule {
    public static let name = "MwonmalAPI"
}

/// 생성된 `Client`를 미들웨어(D-12 3개 + AI 동의 헤더)와 KST 날짜 변환(D-13)으로 조립한다.
public enum MwonmalAPIClientFactory {
    /// - Parameters:
    ///   - serverURL: `…/api`까지 포함한 기준 주소.
    ///   - accessToken: 매 요청마다 읽는 토큰. 없으면 `nil`.
    ///   - unauthorized: 401 신호(동시 401은 한 번으로 합침).
    public static func make(
        serverURL: URL,
        accessToken: @escaping @Sendable () async -> String?,
        unauthorized: UnauthorizedSignal,
        session: URLSession = .shared
    ) -> Client {
        Client(
            serverURL: serverURL,
            configuration: Configuration(dateTranscoder: KSTDateTranscoder()),
            transport: URLSessionTransport(configuration: .init(session: session)),
            middlewares: [
                ErrorMiddleware(),
                RetryMiddleware(),
                AuthMiddleware(accessToken: accessToken, unauthorized: unauthorized),
                AIConsentMiddleware(),
            ]
        )
    }
}
