from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import create_async_engine

from app import main


@pytest.fixture
def client() -> Iterator[TestClient]:
    with TestClient(main.app) as c:
        yield c


def test_ready_ok_when_db_answers(
    client: TestClient, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    engine = create_async_engine(f"sqlite+aiosqlite:///{tmp_path / 'r.db'}")
    monkeypatch.setattr(main, "get_engine", lambda: engine)
    r = client.get("/ready")
    assert r.status_code == 200
    assert r.json() == {"status": "ready", "db": "up"}


def test_ready_503_when_db_down(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    engine = create_async_engine("mysql+aiomysql://nobody:x@127.0.0.1:1/none")
    monkeypatch.setattr(main, "get_engine", lambda: engine)
    r = client.get("/ready")
    assert r.status_code == 503
    assert r.json() == {"status": "not_ready", "db": "down"}
