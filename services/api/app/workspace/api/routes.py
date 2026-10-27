"""프로젝트 조회 (계약 v1.0 getProjects, getProject). 만들기·수정·삭제는 v1.1(#7 온보딩·A-10).

개수는 다른 컨텍스트 테이블을 이름으로만 세어 온다(컨텍스트 독립).
"""

from datetime import datetime
from typing import Any

import sqlalchemy as sa
from fastapi import APIRouter
from sqlalchemy.ext.asyncio import AsyncSession

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


async def _body(s: AsyncSession, p: Project) -> dict[str, Any]:
    meetings = (
        await s.execute(sa.select(sa.func.count()).where(Meeting.project_id == p.id))
    ).scalar_one()
    translations = (
        await s.execute(sa.select(sa.func.count()).where(_translations.c.project_id == p.id))
    ).scalar_one()
    open_actions = (
        await s.execute(
            sa.select(sa.func.count())
            .select_from(_actions)
            .join(_translations, _translations.c.id == _actions.c.translation_id)
            .where(_translations.c.project_id == p.id, _actions.c.is_checked.is_(False))
        )
    ).scalar_one()
    unknown = (
        await s.execute(
            sa.select(sa.func.count())
            .select_from(_cards)
            .join(_translations, _translations.c.id == _cards.c.source_translation_id)
            .where(_translations.c.project_id == p.id, _cards.c.status != "MASTERED")
        )
    ).scalar_one()
    last: datetime | None = (
        await s.execute(
            sa.select(sa.func.max(_translations.c.created_at)).where(
                _translations.c.project_id == p.id
            )
        )
    ).scalar()
    last_meeting: datetime | None = (
        await s.execute(
            sa.select(sa.func.max(Meeting.created_at)).where(Meeting.project_id == p.id)
        )
    ).scalar()
    candidates = [d for d in (last, last_meeting) if d is not None]
    last_activity = max(candidates) if candidates else (p.updated_at or p.created_at)
    return {
        "projectId": p.id,
        "name": p.name,
        "description": p.description or "",
        "meetingCount": int(meetings),
        "color": p.color,
        "translationCount": int(translations),
        "openActionCount": int(open_actions),
        "unknownTermCount": int(unknown),
        "isDefault": bool(p.is_default),
        "lastActivityAt": to_api(last_activity),
        "createdAt": to_api(p.created_at),
    }


@router.get("/projects")
async def get_projects(
    principal: CurrentPrincipal, db: DbSession, page: PageQuery = 1, size: SizeQuery = 10
) -> dict[str, object]:
    where = Project.user_id == principal.user_id
    total = int(
        (
            await db.execute(sa.select(sa.func.count()).select_from(Project).where(where))
        ).scalar_one()
    )
    off = offset_of(page, size)
    if off is None:
        return paged([], page, size, total)
    rows = (
        await db.execute(
            sa.select(Project)
            .where(where)
            .order_by(Project.is_default.desc(), Project.created_at, Project.id)
            .offset(off)
            .limit(size)
        )
    ).scalars()
    return paged([await _body(db, p) for p in rows], page, size, total)


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
    return await _body(db, p)
