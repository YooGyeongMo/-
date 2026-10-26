import Foundation
@testable import MwonmalAPI
import Testing

struct KSTDateTranscoderTests {
    let transcoder = KSTDateTranscoder()
    /// 2026-09-17 13:30:00 KST = 04:30:00 UTC
    let reference = Date(timeIntervalSince1970: 1_789_619_400)

    @Test("오프셋 없는 문자열은 KST로 읽는다") func decodesOffsetlessAsKST() throws {
        #expect(try transcoder.decode("2026-09-17T13:30:00") == reference)
    }

    @Test(
        "오프셋이 있으면 그 오프셋을 따른다",
        arguments: ["2026-09-17T13:30:00+09:00", "2026-09-17T04:30:00Z", "2026-09-17T04:30:00.000Z", "2026-09-17T13:30:00.000+09:00"]
    )
    func honorsExplicitOffset(_ string: String) throws {
        #expect(try transcoder.decode(string) == reference)
    }

    @Test("소수 초를 허용한다") func acceptsFractionalSeconds() throws {
        let date = try transcoder.decode("2026-09-17T13:30:00.250")
        #expect(abs(date.timeIntervalSince(reference) - 0.25) < 0.000_001)
    }

    @Test("인코딩은 오프셋 없는 KST 초 단위") func encodesOffsetlessKSTSeconds() throws {
        #expect(try transcoder.encode(reference) == "2026-09-17T13:30:00")
        #expect(try transcoder.encode(reference.addingTimeInterval(0.9)) == "2026-09-17T13:30:00")
    }

    @Test("왕복하면 같은 문자열") func roundTripsSameString() throws {
        for value in ["2026-01-01T00:00:00", "2026-12-31T23:59:59", "2027-02-28T09:05:07"] {
            #expect(try transcoder.encode(transcoder.decode(value)) == value)
        }
    }

    @Test("기기 시간대와 무관하다") func independentOfDeviceTimeZone() throws {
        // TimeZone.current를 쓰지 않으므로 결과가 고정이어야 한다.
        #expect(try transcoder.decode("2026-09-17T00:00:00").timeIntervalSince1970 == 1_789_570_800)
    }

    @Test(
        "형식이 틀리면 실패한다",
        arguments: ["", "2026-09-17", "2026-09-17 13:30:00", "2026-13-01T00:00:00", "2026-09-17T25:00:00", "abc", "2026-09-17T13:30:00.x"]
    )
    func rejectsMalformed(_ string: String) {
        #expect(throws: DecodingError.self) { try transcoder.decode(string) }
    }
}
