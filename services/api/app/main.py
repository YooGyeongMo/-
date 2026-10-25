"""뭔말인교? API. 원본 계약(contracts/openapi.yml)을 그대로 서빙한다 (14번 §3 계약 고정)."""

from pathlib import Path
from typing import Any

import yaml
from fastapi import FastAPI
from fastapi.responses import JSONResponse

from app.core.db import get_engine, ping
from app.core.settings import settings

CONTRACT = Path(__file__).resolve().parent.parent / settings.contract_path


def load_contract() -> dict[str, Any]:
    with CONTRACT.open(encoding="utf-8") as f:
        data: dict[str, Any] = yaml.safe_load(f)
    return data


app = FastAPI(title="뭔말인교? API", openapi_url=None, docs_url=None)


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
