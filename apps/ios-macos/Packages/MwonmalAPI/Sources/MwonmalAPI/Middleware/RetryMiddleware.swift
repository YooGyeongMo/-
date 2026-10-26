import Foundation
import HTTPTypes
import OpenAPIRuntime

/// 503이면 GET만 한 번 다시 시도한다(D-12). 해석(POST)은 중복 저장 위험이 있어 재시도하지 않는다.
/// 기다리는 시간은 `Retry-After`(초)를 따르되 `maxDelay`로 자른다. 헤더가 없거나 이상하면 `defaultDelay`.
public struct RetryMiddleware: ClientMiddleware {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    let defaultDelay: Duration
    let maxDelay: Duration
    let sleep: Sleep

    public init(
        defaultDelay: Duration = .seconds(1),
        maxDelay: Duration = .seconds(10),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.defaultDelay = defaultDelay
        self.maxDelay = maxDelay
        self.sleep = sleep
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        guard request.method == .get, response.status == .serviceUnavailable else {
            return (response, responseBody)
        }
        try await sleep(delay(for: response))
        return try await next(request, body, baseURL)
    }

    func delay(for response: HTTPResponse) -> Duration {
        guard let raw = response.headerFields[.retryAfter],
              let seconds = Int(raw.trimmingCharacters(in: .whitespaces)), seconds >= 0
        else {
            return defaultDelay
        }
        return min(.seconds(seconds), maxDelay)
    }
}
