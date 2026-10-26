"""POST /api/auth/oauth/{provider}, GET /api/users/me (계약 v1.0 oauthLogin·getMe, Day 2 #6)."""

from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any

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


# --- 레드팀 2026-10-26: Apple 비정상 응답, JWKS 재요청, 토큰 위조 --------------------


def _apple_instance() -> Any:
    from app.identity.api.routes import apple_oauth
    from app.main import app

    return app.dependency_overrides[apple_oauth]()


def _swap_transport(handler: Callable[[Any], Any]) -> Any:
    import httpx

    inst = _apple_instance()
    inst._http = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    inst._jwks = {}
    return inst


@pytest.mark.parametrize(
    "case", ["token_list", "id_token_int", "token_not_json", "jwk_broken", "keys_list"]
)
def test_malformed_apple_responses_are_401_not_500(
    client: TestClient, fake_apple: FakeApple, case: str
) -> None:
    import httpx

    from app.identity.infra.apple import KEYS_URL, TOKEN_URL

    fake_apple.add_user("c-1", sub="s")
    bad = {
        "token_list": (TOKEN_URL, httpx.Response(200, json=[1])),
        "id_token_int": (TOKEN_URL, httpx.Response(200, json={"id_token": 5})),
        "token_not_json": (TOKEN_URL, httpx.Response(200, content=b"<html>")),
        "jwk_broken": (KEYS_URL, httpx.Response(200, json={"keys": [{"kid": fake_apple.kid}]})),
        "keys_list": (KEYS_URL, httpx.Response(200, json=[])),
    }[case]

    def handler(req: httpx.Request) -> httpx.Response:
        return bad[1] if req.url == bad[0] else fake_apple.handler(req)

    _swap_transport(handler)
    r = client.post(LOGIN, json=BODY)
    assert r.status_code == 401 and r.json()["code"] == "OAUTH_CODE_INVALID"


def test_unknown_kid_does_not_refetch_jwks_every_request(
    client: TestClient, fake_apple: FakeApple
) -> None:
    import httpx

    from app.identity.infra.apple import KEYS_URL

    calls = {"keys": 0}

    def handler(req: httpx.Request) -> httpx.Response:
        if req.url == KEYS_URL:
            calls["keys"] += 1
        return fake_apple.handler(req)

    _swap_transport(handler)
    fake_apple.add_user("c-1", sub="s")
    fake_apple.kid = "rotated-unknown"  # 토큰 헤더 kid ≠ JWKS kid 가 되게 아래서 다시 맞춘다
    original = fake_apple.id_token
    fake_apple.id_token = lambda claims, key=None: jwt.encode(  # type: ignore[method-assign]
        claims, fake_apple.signing_key, algorithm="RS256", headers={"kid": "rogue"}
    )
    for _ in range(5):
        assert client.post(LOGIN, json=BODY).status_code == 401
    assert calls["keys"] == 1
    fake_apple.id_token = original  # type: ignore[method-assign]


def test_jwks_outage_uses_cached_key(client: TestClient, fake_apple: FakeApple) -> None:
    import httpx

    from app.identity.infra.apple import JWKS_TTL_SEC, KEYS_URL

    now = [1_000_000.0]
    inst = _apple_instance()
    inst._clock = lambda: now[0]
    fake_apple.add_user("c-1", sub="s")
    fake_apple.add_user("c-2", sub="s")
    assert client.post(LOGIN, json=BODY).status_code == 200  # 캐시 채움
    now[0] += JWKS_TTL_SEC + 1  # 만료

    def handler(req: httpx.Request) -> httpx.Response:
        if req.url == KEYS_URL:
            return httpx.Response(503)
        return fake_apple.handler(req)

    jwks = inst._jwks
    _swap_transport(handler)
    inst._jwks = jwks
    # client_secret 의 iat 는 가짜 시계 기준이지만 FakeApple 은 검사하지 않는다.
    r = client.post(LOGIN, json={**BODY, "code": "c-2"})
    assert r.status_code == 200


def test_alg_none_and_hs256_confusion_rejected(client: TestClient, fake_apple: FakeApple) -> None:
    import base64
    import hmac
    import json
    import time
    from hashlib import sha256

    from app.core import security

    fake_apple.add_user("c-1", sub="s")
    uid = _login(client)["user"]["userId"]

    def b64(d: dict) -> str:  # type: ignore[type-arg]
        return base64.urlsafe_b64encode(json.dumps(d).encode()).rstrip(b"=").decode()

    now = int(time.time())
    claims = {"sub": str(uid), "iss": "mwonmal", "iat": now, "exp": now + 60, "role": "ADMIN"}
    none_tok = f"{b64({'alg': 'none', 'kid': 'local-1'})}.{b64(claims)}."
    signing = f"{b64({'alg': 'HS256', 'kid': 'local-1'})}.{b64(claims)}".encode()
    mac = hmac.new(security._keys().public_pem, signing, sha256).digest()
    hs_tok = signing.decode() + "." + base64.urlsafe_b64encode(mac).rstrip(b"=").decode()
    for tok in (none_tok, hs_tok):
        r = client.get("/api/users/me", headers={"Authorization": f"Bearer {tok}"})
        assert r.status_code == 401


def test_token_with_future_iat_or_without_exp_rejected(
    client: TestClient, fake_apple: FakeApple
) -> None:
    import time

    from app.core import security

    fake_apple.add_user("c-1", sub="s")
    uid = _login(client)["user"]["userId"]
    future = issue_token(uid, "MEMBER", now=datetime.now(UTC) + timedelta(days=30))
    k = security._keys()
    no_exp = jwt.encode(
        {"sub": str(uid), "iss": "mwonmal", "iat": int(time.time())},
        k.private_pem,
        algorithm="RS256",
        headers={"kid": k.kid},
    )
    for tok in (future, no_exp):
        r = client.get("/api/users/me", headers={"Authorization": f"Bearer {tok}"})
        assert r.status_code == 401


@pytest.mark.parametrize("code", ["", "   "])
def test_empty_code_is_401_without_calling_apple(
    client: TestClient, fake_apple: FakeApple, code: str
) -> None:
    # 계약 v1.0 OAuthLoginRequest.code 엔 minLength 가 없다 → 400 이 아니라 OAUTH_CODE_INVALID.
    r = client.post(LOGIN, json={**BODY, "code": code})
    assert r.status_code == 401 and r.json()["code"] == "OAUTH_CODE_INVALID"
    assert fake_apple.token_requests == []


def test_jwks_transient_failure_recovers_on_next_request(
    client: TestClient, fake_apple: FakeApple
) -> None:
    import httpx

    from app.identity.infra.apple import KEYS_URL

    state = {"down": True}

    def handler(req: httpx.Request) -> httpx.Response:
        if req.url == KEYS_URL and state["down"]:
            return httpx.Response(503)
        return fake_apple.handler(req)

    _swap_transport(handler)
    fake_apple.add_user("c-1", sub="s")
    fake_apple.add_user("c-2", sub="s")
    assert client.post(LOGIN, json=BODY).status_code == 401
    state["down"] = False
    assert client.post(LOGIN, json={**BODY, "code": "c-2"}).status_code == 200
