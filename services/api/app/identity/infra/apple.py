"""Sign in with Apple: 네이티브 앱이 받은 authorization code 를 Apple 토큰 엔드포인트에 교환하고
돌아온 id_token 을 Apple 공개키(JWKS)로 검증한다 (14번 §4).

- client_secret = 우리 .p8 키로 서명한 ES256 JWT (iss=팀 ID, sub=client_id, aud=Apple, 5분).
- 네이티브 앱 흐름은 redirect_uri 를 보내지 않는다. 계약상 받는 redirectUri 는 검증 대상이 아니다.
- 실패 이유(제공자 응답 본문)는 사용자·로그에 그대로 내보내지 않는다.
"""

import logging
import time
from collections.abc import Callable
from typing import Any

import httpx
import jwt

from app.core.errors import DomainError, ErrorCode
from app.identity.domain.model import OAuthIdentity

log = logging.getLogger(__name__)

APPLE_ISSUER = "https://appleid.apple.com"
TOKEN_URL = f"{APPLE_ISSUER}/auth/token"
KEYS_URL = f"{APPLE_ISSUER}/auth/keys"
JWKS_TTL_SEC = 3600
# 모르는 kid 로 JWKS 를 다시 받는 최소 간격. 없으면 요청마다 Apple 키 엔드포인트를 친다.
JWKS_MIN_REFETCH_SEC = 60


def _fail() -> DomainError:
    return DomainError(ErrorCode.OAUTH_CODE_INVALID, "로그인에 실패했어요. 다시 시도해 주세요.")


class AppleOAuth:
    def __init__(
        self,
        http: httpx.AsyncClient,
        *,
        client_id: str,
        team_id: str,
        key_id: str,
        private_key: str,
        clock: Callable[[], float] = time.time,
    ) -> None:
        self._http = http
        self._client_id = client_id
        self._team_id = team_id
        self._key_id = key_id
        self._private_key = private_key
        self._clock = clock
        self._jwks: dict[str, Any] = {}
        self._jwks_at = 0.0
        self._jwks_tried_at = float("-inf")

    @property
    def configured(self) -> bool:
        return bool(self._team_id and self._key_id and self._private_key)

    def _client_secret(self) -> str:
        now = int(self._clock())
        claims = {
            "iss": self._team_id,
            "iat": now,
            "exp": now + 300,
            "aud": APPLE_ISSUER,
            "sub": self._client_id,
        }
        return jwt.encode(
            claims, self._private_key, algorithm="ES256", headers={"kid": self._key_id}
        )

    async def _refresh_jwks(self) -> None:
        self._jwks_tried_at = self._clock()
        r = await self._http.get(KEYS_URL)
        r.raise_for_status()
        keys = r.json()["keys"]
        self._jwks = {str(k["kid"]): k for k in keys}
        self._jwks_at = self._clock()

    async def _jwk(self, kid: str) -> Any:
        now = self._clock()
        stale = now - self._jwks_at > JWKS_TTL_SEC
        # 모르는 kid = Apple 키 회전 → 다시 받는다. 단 최소 간격 안에서는 다시 치지 않는다.
        unknown = kid not in self._jwks and now - self._jwks_tried_at >= JWKS_MIN_REFETCH_SEC
        if stale or unknown:
            try:
                await self._refresh_jwks()
            except (httpx.HTTPError, KeyError, TypeError, ValueError):
                if kid not in self._jwks:
                    raise
                log.warning("apple_jwks_refresh_failed using_cached=true")
        if kid not in self._jwks:
            raise jwt.InvalidTokenError("unknown apple kid")
        return jwt.PyJWK(self._jwks[kid]).key

    async def exchange(self, code: str, redirect_uri: str) -> OAuthIdentity:
        if not self.configured:
            log.error("apple_oauth_not_configured")
            raise _fail()
        try:
            r = await self._http.post(
                TOKEN_URL,
                data={
                    "client_id": self._client_id,
                    "client_secret": self._client_secret(),
                    "code": code,
                    "grant_type": "authorization_code",
                },
            )
        except httpx.HTTPError as e:
            log.warning("apple_token_unreachable type=%s", type(e).__name__)
            raise _fail() from e
        if r.status_code != 200:
            log.info("apple_token_rejected status=%s", r.status_code)
            raise _fail()
        try:
            id_token = r.json()["id_token"]
            key = await self._jwk(jwt.get_unverified_header(id_token)["kid"])
            claims = jwt.decode(
                id_token,
                key,
                algorithms=["RS256"],
                audience=self._client_id,
                issuer=APPLE_ISSUER,
                options={"require": ["sub", "exp", "iat", "iss", "aud"]},
                leeway=30,
            )
        except (
            KeyError,
            TypeError,
            ValueError,
            AttributeError,
            jwt.PyJWTError,  # InvalidTokenError + PyJWKError(키 모양 이상) 등
            httpx.HTTPError,
        ) as e:
            log.warning("apple_id_token_invalid type=%s", type(e).__name__)
            raise _fail() from e

        sub = claims["sub"]
        if not isinstance(sub, str) or not sub:
            log.warning("apple_id_token_invalid type=bad_sub")
            raise _fail()
        # 이메일 공유를 거부해도 Apple 은 보통 릴레이 주소를 준다.
        # 그래도 없으면 sub 기반 자리표시자(users.email NOT NULL·unique).
        email = str(claims.get("email") or f"{sub}@apple.invalid")
        return OAuthIdentity(provider="APPLE", provider_id=sub, email=email)
