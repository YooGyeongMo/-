@testable import Data
import Domain
import DomainTesting
import Foundation
import MwonmalAPI
import Testing

private let meJSON = """
{"userId":8,"email":"sub-1@apple.invalid","nickname":"판교뉴비123456","jobGroup":null,"profileImageUrl":null,
 "role":"MEMBER","bestScore":0,"currentStreak":0,"level":null,"currentProjectId":null,"reminderHour":18,
 "actionAlertEnabled":true,"createdAt":"2026-10-25T13:30:00"}
"""

private func repository(_ host: String, _ reply: StubURLProtocol.Reply, token: String? = nil) -> RemoteAuthRepository {
    StubURLProtocol.register(host: host, reply)
    let client = MwonmalAPIClientFactory.make(
        serverURL: URL(string: "https://\(host)/api")!,
        accessToken: { token },
        unauthorized: UnauthorizedSignal(),
        session: StubURLProtocol.session()
    )
    return RemoteAuthRepository(client: client)
}

private func errorJSON(_ code: String, _ message: String) -> String {
    #"{"code":"\#(code)","message":"\#(message)","timestamp":"2026-10-25T13:30:00"}"#
}

struct RemoteAuthRepositoryTests {
    @Test("로그인 성공: 토큰·사용자·플래그를 매핑한다") func signInMaps() async throws {
        let body = #"{"accessToken":"jwt","isNewUser":true,"needsOnboarding":true,"user":\#(meJSON)}"#
        let repo = repository("signin-ok.test", .init(status: 200, body: body))
        let (token, result) = try await repo.signIn(with: .sample)
        #expect(token == "jwt")
        #expect(result.user == UserProfile(id: 8, nickname: "판교뉴비123456", email: "sub-1@apple.invalid", jobGroup: nil))
        #expect(result.isNewUser && result.needsOnboarding)
        let request = try #require(StubURLProtocol.requests(host: "signin-ok.test").first)
        #expect(request.url?.path == "/api/auth/oauth/apple")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("OAUTH_CODE_INVALID → signInFailed(서버 문구)") func invalidCode() async {
        let repo = repository("signin-401.test", .init(status: 401, body: errorJSON("OAUTH_CODE_INVALID", "로그인에 실패했어요. 다시 시도해 주세요.")))
        await #expect(throws: DomainError.signInFailed(message: "로그인에 실패했어요. 다시 시도해 주세요.")) {
            _ = try await repo.signIn(with: .sample)
        }
    }

    @Test("EMAIL_ALREADY_REGISTERED → emailAlreadyRegistered") func emailConflict() async {
        let repo = repository("signin-409.test", .init(status: 409, body: errorJSON("EMAIL_ALREADY_REGISTERED", "이미 가입한 이메일이에요.")))
        await #expect(throws: DomainError.emailAlreadyRegistered(message: "이미 가입한 이메일이에요.")) {
            _ = try await repo.signIn(with: .sample)
        }
    }

    @Test("토큰이 비어 있으면 INVALID_RESPONSE") func emptyTokenRejected() async {
        let repo = repository("signin-empty.test", .init(status: 200, body: #"{"accessToken":"","user":\#(meJSON)}"#))
        await #expect(throws: DomainError.server(code: "INVALID_RESPONSE", message: nil)) {
            _ = try await repo.signIn(with: .sample)
        }
    }

    @Test("me: Bearer를 붙이고 사용자를 매핑한다") func meMaps() async throws {
        let repo = repository("me-ok.test", .init(status: 200, body: meJSON), token: "jwt")
        let user = try await repo.me()
        #expect(user.id == 8)
        #expect(StubURLProtocol.requests(host: "me-ok.test").first?.value(forHTTPHeaderField: "Authorization") == "Bearer jwt")
    }

    @Test("me 401 → unauthorized") func meUnauthorized() async {
        let repo = repository("me-401.test", .init(status: 401, body: errorJSON("UNAUTHORIZED", "다시 로그인해 주세요.")), token: "old")
        await #expect(throws: DomainError.unauthorized) { _ = try await repo.me() }
    }

    @Test("네트워크 없음 → offline") func offline() async {
        let repo = repository("me-offline.test", .init(status: 0, body: "", error: URLError(.notConnectedToInternet)), token: "t")
        await #expect(throws: DomainError.offline) { _ = try await repo.me() }
    }

    @Test("모르는 서버 코드 → server(code, message)") func unknownServerCode() async {
        let repo = repository("me-500.test", .init(status: 500, body: errorJSON("INTERNAL_ERROR", "잠시 후 다시 시도해 주세요.")), token: "t")
        await #expect(throws: DomainError.server(code: "INTERNAL_ERROR", message: "잠시 후 다시 시도해 주세요.")) { _ = try await repo.me() }
    }
}
