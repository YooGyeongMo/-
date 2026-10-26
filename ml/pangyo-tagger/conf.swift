// 사용: xcrun swift conf.swift <modelName> — NLModel.predictedLabelHypotheses(forTokens:maximumCount:) (iOS 14+) 로 토큰별 확률 저장
import CoreML
import Foundation
import NaturalLanguage

struct Row: Codable { let id: String; let tokens: [String]; let labels: [String] }
let name = CommandLine.arguments[1]
let scheme = name.split(separator: "_")[1]
let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let compiled = try MLModel.compileModel(at: base.appendingPathComponent("out/\(name).mlmodel"))
let nl = try NLModel(contentsOf: compiled)
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
    let rows = try JSONDecoder().decode([Row].self, from: Data(contentsOf: base.appendingPathComponent("data/\(split).\(scheme).json")))
    var out: [[String: [[String: Double]]]] = []
    var preds: [[String: Any]] = []
    for r in rows {
        out.append([r.id: nl.predictedLabelHypotheses(forTokens: r.tokens, maximumCount: 3)])
        preds.append(["id": r.id, "pred": nl.predictedLabels(forTokens: r.tokens)])
    }
    try JSONSerialization.data(withJSONObject: preds).write(to: base.appendingPathComponent("out/\(name).\(split).pred.json"))
    try JSONSerialization.data(withJSONObject: out).write(to: base.appendingPathComponent("out/\(name).\(split).conf.json"))
}

print("ok")
