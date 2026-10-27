"""첫 해석 경합: 기본 프로젝트가 동시에 만들어져도 하나만, 교착·500 없음(레드팀 1차 H-3, 2차 B-2).

MySQL(InnoDB)에서만 드러나는 잠금 문제라 CI 의 MySQL 서비스(MWONMAL_TEST_MYSQL_URL)로 실제로 겹친다.
"""

import asyncio
import os
from pathlib import Path

import pytest
import sqlalchemy as sa
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.all_models import active_metadata
from app.decode.infra.repository import ensure_default_project


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.mark.anyio
@pytest.mark.parametrize("backend", ["sqlite", "mysql"])
async def test_concurrent_default_project(tmp_path: Path, backend: str) -> None:
    url = f"sqlite+aiosqlite:///{tmp_path / 'p.db'}"
    if backend == "mysql":
        url = os.environ.get("MWONMAL_TEST_MYSQL_URL", "")
        if not url:
            pytest.skip("MWONMAL_TEST_MYSQL_URL 없음")
    engine = create_async_engine(url)
    async with engine.begin() as conn:
        await conn.run_sync(active_metadata().drop_all)
        await conn.run_sync(active_metadata().create_all)
        await conn.execute(
            sa.text(
                "INSERT INTO users (email, provider, provider_id, nickname) "
                "VALUES ('r@x.com', 'APPLE', 'race', '경합')"
            )
        )
        user_id: int = (await conn.execute(sa.text("SELECT id FROM users"))).scalar_one()
    maker = async_sessionmaker(engine, expire_on_commit=False)

    async def one() -> int:
        async with maker() as s, s.begin():
            return (await ensure_default_project(s, int(user_id))).id

    workers = 1 if backend == "sqlite" else 8  # SQLite 는 쓰기를 직렬화한다
    ids = await asyncio.gather(*(one() for _ in range(workers)))
    assert len(set(ids)) == 1
    async with engine.connect() as conn:
        count: int = (await conn.execute(sa.text("SELECT COUNT(*) FROM projects"))).scalar_one()
    assert count == 1
    async with engine.begin() as conn:
        await conn.run_sync(active_metadata().drop_all)
    await engine.dispose()
