internal import Foundation

/// 원문 안의 구간. **유니코드 스칼라 0-시작, 끝 미포함** — 서버 `DetectedTerm.startIndex/endIndex`,
/// `eval/dataset` gold, Python `str` 인덱스와 같은 단위(ADR-0007 §4-1).
public struct ScalarRange: Hashable, Sendable, Codable, Comparable {
    public let start: Int
    public let end: Int

    public init?(start: Int, end: Int) {
        guard start >= 0, end > start else { return nil }
        self.start = start
        self.end = end
    }

    public var length: Int {
        end - start
    }

    public func overlaps(_ other: ScalarRange) -> Bool {
        start < other.end && other.start < end
    }

    public static func < (lhs: ScalarRange, rhs: ScalarRange) -> Bool {
        (lhs.start, lhs.end) < (rhs.start, rhs.end)
    }
}

public extension String {
    /// 스칼라 구간의 부분 문자열. 범위를 벗어나면 nil.
    func substring(scalars range: ScalarRange) -> String? {
        let scalars = unicodeScalars
        guard range.end <= scalars.count else { return nil }
        let lower = scalars.index(scalars.startIndex, offsetBy: range.start)
        let upper = scalars.index(lower, offsetBy: range.length)
        return String(scalars[lower ..< upper])
    }

    /// 화면(AttributedString)용 `String.Index` 범위로 바꾼다. 그래핌 경계가 아니면 nil(형광펜을 그리지 않는다).
    func indexRange(scalars range: ScalarRange) -> Range<String.Index>? {
        let scalars = unicodeScalars
        guard range.end <= scalars.count else { return nil }
        let lower = scalars.index(scalars.startIndex, offsetBy: range.start)
        let upper = scalars.index(lower, offsetBy: range.length)
        guard let lowerIndex = lower.samePosition(in: self), let upperIndex = upper.samePosition(in: self) else { return nil }
        return lowerIndex ..< upperIndex
    }
}
