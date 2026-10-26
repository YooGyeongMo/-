import Foundation
import OpenAPIRuntime

/// 계약 v1.0 날짜 규칙(D-13): 서버는 `2026-09-17T13:30:00`처럼 오프셋 없는 KST를 낸다.
/// 기본 `ISO8601DateTranscoder`는 오프셋이 없으면 실패하므로 직접 만든다.
/// - 디코딩: 오프셋 없음 → KST로 해석. `Z`·`+09:00` 같은 오프셋이 있으면 그 오프셋을 따른다(v1.1 대비). 소수 초 허용.
/// - 인코딩: 항상 오프셋 없는 KST, 초 단위.
public struct KSTDateTranscoder: DateTranscoder {
    public static let seoul = TimeZone(identifier: "Asia/Seoul")!

    public init() {}

    public func encode(_ date: Date) throws -> String {
        date.formatted(Self.localFormat)
    }

    public func decode(_ string: String) throws -> Date {
        if Self.hasOffset(string) {
            if let date = try? Date(string, strategy: Self.offsetFormat) {
                return date
            }
            if let date = try? Date(string, strategy: Self.offsetFractionalFormat) {
                return date
            }
        } else if let date = Self.decodeLocal(string) {
            return date
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "KST 날짜 형식이 아닙니다: \(string)")
        )
    }

    // swiftlint:disable:next line_length
    private static let pattern: Date.FormatString = "\(year: .padded(4))-\(month: .twoDigits)-\(day: .twoDigits)T\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)"

    private static let localFormat = Date.VerbatimFormatStyle(
        format: pattern,
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: seoul,
        calendar: Calendar(identifier: .gregorian)
    )

    private static let localParse = Date.ParseStrategy(
        format: pattern,
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: seoul,
        calendar: Calendar(identifier: .gregorian),
        isLenient: false
    )

    private static let offsetFormat = Date.ISO8601FormatStyle()
    private static let offsetFractionalFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// 시각 부분(`T` 뒤)에 `Z`나 `+`/`-` 오프셋이 있는지.
    private static func hasOffset(_ string: String) -> Bool {
        guard let separator = string.firstIndex(of: "T") else { return false }
        let time = string[string.index(after: separator)...]
        return time.hasSuffix("Z") || time.contains("+") || time.contains("-")
    }

    /// 오프셋 없는 문자열. 엄격 파싱 뒤 다시 포맷해 같은지 비교한다(관대한 파싱으로 꼬리 문자가 무시되는 것 방지).
    private static func decodeLocal(_ string: String) -> Date? {
        guard let (base, fraction) = splitFraction(string),
              let date = try? Date(base, strategy: localParse),
              date.formatted(localFormat) == base else { return nil }
        return date.addingTimeInterval(fraction)
    }

    /// `13:30:00.123456` → (`13:30:00`, 0.123456), 소수부가 없으면 0. 소수부가 숫자가 아니면 `nil`.
    private static func splitFraction(_ string: String) -> (String, TimeInterval)? {
        guard let dot = string.lastIndex(of: ".") else { return (string, 0) }
        let digits = string[string.index(after: dot)...]
        guard !digits.isEmpty, digits.count <= 9, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Double("0." + digits) else { return nil }
        return (String(string[..<dot]), value)
    }
}
