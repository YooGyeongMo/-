"""사전만으로 하는 간이 해석의 규칙(엔진 `none`, ADR-0008 강등 경로).

원문을 밖으로 보내지 않고 서버 안에서만 계산한다. AI만큼 정확하지 않으므로 뉘앙스 확신도는
낮게(0.6) 둔다. 모든 규칙은 순수 함수다(시각은 인자로 받는다).
레드팀 1차(2026-10-27) 반영: 기한 = 날짜 + 시각 합치기, 문장 꼬리(이모지·ㅎㅎ·^^·~) 무시,
"~해 주세요" 밖의 동사도 할 일 꼴로, 물음표는 결정보다 먼저.
"""

import re
import unicodedata
from datetime import datetime, timedelta

from app.decode.domain.model import ActionDraft, Nuance

KST_OFFSET = timedelta(hours=9)
END_OF_DAY_HOUR = 18  # 날짜만 있으면 그날 18:00(KST)
NUANCE_CONFIDENCE = 0.6

_SENTENCE = re.compile(r"[^.!?\n。~]+[.!?。~]*")

_REQUEST_END = re.compile(
    r"(주세요|주시면(\s?감사하겠습니다|\s?감사합니다|\s?좋겠어요|\s?돼요)?|주실 수 있을까요"
    r"|주시겠어요|주시길|부탁(드려요|드립니다|해요|합니다|드릴게요)?|바랍니다|해 ?줘"
    r"|해야 (해요|합니다|돼요)|하셔야|마세요)$"
)
_DECISION = re.compile(r"(밀죠|가죠|로 가요|하죠|합시다|하기로 (했|해)|확정|드랍|빼죠|접죠)")
_NOT_DECIDED = re.compile(r"(확정(은|이)? 아니|미정|아직 확정)")
_DECLINE = re.compile(
    r"(어려울 것 같|챌린지가 있|힘들 것 같|일단 (팔로업|검토)|검토해 ?보겠|고민해 ?보겠"
    r"|쉽지 않|나중에 (보|챙기)죠)"
)
_QUESTION = re.compile(r"(\?|까요|나요\??|인가요|을지|ㄹ지)$")
# 할 일로 보지 않는 것("참고 부탁드려요" → 할 일 "참고").
_NOT_TODO = frozenset({"참고", "양해", "이해", "확인", "잘", "감사"})

_LEAD_IN = re.compile(r"^(그리고|그 전에|그전에|일단|우선|그럼|그러면|아|네|넵)[ ,]+")
# 동사 어간 + 아/어 + 주세요 → ~기 (올려 주세요 → 올리기). 끝 글자 → 기본형 마지막 글자.
_STEM_TAIL = {
    "려": "리",
    "겨": "기",
    "춰": "추",
    "꿔": "꾸",
    "봐": "보",
    "와": "오",
    "써": "쓰",
    "줘": "주",
}
_POLITE_END = r"(\s?주(세요|시면|실 수 있을까요|시겠어요|시길)|\s?줘)"


def strip_tail(sentence: str) -> str:
    """문장 끝의 이모지·자모 웃음·^^·~·서식 문자를 걷어 낸다(요청 끝맺음을 보려고)."""
    s = sentence.rstrip()
    while s:
        ch = s[-1]
        code = ord(ch)
        if (
            ch.isspace()
            or ch in "~^.!。"
            or unicodedata.category(ch) in ("So", "Sk", "Cf", "Mn", "Me")
            or 0x3131 <= code <= 0x318E  # ㅎㅋㅠㅜ 같은 자모
            or 0x1F000 <= code <= 0x1FAFF
        ):
            s = s[:-1]
            continue
        break
    return s


def sentences(text: str) -> list[str]:
    return [s.strip() for s in _SENTENCE.findall(text) if s.strip()]


_TODO_RULES: tuple[tuple[str, str], ...] = (
    (r"(\s?)해" + _POLITE_END + r"$", r"\1하기"),
    (r"(\s?)해야 (해요|합니다|돼요)$", r"\1하기"),
    (r"(\s?)하셔야( (해요|합니다|돼요))?$", r"\1하기"),
    (r"\s?(도|을|를)?\s?부탁(드려요|드립니다|해요|합니다|드릴게요)?$", ""),
    (r"\s?(을|를)?\s?주시면\s?(감사하겠습니다|감사합니다|좋겠어요|돼요)$", ""),
    (r"\s?바랍니다$", ""),
    (r"지\s?마세요$", "지 않기"),
)


def to_todo(sentence: str) -> str:
    text = _LEAD_IN.sub("", strip_tail(sentence).strip())
    for pattern, repl in _TODO_RULES:
        new = re.sub(pattern, repl, text)
        if new != text:
            text = new
            break
    else:
        m = re.search(r"(\S*?)(\S)" + _POLITE_END + r"$", text)
        if m:
            stem, last = m.group(1), m.group(2)
            if last in _STEM_TAIL:
                base = stem + _STEM_TAIL[last]
            elif last in ("어", "아"):
                base = stem  # 만들어 → 만들, 잡아 → 잡
            elif last == "여":
                base = stem + "이"  # 붙여 → 붙이
            elif last == "내":
                base = stem + last  # 보내 → 보내
            else:
                base = ""  # "피드백 주세요": 이름씨 + 주세요 → "피드백 주기"
            text = text[: m.start()] + (base + "기" if base else m.group(1) + m.group(2) + " 주기")
    text = re.sub(r"\s잘$", "", text)  # "관리 잘 부탁" → "관리"
    text = re.sub(r"기\s?하기$", "기", text)  # "방향 맞추기하기" → "방향 맞추기"
    return text.strip(" ,")


# ---------- 기한 ----------
# 레드팀 2차(B-5·B-6·B-7): 절대 날짜(11월 3일·10/30·30일), 새벽·밤·자정·정오, 분, 한 문장 여러 날짜.

_DATE = re.compile(
    r"(?P<md>(?P<m>\d{1,2})\s?월\s?(?P<d>\d{1,2})\s?일)"
    r"|(?P<slash>(?P<sm>\d{1,2})/(?P<sd>\d{1,2}))"
    r"|(?P<dom>(?<![\d월])(?P<dd>\d{1,2})\s?일(?![간동째]))"
    r"|(?P<word>오늘\s?중|오늘|EOD|퇴근\s?전|아삽|ASAP|최대한\s?빨리|내일|모레"
    r"|(?:(?P<week>이번|다음)\s?주\s?)?(?P<wd>[월화수목금토일])요일|이번\s?주|다음\s?주|다음\s?스프린트"
    r"|주말\s?전|이번\s?달\s?말|월말)",
    re.IGNORECASE,
)
_TIME = re.compile(
    r"(?P<period>오전|오후|아침|저녁|밤|새벽)?\s?(?P<h>\d{1,2})\s?시(?![간안즌리키켜])"
    r"(?:\s?(?P<half>반)|\s?(?P<min>\d{1,2})\s?분)?"
    r"|(?P<named>자정|정오)"
    r"|(?P<alone>오전|오후|아침|저녁|밤)(?=\s?(까지|중|안|전))"
)
_TAIL = re.compile(r"(까지| 안에| 중으로| 전에|까진)")
_WEEKDAY = {"월": 0, "화": 1, "수": 2, "목": 3, "금": 4, "토": 5, "일": 6}


def _pick(pattern: re.Pattern[str], sentence: str) -> re.Match[str] | None:
    """여러 개면 "까지/안에" 바로 앞의 것, 없으면 마지막 것(레드팀 B-7: "오늘은 어렵고 내일
    3시까지")."""
    found = list(pattern.finditer(sentence))
    if not found:
        return None
    for m in reversed(found):
        if _TAIL.match(sentence, m.end()) or _TAIL.match(sentence, m.end() + 1):
            return m
    return found[-1]


def due_hint(sentence: str) -> str | None:
    """원문에서 기한 표현(날짜 + 시각 + 꼬리)을 뽑는다. 없으면 None."""
    date, time = _pick(_DATE, sentence), _pick(_TIME, sentence)
    parts = sorted([m for m in (date, time) if m], key=lambda m: m.start())
    if not parts:
        return None
    hint = " ".join(m.group(0).strip() for m in parts)
    tail = _TAIL.match(sentence, parts[-1].end())
    return hint + (tail.group(1) if tail else "")


def _date_of(hint: str, now: datetime) -> datetime | None:
    """그날 0시(KST). 날짜 표현이 없으면 None. 이미 지난 날짜는 None(레드팀 Low "이번 주
    월요일")."""
    m = _DATE.search(hint)
    if not m:
        return None
    day0 = now.replace(hour=0, minute=0, second=0, microsecond=0)
    try:
        if m.group("md") or m.group("slash"):
            month = int(m.group("m") or m.group("sm"))
            day = int(m.group("d") or m.group("sd"))
            when = day0.replace(month=month, day=day)
            return when if when >= day0 else when.replace(year=when.year + 1)
        if m.group("dom"):
            day = int(m.group("dd"))
            when = day0.replace(day=day)
            if when < day0:
                month = when.month % 12 + 1
                when = when.replace(year=when.year + (when.month == 12), month=month)
            return when
    except ValueError:
        return None  # 2월 30일 같은 없는 날
    word = re.sub(r"\s", "", m.group("word") or "").upper()
    monday = day0 - timedelta(days=now.weekday())
    if word.startswith(("오늘", "EOD", "퇴근전", "아삽", "ASAP", "최대한빨리")):
        return day0
    if word == "내일":
        return day0 + timedelta(days=1)
    if word == "모레":
        return day0 + timedelta(days=2)
    if m.group("wd"):
        target = _WEEKDAY[m.group("wd")]
        if m.group("week") == "다음":
            return monday + timedelta(days=7 + target)
        if m.group("week") == "이번":
            when = monday + timedelta(days=target)
            return when if when >= day0 else None
        return day0 + timedelta(days=(target - now.weekday()) % 7)
    if word.startswith("이번주"):
        return max(day0, monday + timedelta(days=4))  # 이번 주 금요일(주말이면 오늘)
    if word.startswith("주말전"):
        return max(day0, monday + timedelta(days=4))
    if word in ("이번달말", "월말"):
        nxt = (day0.replace(day=28) + timedelta(days=4)).replace(day=1)
        return nxt - timedelta(days=1)
    if word.startswith("다음주"):
        return monday + timedelta(days=7 + 4)  # 다음 주까지 = 다음 주 금요일
    return monday + timedelta(days=7)  # 다음 스프린트 = 다음 주 월요일


def _time_of(hint: str) -> tuple[int, int, bool] | None:
    """(시, 분, 오전·오후를 밝혔는지). 24 는 그날이 끝날 때(자정)."""
    m = _TIME.search(hint)
    if not m:
        return None
    if m.group("named"):
        return (24, 0, True) if m.group("named") == "자정" else (12, 0, True)
    if m.group("alone"):
        h = {"오전": 12, "아침": 9, "오후": END_OF_DAY_HOUR, "저녁": 19, "밤": 23}[m.group("alone")]
        return (h, 0, True)
    period, hour = m.group("period"), int(m.group("h"))
    minute = 30 if m.group("half") else int(m.group("min") or 0)
    if hour > 24 or minute > 59:
        return None
    if period in ("오후", "저녁") and hour < 12:
        hour += 12
    elif period == "밤":
        hour = 24 if hour == 12 else (hour + 12 if hour < 12 and hour >= 6 else hour)
    elif period == "오전" and hour == 12:
        hour = 24  # "오전 12시" = 자정
    elif period in ("아침", "새벽") and hour == 12:
        hour = 0
    elif period is None and 1 <= hour <= 6:
        hour += 12  # 근무 시간: "3시까지" = 오후 3시
    return (hour, minute, period is not None)


def due_at(hint: str | None, now_utc: datetime) -> datetime | None:
    """기한 힌트 → 마감 시각(UTC naive). 모르는 힌트나 이미 지난 시각이면 None."""
    if not hint:
        return None
    now = now_utc + KST_OFFSET  # KST naive
    day = _date_of(hint, now)
    clock = _time_of(hint)
    if day is None and clock is None:
        return None
    if day is None and _DATE.search(hint) is None and re.search(r"\d+\s?(월|일|/)", hint):
        return None  # 모르는 날짜 표기가 있으면 오늘로 단정하지 않는다
    base = day if day is not None else now.replace(hour=0, minute=0, second=0, microsecond=0)
    hour, minute, explicit = clock if clock is not None else (END_OF_DAY_HOUR, 0, True)
    when = base + timedelta(hours=hour, minutes=minute)
    if when <= now and day is None and clock is not None:
        # 날짜 없이 시각만: 오전·오후를 안 밝혔으면 오후로 한 번 더 보고, 그래도 지났으면 내일
        # 같은 시각
        later = when + timedelta(hours=12)
        when = later if not explicit and hour < 12 and later > now else when + timedelta(days=1)
    if when <= now:
        return None
    return when - KST_OFFSET


def actions(plain_text: str, now_utc: datetime) -> tuple[ActionDraft, ...]:
    out: list[ActionDraft] = []
    seen: set[str] = set()
    for s in sentences(plain_text):
        core = strip_tail(s)
        if not _REQUEST_END.search(core) or _QUESTION.search(core):
            continue
        todo = to_todo(s)
        if len(todo) < 2 or todo in _NOT_TODO or todo in seen:
            continue
        seen.add(todo)
        hint = due_hint(s)
        out.append(ActionDraft(text=todo[:300], due_hint=hint, due_at=due_at(hint, now_utc)))
    return tuple(out[:5])


def intent(source_text: str, has_actions: bool) -> str:
    cores = [strip_tail(s) for s in sentences(source_text)]
    if cores and all(c.endswith("?") for c in cores):
        return "QUESTION"  # "놀러 가죠?" 는 결정이 아니라 질문(물음표가 있을 때만)
    if _DECLINE.search(source_text):
        return "DECLINE"
    if _DECISION.search(source_text) and not _NOT_DECIDED.search(source_text):
        return "DECISION"
    if has_actions or any(_REQUEST_END.search(c) for c in cores):
        return "REQUEST"
    if any(_QUESTION.search(c) for c in cores):
        return "QUESTION"
    return "SHARE"


def _topic(word: str) -> str:
    """'"확정"은' / '"밀죠"는' — 받침에 맞는 보조사."""
    code = ord(word[-1]) if word else 0
    has_batchim = 0xAC00 <= code <= 0xD7A3 and (code - 0xAC00) % 28 != 0
    return f'"{word}"{"은" if has_batchim else "는"}'


def nuance(source_text: str, intent_type: str) -> Nuance | None:
    if intent_type == "DECISION":
        m = _DECISION.search(source_text)
        word = m.group(0) if m else "이 말"
        return Nuance(
            note=f"{_topic(word)} 제안처럼 들려도 이미 정해진 내용을 알리는 말일 때가 많아요.",
            tip="되묻기보다 일정만 확인하는 편이 안전해요.",
            confidence=NUANCE_CONFIDENCE,
        )
    if intent_type == "DECLINE":
        return Nuance(
            note="돌려 말한 거절일 수 있어요. 지금은 하지 않겠다는 뜻으로 쓰일 때가 많아요.",
            tip="기한을 정해 다시 확인하거나 다른 방법을 물어보세요.",
            confidence=NUANCE_CONFIDENCE,
        )
    return None
