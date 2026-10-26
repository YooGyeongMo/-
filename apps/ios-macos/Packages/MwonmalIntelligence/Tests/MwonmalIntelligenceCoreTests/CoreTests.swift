import Foundation
import IntelligenceTesting
@testable import MwonmalIntelligenceCore
import Testing

@Suite("EngineTag — ADR-0007 §4-5 출처 규약")
struct EngineTagTests {
    @Test(arguments: [
        "fm/apple-26.4#p1",
        "fm/apple-27-core#p1",
        "tagger/pangyo-c-crf-v1#p2",
        "none/dictionary#p1",
        "gemini/gemini-2.5-flash#p1",
    ])
    func roundTrip(_ raw: String) throws {
        let tag = try #require(EngineTag(raw))
        #expect(tag.description == raw)
        let data = try JSONEncoder().encode(tag)
        #expect(try JSONDecoder().decode(EngineTag.self, from: data) == tag)
    }

    @Test(arguments: [
        "fm/apple-26.4",
        "FM/apple#p1",
        "fm/#p1",
        "fm/apple#1",
        "fm/apple#p01",
        "fm/a b#p1",
        "tagger/" + String(repeating: "x", count: 45) + "#p1",
    ])
    func rejects(_ raw: String) {
        #expect(EngineTag(raw) == nil)
    }

    @Test func modelKeyDropsPromptVersion() {
        #expect(EngineTag("fm/apple-27-adv#p3")?.modelKey == "fm/apple-27-adv")
    }
}

@Suite("ScalarRange — 유니코드 스칼라 인덱스(서버·eval과 같은 단위)")
struct ScalarRangeTests {
    @Test func koreanAndAscii() throws {
        let text = "이번 스프린트 얼라인 한번 하고 다음 주에 킥오프 밀죠."
        #expect(try text.substring(scalars: #require(ScalarRange(start: 8, end: 11))) == "얼라인")
        #expect(try text.substring(scalars: #require(ScalarRange(start: 24, end: 27))) == "킥오프")
    }

    @Test func emojiAndCombiningDoNotShiftScalars() throws {
        // 👍🏻 = 스칼라 2개, 그래핌 1개. 서버 인덱스는 스칼라 기준이다.
        let text = "👍🏻 ASAP 부탁"
        let range = try #require(ScalarRange(start: 3, end: 7))
        #expect(text.substring(scalars: range) == "ASAP")
        #expect(text.indexRange(scalars: range).map { String(text[$0]) } == "ASAP")
        // 그래핌 한가운데를 자르는 구간은 화면 범위로 바꾸지 않는다(형광펜 안 그림).
        #expect(try text.indexRange(scalars: #require(ScalarRange(start: 0, end: 1))) == nil)
    }

    @Test func invalid() {
        #expect(ScalarRange(start: 3, end: 3) == nil)
        #expect(ScalarRange(start: -1, end: 2) == nil)
    }
}

@Suite("평가 — eval/dataset 형식과 스팬 F1")
struct EvaluationTests {
    static let readmeSample = #"""
    # 주석 줄은 건너뛴다
    {"id": "v1-0001", "direction": "JARGON_TO_PLAIN", "sourceType": "MESSAGE", \#
    "sourceText": "이번 스프린트 얼라인 한번 하고 다음 주에 킥오프 밀죠.", \#
    "gold": {"resultText": "…", "jargonCount": 2, "intentType": "DECISION", "nuance": null, "actionItems": [], \#
    "detectedTerms": [{"termId": 3, "termKo": "얼라인", "plainKo": "방향 맞추기", "matchedText": "얼라인", "startIndex": 8, "endIndex": 11}, \#
    {"termId": null, "termKo": "킥오프", "plainKo": "시작 회의", "matchedText": "킥오프", "startIndex": 24, "endIndex": 27}]}, \#
    "meta": {"source": "synthetic"}}

    """#

    @Test func decodesServerEvalFormat() throws {
        let items = try EvalJSONL.decode(Data(Self.readmeSample.utf8))
        #expect(items.count == 1)
        let item = try #require(items.first)
        for term in item.gold.detectedTerms {
            // gold 인덱스가 우리 스칼라 함수와 맞는지 = 단위 일치 검증.
            let range = try #require(ScalarRange(start: term.startIndex, end: term.endIndex))
            #expect(item.sourceText.substring(scalars: range) == term.matchedText)
        }
    }

    @Test func microF1() {
        var score = SpanScore()
        let span = { (start: Int, end: Int) in ScalarRange(start: start, end: end)! }
        score.add(gold: [span(0, 3), span(5, 8)], predicted: [span(0, 3), span(9, 10)])
        score.add(gold: [], predicted: [])
        #expect(score.truePositives == 1 && score.predicted == 2 && score.gold == 2)
        #expect(abs(score.f1Score - 0.5) < 1e-9)
    }
}

@Suite("텔레메트리 — 원문이 실릴 자리가 없다")
struct TelemetryTests {
    @Test func eventHasNoFreeTextField() {
        let event = IntelligenceEvent(
            kind: .detect,
            engine: .dictionaryOnly,
            outcome: .success,
            latency: .milliseconds(12),
            inputLength: 140,
            spanCount: 2
        )
        // 저장 프로퍼티 중 String 은 없다(EngineTag 안의 track/model 은 규약 문자열).
        let strings = Mirror(reflecting: event).children.filter { $0.value is String }
        #expect(strings.isEmpty)
        #expect(event.inputLengthBucket == .upTo300)
        #expect(event.latencyMilliseconds == 12)
    }

    @Test func instrumentedDetectorRecordsWithoutText() async throws {
        let canary = Canary.make()
        let sink = RecordingEventSink()
        let span = try JargonSpan(range: #require(ScalarRange(start: 0, end: 4)), matchedText: "ASAP", origin: .dictionary)
        let detector = InstrumentedDetector(FakeJargonDetector(result: .success([span])), sink: sink)
        _ = try await detector.detect(in: "ASAP \(canary)")
        #expect(sink.events.count == 1)
        #expect(!String(describing: sink.events).contains(canary))
    }
}

@Suite("프라이버시 — 패키지 소스에 네트워크 코드 0 (ADR-0008)")
struct NoNetworkTests {
    @Test func sourcesHaveNoNetworkingAPIs() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let forbidden = ["URLSession", "URLRequest", "import Network", "NWConnection", "CFNetwork", "PrivateCloudCompute"]
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(files.count >= 8)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let code = text.split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && !$0.contains("///") }
            for word in forbidden {
                #expect(!code.contains { $0.contains(word) }, "\(file.lastPathComponent)에 \(word)")
            }
        }
    }
}
