// 앱(Platform/JargonDetector)에 들어갈 토큰화 스케치: 유니코드 스칼라 인덱스 기준 → 서버 startIndex/endIndex 와 같은 좌표계(REQ-14)
import Foundation

enum Cls { case h, l, p }
func cls(_ u: Unicode.Scalar) -> Cls {
    let v = u.value
    if (0xAC00 ... 0xD7A3).contains(v) || (0x3131 ... 0x3163).contains(v) {
        return .h
    }
    if CharacterSet.alphanumerics.contains(u) || "&/-:".unicodeScalars.contains(u) {
        return .l
    }
    return .p
}

func wordTokens(_ s: String) -> [(String, Int, Int)] {
    let u = Array(s.unicodeScalars); var out: [(String, Int, Int)] = []; var i = 0
    while i < u.count {
        if CharacterSet.whitespacesAndNewlines.contains(u[i]) {
            i += 1; continue
        }
        let c = cls(u[i]); var j = i + 1
        while j < u.count, !CharacterSet.whitespacesAndNewlines.contains(u[j]), cls(u[j]) == c, c != .p {
            j += 1
        }
        var t = String.UnicodeScalarView(); t.append(contentsOf: u[i ..< j]); out.append((String(t), i, j)); i = j
    }
    return out
}

func charTokens(_ s: String) -> [(String, Int, Int)] {
    let u = Array(s.unicodeScalars); var out: [(String, Int, Int)] = []
    for (i, ch) in u.enumerated() where !CharacterSet.whitespacesAndNewlines.contains(ch) {
        let sp = i == 0 || CharacterSet.whitespacesAndNewlines.contains(u[i - 1])
        out.append(((sp ? "▁" : "") + String(ch), i, i + 1))
    }
    return out
}

struct Row: Codable { let id: String; let tokens: [String]; let labels: [String] }
struct Src: Codable { let id: String; let text: String }
let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
var bad = 0, n = 0
for split in ["test_seen", "test_unseen_tpl", "test_novel_spelling", "test_new_terms", "test_hardneg3", "train"] {
    let lines = try String(contentsOf: base.appendingPathComponent("data/\(split).jsonl"), encoding: .utf8).split(separator: "\n")
    let src = try lines.map { try JSONDecoder().decode(Src.self, from: Data($0.utf8)) }
    for (scheme, fn) in [("C", charTokens), ("W", wordTokens)] as [(String, (String) -> [(String, Int, Int)])] {
        let rows = try JSONDecoder().decode([Row].self, from: Data(contentsOf: base.appendingPathComponent("data/\(split).\(scheme).json")))
        for (r, s) in zip(rows, src) {
            n += 1; if fn(s.text).map(\.0) != r.tokens {
                bad += 1; if bad < 4 {
                    print(scheme, s.text)
                }
            }
        }
    }
}

print("swift tokenizer vs python: \(n) sentences, mismatch \(bad)")
