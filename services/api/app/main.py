"""뭔말인교? API. 원본 계약(contracts/openapi.yml)을 그대로 서빙한다 (14번 §3 계약 고정)."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

import yaml
from fastapi import FastAPI
from fastapi.responses import JSONResponse

from app.core import errors, security
from app.core.db import get_engine, ping
from app.core.http import BodyLimitMiddleware, SecurityHeadersMiddleware, UnhandledErrorMiddleware
from app.core.settings import settings
from app.identity.api.routes import router as identity_router

CONTRACT = Path(__file__).resolve().parent.parent / settings.contract_path


def load_contract() -> dict[str, Any]:
    with CONTRACT.open(encoding="utf-8") as f:
        data: dict[str, Any] = yaml.safe_load(f)
    return data


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    # 키가 없거나 잘못된 green 은 여기서 기동 실패 → /ready 실패 → 블루그린 전환 안 함.
    # (지연 로딩이면 /ready 는 통과하고 첫 로그인에서야 500 이 난다.)
    security.check_keys()
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
