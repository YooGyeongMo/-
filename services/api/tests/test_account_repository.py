"""SqlAccountRepository: 같은 사람의 첫 로그인이 동시에 두 번 와도 계정은 하나."""

import os
from pathlib import Path

import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.all_models import metadata
from app.identity.domain.model import OAuthIdentity
from app.identity.infra.repository import SqlAccountRepository


@pytest.mark.anyio
@pytest.mark.parametrize("backend", ["sqlite", "mysql"])
async def test_create_twice_returns_existing(tmp_path: Path, backend: str) -> None:
    url = f"sqlite+aiosqlite:///{tmp_path / 'r.db'}"
    if backend == "mysql":
        url = os.environ.get("MWONMAL_TEST_MYSQL_URL", "")
        if not url:
            pytest.skip("MWONMAL_TEST_MYSQL_URL 없음")
    engine = create_async_engine(url)
    async with engine.begin() as conn:
        await conn.run_sync(metadata.drop_all)
        await conn.run_sync(metadata.create_all)
    maker = async_sessionmaker(engine, expire_on_commit=False)
    who = OAuthIdentity(provider="APPLE", provider_id="same", email="s@x.com")
    async with maker() as s, s.begin():
        repo = SqlAccountRepository(s)
        first, created1 = await repo.create(who, "닉1")
        second, created2 = await repo.create(who, "닉2")
    assert (created1, created2) == (True, False)
    assert second.id == first.id and second.nickname == "닉1"
    async with engine.begin() as conn:
        await conn.run_sync(metadata.drop_all)
    await engine.dispose()


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"
