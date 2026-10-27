"""공용 픽스처: SQLite DB(테이블 = dbml 17개), 가짜 Apple 서버, 테스트 클라이언트."""

import json
import time
from collections.abc import AsyncIterator, Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.all_models import metadata
from app.core.db import session
from app.decode.infra.repository import reset_dictionary_cache
from app.decode.infra.seed import seed
from app.identity.api.routes import apple_oauth
from app.identity.infra.apple import APPLE_ISSUER, KEYS_URL, TOKEN_URL, AppleOAuth
from app.main import app

CLIENT_ID = "kr.mwonmal.app"


def _pem(key: rsa.RSAPrivateKey | ec.EllipticCurvePrivateKey) -> str:
    return key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    ).decode()


@dataclass
class FakeApple:
    """Apple 토큰·키 엔드포인트 흉내. codes[code] = id_token 클레임(없으면 invalid_grant)."""

    signing_key: rsa.RSAPrivateKey = field(
        default_factory=lambda: rsa.generate_private_key(public_exponent=65537, key_size=2048)
    )
    kid: str = "apple-kid-1"
    codes: dict[str, dict[str, Any]] = field(default_factory=dict)
    token_requests: list[dict[str, str]] = field(default_factory=list)
    secret_key: ec.EllipticCurvePrivateKey = field(
        default_factory=lambda: ec.generate_private_key(ec.SECP256R1())
    )

    def add_user(
        self, code: str, sub: str, email: str | None = "u@privaterelay.appleid.com"
    ) -> None:
        now = int(time.time())
        claims: dict[str, Any] = {
            "iss": APPLE_ISSUER,
            "aud": CLIENT_ID,
            "sub": sub,
            "iat": now,
            "exp": now + 600,
        }
        if email is not None:
            claims["email"] = email
        self.codes[code] = claims

    def id_token(self, claims: dict[str, Any], key: rsa.RSAPrivateKey | None = None) -> str:
        return jwt.encode(
            claims, key or self.signing_key, algorithm="RS256", headers={"kid": self.kid}
        )

    def handler(self, request: httpx.Request) -> httpx.Response:
        if request.url == KEYS_URL:
            jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(self.signing_key.public_key()))
            jwk.update(kid=self.kid, alg="RS256", use="sig")
            return httpx.Response(200, json={"keys": [jwk]})
        if request.url == TOKEN_URL:
            form = dict(httpx.QueryParams(request.content.decode()))
            self.token_requests.append(form)
            claims = self.codes.get(form["code"])
            if claims is None:
                return httpx.Response(400, json={"error": "invalid_grant"})
            return httpx.Response(200, json={"id_token": self.id_token(claims)})
        return httpx.Response(404)

    def client(self) -> AppleOAuth:
        return AppleOAuth(
            httpx.AsyncClient(transport=httpx.MockTransport(self.handler)),
            client_id=CLIENT_ID,
            team_id="TEAM123456",
            key_id="KEY1234567",
            private_key=_pem(self.secret_key),
        )


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.fixture
def fake_apple() -> FakeApple:
    return FakeApple()


@pytest.fixture
def client(tmp_path: Path, fake_apple: FakeApple) -> Iterator[TestClient]:
    engine = create_async_engine(f"sqlite+aiosqlite:///{tmp_path / 'api.db'}")
    maker = async_sessionmaker(engine, expire_on_commit=False)

    async def _session() -> AsyncIterator[AsyncSession]:
        async with maker() as s, s.begin():
            yield s

    apple = fake_apple.client()
    app.dependency_overrides[session] = _session
    app.dependency_overrides[apple_oauth] = lambda: apple
    with TestClient(app) as c:
        c.portal.call(_create_all, engine)  # type: ignore[union-attr]
        yield c
    app.dependency_overrides.clear()


async def _create_all(engine: Any) -> None:
    async with engine.begin() as conn:
        await conn.run_sync(metadata.create_all)
        await conn.run_sync(seed)
    reset_dictionary_cache()


def login(client: TestClient, fake_apple: FakeApple, name: str = "u1") -> dict[str, str]:
    """가짜 Apple 로 가입·로그인하고 Authorization 헤더를 돌려준다."""
    fake_apple.add_user(f"code-{name}", sub=f"sub-{name}", email=f"{name}@privaterelay.appleid.com")
    r = client.post("/api/auth/oauth/apple", json={"code": f"code-{name}", "redirectUri": "x"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['accessToken']}"}
