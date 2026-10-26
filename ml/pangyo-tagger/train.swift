// 사용: xcrun swift train.swift <C|W> <crf|bert|elmo>
// Create ML MLWordTagger 학습 → .mlmodel 저장 → 컴파일 → NLModel(iOS 12+/17 OK API)로 로드해 테스트셋 예측·지연 측정.
import CoreML
import CreateML
import Foundation
import NaturalLanguage

struct Row: Codable { let id: String; let tokens: [String]; let labels: [String] }
struct Pred: Codable { let id: String; let pred: [String] }

let args = CommandLine.arguments
let scheme = args.count > 1 ? args[1] : "C"
let algoName = args.count > 2 ? args[2] : "crf"
let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let data = base.appendingPathComponent("data")
let outDir = base.appendingPathComponent("out")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func load(_ split: String) throws -> [Row] {
    try JSONDecoder().decode([Row].self, from: Data(contentsOf: data.appendingPathComponent("\(split).\(scheme).json")))
}

let trainSplit = args.count > 3 ? args[3] : "train"
let train = try load(trainSplit)
let algo: MLWordTagger.ModelAlgorithmType = switch algoName {
case "bert": .transferLearning(.bertEmbedding, revision: 1)
case "elmo": .transferLearning(.elmoEmbedding, revision: 1)
default: .crf(revision: 1)
}
let params = MLWordTagger.ModelParameters(validation: .split(strategy: .automatic), algorithm: algo, language: .korean)
let t0 = Date()
let tagger = try MLWordTagger(trainingData: train.map { (tokens: $0.tokens, labels: $0.labels) }, parameters: params)
let trainSec = Date().timeIntervalSince(t0)
print(
    "train \(scheme)-\(algoName): \(String(format: "%.1f", trainSec))s, train acc \(1 - tagger.trainingMetrics.taggingError), val acc \(1 - tagger.validationMetrics.taggingError)"
)

let name = "PangyoTagger_\(scheme)_\(algoName)" + (trainSplit == "train" ? "" : "-\(trainSplit)")
let mlURL = outDir.appendingPathComponent("\(name).mlmodel")
try? FileManager.default.removeItem(at: mlURL)
try tagger.write(
    to: mlURL,
    metadata: MLModelMetadata(author: "mwonmal-experiment", shortDescription: "판교어 스팬 BIO 태거 (합성 데이터)", version: "0.1")
)

// iOS 앱과 같은 경로: .mlmodel → .mlmodelc → NLModel
let compiled = try MLModel.compileModel(at: mlURL)
let nl = try NLModel(contentsOf: compiled)
print(
    "NLModel loaded: type=\(nl.configuration.type == .sequence ? "sequence" : "classifier") lang=\(String(describing: nl.configuration.language)) rev=\(nl.configuration.revision)"
)

var report: [String: Any] = [
    "trainSec": trainSec,
    "trainAcc": 1 - tagger.trainingMetrics.taggingError,
    "valAcc": 1 - tagger.validationMetrics.taggingError,
]
for split in [
    "test_seen",
    "test_unseen_tpl",
    "test_novel_spelling",
    "test_new_terms",
    "test_novel_x_unseen_tpl",
    "test_new_x_unseen_tpl",
    "test_traps",
    "test_hardneg",
    "test_hardneg3",
] {
    let rows = try load(split)
    var preds: [Pred] = []
    var times: [Double] = []
    for r in rows {
        let s = DispatchTime.now().uptimeNanoseconds
        let p = nl.predictedLabels(forTokens: r.tokens)
        times.append(Double(DispatchTime.now().uptimeNanoseconds - s) / 1e6)
        preds.append(Pred(id: r.id, pred: p))
    }
    try JSONEncoder().encode(preds).write(to: outDir.appendingPathComponent("\(name).\(split).pred.json"))
    times.sort()
    report[split + ".p50ms"] = times[times.count / 2]
    report[split + ".p95ms"] = times[Int(Double(times.count) * 0.95)]
}

let sz = (try? FileManager.default.attributesOfItem(atPath: mlURL.path)[.size] as? Int) ?? 0
report["mlmodelBytes"] = sz
let cdir = try FileManager.default.subpathsOfDirectory(atPath: compiled.path)
var csz = 0
for f in cdir {
    csz += (try? FileManager.default.attributesOfItem(atPath: compiled.appendingPathComponent(f).path)[.size] as? Int) ?? 0
}

report["mlmodelcBytes"] = csz
let rj = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try rj.write(to: outDir.appendingPathComponent("\(name).report.json"))
print(String(data: rj, encoding: .utf8)!)
try? FileManager.default.removeItem(at: compiled)
