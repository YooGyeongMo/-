"""계약 v1.0(OpenAPI 3.0.3) 스키마로 실제 응답을 검증하는 도우미.

OpenAPI 3.0 의 `nullable` 을 JSON Schema 로 바꾸고 $ref 를 풀어서 jsonschema 로 검사한다.
계약에 없는 필드를 응답에 넣으면 실패하도록 additionalProperties=false 를 덧붙인다.
"""

from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator

CONTRACT = Path(__file__).resolve().parents[3] / "contracts" / "openapi.yml"


@lru_cache(maxsize=1)
def _doc() -> dict[str, Any]:
    doc: dict[str, Any] = yaml.safe_load(CONTRACT.read_text(encoding="utf-8"))
    return doc


def _convert(node: Any) -> Any:
    if isinstance(node, list):
        return [_convert(n) for n in node]
    if not isinstance(node, dict):
        return node
    if "$ref" in node:
        name = node["$ref"].rsplit("/", 1)[-1]
        return _convert(_doc()["components"]["schemas"][name])
    out = {k: _convert(v) for k, v in node.items() if k not in ("nullable", "example")}
    out.pop("format", None)  # date-time 등 형식은 따로 검사한다(KST 오프셋 없음 규칙)
    if out.get("type") == "object" and "properties" in out:
        out.setdefault("additionalProperties", False)
    if node.get("nullable"):
        return {"anyOf": [out, {"type": "null"}]}
    return out


def assert_matches(schema_name: str, value: Any) -> None:
    schema = _convert({"$ref": f"#/components/schemas/{schema_name}"})
    errors = sorted(Draft202012Validator(schema).iter_errors(value), key=str)
    assert not errors, "\n".join(f"{list(e.path)}: {e.message}" for e in errors)
