"""뭔말인교? API. 원본 계약(contracts/openapi.yml)을 그대로 서빙한다 (14번 §3 계약 고정)."""

from pathlib import Path
from typing import Any

import yaml
from fastapi import FastAPI
from fastapi.responses import JSONResponse

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
def ready() -> dict[str, str]:
    # S0 Day 4: DB·Redis·S3 ping 추가
    return {"status": "ready"}
