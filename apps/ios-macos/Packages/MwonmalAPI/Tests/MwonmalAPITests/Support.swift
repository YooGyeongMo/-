import Foundation
import HTTPTypes
@testable import MwonmalAPI
import OpenAPIRuntime
import Testing

/// 요청을 기록하고, 순서대로 준비한 응답을 돌려주는 가짜 전송 계층.
final class FakeTransport: ClientTransport, @unchecked Sendable {
    struct Reply: Sendable {
        var status: HTTPResponse.Status
        var headers: HTTPFields = [:]
        var body: String?
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [(HTTPRequest, String)] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    var requestCount: Int {
        lock.withLock { requests.count }
    }

    func send(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let reply: Reply = lock.withLock {
            requests.append((request, operationID))
            return replies.count > 1 ? replies.removeFirst() : replies[0]
        }
        var fields = reply.headers
        if reply.body != nil, fields[.contentType] == nil {
            fields[.contentType] = "application/json"
        }
        return (HTTPResponse(status: reply.status, headerFields: fields), reply.body.map { HTTPBody($0) })
    }
}

func makeClient(
    _ transport: FakeTransport,
    token: String? = "tok",
    signal: UnauthorizedSignal = UnauthorizedSignal(),
    sleeps: SleepRecorder = SleepRecorder()
) -> Client {
    Client(
        serverURL: URL(string: "https://example.invalid/api")!,
        configuration: Configuration(dateTranscoder: KSTDateTranscoder()),
        transport: transport,
        middlewares: [
            ErrorMiddleware(),
            RetryMiddleware(sleep: { await sleeps.record($0) }),
            AuthMiddleware(accessToken: { token }, unauthorized: signal),
        ]
    )
}

actor SleepRecorder {
    private(set) var delays: [Duration] = []
    func record(_ delay: Duration) {
        delays.append(delay)
    }
}

/// 서버 Day 2 `GET /api/users/me` 응답과 같은 모양(가짜 값).
let meJSON = """
{"userId":8,"email":"sub-1@apple.invalid","nickname":"판교뉴비123456","jobGroup":null,
 "profileImageUrl":null,"role":"MEMBER","bestScore":0,"currentStreak":0,"level":null,
 "currentProjectId":null,"reminderHour":18,"actionAlertEnabled":true,"createdAt":"2026-10-25T13:30:00"}
"""

let errorJSON = #"{"code":"UNAUTHORIZED","message":"다시 로그인해 주세요.","timestamp":"2026-10-25T13:30:00"}"#

/// `#expect(throws:)`가 돌려준 에러에서 `MwonmalServerError`를 꺼낸다(생성 클라이언트가 `ClientError`로 감싼다).
func serverError(_ error: (any Error)?) throws -> MwonmalServerError {
    let error = try #require(error)
    return try #require(MwonmalServerError.unwrap(error))
}
