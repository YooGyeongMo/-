"""사전 매칭: 유니코드 스칼라 trie (REQ-14, #12).

앱 `DictionaryTrie.swift`(MwonmalIntelligence)와 같은 규칙이다. 정답은
`packages/test-vectors/jargon_match.json`을
양쪽 테스트가 같이 읽는다.

- 인덱스 = 유니코드 스칼라 위치(파이썬 str 인덱스와 같다). 계약 DetectedTerm.startIndex/endIndex.
- 최장 일치. 시작 경계: 앞 글자가 공백이 아니고 같은 문자 종류(한글-한글, 라틴-라틴)면 거기서
  시작하지 않는다.
  끝 경계(ends_word): 라틴 뒤 라틴 금지, 한글 뒤에는 조사·활용 글자만("얼라인을" O, "싱크대" X).
- 대소문자는 ASCII만 접는다.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class Match:
    start: int
    end: int  # 포함하지 않음
    key: str  # 사전 키(표준 표기). 같은 용어의 이형 표기는 같은 키로 모인다.
    matched_text: str


def _fold(ch: str) -> str:
    return chr(ord(ch) + 32) if "A" <= ch <= "Z" else ch


def scalar_class(ch: str) -> str:
    """H(한글) / L(라틴·숫자·&/-:) / P(그 외). Swift `ScalarClass`와 같다."""
    o = ord(ch)
    if 0xAC00 <= o <= 0xD7A3 or 0x3131 <= o <= 0x3163:
        return "H"
    if ch.isalpha() or ch.isnumeric() or ch in "&/-:":
        return "L"
    return "P"


class Trie:
    def __init__(self, entries: dict[str, str]) -> None:
        """entries: 표기 → 사전 키. 빈 표기는 무시한다."""
        self._root: dict[str, object] = {}
        for surface, key in entries.items():
            if not surface:
                continue
            node = self._root
            for ch in surface:
                node = node.setdefault(_fold(ch), {})  # type: ignore[assignment]
            node["$"] = key

    def find(self, text: str) -> list[Match]:
        low = [_fold(c) for c in text]
        out: list[Match] = []
        i = 0
        while i < len(low):
            if i > 0 and not text[i - 1].isspace() and same_word(text[i - 1], text[i]):
                i += 1
                continue
            node: dict[str, object] = self._root
            j = i
            best: tuple[int, str] | None = None
            while j < len(low) and low[j] in node:
                node = node[low[j]]  # type: ignore[assignment]
                j += 1
                key = node.get("$")
                if isinstance(key, str) and ends_word(text, j):
                    best = (j, key)  # 끝 경계를 지키는 것 중 가장 긴 것
            if best is not None:
                out.append(Match(i, best[0], best[1], text[i : best[0]]))
                i = best[0]
            else:
                i += 1
        return out


def same_word(prev: str, ch: str) -> bool:
    """앞 글자와 같은 단어로 이어지는지(같은 문자 종류)."""
    return scalar_class(prev) == scalar_class(ch)


# 한글 용어 바로 뒤에 붙을 수 있는 것(레드팀 2차 B-3: 한 글자가 아니라 문자열로 본다).
# - 활용(뒤에 무엇이 와도 된다): 하다·되다·치다·시키다·받다·드리다·있다·없다·맞추다 …
# - 조사·의존명사(뒤가 끝·공백·문장부호이거나 다른 조사로 이어질 때만): "로" O, "로율"(싱크로율) X.
VERB_STEMS: tuple[str, ...] = (
    "하",
    "해",
    "했",
    "합",
    "한",
    "할",
    "함",
    "되",
    "돼",
    "됐",
    "된",
    "될",
    "됩",
    "치",
    "쳐",
    "쳤",
    "칠",
    "칩",
    "친",
    "시키",
    "시켜",
    "시킨",
    "시킬",
    "시켰",
    "받",
    "드리",
    "드려",
    "드릴",
    "드립",
    "드렸",
    "있",
    "없",
    "맞추",
    "맞춰",
    "좀",
)
PARTICLES: tuple[str, ...] = tuple(
    sorted(
        {
            "을",
            "를",
            "이",
            "가",
            "은",
            "는",
            "도",
            "만",
            "의",
            "로",
            "으로",
            "에",
            "에서",
            "에게",
            "께",
            "과",
            "와",
            "랑",
            "이랑",
            "까지",
            "부터",
            "보다",
            "처럼",
            "마다",
            "뿐",
            "대로",
            "상",
            "별",
            "별로",
            "쪽",
            "용",
            "엔",
            "밖",
            "때",
            "전",
            "후",
            "중",
            "들",
            "이나",
            "나",
            "요",
            "예요",
            "이에요",
            "이야",
            "야",
            "이고",
            "고",
            "이라",
            "라",
            "이며",
            "며",
            "이면",
            "면",
            "인",
            "일",
            "입니다",
            "이죠",
            "죠",
            "이다",
            "다",
            "이었",
            "였",
        },
        key=len,
        reverse=True,
    )
)
FOLLOWER_DEPTH = 3


def _particles_ok(rest: str, depth: int) -> bool:
    """`rest`가 조사 사슬로 시작해 낱말 경계에서 끝나는지."""
    if not rest or scalar_class(rest[0]) != "H":
        return True
    if depth == 0:
        return False
    return any(rest.startswith(p) and _particles_ok(rest[len(p) :], depth - 1) for p in PARTICLES)


def ends_word(text: str, end: int) -> bool:
    """`end` 위치에서 낱말이 끝나는지(끝 경계, ADR-0018 오탐 관문).

    - 라틴·숫자 뒤에 라틴·숫자가 이어지면 아니다. 단 영어 복수 s 하나는 된다("APIs").
    - 한글 뒤: 활용(VERB_STEMS)이면 된다. 아니면 조사 사슬이 낱말 경계에서 끝나야 한다.
    """
    if end >= len(text) or end == 0:
        return True
    last, rest = text[end - 1], text[end:]
    if scalar_class(last) == "L":
        if scalar_class(rest[0]) != "L":
            return True
        return rest[0] == "s" and (len(rest) == 1 or scalar_class(rest[1]) != "L")
    if scalar_class(last) == "H" and scalar_class(rest[0]) == "H":
        return rest.startswith(VERB_STEMS) or _particles_ok(rest, FOLLOWER_DEPTH)
    return True


# 한국어 조사: 앞말의 받침에 따라 모양이 바뀐다. (받침 있을 때, 없을 때)
_JOSA_PAIRS: tuple[tuple[str, str], ...] = (
    ("으로", "로"),
    ("이랑", "랑"),
    ("과", "와"),
    ("을", "를"),
    ("이", "가"),
    ("은", "는"),
)


def _has_batchim(ch: str) -> bool | None:
    o = ord(ch)
    if 0xAC00 <= o <= 0xD7A3:
        return (o - 0xAC00) % 28 != 0
    return None  # 한글 음절이 아니면 판단하지 않는다


def _rieul(ch: str) -> bool:
    o = ord(ch)
    return 0xAC00 <= o <= 0xD7A3 and (o - 0xAC00) % 28 == 8


_LIGHT_VERBS: dict[str, str] = {
    " 쳐주세요": " 해 주세요",
    " 쳐 주세요": " 해 주세요",
    " 쳐 줘": " 해 줘",
    " 쳐줘": " 해 줘",
    " 치죠": " 하죠",
    " 칩시다": " 합시다",
    " 쳐서": " 해서",
    " 쳤어요": " 했어요",
    " 칠게요": " 할게요",
    " 쳐야": " 해야",
    " 치고": " 하고",
}
# 붙여 쓴 꼴("얼라인쳐 주세요")도 같게 본다.
_LIGHT_VERBS.update({k.lstrip(): v for k, v in list(_LIGHT_VERBS.items())})

# 서술격 조사(이다): 받침 없는 말 뒤에서는 '이'가 빠진다("출시이에요" → "출시예요").
_COPULA_DROP = ("이라", "이고", "이야", "이었", "이니", "이면", "이다", "이지", "이죠")

_JOSA_TAILS = ("는", "도", "만", "의")


def _josa_ends(following: str, length: int) -> bool:
    """조사 뒤가 끝·공백·문장부호이거나 흔한 보조사면 조사로 본다("이에요"의 '이'는 조사가
    아니다)."""
    if len(following) == length:
        return True
    nxt = following[length]
    return scalar_class(nxt) != "H" or nxt in _JOSA_TAILS


def fix_josa(replacement: str, following: str) -> str:
    """바꿔 넣은 말 뒤에 붙은 조사를 받침에 맞게 고친다. 바꿀 조사 부분만 돌려준다(없으면 "")."""
    if not replacement or not following:
        return ""
    batchim = _has_batchim(replacement[-1])
    if batchim is None:
        return ""
    for with_b, without_b in _JOSA_PAIRS:
        for current in (with_b, without_b):
            if following.startswith(current) and _josa_ends(following, len(current)):
                if with_b == "으로" and _rieul(replacement[-1]):
                    return "로"  # ㄹ 받침 + 로 ("길로")
                want = with_b if batchim else without_b
                return want if want != current else ""
    return ""


def _same_verb(plain: str, rest: str) -> bool:
    """쉬운 말 끝 동사(맞추기)와 원문 바로 뒤 동사(맞춰)가 같은 말인지 — 첫 음절로 본다."""
    last = plain.rsplit(" ", 1)[-1]
    nxt = rest.lstrip()
    return rest[:1] == " " and len(last) >= 2 and nxt[:1] == last[:1]


def _fix_copula(replacement: str, rest: str) -> tuple[str, int] | None:
    """(새로 쓸 글자, 원문에서 건너뛸 길이). 고칠 것이 없으면 None."""
    batchim = _has_batchim(replacement[-1]) if replacement else None
    if batchim is None:
        return None
    if rest.startswith("이에요") and not batchim:
        return "예요", 3
    if rest.startswith("예요") and batchim:
        return "이에요", 2
    if not batchim:
        for form in _COPULA_DROP:
            if rest.startswith(form):
                return form[1:], len(form)
    return None


def substitute(text: str, matches: list[Match], plain_of: dict[str, str]) -> str:
    """원문의 용어 자리에 쉬운 말을 넣는다. 바로 뒤 조사도 받침에 맞게 고친다."""
    out: list[str] = []
    cursor = 0
    for m in matches:
        plain = plain_of.get(m.key)
        if plain is None:
            continue
        out.append(text[cursor : m.start])
        out.append(plain)
        cursor = m.end
        rest = text[cursor:]
        light = next((lv for lv in _LIGHT_VERBS if rest.startswith(lv)), None)
        if light is not None:
            # "얼라인 쳐주세요" → "방향 맞추기 해 주세요": 판교어에 붙는 '치다'는 '하다'로.
            out.append(_LIGHT_VERBS[light])
            cursor += len(light)
            continue
        if plain.endswith("기") and rest[:1] in ("하", "해", "했", "합", "한", "할"):
            out.append("를 ")  # "방향 맞추기해서" → "방향 맞추기를 해서"(레드팀 2차 B-8)
            continue
        if plain.endswith("기") and _same_verb(plain, rest):
            out[-1] = (
                plain.rsplit(" ", 1)[0] if " " in plain else plain
            )  # "방향 맞추기 맞춰" → "방향 맞춰"
            continue
        copula = _fix_copula(plain, rest)
        if copula is not None:
            out.append(copula[0])
            cursor += copula[1]
            continue
        fixed = fix_josa(plain, rest)
        if fixed:
            for with_b, without_b in _JOSA_PAIRS:
                hit = next(
                    (
                        c
                        for c in (with_b, without_b)
                        if rest.startswith(c) and _josa_ends(rest, len(c))
                    ),
                    None,
                )
                if hit is not None:
                    out.append(fixed)
                    cursor += len(hit)
                    break
    out.append(text[cursor:])
    return "".join(out)
