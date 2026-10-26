import Foundation
import HTTPTypes
import OpenAPIRuntime

/// 서버 공통 에러 봉투(계약 `Error` 스키마). 제공자 원문 같은 것은 서버가 넣지 않는다.
public struct MwonmalServerError: Error, Sendable, Equatable {
    public let status: Int
    public let code: String
    public let message: String
    public let field: String?
    /// 503일 때 `Retry-After`(초).
    public let retryAfterSeconds: Int?

    public init(status: Int, code: String, message: String, field: String? = nil, retryAfterSeconds: Int? = nil) {
        self.status = status
        self.code = code
        self.message = message
        self.field = field
        self.retryAfterSeconds = retryAfterSeconds
    }

    /// 생성 클라이언트는 미들웨어가 던진 에러를 `ClientError`로 감싼다. 원래 `MwonmalServerError`를 꺼낸다.
    public static func unwrap(_ error: any Error) -> MwonmalServerError? {
        if let error = error as? MwonmalServerError {
            return error
        }
        if let error = error as? ClientError {
            return unwrap(error.underlyingError)
        }
        return nil
    }
}

/// 상태 코드 ≥ 400이면 바디를 공통 에러로 읽어 `MwonmalServerError`를 던진다(D-12).
/// 바디가 에러 봉투가 아니면(프록시 502 HTML 등) `code = "HTTP_<status>"`로 바꾼다. 본문은 메시지에 넣지 않는다.
public struct ErrorMiddleware: ClientMiddleware {
    /// 에러 바디는 작다. 그 이상은 읽지 않는다.
    static let maxBodyBytes = 64 * 1024

    public init() {}

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        let status = response.status.code
        guard status >= 400 else { return (response, responseBody) }

        let retryAfter = response.headerFields[.retryAfter].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        var envelope: Envelope?
        if let responseBody {
            if let data = try? await Data(collecting: responseBody, upTo: Self.maxBodyBytes) {
                envelope = try? JSONDecoder().decode(Envelope.self, from: data)
            }
        }
        throw MwonmalServerError(
            status: status,
            code: envelope?.code ?? "HTTP_\(status)",
            message: envelope?.message ?? "잠시 후 다시 시도해 주세요.",
            field: envelope?.field,
            retryAfterSeconds: retryAfter
        )
    }

    /// 날짜(`timestamp`)는 쓰지 않으므로 읽지 않는다. 날짜 형식이 바뀌어도 에러 처리는 깨지지 않는다.
    private struct Envelope: Decodable {
        let code: String
        let message: String
        let field: String?
    }
}

/// 생성 클라이언트가 감싼 에러(`ClientError`)를 벗겨 가장 안쪽 원인을 돌려준다.
/// Data가 `URLError`·`CancellationError`·`MwonmalServerError`를 구분할 때 쓴다(OpenAPIRuntime을 import하지 않고).
public enum APIErrorCause {
    public static func root(of error: any Error) -> any Error {
        var current: any Error = error
        while let wrapped = current as? ClientError {
            current = wrapped.underlyingError
        }
        return current
    }
}
