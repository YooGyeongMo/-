import Foundation
import HTTPTypes
@testable import MwonmalAPI
import OpenAPIRuntime
import Testing

struct AuthMiddlewareTests {
    @Test("토큰을 Bearer로 붙인다") func addsBearerToken() async throws {
        let transport = FakeTransport([.init(status: .ok, body: meJSON)])
        _ = try await makeClient(transport, token: "abc").getMe()
        #expect(transport.requests[0].0.headerFields[.authorization] == "Bearer abc")
    }

    @Test("토큰이 없으면 헤더를 붙이지 않는다") func omitsHeaderWithoutToken() async throws {
        let transport = FakeTransport([.init(status: .ok, body: meJSON)])
        _ = try await makeClient(transport, token: nil).getMe()
        #expect(transport.requests[0].0.headerFields[.authorization] == nil)
    }

    @Test("로그인 요청에는 토큰을 붙이지 않고 401도 신호가 아니다") func loginSkipsTokenAndSignal() async throws {
        let signal = UnauthorizedSignal()
        let transport = FakeTransport([.init(
            status: .unauthorized,
            body: #"{"code":"OAUTH_CODE_INVALID","message":"로그인에 실패했어요. 다시 시도해 주세요.","timestamp":"2026-10-25T13:30:00"}"#
        )])
        let client = makeClient(transport, token: "abc", signal: signal)
        let error = await #expect(throws: (any Error).self) {
            _ = try await client.oauthLogin(
                path: .init(provider: .apple),
                body: .json(.init(code: "c", redirectUri: "https://example.invalid/cb"))
            )
        }
        #expect(transport.requests[0].0.headerFields[.authorization] == nil)
        #expect(try serverError(error).code == "OAUTH_CODE_INVALID")
        #expect(await signal.isPending == false)
    }

    @Test("동시 401 여러 개는 신호 한 번") func concurrent401sSignalOnce() async {
        let signal = UnauthorizedSignal()
        let transport = FakeTransport([.init(status: .unauthorized, body: errorJSON)])
        let client = makeClient(transport, signal: signal)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 10 {
                group.addTask { _ = try? await client.getMe() }
            }
        }
        #expect(transport.requestCount == 10)
        #expect(await signal.deliveredCount == 1)
        var iterator = signal.events.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }

    @Test("신호는 reset 전까지 한 번만 간다") func signalOncePerReset() async {
        let signal = UnauthorizedSignal()
        await signal.notify()
        await signal.notify()
        await signal.notify()
        #expect(await signal.isPending)
        #expect(await signal.deliveredCount == 1)
        await signal.reset()
        #expect(await signal.isPending == false)
        await signal.notify()
        #expect(await signal.deliveredCount == 2)
    }
}

struct RetryMiddlewareTests {
    @Test("GET 503은 Retry After만큼 기다려 한 번 다시 시도한다") func retriesGet503OnceAfterRetryAfter() async throws {
        let sleeps = SleepRecorder()
        let transport = FakeTransport([
            .init(status: .serviceUnavailable, headers: [.retryAfter: "5"], body: errorJSON),
            .init(status: .ok, body: meJSON),
        ])
        _ = try await makeClient(transport, sleeps: sleeps).getMe().ok
        #expect(transport.requestCount == 2)
        #expect(await sleeps.delays == [.seconds(5)])
        // 재시도 요청에도 토큰이 붙어야 한다(Auth가 Retry 안쪽).
        #expect(transport.requests[1].0.headerFields[.authorization] == "Bearer tok")
    }

    @Test("두 번째도 503이면 더 시도하지 않고 에러") func secondFailureThrows() async throws {
        let transport = FakeTransport([.init(status: .serviceUnavailable, headers: [.retryAfter: "5"], body: errorJSON)])
        let error = await #expect(throws: (any Error).self) { _ = try await makeClient(transport).getMe() }
        #expect(transport.requestCount == 2)
        #expect(try serverError(error).retryAfterSeconds == 5)
    }

    @Test("POST는 재시도하지 않는다") func doesNotRetryPost() async throws {
        let transport = FakeTransport([.init(status: .serviceUnavailable, headers: [.retryAfter: "1"], body: errorJSON)])
        await #expect(throws: (any Error).self) {
            _ = try await makeClient(transport).oauthLogin(
                path: .init(provider: .apple),
                body: .json(.init(code: "c", redirectUri: "https://example.invalid/cb"))
            )
        }
        #expect(transport.requestCount == 1)
    }

    @Test("다른 5xx는 재시도하지 않는다") func doesNotRetryOther5xx() async throws {
        let transport = FakeTransport([.init(status: .internalServerError, body: errorJSON)])
        await #expect(throws: (any Error).self) { _ = try await makeClient(transport).getMe() }
        #expect(transport.requestCount == 1)
    }

    @Test("Retry After 파싱", arguments: [
        (nil as String?, Duration.seconds(1)),
        ("0", .seconds(0)),
        ("3", .seconds(3)),
        (" 7 ", .seconds(7)),
        ("3600", .seconds(10)),
        ("-1", .seconds(1)),
        ("Wed, 21 Oct 2026 07:28:00 GMT", .seconds(1)),
        ("abc", .seconds(1)),
    ])
    func parsesRetryAfter(_ header: String?, _ expected: Duration) {
        var fields = HTTPFields()
        if let header {
            fields[.retryAfter] = header
        }
        let response = HTTPResponse(status: .serviceUnavailable, headerFields: fields)
        #expect(RetryMiddleware().delay(for: response) == expected)
    }
}

struct ErrorMiddlewareTests {
    @Test("에러 봉투를 MwonmalServerError로 바꾼다") func mapsEnvelopeToServerError() async throws {
        let body = #"{"code":"INVALID_INPUT","message":"입력을 확인해 주세요.","field":"provider","timestamp":"2026-10-25T13:30:00"}"#
        let transport = FakeTransport([.init(status: .badRequest, body: body)])
        let error = await #expect(throws: (any Error).self) { _ = try await makeClient(transport).getMe() }
        #expect(try serverError(error) == MwonmalServerError(
            status: 400,
            code: "INVALID_INPUT",
            message: "입력을 확인해 주세요.",
            field: "provider"
        ))
    }

    @Test("봉투의 날짜가 오프셋을 가져도 깨지지 않는다") func toleratesOffsetTimestampInEnvelope() async throws {
        let body = #"{"code":"UNAUTHORIZED","message":"다시 로그인해 주세요.","timestamp":"2026-10-25T13:30:00+09:00"}"#
        let transport = FakeTransport([.init(status: .unauthorized, body: body)])
        let error = await #expect(throws: (any Error).self) { _ = try await makeClient(transport).getMe() }
        #expect(try serverError(error).code == "UNAUTHORIZED")
    }

    @Test("봉투가 아니면 HTTP 상태코드와 기본 문구 본문은 노출하지 않는다") func nonEnvelopeHidesBody() async throws {
        let transport = FakeTransport([.init(
            status: .badGateway,
            headers: [.contentType: "text/html"],
            body: "<html>nginx secret-host</html>"
        )])
        let error = await #expect(throws: (any Error).self) { _ = try await makeClient(transport).getMe() }
        let server = try serverError(error)
        #expect(server.code == "HTTP_502")
        #expect(!server.message.contains("secret-host"))
    }

    @Test("성공 응답은 건드리지 않는다") func passesSuccessThrough() async throws {
        let transport = FakeTransport([.init(status: .ok, body: meJSON)])
        _ = try await makeClient(transport).getMe().ok
    }

    @Test("unwrap은 관계없는 에러에 nil") func unwrapReturnsNilForOtherErrors() {
        #expect(MwonmalServerError.unwrap(URLError(.notConnectedToInternet)) == nil)
    }
}

struct ClientFactoryTests {
    @Test("팩토리가 만든 클라이언트로 요청을 만든다") func factoryBuildsClient() throws {
        _ = try MwonmalAPIClientFactory.make(
            serverURL: #require(URL(string: "https://example.invalid/api")),
            accessToken: { nil },
            unauthorized: UnauthorizedSignal()
        )
        #expect(MwonmalAPIModule.name == "MwonmalAPI")
    }
}

struct APIErrorCauseTests {
    @Test("ClientError를 벗겨 URLError를 돌려준다") func unwrapsURLError() async {
        struct Failing: ClientTransport {
            func send(_: HTTPRequest, body _: HTTPBody?, baseURL _: URL, operationID _: String) async throws -> (HTTPResponse, HTTPBody?) {
                throw URLError(.notConnectedToInternet)
            }
        }
        let client = Client(
            serverURL: URL(fileURLWithPath: "/"),
            configuration: .init(dateTranscoder: KSTDateTranscoder()),
            transport: Failing()
        )
        do {
            _ = try await client.getMe()
            Issue.record("에러가 나야 한다")
        } catch {
            #expect((APIErrorCause.root(of: error) as? URLError)?.code == .notConnectedToInternet)
        }
    }
}

struct AIConsentMiddlewareTests {
    static let translationJSON = #"{"translationId":1,"sourceText":"a","resultText":"a","jargonCount":0,"actionItems":[],"detectedTerms":[],"aiModel":"none/dictionary#p1","createdAt":"2026-10-27T10:00:00"}"#

    private func translate(_ client: Client) async throws {
        _ = try await client.createTranslation(body: .json(.init(sourceText: "a", direction: .jargonToPlain))).created
    }

    @Test("동의하지 않으면 헤더가 없다(기본)") func noHeaderByDefault() async throws {
        let transport = FakeTransport([.init(status: .created, body: Self.translationJSON)])
        try await translate(makeClient(transport))
        #expect(transport.requests[0].0.headerFields[AIConsent.headerName] == nil)
    }

    @Test("동의하면 해석 요청에만 1을 붙인다") func headerOnlyOnTranslate() async throws {
        let transport = FakeTransport([.init(status: .created, body: Self.translationJSON), .init(status: .ok, body: meJSON)])
        let client = makeClient(transport)
        try await AIConsent.$granted.withValue(true) {
            try await translate(client)
            _ = try await client.getMe()
        }
        #expect(transport.requests[0].0.headerFields[AIConsent.headerName] == "1")
        #expect(transport.requests[1].0.headerFields[AIConsent.headerName] == nil)
    }
}
