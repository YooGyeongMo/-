"""요청의 Bearer 토큰 → Principal. 모든 컨텍스트가 같은 의존성을 쓴다."""

from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.errors import DomainError, ErrorCode
from app.core.security import Principal, verify_token

_bearer = HTTPBearer(auto_error=False)


def current_principal(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> Principal:
    if creds is None or creds.scheme.lower() != "bearer":
        raise DomainError(ErrorCode.UNAUTHORIZED, "로그인이 필요한 기능이에요.")
    return verify_token(creds.credentials)


CurrentPrincipal = Annotated[Principal, Depends(current_principal)]
