public import MwonmalIntelligenceCore

/// 태거 입력 토큰화 — 학습 스크립트(`prep.py` C 방식)와 **바이트 단위로 같아야 한다**.
/// 공백이 아닌 유니코드 스칼라 1개 = 토큰 1개, 어절 첫 글자엔 `▁`(U+2581) 접두. 토큰 i ↔ 스칼라 오프셋 1:1.
/// 학습·추론 토큰화가 어긋나면 정확도가 소리 없이 떨어지므로 테스트 벡터(`TokenizerParityTests`)로 고정한다.
public struct CharTokenizer: Sendable {
    public static let wordStartMarker: Character = "\u{2581}"

    public init() {}

    public struct Output: Sendable, Equatable {
        public let tokens: [String]
        /// 각 토큰의 원문 스칼라 오프셋.
        public let offsets: [Int]
    }

    public func tokenize(_ text: String) -> Output {
        let scalars = Array(text.unicodeScalars)
        var tokens: [String] = []
        var offsets: [Int] = []
        tokens.reserveCapacity(scalars.count)
        for (index, scalar) in scalars.enumerated() where !scalar.properties.isWhitespace {
            let prevSpace = index == 0 || scalars[index - 1].properties.isWhitespace
            tokens.append((prevSpace ? String(Self.wordStartMarker) : "") + String(Character(scalar)))
            offsets.append(index)
        }
        return Output(tokens: tokens, offsets: offsets)
    }
}

/// BIO 라벨(`B-T`/`I-T`/`O`) → 스칼라 구간. `prep.py decode()`와 같은 규칙: 앞에 B 없는 I는 새 구간을 연다.
public enum BIODecoder {
    public static func ranges(labels: [String], offsets: [Int]) -> [ScalarRange] {
        precondition(labels.count == offsets.count, "라벨과 오프셋 길이가 다르다")
        var out: [ScalarRange] = []
        var cur: (start: Int, end: Int)?
        func flush() {
            if let current = cur, let range = ScalarRange(start: current.start, end: current.end) {
                out.append(range)
            }
            cur = nil
        }
        for (position, label) in labels.enumerated() {
            let lower = offsets[position], upper = offsets[position] + 1
            switch label {
            case "B-T":
                flush()
                cur = (lower, upper)
            case "I-T":
                if cur == nil {
                    cur = (lower, upper)
                } else {
                    cur!.end = upper
                }
            default:
                flush()
            }
        }
        flush()
        return out
    }
}
