"""POST /api/auth/oauth/{provider}, GET /api/users/me (계약 v1.0 oauthLogin·getMe, Day 2 #6)."""

from datetime import UTC, datetime, timedelta

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from app.core.security import issue_token, verify_token
from tests.conftest import CLIENT_ID, FakeApple
from tests.contract_schema import assert_matches

LOGIN = "/api/auth/oauth/apple"
BODY = {"code": "c-1", "redirectUri": "kr.mwonmal.app://auth"}


def _login(client: TestClient, code: str = "c-1") -> dict:  # type: ignore[type-arg]
    r = client.post(LOGIN, json={**BODY, "code": code})
    assert r.status_code == 200, r.text
    return r.json()  # type: ignore[no-any-return]


def test_first_login_creates_user(client: TestClient, fake_apple: FakeApple) -> None:
    fake_apple.add_user("c-1", sub="apple-sub-1", email="a@privaterelay.appleid.com")
    body = _login(client)
    assert_matches("AuthResponse", body)
    assert body["isNewUser"] is True
    assert body["needsOnboarding"] is True
    u = body["user"]
    assert u["email"] == "a@privaterelay.appleid.com"
    assert u["nickname"].startswith("판교뉴비")
    assert u["role"] == "MEMBER"
    assert u["level"] is None and u["jobGroup"] is None
    assert u["reminderHour"] == 18 and u["actionAlertEnabled"] is True
    datetime.fromisoformat(u["createdAt"])  # KST, 오프셋 없음
    assert "+" not in u["createdAt"]
    assert verify_token(body["accessToken"]).user_id == u["userId"]


def test_client_secret_sent_to_apple_is_es256_signed(
    client: TestClient, fake_apple: FakeApple
) -> None:
    fake_apple.add_user("c-1", sub="s")
    _login(client)
    form = fake_apple.token_requests[0]
    assert form["grant_type"] == "authorization_code" and form["client_id"] == CLIENT_ID
    claims = jwt.decode(
        form["client_secret"],
        fake_apple.secret_key.public_key(),
        algorithms=["ES256"],
        audience="https://appleid.apple.com",
    )
    assert claims["iss"] == "TEAM123456" and claims["sub"] == CLIENT_ID
    assert jwt.get_unverified_header(form["client_secret"])["kid"] == "KEY1234567"


def test_second_login_is_same_user(client: TestClient, fake_apple: FakeApple) -> None:
    fake_apple.add_user("c-1", sub="apple-sub-1")
    fake_apple.add_user("c-2", sub="apple-sub-1")
    first = _login(client, "c-1")
    second = _login(client, "c-2")
    assert second["isNewUser"] is False
    assert second["user"]["userId"] == first["user"]["userId"]
    assert second["user"]["nickname"] == first["user"]["nickname"]


def test_missing_email_gets_placeholder(client: TestClient, fake_apple: FakeApple) -> None:
    fake_apple.add_user("c-1", sub="nomail", email=None)
    assert _login(client)["user"]["email"] == "nomail@apple.invalid"


def test_rejected_code_is_401_oauth_code_invalid(client: TestClient) -> None:
    r = client.post(LOGIN, json={**BODY, "code": "unknown"})
    assert r.status_code == 401
    assert_matches("Error", r.json())
    assert r.json()["code"] == "OAUTH_CODE_INVALID"
    assert "invalid_grant" not in r.text  # 제공자 응답 본문을 그대로 내보내지 않는다


@pytest.mark.parametrize(
    "tamper",
    [
        {"aud": "someone.else"},
        {"iss": "https://evil.example"},
        {"exp": 1},
    ],
)
def test_bad_id_token_claims_are_rejected(
    client: TestClient,
    fake_apple: FakeApple,
    tamper: dict,  # type: ignore[type-arg]
) -> None:
    fake_apple.add_user("c-1", sub="s")
    fake_apple.codes["c-1"].update(tamper)
    r = client.post(LOGIN, json=BODY)
    assert r.status_code == 401 and r.json()["code"] == "OAUTH_CODE_INVALID"


def test_id_token_signed_by_other_key_is_rejected(
    client: TestClient, fake_apple: FakeApple
) -> None:
    fake_apple.add_user("c-1", sub="s")
    attacker = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    original = fake_apple.id_token
    fake_apple.id_token = lambda claims, key=None: original(claims, attacker)  # type: ignore[method-assign]
    r = client.post(LOGIN, json=BODY)
    assert r.status_code == 401 and r.json()["code"] == "OAUTH_CODE_INVALID"


def test_same_email_other_provider_is_409(client: TestClient, fake_apple: FakeApple) -> None:
    # 다른 제공자로 먼저 가입한 사람을 DB 에 직접 만든다 (카카오는 v1.0 에 없음).
    fake_apple.add_user("c-1", sub="first", email="dup@x.com")
    _login(client)
    fake_apple.add_user("c-2", sub="second-apple-account", email="dup@x.com")
    r = client.post(LOGIN, json={**BODY, "code": "c-2"})
    assert r.status_code == 409 and r.json()["code"] == "EMAIL_ALREADY_REGISTERED"


@pytest.mark.parametrize("provider", ["kakao", "google"])
def test_other_providers_not_in_v1_0(client: TestClient, provider: str) -> None:
    r = client.post(f"/api/auth/oauth/{provider}", json=BODY)
    assert r.status_code == 400 and r.json()["field"] == "provider"


def test_unknown_provider_is_400(client: TestClient) -> None:
    r = client.post("/api/auth/oauth/naver", json=BODY)
    assert r.status_code == 400 and r.json()["code"] == "INVALID_INPUT"


def test_missing_code_is_400_with_field(client: TestClient) -> None:
    r = client.post(LOGIN, json={"redirectUri": "x"})
    assert r.status_code == 400
    assert r.json()["code"] == "INVALID_INPUT" and r.json()["field"] == "code"


def test_me_with_token(client: TestClient, fake_apple: FakeApple) -> None:
    fake_apple.add_user("c-1", sub="s")
    login = _login(client)
    r = client.get("/api/users/me", headers={"Authorization": f"Bearer {login['accessToken']}"})
    assert r.status_code == 200
    assert_matches("UserResponse", r.json())
    assert r.json() == login["user"]


@pytest.mark.parametrize(
    "header",
    [None, "Bearer not-a-jwt", "Basic abc"],
)
def test_me_without_valid_token_is_401(client: TestClient, header: str | None) -> None:
    headers = {"Authorization": header} if header else {}
    r = client.get("/api/users/me", headers=headers)
    assert r.status_code == 401 and r.json()["code"] == "UNAUTHORIZED"


def test_expired_token_is_401(client: TestClient, fake_apple: FakeApple) -> None:
    fake_apple.add_user("c-1", sub="s")
    uid = _login(client)["user"]["userId"]
    old = issue_token(uid, "MEMBER", now=datetime.now(UTC) - timedelta(hours=25))
    r = client.get("/api/users/me", headers={"Authorization": f"Bearer {old}"})
    assert r.status_code == 401


def test_token_for_deleted_user_is_401(client: TestClient) -> None:
    r = client.get(
        "/api/users/me", headers={"Authorization": f"Bearer {issue_token(999, 'MEMBER')}"}
    )
    assert r.status_code == 401
