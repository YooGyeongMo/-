import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Bearer 토큰을 붙이고, 401이면 재로그인 신호를 보낸다(D-11, D-12).
/// 로그인 요청(`oauthLogin`)은 토큰을 붙이지 않고, 그 401(OAUTH_CODE_INVALID)은 로그인 화면 에러라 신호를 보내지 않는다.
public struct AuthMiddleware: ClientMiddleware {
    static let unauthenticatedOperations: Set<String> = ["oauthLogin"]

    private let accessToken: @Sendable () async -> String?
    private let unauthorized: UnauthorizedSignal

    public init(accessToken: @escaping @Sendable () async -> String?, unauthorized: UnauthorizedSignal) {
        self.accessToken = accessToken
        self.unauthorized = unauthorized
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let isPublic = Self.unauthenticatedOperations.contains(operationID)
        var request = request
        if !isPublic, let token = await accessToken() {
            request.headerFields[.authorization] = "Bearer \(token)"
        }
        let (response, responseBody) = try await next(request, body, baseURL)
        if response.status == .unauthorized, !isPublic {
            await unauthorized.notify()
        }
        return (response, responseBody)
    }
}
