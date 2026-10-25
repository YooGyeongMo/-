"""ErrorCode enum 이 계약 v1.0 Error.code 설명의 코드 목록과 같고, HTTP 상태도 같다."""

import re
from pathlib import Path

import yaml

from app.core.errors import ErrorCode, status_of

CONTRACT = Path(__file__).resolve().parents[3] / "contracts" / "openapi.yml"


def _contract_codes() -> dict[str, int]:
    doc = yaml.safe_load(CONTRACT.read_text(encoding="utf-8"))
    desc = doc["components"]["schemas"]["Error"]["properties"]["code"]["description"]
    out: dict[str, int] = {}
    for status, codes in re.findall(r"- (\d{3}): ([A-Z_, ]+)", desc):
        for c in codes.split(","):
            out[c.strip()] = int(status)
    return out


def test_codes_and_status_match_contract() -> None:
    contract = _contract_codes()
    assert {c.value for c in ErrorCode} == set(contract)
    for code in ErrorCode:
        assert status_of(code) == contract[code.value], code
