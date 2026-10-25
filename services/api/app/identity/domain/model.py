"""identity 도메인: 프레임워크·DB 를 모르는 값과 포트(Protocol)."""

from dataclasses import dataclass
from datetime import datetime
from typing import Protocol


@dataclass(frozen=True)
class OAuthIdentity:
    """제공자가 확인해 준 사람. provider_id = 제공자의 sub."""

    provider: str  # APPLE | GOOGLE | KAKAO (dbml auth_provider)
    provider_id: str
    email: str
    profile_image_url: str | None = None


@dataclass(frozen=True)
class LevelInfo:
    code: str
    name: str
    min_score: int
    max_score: int
    badge_image_url: str | None


@dataclass(frozen=True)
class Account:
    id: int
    email: str
    provider: str
    nickname: str
    job_group: str | None
    profile_image_url: str | None
    role: str
    best_score: int
    current_streak: int
    level: LevelInfo | None
    current_project_id: int | None
    reminder_hour: int
    action_alert_enabled: bool
    onboarded_at: datetime | None
    created_at: datetime


class OAuthProvider(Protocol):
    async def exchange(self, code: str, redirect_uri: str) -> OAuthIdentity:
        """code 를 제공자에 교환해 신원을 돌려준다. 실패하면 DomainError(OAUTH_CODE_INVALID)."""
        ...


class AccountRepository(Protocol):
    async def by_provider(self, provider: str, provider_id: str) -> Account | None: ...
    async def by_email(self, email: str) -> Account | None: ...
    async def by_id(self, user_id: int) -> Account | None: ...
    async def nickname_taken(self, nickname: str) -> bool: ...
    async def create(self, identity: OAuthIdentity, nickname: str) -> tuple[Account, bool]:
        """(계정, 새로 만들었는지).

        같은 (provider, provider_id) 가 동시에 생겼으면 (기존 계정, False).
        """
        ...
