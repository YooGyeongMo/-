"""POST /translations (#11): 사전 매칭 → 엔진 라우터 → 저장.

원문은 이 함수 밖 로그·예외 어디에도 싣지 않는다(카나리 테스트, REQ-14).
"""

import unicodedata
from typing import Protocol

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import DomainError, ErrorCode
from app.core.time import utcnow
from app.decode.domain.model import EngineRequest, EngineResult, NewTerm, Span
from app.decode.infra import repository as repo

NEW_TERM_CONFIDENCE = 0.7


def visible(text: str) -> bool:
    """공백·서식 문자(ZWSP 등)만으로 된 입력은 내용이 없다."""
    return any(
        not ch.isspace()
        and unicodedata.category(ch) not in ("Cf", "Cc", "Zs")
        and ch not in INVISIBLE_FILLERS
        for ch in text
    )


# 한글 채움 문자·점자 빈칸: 글자처럼 보이지만 내용이 없다(레드팀 2차 L-4).
INVISIBLE_FILLERS = frozenset("\u3164\uffa0\u115f\u1160\u2800")


class Router(Protocol):
    def can_use_external(self, consent: bool) -> bool: ...

    async def decode(
        self, request: EngineRequest, *, consent: bool
    ) -> tuple[EngineResult, int]: ...


def place_new_terms(text: str, spans: list[Span], new_terms: tuple[NewTerm, ...]) -> list[Span]:
    """AI가 찾은 새 말을 원문에서 직접 찾는다. 이미 잡힌 자리와 겹치면 버린다(사전이 우선)."""
    taken = [(s.start, s.end) for s in spans]
    out = list(spans)
    for nt in new_terms:
        needle = nt.matched_text.strip()
        if not needle:
            continue
        start = text.find(needle)
        while start != -1:
            end = start + len(needle)
            if all(end <= a or start >= b for a, b in taken):
                out.append(
                    Span(None, nt.term_ko, nt.plain_ko, needle, start, end, NEW_TERM_CONFIDENCE)
                )
                taken.append((start, end))
                break
            start = text.find(needle, start + 1)
    out.sort(key=lambda s: s.start)
    return out


async def translate(
    s: AsyncSession,
    router: Router,
    *,
    user_id: int,
    source_text: str,
    direction: str,
    project_id: int | None,
    meeting_id: int | None,
    input_source: str,
    source_image_url: str | None,
    consent: bool,
) -> "int | repo.TranslationRow":
    """재사용이면 기존 id(int), 새로 만들었으면 응답 모양 그대로(다시 읽지 않는다)."""
    # 한글 자모가 풀려 들어온 입력(NFD)도 사전에 맞도록 NFC 로 저장·매칭한다. 인덱스는 저장한 원문
    # 기준.
    source_text = unicodedata.normalize("NFC", source_text)
    if not visible(source_text):
        raise DomainError(ErrorCode.INVALID_INPUT, "문장을 입력해 주세요.", "sourceText")
    project = await repo.resolve_project(s, user_id, project_id)
    meeting_title = None
    if meeting_id is not None:
        meeting_title = await repo.check_meeting(s, user_id, project.id, meeting_id)

    reused = await repo.recent_duplicate(
        s,
        user_id=user_id,
        project_id=project.id,
        meeting_id=meeting_id,
        direction=direction,
        source_text=source_text,
        input_source=input_source,
        source_image_url=source_image_url,
        prefer_external=router.can_use_external(consent),
    )
    if reused is not None:
        return reused

    dictionary = await repo.load_dictionary(s)
    spans = dictionary.spans(source_text) if direction == "JARGON_TO_PLAIN" else []
    request = EngineRequest(source_text, direction, tuple(spans), utcnow())
    result, latency = await router.decode(request, consent=consent)
    spans = place_new_terms(source_text, spans, result.new_terms)

    return await repo.insert_translation(
        s,
        repo.NewTranslation(
            user_id=user_id,
            project_id=project.id,
            meeting_id=meeting_id,
            direction=direction,
            input_source=input_source,
            source_image_url=source_image_url,
            source_text=source_text,
            result_text=result.result_text,
            intent=result.intent,
            nuance_note=result.nuance.note if result.nuance else None,
            nuance_tip=result.nuance.tip if result.nuance else None,
            nuance_confidence=result.nuance.confidence if result.nuance else None,
            ai_model=result.ai_model,
            latency_ms=latency,
            actions=result.actions,
            spans=tuple(spans),
        ),
        project_name=project.name,
        meeting_title=meeting_title,
    )
