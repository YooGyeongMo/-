import Foundation
import HTTPTypes
@testable import MwonmalAPI
import Testing

/// 생성 코드가 계약 v1.0 응답을 실제로 읽는지(nullable + allOf `value1` 포함).
struct GeneratedClientTests {
    @Test("getMe 오프셋 없는 날짜와 null allOf를 읽는다") func getMeDecodesOffsetlessDateAndNullAllOf() async throws {
        let transport = FakeTransport([.init(status: .ok, body: meJSON)])
        let user = try await makeClient(transport).getMe().ok.body.json
        #expect(user.userId == 8)
        #expect(user.jobGroup == nil)
        #expect(user.level == nil)
        #expect(try user.createdAt == (KSTDateTranscoder().decode("2026-10-25T13:30:00")))
    }

    @Test("getMe allOf value1을 읽는다") func getMeDecodesAllOfValue1() async throws {
        let json = meJSON
            .replacingOccurrences(of: #""jobGroup":null"#, with: #""jobGroup":"개발""#)
            .replacingOccurrences(of: #""level":null"#, with: #""level":{"code":"OUTSIDER","name":"외지인","minScore":0,"maxScore":19}"#)
        let transport = FakeTransport([.init(status: .ok, body: json)])
        let user = try await makeClient(transport).getMe().ok.body.json
        #expect(user.jobGroup?.value1 == .개발)
        #expect(user.level?.value1.name == "외지인")
    }

    @Test("연산은 43개다") func contractHas43Operations() throws {
        // 계약 operationId 개수와 생성된 Client 메서드 수가 같아야 한다(계약 v1.0 = 43).
        let yml = try String(contentsOf: Self.contractURL, encoding: .utf8)
        let count = yml.components(separatedBy: "operationId:").count - 1
        #expect(count == 43)
    }

    static var contractURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MwonmalAPI/openapi.yaml")
    }
}
