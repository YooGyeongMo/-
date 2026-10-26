"""레드팀 2026-10-26 회귀 테스트: 트랜잭션 경계, 본문 한도, 에러 봉투, 보안 헤더, 키 기동 검사."""

import logging
from collections.abc import AsyncIterator, Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import security
from app.core.db import get_engine, session
from app.core.settings import settings
from app.main import app
from tests.conftest import FakeApple
from tests.contract_schema import assert_matches

LOGIN = "/api/auth/oauth/apple"
BODY = {"code": "c-1", "redirectUri": "kr.mwonmal.app://auth"}


@pytest.fixture
def lenient(client: TestClient) -> Iterator[TestClient]:
    """서버 예외를 테스트로 올리지 않고 실제 응답을 본다 (client 픽스처의 DB·Apple 재사용)."""
    with TestClient(app, raise_server_exceptions=False) as c:
        yield c


# --- 트랜잭션: 커밋은 응답 전에 -------------------------------------------------


def test_commit_failure_is_500_not_200(client: TestClient, fake_apple: FakeApple) -> None:
    """커밋이 실패하면 클라이언트는 200(토큰)이 아니라 500 을 받아야 한다.

    scope="function" 이 없으면 FastAPI 는 커밋을 응답 전송 뒤에 해서 200 + 저장 안 된 계정이 된다.
    """
    real = app.dependency_overrides[session]

    async def commit_fails() -> AsyncIterator[AsyncSession]:
        async for s in real():
            yield s
            raise RuntimeError("commit failed: Duplicate entry 'victim@example.com'")

    app.dependency_overrides[session] = commit_fails
    fake_apple.add_user("c-1", sub="s")
    with TestClient(app, raise_server_exceptions=False) as c:
        r = c.post(LOGIN, json=BODY)
    app.dependency_overrides[session] = real
    assert r.status_code == 500
    assert "accessToken" not in r.text
    assert r.json()["code"] == "INTERNAL_ERROR"
    assert "victim" not in r.text and "Duplicate" not in r.text


# --- 처리 안 된 예외: 봉투 + 로그에 메시지 없음 -----------------------------------


def test_unhandled_error_is_enveloped_and_message_not_logged(
    lenient: TestClient, fake_apple: FakeApple, caplog: pytest.LogCaptureFixture
) -> None:
    async def boom() -> AsyncIterator[AsyncSession]:
        raise RuntimeError("Duplicate entry 'victim@example.com' for key 'ux_users_email'")
        yield  # pragma: no cover

    real = app.dependency_overrides[session]
    app.dependency_overrides[session] = boom
    fake_apple.add_user("c-1", sub="s")
    with caplog.at_level(logging.DEBUG):
        r = lenient.post(LOGIN, json=BODY)
    app.dependency_overrides[session] = real
    assert r.status_code == 500
    assert_matches("Error", r.json())
    assert "victim" not in r.text
    assert "victim@example.com" not in caplog.text
    assert "unhandled_error type=RuntimeError" in caplog.text


# --- 라우팅 실패도 Error 봉투 ------------------------------------------------------


@pytest.mark.parametrize(
    ("method", "path", "status", "code"),
    [
        ("GET", "/nope", 404, "NOT_FOUND"),
        ("DELETE", "/api/users/me", 405, "METHOD_NOT_ALLOWED"),
        ("GET", LOGIN, 405, "METHOD_NOT_ALLOWED"),
    ],
)
def test_framework_errors_use_error_envelope(
    client: TestClient, method: str, path: str, status: int, code: str
) -> None:
    r = client.request(method, path)
    assert r.status_code == status
    assert_matches("Error", r.json())
    assert r.json()["code"] == code
    assert "detail" not in r.json()


# --- 본문 크기 한도 ------------------------------------------------------------------


def test_oversized_body_by_content_length_is_413(client: TestClient, fake_apple: FakeApple) -> None:
    r = client.post(LOGIN, json={"code": "a" * (2 * 1024 * 1024), "redirectUri": "x"})
    assert r.status_code == 413
    assert_matches("Error", r.json())
    assert r.json()["code"] == "FILE_TOO_LARGE"
    assert fake_apple.token_requests == []  # Apple 로 넘기지 않는다


def test_oversized_chunked_body_is_413(client: TestClient, fake_apple: FakeApple) -> None:
    def chunks() -> Iterator[bytes]:
        yield b'{"code":"'
        for _ in range(40):
            yield b"a" * 65536
        yield b'","redirectUri":"x"}'

    r = client.post(LOGIN, content=chunks(), headers={"content-type": "application/json"})
    assert r.status_code == 413 and r.json()["code"] == "FILE_TOO_LARGE"
    assert fake_apple.token_requests == []


def test_bad_content_length_is_rejected(client: TestClient) -> None:
    r = client.post(LOGIN, content=b"{}", headers={"content-length": "-1"})
    assert r.status_code in (400, 413)


def test_normal_body_still_works(client: TestClient, fake_apple: FakeApple) -> None:
    fake_apple.add_user("c-1", sub="s")
    assert client.post(LOGIN, json=BODY).status_code == 200


# --- 보안 헤더 ------------------------------------------------------------------------


@pytest.mark.parametrize("path", ["/health", "/api/users/me", "/nope"])
def test_security_headers(client: TestClient, path: str) -> None:
    r = client.get(path)
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["cache-control"] == "no-store"  # 토큰·개인정보 응답이 캐시에 남지 않게


def test_token_response_is_not_cacheable(client: TestClient, fake_apple: FakeApple) -> None:
    fake_apple.add_user("c-1", sub="s")
    r = client.post(LOGIN, json=BODY)
    assert r.status_code == 200 and r.headers["cache-control"] == "no-store"


# --- JWT 키: local·test 밖에서 키가 없으면 기동 실패 -----------------------------------


@pytest.fixture
def fresh_keys() -> Iterator[None]:
    security._keys.cache_clear()
    yield
    security._keys.cache_clear()


@pytest.mark.parametrize("env", ["prod", "dev", "production", "staging"])
def test_startup_refuses_without_jwt_key_outside_local(
    monkeypatch: pytest.MonkeyPatch, fresh_keys: None, env: str
) -> None:
    monkeypatch.setattr(settings, "env", env)
    monkeypatch.setattr(settings, "jwt_private_key", "")
    with pytest.raises(RuntimeError), TestClient(app):
        pass


def test_startup_refuses_weak_rsa_key(monkeypatch: pytest.MonkeyPatch, fresh_keys: None) -> None:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    weak = rsa.generate_private_key(public_exponent=65537, key_size=1024)  # noqa: S505 - 일부러 약한 키
    pem = weak.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    ).decode()
    monkeypatch.setattr(settings, "env", "prod")
    monkeypatch.setattr(settings, "jwt_private_key", pem)
    with pytest.raises(RuntimeError, match="2048"):
        security.check_keys()


def test_startup_ok_with_real_key_in_prod(
    monkeypatch: pytest.MonkeyPatch, fresh_keys: None
) -> None:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    ).decode()
    monkeypatch.setattr(settings, "env", "prod")
    monkeypatch.setattr(settings, "jwt_private_key", pem)
    security.check_keys()
    tok = security.issue_token(7, "MEMBER")
    assert security.verify_token(tok).user_id == 7


# --- DB 오류에 바인드 값을 싣지 않는다 ----------------------------------------------


def test_engine_hides_bound_parameters() -> None:
    get_engine.cache_clear()
    try:
        assert get_engine().sync_engine.hide_parameters is True
    finally:
        get_engine.cache_clear()
