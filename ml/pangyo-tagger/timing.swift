// 사용: xcrun swift timing.swift <modelName> — 단독 실행 지연(로드 포함/제외), test_seen+test_unseen_tpl
import CoreML
import Foundation
import NaturalLanguage

struct Row: Codable { let id: String; let tokens: [String]; let labels: [String] }
let name = CommandLine.arguments[1]; let scheme = name.split(separator: "_")[1]
let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let compiled = try MLModel.compileModel(at: base.appendingPathComponent("out/\(name).mlmodel"))
let t0 = Date(); let nl = try NLModel(contentsOf: compiled); let load = Date().timeIntervalSince(t0) * 1000
var rows: [Row] = []
for s in ["test_seen", "test_unseen_tpl"] {
    rows += try JSONDecoder().decode(
        [Row].self,
        from: Data(contentsOf: base.appendingPathComponent("data/\(s).\(scheme).json"))
    )
}

let w0 = Date(); _ = nl.predictedLabels(forTokens: rows[0].tokens); let first = Date().timeIntervalSince(w0) * 1000
var ts: [Double] = []
for r in rows {
    let s = Date(); _ = nl.predictedLabels(forTokens: r.tokens); ts.append(Date().timeIntervalSince(s) * 1000)
}

ts.sort()
print(
    name,
    String(
        format: "load %.1fms first %.1fms p50 %.3fms p95 %.3fms (n=%d)",
        load,
        first,
        ts[ts.count / 2],
        ts[Int(Double(ts.count) * 0.95)],
        ts.count
    )
)
