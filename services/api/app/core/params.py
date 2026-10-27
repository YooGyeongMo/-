"""계약의 id·페이지 파라미터.

계약 v1.0 은 경로 id 에 400 응답을 적지 않았다.
int64 를 넘는 id 는 "그런 자원은 없다"(404)로 답한다.
페이지 번호에는 상한이 없다 → 아주 큰 값은 빈 페이지로 답한다(DB 오프셋 넘침 방지).
"""

from typing import Annotated

from fastapi import Path, Query

from app.core.errors import DomainError, ErrorCode

INT64_MIN = -(2**63)
INT64_MAX = 2**63 - 1
MAX_OFFSET = 10_000_000

# 경로 id 는 문자열로 받아 숫자가 아니거나 int64 를 넘으면 404 로 답한다(계약에 400 이 없다).
IdPath = Annotated[str, Path()]
PageQuery = Annotated[int, Query(ge=1)]
SizeQuery = Annotated[int, Query(ge=1, le=100)]


def in_int64(value: int) -> bool:
    return INT64_MIN <= value <= INT64_MAX


def require_id(raw: str, code: ErrorCode, message: str) -> int:
    try:
        value = int(raw)
    except ValueError:
        raise DomainError(code, message) from None
    if not in_int64(value) or not raw.strip().lstrip("-").isdigit():
        raise DomainError(code, message)
    return value


def offset_of(page: int, size: int) -> int | None:
    """None 이면 범위 밖 페이지(빈 결과)."""
    offset = (page - 1) * size
    return offset if offset <= MAX_OFFSET else None


def paged(content: list[object], page: int, size: int, total: int) -> dict[str, object]:
    return {
        "content": content,
        "page": page,
        "size": size,
        "totalElements": total,
        "totalPages": (total + size - 1) // size,
    }
