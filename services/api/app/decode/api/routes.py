"""해석·할 일·용어 라우터 (계약 v1.0 createTranslation, getTranslations, getTranslation,
deleteTranslation, updateAction, getActions, getTerm). 응답 모양은 contracts/openapi.yml 이 원본."""

from datetime import datetime
from functools import lru_cache
from typing import Annotated, Any, Literal
from urllib.parse import urlsplit

import httpx
from fastapi import APIRouter, Depends, Header, Query, Response
from pydantic import BaseModel, Field, StrictBool, StrictInt, model_validator

from app.core.auth import CurrentPrincipal, OptionalPrincipal
from app.core.db import DbSession
from app.core.errors import ErrorCode
from app.core.kv import get_kv
from app.core.params import INT64_MAX, INT64_MIN, IdPath, PageQuery, SizeQuery, paged, require_id
from app.core.settings import settings
from app.core.time import to_api
from app.decode.infra import repository as repo
from app.decode.infra.engines.gemini import GeminiEngine
from app.decode.infra.engines.guards import Breaker, Quota
from app.decode.infra.engines.none_engine import NoneEngine
from app.decode.infra.engines.router import EngineRouter, ExternalEngine
from app.decode.usecases.translate import translate

router = APIRouter(prefix="/api")

Int64 = Annotated[StrictInt, Field(ge=INT64_MIN, le=INT64_MAX)]
Direction = Literal["JARGON_TO_PLAIN", "PLAIN_TO_JARGON"]
InputSource = Literal["TYPED", "SCREENSHOT", "RECORDING", "EXTENSION"]


@lru_cache(maxsize=1)
def engine_router() -> EngineRouter:
    external = None
    if settings.gemini_api_key:
        kv = get_kv()
        external = ExternalEngine(
            engine=GeminiEngine(
                httpx.AsyncClient(),
                api_key=settings.gemini_api_key,
                model=settings.gemini_model,
                timeout=settings.gemini_timeout_sec,
            ),
            quota=Quota(
                kv,
                engine="gemini_free",
                model=settings.gemini_model,
                rpm=settings.gemini_rpm,
                rpd=settings.gemini_rpd,
            ),
            breaker=Breaker(kv, "gemini_free"),
            model=settings.gemini_model,
        )
    return EngineRouter(
        fallback=NoneEngine(),
        external=external,
        external_enabled=settings.ai_external_text,
        allow_degraded=settings.router_allow_degraded,
    )


EngineRouterDep = Annotated[EngineRouter, Depends(engine_router)]


class TranslationRequest(BaseModel):
    sourceText: str = Field(min_length=1, max_length=500)  # noqa: N815 - 계약 필드 이름
    direction: Direction
    projectId: Int64 | None = None  # noqa: N815
    meetingId: Int64 | None = None  # noqa: N815
    inputSource: InputSource = "TYPED"  # noqa: N815
    sourceImageUrl: str | None = Field(default=None, max_length=500)  # noqa: N815

    @model_validator(mode="after")
    def _uri(self) -> "TranslationRequest":
        # http(s) 만(javascript:·file: 을 저장했다가 나중에 서버가 가져가면 SSRF, 레드팀 L-3).
        # 이미지를 서버가 가져오는 v1.1 OCR 에서는 자사 업로드 호스트만 허용한다.
        url = self.sourceImageUrl
        if url is not None:
            parts = urlsplit(url)
            if parts.scheme not in ("http", "https") or not parts.netloc or not url.isascii():
                raise ValueError("sourceImageUrl 은 http(s) URL 이어야 한다")
        return self


class ActionUpdateRequest(BaseModel):
    isChecked: StrictBool | None = None  # noqa: N815
    alertEnabled: StrictBool | None = None  # noqa: N815

    @model_validator(mode="after")
    def _at_least_one(self) -> "ActionUpdateRequest":
        if self.isChecked is None and self.alertEnabled is None:
            raise ValueError("isChecked 나 alertEnabled 중 하나는 있어야 한다")
        return self


def _dt(value: datetime | None) -> str | None:
    return None if value is None else to_api(value)


def action_body(a: repo.ActionRow) -> dict[str, Any]:
    return {
        "actionId": a.id,
        "sortOrder": a.sort_order,
        "actionText": a.text,
        "dueHint": a.due_hint,
        "dueAt": _dt(a.due_at),
        "isChecked": a.is_checked,
        "alertEnabled": a.alert_enabled,
        "checkedAt": _dt(a.checked_at),
    }


def translation_body(t: repo.TranslationRow) -> dict[str, Any]:
    nuance = None
    if t.nuance_note:
        nuance = {
            "note": t.nuance_note,
            "tip": t.nuance_tip or "",
            "confidence": t.nuance_confidence if t.nuance_confidence is not None else 0.0,
        }
    return {
        "translationId": t.id,
        "projectId": t.project_id,
        "projectName": t.project_name,
        "meetingId": t.meeting_id,
        "meetingTitle": t.meeting_title,
        "sourceType": t.source_type,
        "inputSource": t.input_source,
        "direction": t.direction,
        "sourceText": t.source_text,
        "resultText": t.result_text,
        "jargonCount": t.jargon_count,
        "intentType": t.intent,
        "nuance": nuance,
        "actionItems": [action_body(a) for a in t.actions],
        "aiModel": t.ai_model,
        "latencyMs": t.latency_ms if t.latency_ms is not None else 0,
        "detectedTerms": [
            {
                "termId": d.term_id,
                "termKo": d.term_ko,
                "plainKo": d.plain_ko,
                "matchedText": d.matched_text,
                "startIndex": d.start,
                "endIndex": d.end,
                "confidence": d.confidence,
                "inMyCards": d.in_my_cards,
            }
            for d in t.terms
        ],
        "createdAt": to_api(t.created_at),
    }


TITLE_CHARS = 24


def summary_body(r: repo.SummaryRow) -> dict[str, Any]:
    title = r.source_text.strip().replace("\n", " ")
    if len(title) > TITLE_CHARS:
        title = title[:TITLE_CHARS].rstrip() + "…"
    return {
        "translationId": r.id,
        "projectId": r.project_id,
        "title": title,
        "meetingId": r.meeting_id,
        "inputSource": r.input_source,
        "direction": r.direction,
        "sourceText": r.source_text,
        "resultText": r.result_text,
        "jargonCount": r.jargon_count,
        "intentType": r.intent,
        "actionCount": r.action_count,
        "openActionCount": r.open_action_count,
        "createdAt": to_api(r.created_at),
    }


@router.post("/translations", status_code=201)
async def create_translation(
    body: TranslationRequest,
    principal: CurrentPrincipal,
    db: DbSession,
    engines: EngineRouterDep,
    consent_header: Annotated[str | None, Header(alias="X-Mw-AI-Consent")] = None,
) -> dict[str, Any]:
    translation_id = await translate(
        db,
        engines,
        user_id=principal.user_id,
        source_text=body.sourceText,
        direction=body.direction,
        project_id=body.projectId,
        meeting_id=body.meetingId,
        input_source=body.inputSource,
        source_image_url=body.sourceImageUrl,
        consent=consent_header == "1",
    )
    return translation_body(await repo.get_translation(db, translation_id, principal.user_id))


def _meeting_filter(raw: str | None) -> int | str | None:
    """계약상 meetingId 는 문자열: "none" = 회의 밖, 숫자 = 그 회의. 그 밖의 값은 맞는 회의가
    없다."""
    if raw is None:
        return None
    if raw == "none":
        return "none"
    try:
        value = int(raw)
    except ValueError:
        return NO_MEETING
    return value if INT64_MIN <= value <= INT64_MAX else NO_MEETING


NO_MEETING = 0  # 회의 id 는 1부터라 0 은 아무것도 안 맞는다


@router.get("/translations")
async def get_translations(
    principal: CurrentPrincipal,
    db: DbSession,
    meetingId: Annotated[str | None, Query()] = None,  # noqa: N803
    projectId: Annotated[int | None, Query(ge=INT64_MIN, le=INT64_MAX)] = None,  # noqa: N803
    direction: Direction | None = None,
    page: PageQuery = 1,
    size: SizeQuery = 10,
) -> dict[str, object]:
    rows, total = await repo.list_translations(
        db,
        user_id=principal.user_id,
        project_id=projectId,
        meeting=_meeting_filter(meetingId),
        direction=direction,
        page=page,
        size=size,
    )
    return paged([summary_body(r) for r in rows], page, size, total)


@router.get("/translations/{translationId}")
async def get_translation(
    translationId: IdPath,  # noqa: N803
    principal: CurrentPrincipal,
    db: DbSession,
) -> dict[str, Any]:
    tid = require_id(translationId, ErrorCode.TRANSLATION_NOT_FOUND, "해석 기록을 찾을 수 없어요.")
    return translation_body(await repo.get_translation(db, tid, principal.user_id))


@router.delete("/translations/{translationId}", status_code=204)
async def delete_translation(
    translationId: IdPath,  # noqa: N803
    principal: CurrentPrincipal,
    db: DbSession,
) -> Response:
    tid = require_id(translationId, ErrorCode.TRANSLATION_NOT_FOUND, "해석 기록을 찾을 수 없어요.")
    await repo.delete_translation(db, tid, principal.user_id)
    return Response(status_code=204)


@router.patch("/translations/{translationId}/actions/{actionId}")
async def update_action(
    translationId: IdPath,  # noqa: N803
    actionId: IdPath,  # noqa: N803
    body: ActionUpdateRequest,
    principal: CurrentPrincipal,
    db: DbSession,
) -> dict[str, Any]:
    tid = require_id(translationId, ErrorCode.TRANSLATION_NOT_FOUND, "해석 기록을 찾을 수 없어요.")
    aid = require_id(actionId, ErrorCode.ACTION_NOT_FOUND, "할 일을 찾을 수 없어요.")
    a = await repo.update_action(
        db,
        user_id=principal.user_id,
        translation_id=tid,
        action_id=aid,
        is_checked=body.isChecked,
        alert_enabled=body.alertEnabled,
    )
    return action_body(a)


@router.get("/actions")
async def get_actions(
    principal: CurrentPrincipal,
    db: DbSession,
    meetingId: Annotated[int | None, Query(ge=INT64_MIN, le=INT64_MAX)] = None,  # noqa: N803
    projectId: Annotated[int | None, Query(ge=INT64_MIN, le=INT64_MAX)] = None,  # noqa: N803
    checked: bool = False,
    page: PageQuery = 1,
    size: SizeQuery = 10,
) -> dict[str, object]:
    rows, total = await repo.list_actions(
        db,
        user_id=principal.user_id,
        project_id=projectId,
        meeting_id=meetingId,
        checked=checked,
        page=page,
        size=size,
    )
    content: list[object] = [
        {
            **action_body(r.action),
            "translationId": r.translation_id,
            "projectId": r.project_id,
            "projectName": r.project_name,
            "meetingId": r.meeting_id,
            "meetingTitle": r.meeting_title,
            "sourceText": r.source_text,
            "createdAt": to_api(r.created_at),
        }
        for r in rows
    ]
    return paged(content, page, size, total)


@router.get("/terms/{termId}")
async def get_term(
    termId: IdPath,  # noqa: N803
    principal: OptionalPrincipal,
    db: DbSession,
) -> dict[str, Any]:
    term = require_id(termId, ErrorCode.TERM_NOT_FOUND, "용어를 찾을 수 없어요.")
    d = await repo.get_term(db, term, principal.user_id if principal else None)
    t = d.term
    card = d.card
    my_card = None
    if card is not None:
        my_card = {
            "cardId": card["id"],
            "status": card["status"],
            "intervalDays": card["interval_days"],
            "repetitionCount": card["repetition_count"],
            "dueDate": str(card["due_date"]),
        }
    return {
        "termId": t.id,
        "slug": t.slug,
        "termKo": t.term_ko,
        "originEn": t.origin_en or "",
        "plainKo": t.plain_ko,
        "category": t.category,
        "inMyCards": card is not None,
        "cardId": card["id"] if card is not None else None,
        "createdAt": to_api(t.created_at),
        "meaning": t.meaning,
        "viewCount": t.view_count,
        "createdBy": {"userId": t.created_by, "nickname": d.creator_nickname},
        "myCard": my_card,
        "examples": [
            {
                "exampleId": e.id,
                "termId": e.term_id,
                "sentenceJargon": e.sentence_jargon,
                "sentencePlain": e.sentence_plain,
                "createdBy": {"userId": e.created_by, "nickname": nick},
                "createdAt": to_api(e.created_at),
            }
            for e, nick in d.examples
        ],
    }
