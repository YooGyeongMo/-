"""FD-5 / ADR-0007 — AI 4트랙 평가 하네스 뼈대. 표준 라이브러리만.

데이터셋  eval/dataset/{v0_50,v1_200}.jsonl  (합성 + 검수, 실사용자 문장 0 — 형식은 eval/dataset/README.md)
엔진      --engine gemini_free | fm | mlx_qwen3_4b | qwen3_4b_base | none   (어댑터는 스텁, 실제 호출 코드는 S2 에서)
채점      ① 용어 스팬 F1  ② 쉬운 말·숨은 뜻 LLM-judge 5점  ③ 할 일 정확 일치 + F1
캐시      --cache-dir (기본 eval/cache, .gitignore) — 같은 (engine, item.id, prompt_ver) 응답은 재호출하지 않는다 (QA-2: 캐시 우선)
사용      python3 eval/run.py --engine none --limit 10          (= make eval ENGINE=none LIMIT=10)
CI 규칙   외부 호출 0 (FD-4). PR 에서는 --engine none 또는 캐시 적중분만.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Protocol, runtime_checkable

HERE = Path(__file__).resolve().parent
PROMPT_VER = "p1"  # aiModel 출처 규약 `{track}/{model}#p{ver}` (FD-5)

# ---------------------------------------------------------------------------
# 1. 데이터셋
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class EvalItem:
    """한 문장. gold 는 contracts/openapi.yml TranslationResponse 의 AI 생성 부분집합(dataset/README.md)."""

    id: str
    direction: str  # TranslationDirection enum 그대로: JARGON_TO_PLAIN | PLAIN_TO_JARGON
    source_type: str  # SourceType: MESSAGE | MEETING_NOTE
    source_text: str
    gold: dict[str, Any]
    meta: dict[str, Any] = field(default_factory=dict)


def load_dataset(path: Path, limit: int | None = None, sample: int | None = None, seed: int = 0) -> list[EvalItem]:
    items: list[EvalItem] = []
    with path.open(encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            d = json.loads(line)
            try:
                items.append(
                    EvalItem(
                        id=str(d["id"]),
                        direction=d["direction"],
                        source_type=d["sourceType"],
                        source_text=d["sourceText"],
                        gold=d["gold"],
                        meta=d.get("meta", {}),
                    )
                )
            except KeyError as e:
                raise ValueError(f"{path}:{lineno}: 필수 키 없음 {e}") from e
    if sample is not None:
        items = random.Random(seed).sample(items, min(sample, len(items)))
    if limit is not None:
        items = items[:limit]
    return items


# ---------------------------------------------------------------------------
# 2. 엔진 어댑터 — Protocol + 스텁 (실제 API 호출은 S2 타임박스에서 채운다)
# ---------------------------------------------------------------------------


@runtime_checkable
class EngineAdapter(Protocol):
    name: str  # `{track}/{model}` 예 gemini/gemini-2.5-flash

    def translate(self, item: EvalItem) -> dict[str, Any]:
        """TranslationResponse AI 생성 부분집합(resultText, detectedTerms, nuance, actionItems, intentType)을 반환."""
        ...

    def latency_ms(self) -> int | None:
        """마지막 호출 지연(p50 산출용). 없으면 None."""
        ...


class _Stub:
    name = "stub"
    _last_ms: int | None = None

    def translate(self, item: EvalItem) -> dict[str, Any]:
        raise NotImplementedError(f"{self.name}: 어댑터 미구현 (S2 타임박스). 캐시 적중분만 채점 가능")

    def latency_ms(self) -> int | None:
        return self._last_ms


class GeminiFreeAdapter(_Stub):
    """① 서버 라우터와 같은 프롬프트로 Gemini 무료 티어 호출. 키 = 평가셋 전용 운영자 키(.env sops)."""

    name = "gemini/gemini-2.5-flash"


class FoundationModelsAdapter(_Stub):
    """② Apple Foundation Models — Mac 26 + iPhone 26 실기. 로컬 브리지 CLI(swift) 결과 JSON 을 읽는다."""

    name = "fm/apple-26.4"


class MLXQwenAdapter(_Stub):
    """③ MLX Qwen3-4B 4bit (Mac). 모델 파일(*.safetensors)은 eval/.gitignore."""

    name = "mlx/qwen3-4b-4bit"


class QwenBaseAdapter(_Stub):
    """④ Qwen3-4B 베이스 하한선 (Kaggle 노트북 출력 JSON 을 읽는다)."""

    name = "qwen/qwen3-4b-base"


class NoneAdapter(_Stub):
    """사전 + 규칙 기반 간이 해석 (FD-4 미동의 사용자 경로). 서버 decode 패키지를 import 해서 채울 예정."""

    name = "none/dictionary"


ENGINES: dict[str, type[_Stub]] = {
    "gemini_free": GeminiFreeAdapter,
    "fm": FoundationModelsAdapter,
    "mlx_qwen3_4b": MLXQwenAdapter,
    "qwen3_4b_base": QwenBaseAdapter,
    "none": NoneAdapter,
}


# ---------------------------------------------------------------------------
# 3. 채점기 3종
# ---------------------------------------------------------------------------


def _span_set(terms: list[dict[str, Any]]) -> set[tuple[int, int]]:
    return {(int(t["startIndex"]), int(t["endIndex"])) for t in terms}


def _prf(tp: int, pred_n: int, gold_n: int) -> dict[str, float]:
    p = tp / pred_n if pred_n else 0.0
    r = tp / gold_n if gold_n else 0.0
    f1 = 2 * p * r / (p + r) if (p + r) else 0.0
    return {"precision": p, "recall": r, "f1": f1}


def score_term_spans(pred: dict[str, Any], gold: dict[str, Any]) -> dict[str, float]:
    """① detectedTerms 의 (startIndex, endIndex) 정확 일치 기준 P/R/F1."""
    ps, gs = _span_set(pred.get("detectedTerms", [])), _span_set(gold.get("detectedTerms", []))
    return _prf(len(ps & gs), len(ps), len(gs))


def score_plain_and_nuance(pred: dict[str, Any], gold: dict[str, Any], judge: EngineAdapter | None = None) -> dict[str, float]:
    """② 쉬운 말(detectedTerms[].plainKo)·숨은 뜻(nuance.note/tip) LLM-judge 1~5점.
    judge 어댑터가 없으면 NotImplementedError — 자동 판정 없이 점수를 지어내지 않는다."""
    if judge is None:
        raise NotImplementedError("LLM-judge 어댑터 필요 (--judge). 루브릭은 eval/scores/README 에 기록 예정")
    raise NotImplementedError("judge 프롬프트 미작성 (S2)")


def score_actions(pred: dict[str, Any], gold: dict[str, Any]) -> dict[str, float]:
    """③ actionItems[].actionText 정확 일치(정규화: 공백·마침표 제거) 비율 + 집합 F1."""

    def norm(s: str) -> str:
        return "".join(ch for ch in s if not ch.isspace() and ch not in ".。!?")

    ps = {norm(a["actionText"]) for a in pred.get("actionItems", [])}
    gs = {norm(a["actionText"]) for a in gold.get("actionItems", [])}
    out = _prf(len(ps & gs), len(ps), len(gs))
    out["exact"] = 1.0 if ps == gs else 0.0
    return out


# ---------------------------------------------------------------------------
# 4. 캐시 + 실행
# ---------------------------------------------------------------------------


def cache_path(cache_dir: Path, engine: str, item: EvalItem) -> Path:
    key = hashlib.sha256(f"{engine}|{PROMPT_VER}|{item.id}|{item.source_text}".encode()).hexdigest()[:16]
    return cache_dir / engine.replace("/", "_") / f"{item.id}-{key}.json"


def run_one(adapter: EngineAdapter, item: EvalItem, cache_dir: Path) -> tuple[dict[str, Any], bool]:
    cp = cache_path(cache_dir, adapter.name, item)
    if cp.exists():
        return json.loads(cp.read_text(encoding="utf-8")), True
    pred = adapter.translate(item)
    cp.parent.mkdir(parents=True, exist_ok=True)
    cp.write_text(json.dumps(pred, ensure_ascii=False, indent=1), encoding="utf-8")
    return pred, False


@dataclass
class RunSummary:
    engine: str
    total: int
    scored: int
    cache_hits: int
    skipped_not_implemented: int
    term_f1_mean: float
    action_f1_mean: float
    action_exact_rate: float
    judge: str = "not_run"


def run(engine_key: str, items: list[EvalItem], cache_dir: Path) -> RunSummary:
    adapter = ENGINES[engine_key]()
    term_f1: list[float] = []
    act_f1: list[float] = []
    act_exact: list[float] = []
    hits = skipped = 0
    for item in items:
        try:
            pred, hit = run_one(adapter, item, cache_dir)
        except NotImplementedError:
            skipped += 1
            continue
        hits += int(hit)
        term_f1.append(score_term_spans(pred, item.gold)["f1"])
        a = score_actions(pred, item.gold)
        act_f1.append(a["f1"])
        act_exact.append(a["exact"])
    mean = lambda xs: sum(xs) / len(xs) if xs else 0.0  # noqa: E731
    return RunSummary(
        engine=adapter.name,
        total=len(items),
        scored=len(term_f1),
        cache_hits=hits,
        skipped_not_implemented=skipped,
        term_f1_mean=mean(term_f1),
        action_f1_mean=mean(act_f1),
        action_exact_rate=mean(act_exact),
    )


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="FD-5 AI 4트랙 평가 하네스")
    ap.add_argument("--engine", choices=sorted(ENGINES), required=True)
    ap.add_argument("--dataset", type=Path, default=HERE / "dataset" / "v0_50.jsonl")
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--sample", type=int, default=None, help="무작위 표본 크기 (야간 40문장 회전)")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--cache-dir", type=Path, default=HERE / "cache")
    ap.add_argument("--format", choices=["md", "json"], default="md")
    a = ap.parse_args(argv)
    if not a.dataset.exists():
        print(f"데이터셋 없음: {a.dataset} (S2 Day 11 v0_50 작성 예정 — 형식 eval/dataset/README.md)", file=sys.stderr)
        return 2
    items = load_dataset(a.dataset, limit=a.limit, sample=a.sample, seed=a.seed)
    s = run(a.engine, items, a.cache_dir)
    if a.format == "json":
        print(json.dumps(asdict(s), ensure_ascii=False, indent=2))
    else:
        print(f"| 엔진 | 문장 | 채점 | 캐시 | 미구현 스킵 | 용어 F1 | 할 일 F1 | 할 일 정확 | judge |")
        print("|---|---|---|---|---|---|---|---|---|")
        print(
            f"| {s.engine} | {s.total} | {s.scored} | {s.cache_hits} | {s.skipped_not_implemented} | "
            f"{s.term_f1_mean:.3f} | {s.action_f1_mean:.3f} | {s.action_exact_rate:.3f} | {s.judge} |"
        )
    return 0 if s.scored or not items else 1


if __name__ == "__main__":
    sys.exit(main())
