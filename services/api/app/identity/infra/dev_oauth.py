"""로컬·테스트 전용 가짜 로그인(MWONMAL_DEV_LOGIN=1). code = "dev:<이름>".

시뮬레이터 E2E 와 계약 검사(#110)가 Apple 키 없이 성공 경로를 돌게 한다.
local·test 밖에서 켜면 기동이 거부된다(core.security.check_keys). 실제 Apple 로그인과 섞이지 않게
provider_id 앞에 "dev-" 를 붙이고 이메일은 .invalid 도메인을 쓴다.
"""

import re

from app.core.errors import DomainError, ErrorCode
from app.identity.domain.model import OAuthIdentity, OAuthProvider

PREFIX = "dev:"
_NAME = re.compile(r"^[a-z0-9_-]{1,32}$")


class DevOAuth:
    """dev: 코드만 처리하고 나머지는 진짜 제공자에게 넘긴다."""

    def __init__(self, real: OAuthProvider) -> None:
        self._real = real

    async def exchange(self, code: str, redirect_uri: str) -> OAuthIdentity:
        if not code.startswith(PREFIX):
            return await self._real.exchange(code, redirect_uri)
        name = code[len(PREFIX) :]
        if not _NAME.match(name):
            raise DomainError(
                ErrorCode.OAUTH_CODE_INVALID, "로그인에 실패했어요. 다시 시도해 주세요."
            )
        return OAuthIdentity(
            provider="APPLE", provider_id=f"dev-{name}", email=f"{name}@dev.mwonmal.invalid"
        )
