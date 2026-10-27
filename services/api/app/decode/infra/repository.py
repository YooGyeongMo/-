"""decode 저장소(SQLAlchemy). 다른 컨텍스트 테이블(users·projects·meetings·cards)은 import 하지 않고
이름으로만 읽는다(14번 §3, import-linter 컨텍스트 독립).

트랜잭션은 요청 하나 = 하나(core.db). 해석 저장은
translations·translation_actions·translation_terms 3테이블을
한 트랜잭션으로 쓴다(#11).
"""

import time
from dataclasses import dataclass
from datetime import datetime, timedelta
from decimal import Decimal

import sqlalchemy as sa
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import DomainError, ErrorCode
from app.core.params import offset_of
from app.core.time import utcnow
from app.decode.domain.matching import Trie
from app.decode.domain.model import ActionDraft, DictTerm, Span
from app.decode.infra.models import (
    Term,
    TermExample,
    Translation,
    TranslationAction,
    TranslationTerm,
)
from app.decode.infra.seed_terms import TERMS

_users = sa.table("users", sa.column("id"), sa.column("nickname"), sa.column("current_project_id"))
_projects = sa.table(
    "projects",
    sa.column("id"),
    sa.column("user_id"),
    sa.column("name"),
    sa.column("description"),
    sa.column("color"),
    sa.column("is_default", sa.Boolean()),
    sa.column("created_at", sa.DateTime()),
)
_meetings = sa.table(
    "meetings", sa.column("id"), sa.column("user_id"), sa.column("project_id"), sa.column("title")
)
_cards = sa.table(
    "cards",
    sa.column("id"),
    sa.column("user_id"),
    sa.column("term_id"),
    sa.column("source_translation_id"),
    sa.column("status"),
    sa.column("interval_days"),
    sa.column("repetition_count"),
    sa.column("due_date", sa.Date()),
)
_recordings = sa.table("meeting_recordings", sa.column("translation_id"))

DEFAULT_PROJECT_NAME = "내 프로젝트"
REUSE_WINDOW = timedelta(minutes=10)
DICTIONARY_TTL_SEC = 300.0
DICT_CONFIDENCE = Decimal("0.950")


# ---------- 사전 ----------


@dataclass(frozen=True)
class Dictionary:
    trie: Trie
    terms: dict[str, DictTerm]  # slug → 용어

    def spans(self, text: str) -> list[Span]:
        out: list[Span] = []
        has_hangul = any("\uac00" <= ch <= "\ud7a3" for ch in text)
        for m in self.trie.find(text):
            if not has_hangul and m.matched_text.lower() in LATIN_ALLOW:
                continue  # 영어 문장의 "align"은 판교어가 아니다(레드팀 2차)
            t = self.terms.get(m.key)
            if t is not None:
                out.append(
                    Span(
                        t.id, t.ko, t.plain, m.matched_text, m.start, m.end, float(DICT_CONFIDENCE)
                    )
                )
        return out


_ALIASES = {t.slug: t.aliases for t in TERMS}

# 영어 원어 중 그대로 매칭해도 되는 것(판교어로만 쓰이는 짧은 낱말). 그 밖의 한 낱말 영어(next,
# hold, drop,
# input, spec …)는 평범한 영어 문장에서 오탐이 나서 매칭하지 않는다(레드팀 H-1, ADR-0018).
LATIN_ALLOW = frozenset({"align", "asap", "1on1", "fyi", "eod"})


def usable_surface(surface: str) -> bool:
    """사전 매칭에 쓸 표기인지. 한글이 섞이면 그대로 쓴다. 영어만이면 약어·여러 낱말·허용 목록만."""
    if not surface.isascii():
        return True
    if surface.lower() in LATIN_ALLOW:
        return True
    if any(c in " -&/:" for c in surface):
        return True  # "scope out", "kick-off", "R&R", "A/B test"
    letters = [c for c in surface if c.isalpha()]
    return bool(letters) and all(c.isupper() for c in letters)  # 약어(KPI, POC)


_cache: tuple[float, Dictionary] | None = None


def reset_dictionary_cache() -> None:
    global _cache
    _cache = None


async def load_dictionary(s: AsyncSession) -> Dictionary:
    """검수된 용어로 trie 를 만든다. 5분 캐시(용어 검수는 드물다)."""
    global _cache
    now = time.monotonic()
    if _cache is not None and now - _cache[0] < DICTIONARY_TTL_SEC:
        return _cache[1]
    rows = (
        await s.execute(
            sa.select(Term.id, Term.slug, Term.term_ko, Term.origin_en, Term.plain_ko).where(
                Term.status == "APPROVED"
            )
        )
    ).all()
    terms: dict[str, DictTerm] = {}
    surfaces: dict[str, str] = {}
    for r in rows:
        terms[r.slug] = DictTerm(r.id, r.slug, r.term_ko, r.plain_ko)
        for surface in (r.term_ko, r.origin_en, *_ALIASES.get(r.slug, ())):
            if surface and surface.strip() and usable_surface(surface.strip()):
                surfaces.setdefault(surface.strip(), r.slug)
    d = Dictionary(Trie(surfaces), terms)
    _cache = (now, d)
    return d


# ---------- 프로젝트·회의 (workspace 테이블을 이름으로) ----------


@dataclass(frozen=True)
class ProjectRef:
    id: int
    name: str


async def resolve_project(s: AsyncSession, user_id: int, project_id: int | None) -> ProjectRef:
    if project_id is not None:
        row = (
            await s.execute(
                sa.select(_projects.c.id, _projects.c.user_id, _projects.c.name).where(
                    _projects.c.id == project_id
                )
            )
        ).first()
        if row is None:
            raise DomainError(
                ErrorCode.PROJECT_NOT_FOUND, "프로젝트를 찾을 수 없어요.", "projectId"
            )
        if row.user_id != user_id:
            raise DomainError(ErrorCode.NOT_OWNER, "내 프로젝트가 아니에요.", "projectId")
        return ProjectRef(row.id, row.name)

    current = (
        await s.execute(sa.select(_users.c.current_project_id).where(_users.c.id == user_id))
    ).scalar()
    if current is not None:
        row = (
            await s.execute(
                sa.select(_projects.c.id, _projects.c.name).where(
                    _projects.c.id == current, _projects.c.user_id == user_id
                )
            )
        ).first()
        if row is not None:
            return ProjectRef(row.id, row.name)
    return await ensure_default_project(s, user_id)


async def _default_project(
    s: AsyncSession, user_id: int, *, locking: bool = False
) -> ProjectRef | None:
    # 첫 조회는 잠금 없이(없는 행을 FOR SHARE 하면 InnoDB 가 gap 잠금을 걸어 동시 INSERT 끼리 교착,
    # 레드팀 2차 B-2). INSERT 가 유니크 위반으로 실패한 뒤에만 잠금 읽기로 최신 커밋을 본다.
    stmt = sa.select(_projects.c.id, _projects.c.name).where(
        _projects.c.user_id == user_id, _projects.c.name == DEFAULT_PROJECT_NAME
    )
    row = (await s.execute(stmt.with_for_update(read=True) if locking else stmt)).first()
    if row is None:
        row = (
            await s.execute(
                sa.select(_projects.c.id, _projects.c.name)
                .where(_projects.c.user_id == user_id, _projects.c.is_default.is_(True))
                .order_by(_projects.c.id)
                .limit(1)
            )
        ).first()
    return None if row is None else ProjectRef(row.id, row.name)


async def ensure_default_project(s: AsyncSession, user_id: int) -> ProjectRef:
    """온보딩을 건너뛴 사용자의 "내 프로젝트". 없으면 만들고 현재 프로젝트로 고른다.

    첫 해석을 동시에 여러 번 보내도(두 번 누름·재시도) 하나만 생긴다: 유니크 위반은 SAVEPOINT 로
    받고
    먼저 만들어진 행을 다시 읽는다(레드팀 H-3).
    """
    # 사용자 행을 먼저 배타 잠금: 같은 사람의 첫 해석들이 여기서 한 줄로 선다. 안 그러면 각자
    # projects INSERT 의
    # 외래 키 확인으로 users 행에 공유 잠금을 쥔 채 UPDATE(배타)로 올리려다 서로 교착한다(MySQL
    # 1213, CI 경합 테스트).
    await s.execute(sa.select(_users.c.id).where(_users.c.id == user_id).with_for_update())
    ref = await _default_project(s, user_id)
    if ref is None:
        try:
            async with s.begin_nested():
                await s.execute(
                    _projects.insert().values(
                        user_id=user_id,
                        name=DEFAULT_PROJECT_NAME,
                        is_default=True,
                        created_at=utcnow(),
                    )
                )
        except IntegrityError:
            ref = await _default_project(s, user_id, locking=True)  # 다른 요청이 막 만들었다
        else:
            ref = await _default_project(s, user_id)
        if ref is None:  # 이론상 없음(만들었거나 남이 만들었다)
            raise DomainError(ErrorCode.PROJECT_NOT_FOUND, "프로젝트를 찾을 수 없어요.")
    await s.execute(_users.update().where(_users.c.id == user_id).values(current_project_id=ref.id))
    return ref


async def check_meeting(s: AsyncSession, user_id: int, project_id: int, meeting_id: int) -> str:
    row = (
        await s.execute(
            sa.select(_meetings.c.user_id, _meetings.c.project_id, _meetings.c.title).where(
                _meetings.c.id == meeting_id
            )
        )
    ).first()
    if row is None or row.project_id != project_id:
        raise DomainError(ErrorCode.MEETING_NOT_FOUND, "회의를 찾을 수 없어요.", "meetingId")
    if row.user_id != user_id:
        raise DomainError(ErrorCode.NOT_OWNER, "내 회의가 아니에요.", "meetingId")
    return str(row.title)


# ---------- 해석 ----------


async def recent_duplicate(
    s: AsyncSession,
    *,
    user_id: int,
    project_id: int,
    meeting_id: int | None,
    direction: str,
    source_text: str,
    input_source: str,
    source_image_url: str | None,
    prefer_external: bool,
) -> int | None:
    """10분 안에 같은 원문을 같은 곳·같은 입력으로 해석했으면 그 기록을 다시 쓴다(중복 저장·AI
    호출 방지).

    - 원문 비교는 파이썬에서 한 번 더 한다(MySQL 기본 collation 은 대소문자·악센트를 무시한다).
    - 이번엔 외부 엔진을 쓸 수 있는데(동의 + 설정 + 키) 지난 결과가 사전 간이 해석이면 다시 쓰지
      않는다.
    """
    stmt = (
        sa.select(Translation.id, Translation.source_text, Translation.ai_model)
        .where(
            Translation.user_id == user_id,
            Translation.project_id == project_id,
            Translation.direction == direction,
            Translation.input_source == input_source,
            Translation.source_text == source_text,
            Translation.created_at >= utcnow() - REUSE_WINDOW,
            Translation.meeting_id.is_(None)
            if meeting_id is None
            else Translation.meeting_id == meeting_id,
            Translation.source_image_url.is_(None)
            if source_image_url is None
            else Translation.source_image_url == source_image_url,
        )
        .order_by(Translation.id.desc())
        .limit(5)
    )
    for row in (await s.execute(stmt)).all():
        if row.source_text != source_text:
            continue
        if prefer_external and str(row.ai_model).startswith("none/"):
            return None  # 지금은 AI 로 할 수 있는데 지난 건 사전 결과 → 새로 해석(레드팀 2차 B-1)
        return int(row.id)
    return None


@dataclass(frozen=True)
class NewTranslation:
    user_id: int
    project_id: int
    meeting_id: int | None
    direction: str
    input_source: str
    source_image_url: str | None
    source_text: str
    result_text: str
    intent: str | None
    nuance_note: str | None
    nuance_tip: str | None
    nuance_confidence: float | None
    ai_model: str
    latency_ms: int
    actions: tuple[ActionDraft, ...]
    spans: tuple[Span, ...]


def _dec(value: float | None) -> Decimal | None:
    return None if value is None else Decimal(str(round(value, 3)))


async def insert_translation(s: AsyncSession, t: NewTranslation) -> int:
    row = Translation(
        user_id=t.user_id,
        project_id=t.project_id,
        meeting_id=t.meeting_id,
        direction=t.direction,
        source_type="MESSAGE",
        source_text=t.source_text,
        input_source=t.input_source,
        source_image_url=t.source_image_url,
        result_text=t.result_text,
        jargon_count=len(t.spans),
        intent_type=t.intent,
        nuance_note=t.nuance_note,
        nuance_tip=t.nuance_tip,
        nuance_confidence=_dec(t.nuance_confidence),
        ai_model=t.ai_model[:50],
        latency_ms=t.latency_ms,
        created_at=utcnow(),
    )
    s.add(row)
    await s.flush()
    for i, a in enumerate(t.actions, start=1):
        s.add(
            TranslationAction(
                translation_id=row.id,
                sort_order=i,
                action_text=a.text,
                due_hint=a.due_hint,
                due_at=a.due_at,
                created_at=utcnow(),
            )
        )
    for sp in t.spans:
        s.add(
            TranslationTerm(
                translation_id=row.id,
                term_id=sp.term_id,
                ai_term_ko=None if sp.term_id is not None else sp.term_ko[:100],
                ai_plain_ko=None if sp.term_id is not None else sp.plain_ko[:200],
                matched_text=sp.matched_text[:100],
                start_index=sp.start,
                end_index=sp.end,
                confidence=_dec(sp.confidence) or Decimal("0"),
            )
        )
    await s.flush()
    return int(row.id)


@dataclass(frozen=True)
class ActionRow:
    id: int
    sort_order: int
    text: str
    due_hint: str | None
    due_at: datetime | None
    is_checked: bool
    alert_enabled: bool
    checked_at: datetime | None


@dataclass(frozen=True)
class TermRow:
    term_id: int | None
    term_ko: str
    plain_ko: str
    matched_text: str
    start: int
    end: int
    confidence: float
    in_my_cards: bool


@dataclass(frozen=True)
class TranslationRow:
    id: int
    user_id: int
    project_id: int
    project_name: str
    meeting_id: int | None
    meeting_title: str | None
    source_type: str
    input_source: str
    direction: str
    source_text: str
    result_text: str
    jargon_count: int
    intent: str | None
    nuance_note: str | None
    nuance_tip: str | None
    nuance_confidence: float | None
    ai_model: str
    latency_ms: int | None
    created_at: datetime
    actions: tuple[ActionRow, ...]
    terms: tuple[TermRow, ...]


def _action(a: TranslationAction) -> ActionRow:
    return ActionRow(
        a.id,
        a.sort_order,
        a.action_text,
        a.due_hint,
        a.due_at,
        a.is_checked,
        a.alert_enabled,
        a.checked_at,
    )


async def _card_term_ids(s: AsyncSession, user_id: int, term_ids: list[int]) -> set[int]:
    if not term_ids:
        return set()
    rows = await s.execute(
        sa.select(_cards.c.term_id).where(
            _cards.c.user_id == user_id, _cards.c.term_id.in_(term_ids)
        )
    )
    return set(map(int, rows.scalars()))


async def get_translation(s: AsyncSession, translation_id: int, user_id: int) -> TranslationRow:
    t = await s.get(Translation, translation_id)
    if t is None:
        raise DomainError(ErrorCode.TRANSLATION_NOT_FOUND, "해석 기록을 찾을 수 없어요.")
    if t.user_id != user_id:
        raise DomainError(ErrorCode.NOT_OWNER, "내 해석 기록이 아니에요.")
    project_name = (
        await s.execute(sa.select(_projects.c.name).where(_projects.c.id == t.project_id))
    ).scalar() or ""
    meeting_title = None
    if t.meeting_id is not None:
        meeting_title = (
            await s.execute(sa.select(_meetings.c.title).where(_meetings.c.id == t.meeting_id))
        ).scalar()
    actions = (
        await s.execute(
            sa.select(TranslationAction)
            .where(TranslationAction.translation_id == t.id)
            .order_by(TranslationAction.sort_order)
        )
    ).scalars()
    tt_rows = (
        await s.execute(
            sa.select(TranslationTerm, Term.term_ko, Term.plain_ko)
            .outerjoin(Term, Term.id == TranslationTerm.term_id)
            .where(TranslationTerm.translation_id == t.id)
            .order_by(TranslationTerm.start_index)
        )
    ).all()
    carded = await _card_term_ids(
        s, user_id, [r[0].term_id for r in tt_rows if r[0].term_id is not None]
    )
    terms = tuple(
        TermRow(
            term_id=tt.term_id,
            term_ko=(ko if tt.term_id is not None else tt.ai_term_ko) or tt.matched_text,
            plain_ko=(plain if tt.term_id is not None else tt.ai_plain_ko) or "",
            matched_text=tt.matched_text,
            start=tt.start_index,
            end=tt.end_index,
            confidence=float(tt.confidence),
            in_my_cards=tt.term_id in carded,
        )
        for tt, ko, plain in tt_rows
    )
    return TranslationRow(
        id=t.id,
        user_id=t.user_id,
        project_id=t.project_id,
        project_name=project_name,
        meeting_id=t.meeting_id,
        meeting_title=meeting_title,
        source_type=t.source_type,
        input_source=t.input_source,
        direction=t.direction,
        source_text=t.source_text,
        result_text=t.result_text,
        jargon_count=t.jargon_count,
        intent=t.intent_type,
        nuance_note=t.nuance_note,
        nuance_tip=t.nuance_tip,
        nuance_confidence=None if t.nuance_confidence is None else float(t.nuance_confidence),
        ai_model=t.ai_model,
        latency_ms=t.latency_ms,
        created_at=t.created_at,
        actions=tuple(_action(a) for a in actions),
        terms=terms,
    )


@dataclass(frozen=True)
class SummaryRow:
    id: int
    project_id: int
    meeting_id: int | None
    input_source: str
    direction: str
    source_text: str
    result_text: str
    jargon_count: int
    intent: str | None
    action_count: int
    open_action_count: int
    created_at: datetime


async def list_translations(
    s: AsyncSession,
    *,
    user_id: int,
    project_id: int | None,
    meeting: int | None | str,  # None=전부, "none"=회의 밖만, int=그 회의
    direction: str | None,
    page: int,
    size: int,
) -> tuple[list[SummaryRow], int]:
    where = [Translation.user_id == user_id]
    if project_id is not None:
        where.append(Translation.project_id == project_id)
    if meeting == "none":
        where.append(Translation.meeting_id.is_(None))
    elif isinstance(meeting, int):
        where.append(Translation.meeting_id == meeting)
    if direction is not None:
        where.append(Translation.direction == direction)
    total = int(
        (
            await s.execute(sa.select(sa.func.count()).select_from(Translation).where(*where))
        ).scalar_one()
    )
    off = offset_of(page, size)
    if off is None:
        return [], total
    acount = (
        sa.select(sa.func.count())
        .where(TranslationAction.translation_id == Translation.id)
        .correlate(Translation)
        .scalar_subquery()
    )
    aopen = (
        sa.select(sa.func.count())
        .where(
            TranslationAction.translation_id == Translation.id,
            TranslationAction.is_checked.is_(False),
        )
        .correlate(Translation)
        .scalar_subquery()
    )
    rows = (
        await s.execute(
            sa.select(Translation, acount, aopen)
            .where(*where)
            .order_by(Translation.created_at.desc(), Translation.id.desc())
            .offset(off)
            .limit(size)
        )
    ).all()
    out = [
        SummaryRow(
            t.id,
            t.project_id,
            t.meeting_id,
            t.input_source,
            t.direction,
            t.source_text,
            t.result_text,
            t.jargon_count,
            t.intent_type,
            int(ac),
            int(ao),
            t.created_at,
        )
        for t, ac, ao in rows
    ]
    return out, total


async def delete_translation(s: AsyncSession, translation_id: int, user_id: int) -> None:
    t = await s.get(Translation, translation_id)
    if t is None:
        raise DomainError(ErrorCode.TRANSLATION_NOT_FOUND, "해석 기록을 찾을 수 없어요.")
    if t.user_id != user_id:
        raise DomainError(ErrorCode.NOT_OWNER, "내 해석 기록이 아니에요.")
    await s.execute(sa.delete(TranslationAction).where(TranslationAction.translation_id == t.id))
    await s.execute(sa.delete(TranslationTerm).where(TranslationTerm.translation_id == t.id))
    # 카드·녹음은 남기고 출처만 끊는다(원문이 사라져도 외운 말은 남는다).
    await s.execute(
        _cards.update()
        .where(_cards.c.source_translation_id == t.id)
        .values(source_translation_id=None)
    )
    await s.execute(
        _recordings.update().where(_recordings.c.translation_id == t.id).values(translation_id=None)
    )
    await s.delete(t)


# ---------- 할 일 ----------


async def update_action(
    s: AsyncSession,
    *,
    user_id: int,
    translation_id: int,
    action_id: int,
    is_checked: bool | None,
    alert_enabled: bool | None,
) -> ActionRow:
    t = await s.get(Translation, translation_id)
    if t is None:
        raise DomainError(ErrorCode.TRANSLATION_NOT_FOUND, "해석 기록을 찾을 수 없어요.")
    if t.user_id != user_id:
        raise DomainError(ErrorCode.NOT_OWNER, "내 해석 기록이 아니에요.")
    a = await s.get(TranslationAction, action_id)
    if a is None or a.translation_id != translation_id:
        raise DomainError(ErrorCode.ACTION_NOT_FOUND, "할 일을 찾을 수 없어요.")
    if is_checked is not None and is_checked != a.is_checked:
        a.is_checked = is_checked
        a.checked_at = utcnow() if is_checked else None
    if alert_enabled is not None:
        a.alert_enabled = alert_enabled
    await s.flush()
    return _action(a)


@dataclass(frozen=True)
class ActionWithSourceRow:
    action: ActionRow
    translation_id: int
    project_id: int
    project_name: str
    meeting_id: int | None
    meeting_title: str | None
    source_text: str
    created_at: datetime


async def list_actions(
    s: AsyncSession,
    *,
    user_id: int,
    project_id: int | None,
    meeting_id: int | None,
    checked: bool,
    page: int,
    size: int,
) -> tuple[list[ActionWithSourceRow], int]:
    where = [Translation.user_id == user_id, TranslationAction.is_checked.is_(checked)]
    if project_id is not None:
        where.append(Translation.project_id == project_id)
    if meeting_id is not None:
        where.append(Translation.meeting_id == meeting_id)
    base = sa.select(TranslationAction).join(
        Translation, Translation.id == TranslationAction.translation_id
    )
    total = int(
        (
            await s.execute(
                sa.select(sa.func.count())
                .select_from(TranslationAction)
                .join(Translation, Translation.id == TranslationAction.translation_id)
                .where(*where)
            )
        ).scalar_one()
    )
    off = offset_of(page, size)
    if off is None:
        return [], total
    # 기한 있는 것 먼저(가까운 순), 그다음 최근 해석 순.
    rows = (
        await s.execute(
            base.add_columns(
                Translation.project_id,
                _projects.c.name,
                Translation.meeting_id,
                _meetings.c.title,
                Translation.source_text,
            )
            .outerjoin(_projects, _projects.c.id == Translation.project_id)
            .outerjoin(_meetings, _meetings.c.id == Translation.meeting_id)
            .where(*where)
            .order_by(
                TranslationAction.due_at.is_(None),
                TranslationAction.due_at,
                TranslationAction.created_at.desc(),
                TranslationAction.id,
            )
            .offset(off)
            .limit(size)
        )
    ).all()
    out = [
        ActionWithSourceRow(
            _action(a), a.translation_id, pid, pname or "", mid, mtitle, src, a.created_at
        )
        for a, pid, pname, mid, mtitle, src in rows
    ]
    return out, total


# ---------- 용어 ----------


@dataclass(frozen=True)
class TermDetailRow:
    term: Term
    creator_nickname: str
    examples: tuple[tuple[TermExample, str], ...]
    card: dict[str, object] | None


async def get_term(s: AsyncSession, term_id: int, user_id: int | None) -> TermDetailRow:
    t = await s.get(Term, term_id)
    if t is None or t.status != "APPROVED":
        raise DomainError(ErrorCode.TERM_NOT_FOUND, "용어를 찾을 수 없어요.")
    await s.execute(sa.update(Term).where(Term.id == t.id).values(view_count=Term.view_count + 1))
    nickname = (
        await s.execute(sa.select(_users.c.nickname).where(_users.c.id == t.created_by))
    ).scalar() or ""
    ex_rows = (
        await s.execute(
            sa.select(TermExample, _users.c.nickname)
            .outerjoin(_users, _users.c.id == TermExample.created_by)
            .where(TermExample.term_id == t.id)
            .order_by(TermExample.id)
            .limit(5)
        )
    ).all()
    card = None
    if user_id is not None:
        row = (
            await s.execute(
                sa.select(
                    _cards.c.id,
                    _cards.c.status,
                    _cards.c.interval_days,
                    _cards.c.repetition_count,
                    _cards.c.due_date,
                ).where(_cards.c.user_id == user_id, _cards.c.term_id == t.id)
            )
        ).first()
        if row is not None:
            card = dict(row._mapping)
    await s.refresh(t)
    return TermDetailRow(t, nickname, tuple((e, n or "") for e, n in ex_rows), card)
