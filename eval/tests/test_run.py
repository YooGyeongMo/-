"""eval/run.py 뼈대: 데이터셋 로드·채점기·캐시·스텁 어댑터."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

EVAL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVAL))

import run as harness  # noqa: E402

ITEM = {
    "id": "t-1", "direction": "JARGON_TO_PLAIN", "sourceType": "MESSAGE", "sourceText": "얼라인 하고 킥오프 밀죠",
    "gold": {
        "detectedTerms": [{"startIndex": 0, "endIndex": 3, "termKo": "얼라인", "plainKo": "방향 맞추기", "matchedText": "얼라인", "termId": 3},
                          {"startIndex": 7, "endIndex": 10, "termKo": "킥오프", "plainKo": "시작 회의", "matchedText": "킥오프", "termId": None}],
        "actionItems": [{"actionText": "킥오프 일정 확인", "dueHint": None}],
    },
}


def test_load_dataset_and_limit(tmp_path: Path) -> None:
    f = tmp_path / "d.jsonl"
    f.write_text("\n".join(json.dumps({**ITEM, "id": f"t-{i}"}, ensure_ascii=False) for i in range(5)) + "\n# comment\n", encoding="utf-8")
    items = harness.load_dataset(f, limit=3)
    assert [i.id for i in items] == ["t-0", "t-1", "t-2"] and items[0].direction == "JARGON_TO_PLAIN"
    assert len(harness.load_dataset(f, sample=2, seed=1)) == 2


def test_score_term_spans_and_actions() -> None:
    pred = {"detectedTerms": [{"startIndex": 0, "endIndex": 3}, {"startIndex": 4, "endIndex": 6}],
            "actionItems": [{"actionText": "킥오프 일정 확인."}]}
    s = harness.score_term_spans(pred, ITEM["gold"])
    assert s["precision"] == 0.5 and s["recall"] == 0.5 and s["f1"] == 0.5
    a = harness.score_actions(pred, ITEM["gold"])
    assert a["exact"] == 1.0 and a["f1"] == 1.0


def test_judge_requires_adapter() -> None:
    with pytest.raises(NotImplementedError):
        harness.score_plain_and_nuance({}, {})


def test_stub_adapter_skips_and_cache_hit_scores(tmp_path: Path) -> None:
    item = harness.EvalItem("t-1", "JARGON_TO_PLAIN", "MESSAGE", ITEM["sourceText"], ITEM["gold"])
    assert isinstance(harness.NoneAdapter(), harness.EngineAdapter)
    s = harness.run("none", [item], tmp_path)
    assert s.skipped_not_implemented == 1 and s.scored == 0
    cp = harness.cache_path(tmp_path, harness.NoneAdapter.name, item)
    cp.parent.mkdir(parents=True)
    cp.write_text(json.dumps(ITEM["gold"], ensure_ascii=False), encoding="utf-8")
    s = harness.run("none", [item], tmp_path)
    assert s.cache_hits == 1 and s.term_f1_mean == 1.0 and s.action_exact_rate == 1.0
