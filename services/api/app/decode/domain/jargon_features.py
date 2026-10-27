"""문맥 판교어 탐지기(글자 CRF, ADR-0023)의 순수 부분: 특징 만들기 · 스팬 복원 · 관문 · 병합.

학습(`ml/pangyo-tagger/train_crf.py`)과 서버 추론이 **이 파일 하나**를 같이 쓴다. 특징을 바꾸면
`FEATURE_VERSION`을 올리고 모델을 다시 학습한다(버전이 다르면 서버는 모델을 쓰지 않는다).

- 토큰 = 공백이 아닌 유니코드 스칼라 1개(ADR-0018 실험의 "C" 방식). 토큰 k ↔ 원문 인덱스
  `positions[k]` 1:1 이라 스팬 복원에 손실이 없다. 인덱스는 파이썬 str 인덱스 = 계약
  DetectedTerm.startIndex/endIndex 와 같은 좌표계.
- CRF 는 GPT 같은 생성 모델이 아니다. 앞뒤 글자 창(±3)·글자 n-gram·어절 안 위치를 보고 글자마다
  B/I/O 라벨의 **주변 확률(marginal)**을 낸다. 스팬 확신도 = 스팬 안 글자 확률의 최솟값.
"""

from collections.abc import Sequence
from dataclasses import dataclass

from app.decode.domain.matching import ends_word, same_word, scalar_class
from app.decode.domain.model import Span

FEATURE_VERSION = "c1"
LABEL_B, LABEL_I, LABEL_O = "B-T", "I-T", "O"
LABELS = (LABEL_B, LABEL_I, LABEL_O)

WINDOW = 3
MIN_SPAN = 2  # 한 글자 용어는 사전도 넣지 않는다(린·핑·콜, seed_terms 머리말)
MAX_SPAN = 30  # matched_text 열은 100자. 판교어 한 개가 이보다 길 일은 없다
_PREFIX_MAX = 5
_WORD_MAX = 8

# 모델이 찾아도 버리는 평범한 말(음성 사전). 사전이 "판교어인 것"을 우선하듯 "판교어가 아닌 것"도
# 아는 만큼은 모델보다 우선한다. ① 서버 사전이 일부러 뺀 말(seed_terms 머리말) ② 사무실·일상에서
# 흔한 외래어. 모델은 "조사 붙은 외래어 = 판교어"로 넘겨짚는 경향이 있다(ADR-0023 §결과).
# 평가셋 test_fresh_neg 의 어휘와는 겹치지 않게 둔다(train_crf.py 가 확인).
ORDINARY_WORDS: frozenset[str] = frozenset(
    """
    회고 배포 지표 우선순위 스프린트 이슈 미팅 오픈 픽스 프로세스 워크샵 시안 초안 요구사항 자동화
    투명성 전환율 병목 가시성 기획서 결과물 린 핑 콜
    회의록 회의실 보고서 이메일 메일 마우스 키보드 모니터 노트북 컴퓨터 프린터 복사기 스마트폰
    태블릿 엑셀 워드 파워포인트 카톡 메신저 캘린더 백업 로그인 업데이트 비밀번호 계정 파일 폴더
    링크 마케팅 세미나 엘리베이터 에어컨 카메라 택시 버스 지하철 커피 인터넷 앱
    """.split()
)


def _fold(ch: str) -> str:
    return chr(ord(ch) + 32) if "A" <= ch <= "Z" else ch


def char_kind(ch: str) -> str:
    """H(한글) / A(라틴 글자) / D(숫자) / S(&/-: 같은 용어 안 기호) / P(그 밖)."""
    o = ord(ch)
    if 0xAC00 <= o <= 0xD7A3 or 0x3131 <= o <= 0x3163:
        return "H"
    if ch.isascii() and ch.isalpha():
        return "A"
    if ch.isdigit():
        return "D"
    if ch in "&/-:":
        return "S"
    return "P"


def _batchim(ch: str) -> str:
    o = ord(ch)
    if 0xAC00 <= o <= 0xD7A3:
        return "1" if (o - 0xAC00) % 28 else "0"
    return "-"


def positions(text: str) -> list[int]:
    """토큰 k 의 원문 인덱스(공백이 아닌 글자만)."""
    return [i for i, ch in enumerate(text) if not ch.isspace()]


def features(text: str) -> list[list[str]]:
    """토큰마다 특징 문자열 목록. 값은 모두 1(이진 특징)."""
    pos = positions(text)
    n = len(pos)
    if n == 0:
        return []
    starts = [i == 0 or text[i - 1].isspace() for i in pos]
    toks = [("▁" if s else "") + _fold(text[i]) for s, i in zip(starts, pos, strict=True)]
    kinds = [char_kind(text[i]) for i in pos]
    # 어절 경계(토큰 번호): 각 토큰이 속한 어절의 첫·끝 토큰
    word_first = [0] * n
    word_last = [0] * n
    first = 0
    for k in range(n):
        if starts[k]:
            first = k
        word_first[k] = first
    last = n - 1
    for k in range(n - 1, -1, -1):
        word_last[k] = last
        if starts[k]:
            last = k - 1

    def tok(k: int) -> str:
        if k < 0:
            return "<s>"
        if k >= n:
            return "</s>"
        return toks[k]

    def kind(k: int) -> str:
        return kinds[k] if 0 <= k < n else "#"

    out: list[list[str]] = []
    for k in range(n):
        ch = text[pos[k]]
        a, b = word_first[k], word_last[k]
        word = "".join(_fold(text[pos[j]]) for j in range(a, b + 1))
        at = k - a
        f = [
            "bias",
            f"c={toks[k]}",
            f"k={kinds[k]}",
            f"j={_batchim(ch)}",
            f"p={min(at, 4)}",
            f"q={min(b - k, 4)}",
            f"kk={kind(k - 2)}{kind(k - 1)}{kinds[k]}{kind(k + 1)}{kind(k + 2)}",
            f"b-={tok(k - 1)}|{toks[k]}",
            f"b+={toks[k]}|{tok(k + 1)}",
            f"t-={tok(k - 2)}|{tok(k - 1)}|{toks[k]}",
            f"t0={tok(k - 1)}|{toks[k]}|{tok(k + 1)}",
            f"t+={toks[k]}|{tok(k + 1)}|{tok(k + 2)}",
            f"pre={word[max(0, at - _PREFIX_MAX + 1) : at + 1]}",
            f"suf={word[at : at + _PREFIX_MAX]}",
        ]
        if ch.isupper():
            f.append("up")
        if len(word) <= _WORD_MAX:
            f.append(f"w={word}")
        for d in range(1, WINDOW + 1):
            f.append(f"c-{d}={tok(k - d)}")
            f.append(f"c+{d}={tok(k + d)}")
        out.append(f)
    return out


@dataclass(frozen=True)
class Candidate:
    """모델이 찾은 스팬 후보. confidence = 스팬 글자들의 라벨 주변 확률 최솟값."""

    start: int
    end: int  # 포함하지 않음
    confidence: float


def decode(pos: Sequence[int], labels: Sequence[str], probs: Sequence[float]) -> list[Candidate]:
    """BIO 라벨 → 스팬. I 가 B 없이 시작해도 스팬으로 본다. 스팬은 공백을 건너 이어질 수 있다
    ("트레이드 오프")."""
    out: list[Candidate] = []
    cur: list[int] | None = None  # [첫 토큰, 끝 토큰]

    def close() -> None:
        if cur is not None:
            a, b = cur
            out.append(Candidate(pos[a], pos[b] + 1, min(probs[a : b + 1])))

    for k, lab in enumerate(labels):
        if lab == LABEL_B or (lab == LABEL_I and cur is None):
            close()
            cur = [k, k]
        elif lab == LABEL_I and cur is not None:
            cur[1] = k
        else:
            close()
            cur = None
    close()
    return out


def acceptable(text: str, start: int, end: int, ordinary: frozenset[str] = ORDINARY_WORDS) -> bool:
    """사전과 같은 오탐 관문(ADR-0018): 어절·문자 종류 경계에서 시작하고 끝나야 한다.

    - 길이 2~30, 글자는 한글·라틴·숫자·용어 기호(&/-:)·공백만(이모지·문장부호가 끼면 버린다).
    - 시작: 문장 처음이거나 앞 글자가 공백이거나 문자 종류가 바뀌는 곳("싱크대"의 "크대" X).
    - 끝: `matching.ends_word`(뒤에 조사·활용만 오거나 낱말이 끝남. "디벨롭먼트"의 "디벨롭" X).
    - 공백은 낱말 사이 한 칸만(줄바꿈·탭 X). 숫자·자모만으로 된 스팬, 평범한 말 목록
      (`ordinary`)에 있는 스팬은 버린다.
    """
    if not (0 <= start < end <= len(text)) or not (MIN_SPAN <= end - start <= MAX_SPAN):
        return False
    piece = text[start:end]
    if piece != piece.strip() or "  " in piece or any(c.isspace() and c != " " for c in piece):
        return False  # 줄바꿈·탭·겹공백을 건너는 스팬은 한 낱말이 아니다
    if not any("가" <= c <= "힣" or (c.isascii() and c.isalpha()) for c in piece):
        return False  # 숫자만·자모만("ㅋㅋ")
    if "".join(_fold(c) for c in piece) in ordinary:
        return False
    if any(not c.isspace() and scalar_class(c) == "P" for c in piece):
        return False
    if start > 0 and not text[start - 1].isspace() and same_word(text[start - 1], text[start]):
        return False
    return ends_word(text, end)


def add_model_spans(
    text: str,
    spans: Sequence[Span],
    candidates: Sequence[Candidate],
    threshold: float,
    ordinary: frozenset[str] = ORDINARY_WORDS,
) -> list[Span]:
    """이미 잡힌 스팬(사전·AI)은 그대로 두고, 겹치지 않는 모델 스팬만 더한다.

    모델 스팬은 사전에 없는 말이라 term_id=None, term_ko=원문 표기, plain_ko=""(뜻 모름),
    confidence = 모델 확률. 결과는 시작 위치 순.
    """
    taken = [(s.start, s.end) for s in spans]
    out = list(spans)
    for c in sorted(candidates, key=lambda c: (c.start, -c.end)):
        if c.confidence < threshold or not acceptable(text, c.start, c.end, ordinary):
            continue
        if any(c.start < b and a < c.end for a, b in taken):
            continue
        piece = text[c.start : c.end]
        out.append(Span(None, piece, "", piece, c.start, c.end, round(c.confidence, 3)))
        taken.append((c.start, c.end))
    out.sort(key=lambda s: s.start)
    return out
