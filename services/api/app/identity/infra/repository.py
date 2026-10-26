"""AccountRepository 의 SQLAlchemy 구현."""

import sqlalchemy as sa
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import DomainError, ErrorCode
from app.identity.domain.model import Account, LevelInfo, OAuthIdentity
from app.identity.infra.models import User

# levels 는 learning 컨텍스트 테이블이지만 import 하지 않고 이름으로만 읽는다(컨텍스트 독립).
_levels = sa.table(
    "levels",
    sa.column("code"),
    sa.column("name"),
    sa.column("min_score"),
    sa.column("max_score"),
    sa.column("badge_image_url"),
)


class SqlAccountRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._s = session

    async def _to_account(self, u: User) -> Account:
        level = None
        if u.level_code is not None:
            row = (
                await self._s.execute(sa.select(_levels).where(_levels.c.code == u.level_code))
            ).first()
            if row is not None:
                level = LevelInfo(
                    row.code, row.name, row.min_score, row.max_score, row.badge_image_url
                )
        return Account(
            id=u.id,
            email=u.email,
            provider=u.provider,
            nickname=u.nickname,
            job_group=u.job_group,
            profile_image_url=u.profile_image_url,
            role=u.role,
            best_score=u.best_score,
            current_streak=u.current_streak,
            level=level,
            current_project_id=u.current_project_id,
            reminder_hour=u.reminder_hour,
            action_alert_enabled=u.action_alert_enabled,
            onboarded_at=u.onboarded_at,
            created_at=u.created_at,
        )

    async def _one(self, stmt: sa.Select[User]) -> Account | None:
        u = (await self._s.execute(stmt)).scalar_one_or_none()
        return None if u is None else await self._to_account(u)

    async def by_provider(self, provider: str, provider_id: str) -> Account | None:
        return await self._one(
            sa.select(User).where(User.provider == provider, User.provider_id == provider_id)
        )

    async def by_email(self, email: str) -> Account | None:
        return await self._one(sa.select(User).where(User.email == email))

    async def by_id(self, user_id: int) -> Account | None:
        return await self._one(sa.select(User).where(User.id == user_id))

    async def nickname_taken(self, nickname: str) -> bool:
        stmt = sa.select(sa.exists().where(User.nickname == nickname))
        return bool((await self._s.execute(stmt)).scalar())

    async def create(self, identity: OAuthIdentity, nickname: str) -> tuple[Account, bool]:
        user = User(
            email=identity.email,
            provider=identity.provider,
            provider_id=identity.provider_id,
            profile_image_url=identity.profile_image_url,
            nickname=nickname,
        )
        try:
            async with self._s.begin_nested():
                self._s.add(user)
                await self._s.flush()
        except IntegrityError:
            # MySQL 기본 격리(REPEATABLE READ)에선 이 트랜잭션이 앞서 읽은 스냅숏 때문에 평범한
            # SELECT 로는 방금 커밋된 상대 행이 안 보인다 → 잠금 읽기(FOR SHARE)로 최신 커밋을 본다.
            # 같은 사람의 첫 로그인이 동시에 두 번 → 먼저 들어간 행을 쓴다.
            existing = await self._one(
                sa.select(User)
                .where(User.provider == identity.provider, User.provider_id == identity.provider_id)
                .with_for_update(read=True)
            )
            if existing is not None:
                return existing, False
            # 다른 계정이 같은 이메일로 막 가입했다 → 순차 경로와 같은 409.
            taken = await self._one(
                sa.select(User).where(User.email == identity.email).with_for_update(read=True)
            )
            if taken is not None:
                raise DomainError(
                    ErrorCode.EMAIL_ALREADY_REGISTERED,
                    "이미 다른 방법으로 가입한 이메일이에요. 처음 가입한 방법으로 로그인해 주세요.",
                ) from None
            raise
        await self._s.refresh(user)  # server_default(created_at 등) 읽기
        return await self._to_account(user), True
