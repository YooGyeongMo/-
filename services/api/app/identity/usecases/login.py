"""POST /auth/oauth/{provider}: code 교환 → 회원 조회/생성 → 우리 토큰 발급 (14번 §4)."""

import secrets
from collections.abc import Callable
from dataclasses import dataclass

from app.core.errors import DomainError, ErrorCode
from app.identity.domain.model import Account, AccountRepository, OAuthProvider

NICKNAME_PREFIX = "판교뉴비"


@dataclass(frozen=True)
class LoginResult:
    account: Account
    is_new_user: bool
    access_token: str

    @property
    def needs_onboarding(self) -> bool:
        return self.is_new_user or self.account.onboarded_at is None


async def _free_nickname(repo: AccountRepository) -> str:
    for _ in range(20):
        candidate = f"{NICKNAME_PREFIX}{secrets.randbelow(1_000_000):06d}"
        if not await repo.nickname_taken(candidate):
            return candidate
    raise RuntimeError("닉네임 후보 20개가 모두 사용 중")  # 100만 칸에서 사실상 불가


async def login(
    *,
    code: str,
    redirect_uri: str,
    oauth: OAuthProvider,
    repo: AccountRepository,
    issue_token: Callable[[int, str], str],
) -> LoginResult:
    identity = await oauth.exchange(code, redirect_uri)

    account = await repo.by_provider(identity.provider, identity.provider_id)
    is_new = False
    if account is None:
        other = await repo.by_email(identity.email)
        if other is not None:
            raise DomainError(
                ErrorCode.EMAIL_ALREADY_REGISTERED,
                "이미 다른 방법으로 가입한 이메일이에요. 처음 가입한 방법으로 로그인해 주세요.",
            )
        account, is_new = await repo.create(identity, await _free_nickname(repo))

    return LoginResult(
        account=account,
        is_new_user=is_new,
        access_token=issue_token(account.id, account.role),
    )
