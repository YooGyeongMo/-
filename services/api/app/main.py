"""뭔말인교? API. 원본 계약(contracts/openapi.yml)을 그대로 서빙한다 (14번 §3 계약 고정)."""

import logging
import sys
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml
from fastapi import FastAPI
from fastapi.responses import JSONResponse

from app.core import errors, security
from app.core.db import get_engine, ping
from app.core.http import BodyLimitMiddleware, SecurityHeadersMiddleware, UnhandledErrorMiddleware
from app.core.settings import settings
from app.decode.api.routes import router as decode_router
from app.identity.api.routes import router as identity_router
from app.workspace.api.routes import router as workspace_router

CONTRACT = Path(__file__).resolve().parent.parent / settings.contract_path


@lru_cache(maxsize=1)
def load_contract() -> dict[str, Any]:
    # 98KB YAML 파싱은 요청당 ~70ms CPU. 인증 없는 공개 경로라 매번 파싱하면 CPU DoS(레드팀 R2).
    with CONTRACT.open(encoding="utf-8") as f:
        data: dict[str, Any] = yaml.safe_load(f)
    return data


class _StderrHandler(logging.StreamHandler):  # type: ignore[type-arg]
    """매번 지금의 sys.stderr 에 쓴다(테스트·리다이렉트가 바꿔도 따라간다)."""

    @property
    def stream(self) -> Any:
        return sys.stderr

    @stream.setter
    def stream(self, _: Any) -> None:
        pass


def configure_logging() -> None:
    """우리 로거(mwonmal.*)를 INFO 로 표준 오류에 낸다. 루트는 WARNING 이라 설정이 없으면 ai_usage
    기록이
    버려진다(레드팀 M-4). 원문은 어떤 로거에도 넣지 않는다(카나리 테스트)."""
    logger = logging.getLogger("mwonmal")
    logger.setLevel(logging.INFO)
    if not any(getattr(h, "_mwonmal", False) for h in logger.handlers):
        handler = _StderrHandler()
        handler.setFormatter(logging.Formatter("%(levelname)s %(name)s %(message)s"))
        handler._mwonmal = True  # type: ignore[attr-defined]
        logger.addHandler(handler)


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    # 키가 없거나 잘못된 green 은 여기서 기동 실패 → /ready 실패 → 블루그린 전환 안 함.
    # (지연 로딩이면 /ready 는 통과하고 첫 로그인에서야 500 이 난다.)
    security.check_keys()
    configure_logging()
    yield


app = FastAPI(
    title="뭔말인교? API", openapi_url=None, docs_url=None, redoc_url=None, lifespan=lifespan
)
errors.install(app)
# add_middleware 는 바깥쪽으로 쌓인다: 헤더 → 500 봉투 → 본문 한도 → 라우터.
app.add_middleware(BodyLimitMiddleware)
app.add_middleware(UnhandledErrorMiddleware)
app.add_middleware(SecurityHeadersMiddleware)
app.include_router(identity_router)
app.include_router(decode_router)
app.include_router(workspace_router)


@app.get("/openapi.json", include_in_schema=False)
def openapi_json() -> JSONResponse:
    return JSONResponse(load_contract())


@app.get("/health", include_in_schema=False)
def health() -> dict[str, str]:
    return {"status": "ok", "env": settings.env}


@app.get("/ready", include_in_schema=False)
async def ready() -> JSONResponse:
    # 블루그린 전환은 이 응답으로 판단한다(ADR-0003). Redis·S3 ping 은 쓰는 기능이 생길 때 추가.
    if await ping(get_engine()):
        return JSONResponse({"status": "ready", "db": "up"})
    return JSONResponse({"status": "not_ready", "db": "down"}, status_code=503)
