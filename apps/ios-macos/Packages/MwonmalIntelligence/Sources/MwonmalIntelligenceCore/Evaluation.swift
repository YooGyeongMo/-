public import Foundation

/// `eval/dataset/*.jsonl` 한 줄(형식: eval/dataset/README.md). 앱 패키지와 서버 평가가 **같은 파일**을 읽는다.
/// 필요한 필드만 디코드하고 나머지는 무시한다(서버 쪽 스키마가 늘어도 깨지지 않게).
public struct EvalItem: Sendable, Decodable {
    public struct Gold: Sendable, Decodable {
        public let resultText: String?
        public let intentType: String?
        public let detectedTerms: [EvalGoldTerm]
    }

    public let id: String
    public let direction: String
    public let sourceType: String
    public let sourceText: String
    public let gold: Gold

    public var goldRanges: Set<ScalarRange> {
        Set(gold.detectedTerms.compactMap { ScalarRange(start: $0.startIndex, end: $0.endIndex) })
    }
}

/// gold의 용어 한 개(`EvalItem.Gold.detectedTerms`).
public struct EvalGoldTerm: Sendable, Decodable {
    public let termKo: String?
    public let matchedText: String
    public let startIndex: Int
    public let endIndex: Int
}

/// 예측 한 줄. `eval/run.py`에 "device-precomputed" 어댑터로 넣을 수 있게 gold와 같은 키 이름을 쓴다.
public struct EvalPrediction: Sendable, Encodable {
    public struct Term: Sendable, Encodable {
        public let matchedText: String
        public let startIndex: Int
        public let endIndex: Int
        public let origin: String
        public let confidence: Double?
    }

    public let id: String
    public let engine: String
    public let latencyMs: Double
    public let detectedTerms: [Term]

    public init(id: String, result: DetectionResult) {
        self.id = id
        engine = result.engine.description
        let parts = result.latency.components
        latencyMs = Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
        detectedTerms = result.spans.map {
            Term(
                matchedText: $0.matchedText,
                startIndex: $0.range.start,
                endIndex: $0.range.end,
                origin: $0.origin.rawValue,
                confidence: $0.confidence
            )
        }
    }
}

/// 용어 스팬 F1 — 정확 일치(eval/run.py ①과 같은 정의). 집계는 마이크로(합산 후 계산).
public struct SpanScore: Sendable, Equatable {
    public private(set) var truePositives = 0
    public private(set) var predicted = 0
    public private(set) var gold = 0

    public init() {}

    public mutating func add(gold goldSet: Set<ScalarRange>, predicted predictedSet: Set<ScalarRange>) {
        truePositives += goldSet.intersection(predictedSet).count
        predicted += predictedSet.count
        gold += goldSet.count
    }

    public var precision: Double {
        predicted == 0 ? (gold == 0 ? 1 : 0) : Double(truePositives) / Double(predicted)
    }

    public var recall: Double {
        gold == 0 ? (predicted == 0 ? 1 : 0) : Double(truePositives) / Double(gold)
    }

    public var f1Score: Double {
        let prec = precision, rec = recall
        return prec + rec == 0 ? 0 : 2 * prec * rec / (prec + rec)
    }
}

public enum EvalJSONL {
    /// 빈 줄과 `#` 주석 줄은 건너뛴다(eval/run.py load_dataset과 같은 규칙).
    public static func decode(_ data: Data) throws -> [EvalItem] {
        let dec = JSONDecoder()
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "UTF-8이 아닌 데이터셋"))
        }
        return try text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { try dec.decode(EvalItem.self, from: Data($0.utf8)) }
    }
}
