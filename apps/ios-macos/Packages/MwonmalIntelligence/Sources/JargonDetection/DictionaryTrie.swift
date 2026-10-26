public import MwonmalIntelligenceCore

internal import Foundation

/// 유니코드 스칼라 trie. 최장 일치 + 시작 경계 규칙(실험 `pangyo-tagger/score.py` `Trie.find(boundary=True)`와 같은 동작).
/// 값 타입이고 불변이라 `Sendable`. 사전 갱신은 새 인스턴스로 교체한다.
public struct DictionaryTrie: Sendable {
    private struct Node: Sendable {
        var children: [Unicode.Scalar: Int] = [:]
        var term: String?
    }

    private var nodes: [Node] = [Node()]
    public private(set) var termCount = 0

    public init(terms: some Sequence<String>) {
        for term in terms where !term.isEmpty {
            insert(term)
        }
    }

    private mutating func insert(_ term: String) {
        var node = 0
        for scalar in Self.fold(term) {
            if let next = nodes[node].children[scalar] {
                node = next
            } else {
                nodes.append(Node())
                nodes[node].children[scalar] = nodes.count - 1
                node = nodes.count - 1
            }
        }
        if nodes[node].term == nil {
            termCount += 1
        }
        nodes[node].term = term
    }

    /// `boundary == true`: 앞 글자와 같은 문자 종류(한글-한글, 라틴-라틴)면 그 위치에서 시작하지 않는다.
    /// 끝 경계는 보지 않는다(한국어 조사·활용: "얼라인을", "싱크해서").
    public func find(in text: String, boundary: Bool = true) -> [JargonSpan] {
        let raw = Array(text.unicodeScalars)
        let low = raw.map(Self.fold)
        var out: [JargonSpan] = []
        var cursor = 0
        while cursor < low.count {
            if boundary, Self.continuesWord(raw, at: cursor) {
                cursor += 1
                continue
            }
            var node = 0, probe = cursor
            var best: (end: Int, term: String)?
            while probe < low.count, let next = nodes[node].children[low[probe]] {
                node = next
                probe += 1
                if let term = nodes[node].term {
                    best = (probe, term)
                }
            }
            if let best, let range = ScalarRange(start: cursor, end: best.end) {
                let matched = String(String.UnicodeScalarView(raw[cursor ..< best.end]))
                out.append(JargonSpan(range: range, matchedText: matched, origin: .dictionary, termKey: best.term))
                cursor = best.end
            } else {
                cursor += 1
            }
        }
        return out
    }

    /// 앞 글자가 공백이 아니고 같은 문자 종류면 단어 중간이다(시작 경계 아님).
    private static func continuesWord(_ raw: [Unicode.Scalar], at index: Int) -> Bool {
        index > 0 && !raw[index - 1].properties.isWhitespace && ScalarClass(raw[index - 1]) == ScalarClass(raw[index])
    }

    private static func fold(_ text: String) -> [Unicode.Scalar] {
        text.unicodeScalars.map(fold)
    }

    /// 대소문자만 접는다(ASCII). 한글은 그대로. Python `str.lower()`와 ASCII 범위에서 같다.
    private static func fold(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        ("A" ... "Z").contains(scalar) ? Unicode.Scalar(scalar.value + 32)! : scalar
    }
}

/// 실험 `prep.py cls()`와 같은 문자 종류: H(한글) / L(라틴·숫자·`&/-:`) / P(그 외).
enum ScalarClass: Equatable {
    case hangul, latin, other

    init(_ scalar: Unicode.Scalar) {
        switch scalar.value {
        case 0xAC00 ... 0xD7A3, 0x3131 ... 0x3163: self = .hangul
        default:
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil || "&/-:".unicodeScalars.contains(scalar) {
                self = .latin
            } else {
                self = .other
            }
        }
    }
}
