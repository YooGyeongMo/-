"""Auth·User 라우터 (계약 v1.0 oauthLogin, getMe). 응답 모양은 contracts/openapi.yml 이 원본."""

from functools import lru_cache
from typing import Annotated, Any, Literal

import httpx
from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.core.auth import CurrentPrincipal
from app.core.db import DbSession
from app.core.errors import DomainError, ErrorCode
from app.core.security import EPHEMERAL_ENVS, issue_token
from app.core.settings import settings
from app.core.time import to_api
from app.identity.domain.model import Account, OAuthProvider
from app.identity.infra.apple import AppleOAuth
from app.identity.infra.dev_oauth import DevOAuth
from app.identity.infra.repository import SqlAccountRepository
from app.identity.usecases.login import login
from app.identity.usecases.me import get_me

router = APIRouter(prefix="/api")


@lru_cache(maxsize=1)
def apple_oauth() -> OAuthProvider:
    return AppleOAuth(
        httpx.AsyncClient(timeout=10.0),
        client_id=settings.apple_client_id,
        team_id=settings.apple_team_id,
        key_id=settings.apple_key_id,
        private_key=settings.apple_private_key,
    )


def oauth_provider(
    provider: Literal["apple", "kakao", "google"],
    apple: Annotated[OAuthProvider, Depends(apple_oauth)],
) -> OAuthProvider:
    if provider != "apple":
        # v1.0 은 Apple 만 (ADR-0013). 카카오·Google → #90.
        raise DomainError(ErrorCode.INVALID_INPUT, "지금은 Apple 로그인만 지원해요.", "provider")
    if settings.dev_login and settings.env in EPHEMERAL_ENVS:
        return DevOAuth(apple)
    return apple


class OAuthLoginRequest(BaseModel):
    # 계약 v1.0 은 minLength 가 없다 → 빈 code 는 400 이 아니라 "틀린 code"(401, Apple 호출 없음).
    code: str
    redirectUri: str  # noqa: N815 - 계약 필드 이름 그대로


def user_response(a: Account) -> dict[str, Any]:
    level = None
    if a.level is not None:
        level = {
            "code": a.level.code,
            "name": a.level.name,
            "minScore": a.level.min_score,
            "maxScore": a.level.max_score,
            "badgeImageUrl": a.level.badge_image_url,
        }
    return {
        "userId": a.id,
        "email": a.email,
        "nickname": a.nickname,
        "jobGroup": a.job_group,
        "profileImageUrl": a.profile_image_url,
        "role": a.role,
        "bestScore": a.best_score,
        "currentStreak": a.current_streak,
        "level": level,
        "currentProjectId": a.current_project_id,
        "reminderHour": a.reminder_hour,
        "actionAlertEnabled": a.action_alert_enabled,
        "createdAt": to_api(a.created_at),
    }


@router.post("/auth/oauth/{provider}")
async def oauth_login(
    body: OAuthLoginRequest,
    oauth: Annotated[OAuthProvider, Depends(oauth_provider)],
    db: DbSession,
) -> dict[str, Any]:
    result = await login(
        code=body.code,
        redirect_uri=body.redirectUri,
        oauth=oauth,
        repo=SqlAccountRepository(db),
        issue_token=issue_token,
    )
    return {
        "accessToken": result.access_token,
        "isNewUser": result.is_new_user,
        "needsOnboarding": result.needs_onboarding,
        "user": user_response(result.account),
    }


@router.get("/users/me")
async def users_me(principal: CurrentPrincipal, db: DbSession) -> dict[str, Any]:
    return user_response(await get_me(user_id=principal.user_id, repo=SqlAccountRepository(db)))
