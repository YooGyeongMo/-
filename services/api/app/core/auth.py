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


def optional_principal(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> Principal | None:
    """로그인이 선택인 조회(getTerm). 토큰이 있으면 검증하고, 틀리면 401."""
    if creds is None:
        return None
    return current_principal(creds)


OptionalPrincipal = Annotated[Principal | None, Depends(optional_principal)]
