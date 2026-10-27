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

    /// `boundary == true`: 앞 글자와 같은 문자 종류(한글-한글, 라틴-라틴)면 그 위치에서 시작하지 않고,
    /// 끝 경계도 본다(서버 `matching.ends_word`와 같다): 라틴 뒤에 라틴이 오면 아니고, 한글 뒤에는 조사·활용 글자만
    /// 올 수 있다("얼라인을" O, "싱크대" X). 정답은 `packages/test-vectors/jargon_match.json`.
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
                if let term = nodes[node].term, !boundary || Self.endsWord(raw, at: probe) {
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

    /// 한글 용어 바로 뒤 — 활용(뒤에 무엇이 와도 됨). 서버 `matching.VERB_STEMS`와 같다.
    static let verbStems: [String] = [
        "하", "해", "했", "합", "한", "할", "함", "되", "돼", "됐", "된", "될", "됩", "치", "쳐", "쳤", "칠", "칩", "친",
        "시키", "시켜", "시킨", "시킬", "시켰", "받", "드리", "드려", "드릴", "드립", "드렸", "있", "없", "맞추", "맞춰", "좀",
    ]

    /// 조사·의존명사 — 낱말 경계에서 끝나는 사슬일 때만. 서버 `matching.PARTICLES`와 같다(긴 것부터).
    static let particles: [String] = [
        "을", "를", "이", "가", "은", "는", "도", "만", "의", "로", "으로", "에", "에서", "에게", "께",
        "과", "와", "랑", "이랑", "까지", "부터", "보다", "처럼", "마다", "뿐", "대로", "상", "별", "별로",
        "쪽", "용", "엔", "밖", "때", "전", "후", "중", "들", "이나", "나", "요", "예요", "이에요",
        "이야", "야", "이고", "고", "이라", "라", "이며", "며", "이면", "면", "인", "일", "입니다",
        "이죠", "죠", "이다", "다", "이었", "였",
    ].sorted { $0.unicodeScalars.count > $1.unicodeScalars.count }

    private static func starts(_ raw: ArraySlice<Unicode.Scalar>, with word: String) -> Bool {
        let w = Array(word.unicodeScalars)
        return raw.count >= w.count && Array(raw.prefix(w.count)) == w
    }

    private static func particlesOK(_ rest: ArraySlice<Unicode.Scalar>, depth: Int) -> Bool {
        guard let first = rest.first, ScalarClass(first) == .hangul else { return true }
        guard depth > 0 else { return false }
        return particles.contains { p in
            starts(rest, with: p) && particlesOK(rest.dropFirst(p.unicodeScalars.count), depth: depth - 1)
        }
    }

    /// `end`에서 낱말이 끝나는지(서버 `ends_word`와 같은 규칙).
    private static func endsWord(_ raw: [Unicode.Scalar], at end: Int) -> Bool {
        guard end > 0, end < raw.count else { return true }
        let last = ScalarClass(raw[end - 1]), next = ScalarClass(raw[end])
        if last == .latin {
            guard next == .latin else { return true }
            return raw[end] == "s" && (end + 1 == raw.count || ScalarClass(raw[end + 1]) != .latin)
        }
        if last == .hangul, next == .hangul {
            let rest = raw[end...]
            return verbStems.contains { starts(rest, with: $0) } || particlesOK(rest, depth: 3)
        }
        return true
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
