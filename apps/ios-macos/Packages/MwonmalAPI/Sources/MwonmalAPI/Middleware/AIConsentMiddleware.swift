import Foundation
import HTTPTypes
import OpenAPIRuntime

/// AI 외부 전송 동의 헤더(ADR-0008, #25). 계약 v1.0 operation 에 헤더 파라미터가 없어서 미들웨어가 붙인다.
///
/// 동의는 호출마다 `AIConsent.$granted.withValue(true) { … }`로 넘긴다(TaskLocal). 기본은 동의 안 함 → 헤더 없음
/// → 서버는 원문을 밖으로 보내지 않는다. 해석(`createTranslation`) 요청에만 붙인다.
public enum AIConsent {
    @TaskLocal public static var granted = false
    public static let headerName = HTTPField.Name("X-Mw-AI-Consent")!
}

public struct AIConsentMiddleware: ClientMiddleware {
    static let operations: Set<String> = ["createTranslation"]

    public init() {}

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[AIConsent.headerName] = nil // 밖에서 넣은 값은 믿지 않는다
        if AIConsent.granted, Self.operations.contains(operationID) {
            request.headerFields[AIConsent.headerName] = "1"
        }
        return try await next(request, body, baseURL)
    }
}
