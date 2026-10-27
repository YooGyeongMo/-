"""대기 마이그레이션(migrations/staged)을 head 위에 붙이면 계약 17테이블과 차이가 0 인지
(ADR-0021).

v1.0 DB 는 8테이블만 만든다. 나머지 9개는 기능이 열릴 때 붙인다. 그때 가서 초안이 계약과
어긋나 있으면 늦게 알게 되므로, 매번 "head + 대기 초안 = dbml v1.0 전체"를 확인한다.
내리면 다시 8테이블.
"""

import importlib.util
import os
from pathlib import Path
from types import ModuleType

import pytest
import sqlalchemy as sa
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.operations import Operations

from app.all_models import metadata
from app.core.schema import ACTIVE_TABLES, STAGED

API_DIR = Path(__file__).resolve().parent.parent
ORDER = ("learning", "meetings", "notify")  # 서로 참조하지 않는다. 열릴 순서(v1.1 → v1.2)


def _load(name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        f"staged_{name}", API_DIR / "migrations" / "staged" / f"{name}.py"
    )
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _urls(tmp_path: Path) -> dict[str, str]:
    urls = {"sqlite": f"sqlite+aiosqlite:///{tmp_path / 'staged.db'}"}
    if mysql := os.environ.get("MWONMAL_TEST_MYSQL_URL"):
        urls["mysql"] = mysql
    return urls


def _sync(url: str) -> str:
    return url.replace("+aiosqlite", "").replace("+aiomysql", "+pymysql")


def test_staged_covers_every_deferred_table() -> None:
    staged = set().union(*STAGED.values())
    assert staged | ACTIVE_TABLES == set(metadata.tables)
    assert not staged & ACTIVE_TABLES
    assert set(STAGED) == set(ORDER)


@pytest.mark.parametrize("backend", ["sqlite", "mysql"])
def test_head_plus_staged_equals_contract(tmp_path: Path, backend: str) -> None:
    urls = _urls(tmp_path)
    if backend not in urls:
        pytest.skip("MWONMAL_TEST_MYSQL_URL 없음")
    cfg = Config(str(API_DIR / "alembic.ini"))
    cfg.attributes["database_url"] = urls[backend]
    command.upgrade(cfg, "head")
    engine = sa.create_engine(_sync(urls[backend]))
    modules = [_load(n) for n in ORDER]
    try:
        with engine.begin() as conn:
            ops = Operations(MigrationContext.configure(conn))
            for m in modules:
                vars(m)["op"] = ops  # 초안은 `from alembic import op` 를 쓴다 → 이 연결로 묶는다
                m.upgrade()
        with engine.connect() as conn:
            diff = compare_metadata(MigrationContext.configure(conn), metadata)
            tables = set(sa.inspect(conn).get_table_names()) - {"alembic_version"}
        assert tables == set(metadata.tables)
        assert diff == [], diff
        with engine.begin() as conn:
            ops = Operations(MigrationContext.configure(conn))
            for m in reversed(modules):
                vars(m)["op"] = ops
                m.downgrade()
        with engine.connect() as conn:
            assert set(sa.inspect(conn).get_table_names()) - {"alembic_version"} == ACTIVE_TABLES
    finally:
        engine.dispose()
        command.downgrade(cfg, "base")
