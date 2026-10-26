// 개발 Mac 전용 평가 CLI. 앱에는 들어가지 않는다.
//
//   swift run mwintel-eval detect <dataset.jsonl> [<model.mlmodelc> <engine-tag>]   > preds.jsonl
//   swift run mwintel-eval fm     <dataset.jsonl>                                    > drafts.jsonl
//
// 출력 JSONL 은 eval/run.py 의 "device-precomputed" 어댑터가 읽는다(채점은 Python 한 곳에서만 — 채점기 이중화 금지).
// stderr 에는 스팬 F1 요약만 쓴다(원문 출력 없음).
import Foundation
import FoundationModelsEngine
import JargonDetection
import MwonmalIntelligenceCore

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("mwintel-eval: \(msg)\n".utf8))
    exit(2)
}

let args = CommandLine.arguments
guard args.count >= 3 else { fail("usage: mwintel-eval detect|fm <dataset.jsonl> [model.mlmodelc tag]") }
let items: [EvalItem]
do {
    items = try EvalJSONL.decode(Data(contentsOf: URL(fileURLWithPath: args[2])))
} catch {
    fail("데이터셋 읽기 실패: \(error)")
}

let enc = JSONEncoder()
enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

/// JSONEncoder 출력은 항상 UTF-8이다.
func jsonLine(_ value: some Encodable) throws -> String {
    try String(bytes: enc.encode(value), encoding: .utf8) ?? ""
}

struct DraftRow: Encodable {
    let id: String
    let engine: String
    let resultText: String?
    let intentType: String?
    let error: String?
}

switch args[1] {
case "detect":
    var tagger: (any SequenceTagging)?
    if args.count >= 5 {
        guard let tag = EngineTag(args[4]) else { fail("잘못된 엔진 태그 \(args[4])") }
        do {
            tagger = try await CoreMLSequenceTagger(compiledModelURL: URL(fileURLWithPath: args[3]), engine: tag)
        } catch {
            fail("모델 로드 실패: \(error)")
        }
    }
    let detector = try HybridJargonDetector(trie: HybridJargonDetector.bundledSeedTrie(), tagger: tagger)
    var score = SpanScore()
    for item in items {
        let result = try await detector.detect(in: item.sourceText)
        score.add(gold: item.goldRanges, predicted: Set(result.spans.map(\.range)))
        try print(jsonLine(EvalPrediction(id: item.id, result: result)))
    }
    FileHandle.standardError.write(Data(String(
        format: "engine=%@ n=%d P=%.3f R=%.3f F1=%.3f\n",
        detector.engine.description,
        items.count,
        score.precision,
        score.recall,
        score.f1Score
    ).utf8))
case "fm":
    if let reason = FMProbe.liveModelReason {
        fail("FM 사용 불가: \(reason)")
    }
    // 평가 CLI 는 태그 게이트를 열어 둔다(측정이 목적). 앱 정책은 기본 닫힘.
    guard let engine = FMEngineFactory.makeIfSupported(policy: FMGatePolicy(enabledModelKeys: ["fm/apple-26.0", "fm/apple-26.4"])) else {
        fail("OS < 26")
    }
    for item in items {
        let req = DraftRequest(text: item.sourceText, source: SourceKind(rawValue: item.sourceType) ?? .message)
        do {
            let draft = try await engine.draft(for: req)
            try print(jsonLine(DraftRow(
                id: item.id,
                engine: draft.engine.description,
                resultText: draft.resultText,
                intentType: draft.intent?.rawValue,
                error: nil
            )))
        } catch {
            try await print(jsonLine(DraftRow(
                id: item.id,
                engine: engine.engine.description,
                resultText: nil,
                intentType: nil,
                error: "\(error)"
            )))
        }
    }
default:
    fail("알 수 없는 명령 \(args[1])")
}
