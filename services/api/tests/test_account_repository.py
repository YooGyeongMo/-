"""SqlAccountRepository: 같은 사람의 첫 로그인이 동시에 두 번 와도 계정은 하나."""

import os
from pathlib import Path

import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.all_models import active_metadata
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
        await conn.run_sync(active_metadata().drop_all)
        await conn.run_sync(active_metadata().create_all)
    maker = async_sessionmaker(engine, expire_on_commit=False)
    who = OAuthIdentity(provider="APPLE", provider_id="same", email="s@x.com")
    async with maker() as s, s.begin():
        repo = SqlAccountRepository(s)
        first, created1 = await repo.create(who, "닉1")
        second, created2 = await repo.create(who, "닉2")
    assert (created1, created2) == (True, False)
    assert second.id == first.id and second.nickname == "닉1"
    async with engine.begin() as conn:
        await conn.run_sync(active_metadata().drop_all)
    await engine.dispose()


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


async def _fresh(url: str):  # type: ignore[no-untyped-def]
    engine = create_async_engine(url)
    async with engine.begin() as conn:
        await conn.run_sync(active_metadata().drop_all)
        await conn.run_sync(active_metadata().create_all)
    return engine


@pytest.mark.anyio
@pytest.mark.parametrize(
    ("other", "expect"),
    [
        # 같은 Apple 계정의 첫 로그인 두 개가 겹침 → 늦은 쪽도 같은 계정을 받는다.
        (OAuthIdentity(provider="APPLE", provider_id="same", email="s@x.com"), "same"),
        # 다른 Apple 계정이 같은 이메일로 먼저 커밋 → 순차 경로와 같은 409.
        (OAuthIdentity(provider="APPLE", provider_id="other", email="s@x.com"), "409"),
    ],
)
async def test_real_race_on_mysql(other: OAuthIdentity, expect: str) -> None:
    """두 트랜잭션이 실제로 겹친다. MySQL 기본 격리(REPEATABLE READ)에선 먼저 읽은 스냅숏 때문에
    IntegrityError 뒤의 평범한 SELECT 가 상대 행을 못 본다 → 잠금 읽기로 최신 커밋을 봐야 한다."""
    url = os.environ.get("MWONMAL_TEST_MYSQL_URL", "")
    if not url:
        pytest.skip("MWONMAL_TEST_MYSQL_URL 없음")
    from app.core.errors import DomainError

    engine = await _fresh(url)
    maker = async_sessionmaker(engine, expire_on_commit=False)
    me = OAuthIdentity(provider="APPLE", provider_id="same", email="s@x.com")
    try:
        async with maker() as a, a.begin():
            repo_a = SqlAccountRepository(a)
            assert await repo_a.by_provider("APPLE", "same") is None  # 스냅숏 시작
            assert await repo_a.by_email("s@x.com") is None
            async with maker() as b, b.begin():
                winner, _ = await SqlAccountRepository(b).create(other, "닉B")
            if expect == "same":
                got, created = await repo_a.create(me, "닉A")
                assert created is False and got.id == winner.id
            else:
                with pytest.raises(DomainError) as e:
                    await repo_a.create(me, "닉A")
                assert e.value.code.value == "EMAIL_ALREADY_REGISTERED"
    finally:
        async with engine.begin() as conn:
            await conn.run_sync(active_metadata().drop_all)
        await engine.dispose()
