"""FD-3 / ADR-0010: contracts/push-examples/*.json 스키마 적합·금지 텍스트·4KB 검증."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest
from jsonschema import Draft202012Validator

CONTRACTS = Path(__file__).resolve().parents[3] / "contracts"
SCHEMA = json.loads((CONTRACTS / "push-payload.schema.json").read_text(encoding="utf-8"))
EXAMPLES = sorted((CONTRACTS / "push-examples").glob("*.json"))
TYPES = {
    "review_due": "REVIEW_DUE",
    "action_due": "ACTION_DUE",
    "translation_done": "TRANSLATION_DONE",
    "level_up": "LEVEL_UP",
}
FORBIDDEN_KEYS = {
    "sourceText",
    "resultText",
    "transcript",
    "actionText",
    "nuance",
    "extractedText",
    "audioUrl",
}


def _load(path: Path) -> dict[str, Any]:
    data: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
    return data


def _keys(obj: Any) -> set[str]:
    if isinstance(obj, dict):
        return set(obj) | {k for v in obj.values() for k in _keys(v)}
    if isinstance(obj, list):
        return {k for v in obj for k in _keys(v)}
    return set()


def test_schema_itself_is_valid_2020_12() -> None:
    Draft202012Validator.check_schema(SCHEMA)


def test_examples_cover_all_four_types() -> None:
    assert {p.stem for p in EXAMPLES} == set(TYPES)


@pytest.mark.parametrize("path", EXAMPLES, ids=[p.stem for p in EXAMPLES])
def test_example_matches_schema(path: Path) -> None:
    payload = _load(path)
    errors = sorted(Draft202012Validator(SCHEMA).iter_errors(payload), key=lambda e: list(e.path))
    assert not errors, "\n".join(f"{list(e.path)}: {e.message}" for e in errors)
    assert payload["mw"]["type"] == TYPES[path.stem] == payload["aps"]["category"]


@pytest.mark.parametrize("path", EXAMPLES, ids=[p.stem for p in EXAMPLES])
def test_example_has_no_user_text_and_fits_4kb(path: Path) -> None:
    payload = _load(path)
    assert not (_keys(payload) & FORBIDDEN_KEYS)
    strings = {k for k, v in payload["mw"].items() if isinstance(v, str)}
    assert strings == {"type", "deepLink"}, "mw 의 문자열은 type·deepLink 뿐 (텍스트 금지)"
    assert len(json.dumps(payload, ensure_ascii=False).encode()) < 4096


@pytest.mark.parametrize(
    "mutate",
    [
        lambda p: p["mw"].pop("deepLink"),
        lambda p: p["mw"].__setitem__("type", "REVIEW_REMINDER"),
        lambda p: p["mw"].__setitem__("v", 2),
        lambda p: p["mw"].__setitem__("sourceText", "원문"),
        lambda p: p["mw"].__setitem__("deepLink", "https://example.com"),
        lambda p: p["mw"].pop("actionId"),
    ],
    ids=[
        "no_deeplink",
        "old_enum",
        "wrong_version",
        "extra_text_key",
        "non_mwonmal_scheme",
        "action_due_needs_actionId",
    ],
)
def test_schema_rejects_bad_payloads(mutate: Any) -> None:
    payload = _load(CONTRACTS / "push-examples" / "action_due.json")
    mutate(payload)
    assert not Draft202012Validator(SCHEMA).is_valid(payload)
