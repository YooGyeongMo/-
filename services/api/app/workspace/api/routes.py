"""프로젝트 조회 (계약 v1.0 getProjects, getProject). 만들기·수정·삭제는 v1.1(#7 온보딩·A-10).

개수는 다른 컨텍스트 테이블을 이름으로만 세어 온다(컨텍스트 독립).
"""

from dataclasses import dataclass
from datetime import datetime
from typing import Any

import sqlalchemy as sa
from fastapi import APIRouter
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import schema
from app.core.auth import CurrentPrincipal
from app.core.db import DbSession
from app.core.errors import DomainError, ErrorCode
from app.core.params import IdPath, PageQuery, SizeQuery, offset_of, paged, require_id
from app.core.time import to_api
from app.workspace.infra.models import Meeting, Project

router = APIRouter(prefix="/api")

_translations = sa.table(
    "translations",
    sa.column("id"),
    sa.column("project_id"),
    sa.column("created_at", sa.DateTime()),
)
_actions = sa.table(
    "translation_actions", sa.column("translation_id"), sa.column("is_checked", sa.Boolean())
)
_cards = sa.table(
    "cards", sa.column("user_id"), sa.column("source_translation_id"), sa.column("status")
)


@dataclass
class _Stats:
    translations: int = 0
    open_actions: int = 0
    unknown_terms: int = 0
    meetings: int = 0
    last: datetime | None = None


async def _stats(s: AsyncSession, ids: list[int]) -> dict[int, _Stats]:
    """페이지의 프로젝트 전부를 한꺼번에 센다 — 프로젝트마다 6문(N+1) → 표마다 1문(GROUP BY).

    회의·카드 표는 열린 뒤에만 센다(ADR-0021). 없으면 0 이 계약상 맞는 값이다(회의·카드가 없다).
    """
    out = {pid: _Stats() for pid in ids}
    if not ids:
        return out
    tr = _translations.c
    for pid, n, last in await s.execute(
        sa.select(tr.project_id, sa.func.count(), sa.func.max(tr.created_at))
        .where(tr.project_id.in_(ids))
        .group_by(tr.project_id)
    ):
        out[pid].translations, out[pid].last = int(n), last
    for pid, n in await s.execute(
        sa.select(tr.project_id, sa.func.count())
        .select_from(_actions)
        .join(_translations, tr.id == _actions.c.translation_id)
        .where(tr.project_id.in_(ids), _actions.c.is_checked.is_(False))
        .group_by(tr.project_id)
    ):
        out[pid].open_actions = int(n)
    if schema.has("cards"):
        for pid, n in await s.execute(
            sa.select(tr.project_id, sa.func.count())
            .select_from(_cards)
            .join(_translations, tr.id == _cards.c.source_translation_id)
            .where(tr.project_id.in_(ids), _cards.c.status != "MASTERED")
            .group_by(tr.project_id)
        ):
            out[pid].unknown_terms = int(n)
    if schema.has("meetings"):
        for pid, n, last in await s.execute(
            sa.select(Meeting.project_id, sa.func.count(), sa.func.max(Meeting.created_at))
            .where(Meeting.project_id.in_(ids))
            .group_by(Meeting.project_id)
        ):
            st = out[pid]
            st.meetings = int(n)
            st.last = last if st.last is None or (last is not None and last > st.last) else st.last
    return out


def _body(p: Project, st: _Stats) -> dict[str, Any]:
    return {
        "projectId": p.id,
        "name": p.name,
        "description": p.description or "",
        "meetingCount": st.meetings,
        "color": p.color,
        "translationCount": st.translations,
        "openActionCount": st.open_actions,
        "unknownTermCount": st.unknown_terms,
        "isDefault": bool(p.is_default),
        "lastActivityAt": to_api(st.last or p.updated_at or p.created_at),
        "createdAt": to_api(p.created_at),
    }


@router.get("/projects")
async def get_projects(
    principal: CurrentPrincipal, db: DbSession, page: PageQuery = 1, size: SizeQuery = 10
) -> dict[str, object]:
    where = Project.user_id == principal.user_id

    async def total() -> int:
        q = sa.select(sa.func.count()).select_from(Project).where(where)
        return int((await db.execute(q)).scalar_one())

    off = offset_of(page, size)
    if off is None:
        return paged([], page, size, await total())
    rows = (
        await db.execute(
            sa.select(Project, sa.func.count().over())
            .where(where)
            .order_by(Project.is_default.desc(), Project.created_at, Project.id)
            .offset(off)
            .limit(size)
        )
    ).all()
    if not rows:
        return paged([], page, size, 0 if off == 0 else await total())
    projects = [p for p, _ in rows]
    stats = await _stats(db, [p.id for p in projects])
    return paged([_body(p, stats[p.id]) for p in projects], page, size, int(rows[0][1]))


@router.get("/projects/{projectId}")
async def get_project(
    projectId: IdPath,  # noqa: N803
    principal: CurrentPrincipal,
    db: DbSession,
) -> dict[str, Any]:
    pid = require_id(projectId, ErrorCode.PROJECT_NOT_FOUND, "프로젝트를 찾을 수 없어요.")
    p = await db.get(Project, pid)
    if p is None:
        raise DomainError(ErrorCode.PROJECT_NOT_FOUND, "프로젝트를 찾을 수 없어요.")
    if p.user_id != principal.user_id:
        raise DomainError(ErrorCode.NOT_OWNER, "내 프로젝트가 아니에요.")
    return _body(p, (await _stats(db, [p.id]))[p.id])
