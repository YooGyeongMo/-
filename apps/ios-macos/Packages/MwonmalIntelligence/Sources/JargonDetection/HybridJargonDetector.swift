public import MwonmalIntelligenceCore

internal import Foundation

/// 사전 trie + (선택) 태거 하이브리드. 태거가 없거나 못 쓰면 사전만으로 돈다(절대 실패하지 않는 바닥).
///
/// 병합 정책 `longestWins`(실험의 hybridB, 실험 기준 최고 F1): 사전 구간을 기본으로 두고,
/// 모델 구간이 겹치는 사전 구간을 모두 감싸면서 더 길 때만 모델이 이긴다("얼라인업"처럼 새 표기).
public struct HybridJargonDetector: JargonDetecting {
    public enum MergePolicy: Sendable { case dictionaryOnly, longestWins }

    public let trie: DictionaryTrie
    public let tagger: (any SequenceTagging)?
    public let policy: MergePolicy
    /// 모델 구간을 받아들일 최소 평균 확률. 실험의 τ=0.9는 재현율을 깎아 기본은 0(끔).
    public let minimumModelConfidence: Double
    private let tokenizer = CharTokenizer()

    public init(
        trie: DictionaryTrie,
        tagger: (any SequenceTagging)? = nil,
        policy: MergePolicy = .longestWins,
        minimumModelConfidence: Double = 0
    ) {
        self.trie = trie
        self.tagger = tagger
        self.policy = tagger == nil ? .dictionaryOnly : policy
        self.minimumModelConfidence = minimumModelConfidence
    }

    public var engine: EngineTag {
        policy == .dictionaryOnly ? .dictionaryOnly : (tagger?.engine ?? .dictionaryOnly)
    }

    public func detect(in text: String) async throws(IntelligenceError) -> DetectionResult {
        let clock = ContinuousClock()
        let start = clock.now
        let dict = trie.find(in: text)
        guard policy == .longestWins, let tagger else {
            return DetectionResult(spans: dict, engine: engine, latency: clock.now - start)
        }
        let tok = tokenizer.tokenize(text)
        let tagged = try await tagger.tag(tokens: tok.tokens)
        let ranges = BIODecoder.ranges(labels: tagged.map(\.label), offsets: tok.offsets)
        let probByOffset = Dictionary(uniqueKeysWithValues: zip(tok.offsets, tagged.map(\.probability)))
        let model: [JargonSpan] = ranges.compactMap { range in
            let probs = (range.start ..< range.end).compactMap { probByOffset[$0] }
            let conf = probs.isEmpty ? 0 : probs.reduce(0, +) / Double(probs.count)
            guard conf >= minimumModelConfidence, let matched = text.substring(scalars: range) else { return nil }
            return JargonSpan(range: range, matchedText: matched, origin: .model, confidence: conf)
        }
        return DetectionResult(
            spans: Self.mergeLongest(dictionary: dict, model: model),
            engine: engine,
            latency: clock.now - start
        )
    }

    static func mergeLongest(dictionary: [JargonSpan], model: [JargonSpan]) -> [JargonSpan] {
        var result = dictionary
        for candidate in model {
            let over = result.filter { $0.range.overlaps(candidate.range) }
            if over.isEmpty {
                result.append(candidate)
            } else if Self.covers(candidate, over) {
                result.removeAll { span in over.contains(span) }
                result.append(candidate)
            }
        }
        return result.sorted { $0.range < $1.range }
    }

    /// 모델 구간이 겹치는 사전 구간을 모두 감싸고, 그중 가장 긴 것보다 길면 true.
    private static func covers(_ candidate: JargonSpan, _ over: [JargonSpan]) -> Bool {
        let range = candidate.range
        let enclosesAll = over.allSatisfy { range.start <= $0.range.start && $0.range.end <= range.end }
        return enclosesAll && range.length > over.map(\.range.length).max()!
    }
}

extension HybridJargonDetector {
    /// 패키지에 든 합성 시드 사전(`Resources/lexicon-v0.json`). 정본 사전은 서버에 있다(REQ-14) —
    /// 이 시드는 미리보기·오프라인 감지용이고, 갱신본은 호스트가 `DictionaryTrie(terms:)`로 넘긴다.
    public static func bundledSeedTrie() throws -> DictionaryTrie {
        guard let url = Bundle.module.url(forResource: "lexicon-v0", withExtension: "json") else {
            throw IntelligenceError.unavailable(.modelAssetMissing)
        }
        let lex = try JSONDecoder().decode(Lexicon.self, from: Data(contentsOf: url))
        return DictionaryTrie(terms: lex.terms.flatMap { [$0.term] + ($0.variants ?? []) })
    }

    struct Lexicon: Decodable {
        let version: String
        let terms: [LexiconEntry]
    }

    struct LexiconEntry: Decodable {
        let term: String
        let variants: [String]?
    }
}
