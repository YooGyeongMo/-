import Foundation
import IntelligenceTesting
@testable import JargonDetection
import MwonmalIntelligenceCore
import Testing

private func span(_ start: Int, _ end: Int) -> ScalarRange {
    ScalarRange(start: start, end: end)!
}

@Suite("사전 trie")
struct DictionaryTrieTests {
    let trie = DictionaryTrie(terms: ["얼라인", "얼라인먼트", "싱크", "R&R", "ASAP", "킥오프"])

    @Test func longestMatchAndParticles() {
        let text = "얼라인먼트 하고 싱크해서 R&R 정리"
        #expect(trie.find(in: text).map(\.range) == [span(0, 5), span(9, 11), span(14, 17)])
        #expect(trie.find(in: text).first?.termKey == "얼라인먼트")
    }

    @Test func caseInsensitiveAscii() {
        #expect(trie.find(in: "asap 부탁").map(\.matchedText) == ["asap"])
    }

    @Test func startBoundaryBlocksInsideWord() {
        // "인싱크" 안의 "싱크"는 같은 한글 어절 중간이라 시작하지 않는다.
        #expect(trie.find(in: "인싱크로").isEmpty)
        #expect(trie.find(in: "인싱크로", boundary: false).map(\.range) == [span(1, 3)])
    }

    /// 서버(`services/api/app/decode/domain/matching.py`)와 같은 정답 벡터. 규칙이 한쪽만 바뀌면 여기서 깨진다.
    @Test func sharedVectorsMatchServer() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // JargonDetectionTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // MwonmalIntelligence
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // ios-macos
            .deletingLastPathComponent() // apps
            .deletingLastPathComponent() // 저장소 루트
            .appendingPathComponent("packages/test-vectors/jargon_match.json")
        let vectors = try JSONDecoder().decode(MatchVectors.self, from: Data(contentsOf: url))
        let trie = DictionaryTrie(terms: vectors.dictionary.keys)
        for vector in vectors.cases {
            let got: [String] = trie.find(in: vector.text).map { span in
                "\(span.range.start),\(span.range.end),\(vectors.dictionary[span.termKey ?? ""] ?? "?")"
            }
            let want: [String] = vector.spans.map { parts in parts.map(\.text).joined(separator: ",") }
            #expect(got == want, "\(vector.text)")
        }
    }

    @Test func bundledSeedLoads() throws {
        let seed = try HybridJargonDetector.bundledSeedTrie()
        #expect(seed.termCount >= 12)
    }
}

@Suite("토큰화·BIO — 학습 스크립트와 같은 규칙")
struct TokenizerTests {
    @Test func charSchemeMarksWordStarts() {
        let out = CharTokenizer().tokenize("R&R 정리")
        #expect(out.tokens == ["▁R", "&", "R", "▁정", "리"])
        #expect(out.offsets == [0, 1, 2, 4, 5])
    }

    @Test func bioDecodeOrphanInsideStartsSpan() {
        let labels = ["O", "I-T", "I-T", "O", "B-T", "B-T", "I-T"]
        #expect(BIODecoder.ranges(labels: labels, offsets: Array(0 ..< 7)) == [span(1, 3), span(4, 5), span(5, 7)])
    }
}

@Suite("하이브리드 병합(longestWins)")
struct HybridTests {
    struct ScriptedTagger: SequenceTagging {
        let engine = EngineTag("tagger/fake#p1")!
        let labels: [String]
        func tag(tokens: [String]) async throws(IntelligenceError) -> [(label: String, probability: Double)] {
            labels.map { ($0, 0.95) }
        }
    }

    @Test func modelWinsWhenItCoversLongerNewSpelling() async throws {
        // "얼라인업" — 사전은 "얼라인"(0..3), 모델은 "얼라인업"(0..4)을 잡는다 → 모델 승.
        let text = "얼라인업 해요"
        let tagger = ScriptedTagger(labels: ["B-T", "I-T", "I-T", "I-T", "O", "O"])
        let detector = HybridJargonDetector(trie: DictionaryTrie(terms: ["얼라인"]), tagger: tagger)
        let res = try await detector.detect(in: text)
        #expect(res.spans.map(\.range) == [span(0, 4)])
        #expect(res.spans.first?.origin == .model)
        #expect(res.engine.description == "tagger/fake#p1")
    }

    @Test func dictionaryKeptOnPartialOverlap() {
        let dict = [JargonSpan(range: span(0, 3), matchedText: "abc", origin: .dictionary)]
        let model = [JargonSpan(range: span(2, 6), matchedText: "cdef", origin: .model)]
        #expect(HybridJargonDetector.mergeLongest(dictionary: dict, model: model).map(\.range) == [span(0, 3)])
    }

    @Test func noTaggerMeansDictionaryOnlyTag() async throws {
        let detector = HybridJargonDetector(trie: DictionaryTrie(terms: ["킥오프"]))
        let res = try await detector.detect(in: "킥오프 합시다")
        #expect(res.engine == .dictionaryOnly)
        #expect(res.spans.count == 1)
    }
}

/// 실험 산출물(합성 데이터로 학습한 PangyoTagger_C_crf)로 **Swift 추론 경로 = Python 실험 경로**를 확인한다.
@Suite("Core ML 태거 패리티 (실험 모델 fixture)")
struct CoreMLParityTests {
    struct Fixture: Decodable {
        let rows: [ParityRow]
    }

    static func load() throws -> (Fixture, URL) {
        let dir = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: dir.appendingPathComponent("parity.json")))
        return (fixture, dir.appendingPathComponent("PangyoTagger_C_crf.mlmodelc"))
    }

    @Test func tokenizerMatchesTrainingTokens() throws {
        let (fixture, _) = try Self.load()
        for row in fixture.rows {
            #expect(CharTokenizer().tokenize(row.text).tokens == row.tokens, "\(row.id)")
        }
    }

    @Test func predictionsMatchExperimentAndF1() async throws {
        let (fixture, url) = try Self.load()
        let tagger = try await CoreMLSequenceTagger(compiledModelURL: url, engine: #require(EngineTag("tagger/pangyo-c-crf-v0#p1")))
        var score = SpanScore()
        for row in fixture.rows {
            let tok = CharTokenizer().tokenize(row.text)
            let labels = try await tagger.tag(tokens: tok.tokens).map(\.label)
            #expect(labels == row.expectedPred, "\(row.id)")
            let pred = Set(BIODecoder.ranges(labels: labels, offsets: tok.offsets))
            score.add(gold: Set(row.gold.compactMap { ScalarRange(start: $0[0], end: $0[1]) }), predicted: pred)
        }
        print("[parity] n=\(fixture.rows.count) model-only F1=\(String(format: "%.3f", score.f1Score))")
        #expect(score.f1Score > 0.7)
    }

    @Test func missingModelFileIsTypedError() async {
        await #expect(throws: IntelligenceError.unavailable(.modelAssetMissing)) {
            _ = try await TaggerModelLocator.resolve(.file(URL(fileURLWithPath: "/nonexistent/x.mlmodelc")))
        }
    }
}

/// parity.json 한 줄.
struct ParityRow: Decodable {
    let id: String
    let text: String
    let tokens: [String]
    let gold: [[Int]]
    let expectedPred: [String]
}

/// `packages/test-vectors/jargon_match.json` 모양. spans 항목은 [시작, 끝, 키](숫자·문자 섞임).
private struct MatchVectors: Decodable {
    let dictionary: [String: String]
    let cases: [MatchCase]
}

private struct MatchCase: Decodable {
    let text: String
    let spans: [[MatchPart]]
}

private struct MatchPart: Decodable {
    let text: String

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            text = String(number)
        } else {
            text = try container.decode(String.self)
        }
    }
}
