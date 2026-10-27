"""사전만으로 하는 간이 해석의 규칙(엔진 `none`, ADR-0008 강등 경로).

원문을 밖으로 보내지 않고 서버 안에서만 계산한다. AI만큼 정확하지 않으므로 뉘앙스 확신도는
낮게(0.6) 둔다.
모든 규칙은 순수 함수다(시각은 인자로 받는다).
"""

import re
from datetime import datetime, timedelta

from app.decode.domain.model import ActionDraft, Nuance

KST_OFFSET = timedelta(hours=9)
END_OF_DAY_HOUR = 18  # 기한 시각을 모를 때 그날 18:00(KST)

_SENTENCE = re.compile(r"[^.!?\n。]+[.!?。]*")

_REQUEST_END = re.compile(
    r"(주세요|주시면|주실 수 있을까요|주시겠어요|주시길"
    r"|부탁(드려요|드립니다|해요|합니다|드릴게요)?|바랍니다"
    r"|해 ?줘|해야 (해요|합니다|돼요)|하셔야)[\s.!?~]*$"
)
_DECISION = re.compile(r"(밀죠|가죠|하죠|합시다|하기로 (했|해)|진행할게요|확정|드랍|빼죠|접죠)")
_DECLINE = re.compile(
    r"(어려울 것 같|챌린지가 있|힘들 것 같|일단 (팔로업|검토)|검토해 ?보겠|고민해 ?보겠"
    r"|쉽지 않|나중에 (보|챙기)죠)"
)
_QUESTION = re.compile(r"(\?|까요|나요|가요|인가요|을지|ㄹ지)[\s~]*$")

_LEAD_IN = re.compile(r"^(그리고|그 전에|그전에|일단|우선|그럼|그러면|아 |네 |넵 )\s*")
# 끝맺음 → "~하기" 꼴로 줄인다(할 일 목록에 맞는 모양).
_TO_TODO: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"\s*해\s?주(세요|시면|실 수 있을까요|시겠어요|시길)[\s.!?~]*$"), "하기"),
    (re.compile(r"\s*해\s?줘[\s.!?~]*$"), "하기"),
    (re.compile(r"\s*해야 (해요|합니다|돼요)[\s.!?~]*$"), "하기"),
    (re.compile(r"\s*(을|를)?\s*부탁(드려요|드립니다|해요|합니다|드릴게요)?[\s.!?~]*$"), ""),
    (re.compile(r"\s*바랍니다[\s.!?~]*$"), ""),
    (re.compile(r"[\s.!?~]+$"), ""),
)

_DUE = re.compile(
    r"(오늘 ?중|오늘|EOD|퇴근 ?전|아삽|ASAP|최대한 빨리|내일|모레|이번 ?주|다음 ?주|다음 스프린트"
    r"|[월화수목금토일]요일|\d{1,2}시)"
    r"(까지| 안에| 중으로| 오전| 오후)?",
    re.IGNORECASE,
)
_WEEKDAY = {"월": 0, "화": 1, "수": 2, "목": 3, "금": 4, "토": 5, "일": 6}


def sentences(text: str) -> list[str]:
    return [s.strip() for s in _SENTENCE.findall(text) if s.strip()]


def to_todo(sentence: str) -> str:
    text = _LEAD_IN.sub("", sentence.strip())
    for pattern, repl in _TO_TODO:
        new = pattern.sub(repl, text)
        if new != text:
            text = new
            break
    text = re.sub(r"기\s?하기$", "기", text)  # "방향 맞추기하기" → "방향 맞추기"
    return text.strip(" ,")


def due_hint(sentence: str) -> str | None:
    m = _DUE.search(sentence)
    return m.group(0).strip() if m else None


def due_at(hint: str | None, now_utc: datetime) -> datetime | None:
    """기한 힌트 → 알림 기준 시각(UTC naive). 모르는 힌트나 이미 지난 시각이면 None."""
    if not hint:
        return None
    now = now_utc + KST_OFFSET  # KST naive
    today = now.replace(hour=END_OF_DAY_HOUR, minute=0, second=0, microsecond=0)
    h = hint.replace(" ", "").upper()
    when: datetime | None = None
    if h.startswith(("오늘", "EOD", "퇴근전", "아삽", "ASAP", "최대한빨리")):
        when = today
    elif h.startswith("내일"):
        when = today + timedelta(days=1)
    elif h.startswith("모레"):
        when = today + timedelta(days=2)
    elif h.startswith("이번주"):
        when = today + timedelta(days=max(0, 4 - now.weekday()))
    elif h.startswith("다음주") or h.startswith("다음스프린트"):
        when = today + timedelta(days=7 - now.weekday())  # 다음 주 월요일
    elif h[0] in _WEEKDAY and h[1:3] == "요일":
        ahead = (_WEEKDAY[h[0]] - now.weekday()) % 7
        when = today + timedelta(days=ahead)
    else:
        m = re.match(r"(\d{1,2})시", h)
        if m and 0 <= int(m.group(1)) <= 23:
            hour = int(m.group(1))
            if hour < 8:  # "3시까지" = 오후 3시
                hour += 12
            when = now.replace(hour=hour, minute=0, second=0, microsecond=0)
    if when is None or when <= now:
        return None
    return when - KST_OFFSET


def actions(plain_text: str, now_utc: datetime) -> tuple[ActionDraft, ...]:
    out: list[ActionDraft] = []
    for s in sentences(plain_text):
        if not _REQUEST_END.search(s) or _QUESTION.search(s):
            continue
        todo = to_todo(s)
        if len(todo) < 2:
            continue
        hint = due_hint(s)
        out.append(ActionDraft(text=todo[:300], due_hint=hint, due_at=due_at(hint, now_utc)))
    return tuple(out[:5])


def intent(source_text: str, has_actions: bool) -> str:
    if _DECLINE.search(source_text):
        return "DECLINE"
    if _DECISION.search(source_text):
        return "DECISION"
    if has_actions:
        return "REQUEST"
    if any(_QUESTION.search(s) for s in sentences(source_text)):
        return "QUESTION"
    return "SHARE"


def nuance(source_text: str, intent_type: str) -> Nuance | None:
    if intent_type == "DECISION":
        m = _DECISION.search(source_text)
        word = m.group(0) if m else "이 말"
        return Nuance(
            note=f'"{word}"는 제안처럼 들려도 이미 정해진 내용을 알리는 말일 때가 많아요.',
            tip="되묻기보다 일정만 확인하는 편이 안전해요.",
            confidence=0.6,
        )
    if intent_type == "DECLINE":
        return Nuance(
            note="돌려 말한 거절일 수 있어요. 지금은 하지 않겠다는 뜻으로 쓰일 때가 많아요.",
            tip="기한을 정해 다시 확인하거나 다른 방법을 물어보세요.",
            confidence=0.6,
        )
    return None
