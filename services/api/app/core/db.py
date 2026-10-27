"""DB 공용: 선언 Base, 엔진, 핑. 테이블 정의는 각 컨텍스트의 `infra/models.py` 에 있다.

스키마의 단일 원본은 `contracts/db.dbml` v1.0 이다 (14번 §6). 모델을 바꾸면
`tests/test_schema_matches_dbml.py` 가 dbml 과의 차이를 잡는다.
"""

from collections.abc import AsyncIterator
from functools import lru_cache
from typing import Annotated

import sqlalchemy as sa
from fastapi import Depends
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from app.core.settings import settings

# dbml 에 이름이 없는 PK·FK 에만 쓰인다. 인덱스 이름은 dbml 의 것을 그대로 쓴다.
NAMING_CONVENTION = {
    "pk": "pk_%(table_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
}

# SQLite 는 INTEGER PRIMARY KEY 만 자동 증가하므로 테스트용 변형을 둔다.
BigIntPK = sa.BigInteger().with_variant(sa.Integer(), "sqlite")


class Base(DeclarativeBase):
    metadata = sa.MetaData(naming_convention=NAMING_CONVENTION)


def now() -> sa.TextClause:
    return sa.text("CURRENT_TIMESTAMP")


@lru_cache(maxsize=1)
def get_engine() -> AsyncEngine:
    # hide_parameters: DB 오류 메시지·로그에 바인드 값(이메일, 사용자 원문 등)을 싣지 않는다
    # (ADR-0008 / REQ-14: 원문·개인정보는 로그에 남기지 않는다).
    # pool_pre_ping 은 빌릴 때마다 COM_PING 1왕복(~0.3ms)이 든다. 그래도 켠다 — DB 재시작·
    # 장애 조치 뒤 죽은 연결로 첫 요청이 500 나는 것보다 싸다(ADR-0021 §성능).
    pool: dict[str, object] = {}
    if not settings.database_url.startswith("sqlite"):
        pool = {
            "pool_size": settings.db_pool_size,
            "max_overflow": settings.db_max_overflow,
            "pool_timeout": settings.db_pool_timeout_sec,
            "pool_recycle": settings.db_pool_recycle_sec,
        }
    return create_async_engine(
        settings.database_url, pool_pre_ping=True, hide_parameters=True, **pool
    )


async def ping(engine: AsyncEngine) -> bool:
    try:
        async with engine.connect() as conn:
            await conn.execute(sa.text("SELECT 1"))
    except Exception:  # noqa: BLE001 - /ready 는 원인과 무관하게 false 만 알면 된다
        return False
    return True


@lru_cache(maxsize=1)
def _sessionmaker() -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(get_engine(), expire_on_commit=False)


async def session() -> AsyncIterator[AsyncSession]:
    """FastAPI 의존성. 요청 하나 = 트랜잭션 하나(14번 §6). 예외면 롤백, 아니면 커밋."""
    async with _sessionmaker()() as s, s.begin():
        yield s


# 라우터는 반드시 이 별칭을 쓴다. scope="function" 이 없으면 FastAPI 는 yield 뒤(커밋)를
# 응답을 보낸 다음에 실행한다 → 커밋이 실패해도 클라이언트는 이미 200 을 받는다.
# 이 별칭은 핸들러가 끝나면 바로 커밋하고, 커밋이 실패하면 500 을 돌려준다.
DbSession = Annotated[AsyncSession, Depends(session, scope="function")]
