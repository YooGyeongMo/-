"""우리 서버가 발급하는 액세스 토큰 (14번 §4).

JWT RS256, 헤더에 kid, 클레임 sub·role·iat·exp·iss, 수명 24h.
키는 MWONMAL_JWT_PRIVATE_KEY(PEM)로 주입한다. local·test 에서 비어 있으면 프로세스마다
임시 키를 만든다(재시작하면 기존 토큰 무효 — 로컬은 괜찮다). 그 밖의 env 에서 비면 기동 거부
(app.main lifespan 이 check_keys() 를 부른다). 임시 키는 워커 프로세스마다 다르므로 local 은
워커 1개로 돌린다(WEB_CONCURRENCY=1). 이미지 기본 env 는 prod(Dockerfile) — 설정을 빠뜨리면
임시 키로 조용히 뜨지 않고 기동이 실패한다.
"""

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from functools import lru_cache

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from app.core.errors import DomainError, ErrorCode
from app.core.settings import settings

ALGORITHM = "RS256"
ISSUER = "mwonmal"
TOKEN_TTL = timedelta(hours=24)


@dataclass(frozen=True)
class Principal:
    user_id: int
    role: str


@dataclass(frozen=True)
class _Keys:
    kid: str
    private_pem: bytes
    public_pem: bytes


EPHEMERAL_ENVS = ("local", "test")
MIN_RSA_BITS = 2048


@lru_cache(maxsize=1)
def _keys() -> _Keys:
    pem = settings.jwt_private_key
    if pem:
        private = serialization.load_pem_private_key(pem.encode(), password=None)
    elif settings.env in EPHEMERAL_ENVS:
        private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    else:
        raise RuntimeError("MWONMAL_JWT_PRIVATE_KEY 가 없다 (prod 는 sops 로 주입)")
    if not isinstance(private, rsa.RSAPrivateKey):
        raise RuntimeError("JWT 키는 RSA 여야 한다 (RS256)")
    if private.key_size < MIN_RSA_BITS:
        raise RuntimeError(f"JWT RSA 키는 {MIN_RSA_BITS}비트 이상이어야 한다")
    if not settings.jwt_kid.strip():
        raise RuntimeError("MWONMAL_JWT_KID 가 비었다")
    return _Keys(
        kid=settings.jwt_kid,
        private_pem=private.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        ),
        public_pem=private.public_key().public_bytes(
            serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
        ),
    )


def check_keys() -> None:
    """기동 시 호출. 키가 없거나(local·test 제외) 잘못됐으면 예외로 기동을 막는다."""
    _keys()


def issue_token(user_id: int, role: str, now: datetime | None = None) -> str:
    keys = _keys()
    iat = now or datetime.now(UTC)
    claims = {"sub": str(user_id), "role": role, "iss": ISSUER, "iat": iat, "exp": iat + TOKEN_TTL}
    return jwt.encode(claims, keys.private_pem, algorithm=ALGORITHM, headers={"kid": keys.kid})


def verify_token(token: str) -> Principal:
    keys = _keys()
    try:
        header = jwt.get_unverified_header(token)
        if header.get("kid") != keys.kid:
            raise jwt.InvalidTokenError("unknown kid")
        claims = jwt.decode(
            token,
            keys.public_pem,
            algorithms=[ALGORITHM],
            issuer=ISSUER,
            options={"require": ["sub", "exp", "iat", "iss"]},
        )
        return Principal(user_id=int(claims["sub"]), role=str(claims.get("role", "MEMBER")))
    except (jwt.InvalidTokenError, ValueError) as e:
        raise DomainError(ErrorCode.UNAUTHORIZED, "로그인이 필요한 기능이에요.") from e
