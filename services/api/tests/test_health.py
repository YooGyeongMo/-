from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health() -> None:
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_serves_original_contract() -> None:
    r = client.get("/openapi.json")
    assert r.status_code == 200
    body = r.json()
    assert body["openapi"] == "3.0.3"
    methods = ("get", "post", "put", "patch", "delete")
    ops = sum(1 for item in body["paths"].values() for m in item if m in methods)
    assert ops == 43
