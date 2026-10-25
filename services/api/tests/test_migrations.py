"""마이그레이션 왕복: upgrade → downgrade → upgrade, 그리고 모델과 차이 0 (`alembic check`).

SQLite 는 항상 돈다. MySQL 은 `MWONMAL_TEST_MYSQL_URL` 이 있을 때만
(CI 의 mysql 서비스, 로컬 Compose).
"""

import os
from pathlib import Path

import pytest
import sqlalchemy as sa
from alembic import command
from alembic.config import Config

from app.all_models import metadata

API_DIR = Path(__file__).resolve().parents[1]


def _config(url: str) -> Config:
    cfg = Config(str(API_DIR / "alembic.ini"))
    cfg.attributes["database_url"] = url
    return cfg


def _sync_url(url: str) -> str:
    return url.replace("+aiosqlite", "").replace("+aiomysql", "+pymysql")


def _tables(url: str) -> set[str]:
    engine = sa.create_engine(_sync_url(url))
    try:
        return set(sa.inspect(engine).get_table_names()) - {"alembic_version"}
    finally:
        engine.dispose()


def _urls(tmp_path: Path) -> list[str]:
    urls = [f"sqlite+aiosqlite:///{tmp_path / 'mig.db'}"]
    if mysql := os.environ.get("MWONMAL_TEST_MYSQL_URL"):
        urls.append(mysql)
    return urls


@pytest.mark.parametrize("backend", ["sqlite", "mysql"])
def test_round_trip_and_no_drift(tmp_path: Path, backend: str) -> None:
    urls = {u.split("+")[0]: u for u in _urls(tmp_path)}
    if backend not in urls:
        pytest.skip("MWONMAL_TEST_MYSQL_URL 없음")
    url = urls[backend]
    cfg = _config(url)

    command.upgrade(cfg, "head")
    assert _tables(url) == set(metadata.tables)
    command.downgrade(cfg, "base")
    assert _tables(url) == set()
    command.upgrade(cfg, "head")
    command.check(cfg)  # 모델과 마이그레이션 사이 차이가 있으면 예외
    command.downgrade(cfg, "base")
