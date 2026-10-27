"""서버용 글자 CRF 학습·평가 (python-crfsuite, ADR-0023). 합성 데이터만(ADR-0008), 시드 고정.

    cd services/api
    uv run python ../../ml/pangyo-tagger/train_crf.py                # 서버 사전 정렬 데이터로 학습·평가
    uv run python ../../ml/pangyo-tagger/train_crf.py --export       # + 서버 모델·메타데이터 갱신
    python3 -I ../../ml/pangyo-tagger/gen.py                         # (재현용 데이터, 한 번)
    uv run python ../../ml/pangyo-tagger/train_crf.py --replicate    # REPORT.md §3-1 과 같은 데이터로 비교

특징·스팬 복원·관문·병합은 서버 코드(`app/decode/domain/jargon_features.py`)를 그대로 import 한다
→ 학습과 서버 추론이 어긋날 수 없다. 데이터(`data/server/`)·결과(`out/`)는 커밋하지 않는다.
"""

import argparse
import hashlib
import json
import os
import random
import shutil
import statistics
import sys
import time
from importlib.metadata import version
from pathlib import Path

HERE = Path(__file__).resolve().parent
API = HERE.parent.parent / "services" / "api"
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(API))

import pycrfsuite  # noqa: E402

import gen  # noqa: E402
import terms as exp_terms  # noqa: E402
from app.decode.domain.jargon_features import (  # noqa: E402
    FEATURE_VERSION,
    LABEL_B,
    ORDINARY_WORDS,
    LABEL_I,
    LABEL_O,
    Candidate,
    acceptable,
    add_model_spans,
    features,
    positions,
)
from app.decode.domain.matching import Trie  # noqa: E402
from app.decode.domain.model import DictTerm  # noqa: E402
from app.decode.infra.jargon_model import CrfJargonTagger  # noqa: E402
from app.decode.infra.repository import _ALIASES, Dictionary, usable_surface  # noqa: E402
from app.decode.infra.seed_terms import TERMS as SEED_TERMS  # noqa: E402
from server_terms import (  # noqa: E402
    EXTRA_FRESH,
    EXTRA_ORDINARY,
    EXTRA_TRAIN,
    EXTRA_VERBS,
    FILLERS_FRESH,
    FILLERS_TRAIN,
    server_table,
)

SEED = 20261027
THRESHOLD = 0.9  # 실험(ADR-0018)에서 미리 정한 값. 테스트로 튜닝하지 않는다
PARAMS = {"c1": 0.05, "c2": 0.01, "max_iterations": 200, "feature.possible_transitions": True}
DATA = HERE / "data"
OUT = HERE / "out"
EXPORT_DIR = API / "app" / "decode" / "infra" / "model"
TESTS = [
    "test_seen",
    "test_unseen_tpl",
    "test_novel_spelling",
    "test_new_terms",
    "test_novel_x_unseen_tpl",
    "test_new_x_unseen_tpl",
    "test_traps",
    "test_hardneg3",
    "test_fresh_neg",
]
FP_SETS = ("test_traps", "test_hardneg3", "test_fresh_neg")


# ---------- 데이터 (서버 사전 정렬) ----------


def _gen_split(split, n, pool, mode, unseen):
    seen, items = set(), []
    while len(items) < n:
        tx, sp = gen.make_sentence(pool, mode, unseen)
        if tx in seen:
            continue
        seen.add(tx)
        items.append(gen.rec(len(items), split, tx, sp, None))
    return items


def build_server_data(out_dir: Path) -> dict:
    known, new, ord_n, ord_v = server_table(SEED_TERMS)
    leak = ORDINARY_WORDS & set(EXTRA_FRESH)
    assert not leak, f"평범한 말 목록이 새 평가셋 어휘와 겹친다: {sorted(leak)}"
    with_novel = [t for t in known if t[3]]
    # 하드 네거티브 어휘: 실험 v3 어휘 + 서버가 일부러 뺀 말(학습 쪽에만)
    gen.NEG_NOUNS = exp_terms.NEG_NOUNS + ord_n + EXTRA_ORDINARY
    gen.NEG_VERBS = exp_terms.NEG_VERBS + ord_v + EXTRA_VERBS
    neg_train = set(exp_terms.NEG_TRAIN_SET) | set(ord_n) | set(ord_v) | set(EXTRA_TRAIN)
    neg_test = set(exp_terms.NEG_TEST_SET) - set(ord_n) - set(ord_v)
    gen.NEG_TRAIN_SET, gen.NEG_TEST_SET = neg_train, neg_test
    openers = list(gen.OPENERS)
    gen.NEG.update(p=0.0, test=False, big=False)
    gen.rng = random.Random(SEED)
    tests = {
        "test_seen": _gen_split("test_seen", 500, known, "seen", False),
        "test_unseen_tpl": _gen_split("test_unseen_tpl", 300, known, "seen", True),
        "test_novel_spelling": [
            r for r in _gen_split("test_novel_spelling", 400, with_novel, "novel", False) if r["spans"]
        ][:200],
        "test_new_terms": [r for r in _gen_split("test_new_terms", 300, new, "seen", False) if r["spans"]][
            :150
        ],
        "test_novel_x_unseen_tpl": [
            r for r in _gen_split("test_novel_x_unseen_tpl", 300, with_novel, "novel", True) if r["spans"]
        ][:150],
        "test_new_x_unseen_tpl": [
            r for r in _gen_split("test_new_x_unseen_tpl", 300, new, "seen", True) if r["spans"]
        ][:150],
        "test_traps": [gen.rec(i, "test_traps", t, [], None) for i, t in enumerate(exp_terms.TRAPS[1::2])],
    }
    gen.rng = random.Random(SEED + 2)
    gen.NEG.update(p=1.0, test=True, big=True)
    hn = _gen_split("test_hardneg3", 150, known, "seen", False) + _gen_split(
        "test_hardneg3", 150, known, "seen", True
    )
    for i, r in enumerate(hn):
        r["id"] = f"test_hardneg3-{i:05d}"
    tests["test_hardneg3"] = hn
    # 새 평가셋: 학습에 없는 평범한 말(EXTRA_FRESH) + 학습에 없는 여는 말(FILLERS_FRESH)
    gen.rng = random.Random(SEED + 4)
    gen.NEG_TEST_SET = set(EXTRA_FRESH)
    gen.OPENERS = openers + FILLERS_FRESH * 2
    fresh = _gen_split("test_fresh_neg", 150, known, "seen", False) + _gen_split(
        "test_fresh_neg", 150, known, "seen", True
    )
    for i, r in enumerate(fresh):
        r["id"] = f"test_fresh_neg-{i:05d}"
    tests["test_fresh_neg"] = fresh
    gen.NEG_TEST_SET = neg_test
    gen.OPENERS = openers
    test_tri, test_txt = set(), set()
    for v in tests.values():
        for r in v:
            test_tri |= gen.trigrams(r["text"])
            test_txt.add(r["text"])
    gen.rng = random.Random(SEED + 3)
    gen.NEG.update(p=0.4, test=False, big=True)
    gen.OPENERS = openers + FILLERS_TRAIN
    trap_train = exp_terms.TRAPS[0::2]
    train, seen, dropped = [], set(), 0
    while len(train) < 5000:
        if gen.rng.random() < 0.02:
            tx, sp = gen.rng.choice(["", "오늘 ", "아 ", "근데 "]) + gen.rng.choice(trap_train), []
        else:
            tx, sp = gen.make_sentence(known, "train", False)
        if tx in seen or tx in test_txt:
            continue
        if gen.trigrams(tx) & test_tri:
            dropped += 1
            continue
        seen.add(tx)
        train.append(gen.rec(len(train), "train", tx, sp, None))
    gen.NEG.update(p=0.0, big=False)
    gen.OPENERS = openers
    out_dir.mkdir(parents=True, exist_ok=True)
    sets = {"train": train, **tests}
    for name, rows in sets.items():
        with open(out_dir / f"{name}.jsonl", "w", encoding="utf-8") as f:
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
    stats = {
        "known_terms": len(known),
        "known_with_novel": len(with_novel),
        "new_terms": len(new),
        "server_ordinary_negatives": len(ord_n) + len(ord_v),
        "train_dropped_3gram": dropped,
        **{f"{k}": len(v) for k, v in sets.items()},
        **{f"{k}_spans": sum(len(r["spans"]) for r in v) for k, v in sets.items()},
    }
    return stats


def load(d: Path, split: str) -> list[dict]:
    with open(d / f"{split}.jsonl", encoding="utf-8") as f:
        return [json.loads(line) for line in f]


# ---------- 학습 ----------


def bio(text: str, spans) -> list[str]:
    pos = positions(text)
    labels = [LABEL_O] * len(pos)
    for s, e, *_ in spans:
        first = True
        for k, i in enumerate(pos):
            if s <= i < e:
                labels[k] = LABEL_B if first else LABEL_I
                first = False
    return labels


def train(rows: list[dict], path: Path) -> float:
    trainer = pycrfsuite.Trainer(verbose=False)
    for r in rows:
        x = features(r["text"])
        if x:
            trainer.append(x, bio(r["text"], r["spans"]))
    trainer.set_params(PARAMS)
    began = time.perf_counter()
    trainer.train(str(path))
    return time.perf_counter() - began


# ---------- 평가 ----------


def server_dictionary() -> Dictionary:
    """repository.load_dictionary 와 같은 규칙으로 시드에서 바로 만든다(DB 없이)."""
    terms: dict[str, DictTerm] = {}
    surfaces: dict[str, str] = {}
    for i, t in enumerate(SEED_TERMS, start=1):
        terms[t.slug] = DictTerm(i, t.slug, t.ko, t.plain)
        for surface in (t.ko, t.en, *_ALIASES.get(t.slug, ())):
            if surface and surface.strip() and usable_surface(surface.strip()):
                surfaces.setdefault(surface.strip(), t.slug)
    return Dictionary(Trie(surfaces), terms)


def prf(pairs) -> dict:
    tp = sum(len(p & g) for p, g in pairs)
    pn = sum(len(p) for p, _ in pairs)
    gn = sum(len(g) for _, g in pairs)
    p = tp / pn if pn else 0.0
    r = tp / gn if gn else 0.0
    f = 2 * p * r / (p + r) if p + r else 0.0
    return {"P": round(p, 3), "R": round(r, 3), "F1": round(f, 3), "tp": tp, "pred": pn, "gold": gn}


def longest(dic: set, add: set) -> set:
    """ADR-0018 실험의 하이브리드 B/C 병합(겹치면 더 긴 쪽)."""
    res = set(dic)
    for s, e in add:
        over = {(a, b) for a, b in res if s < b and e > a}
        if not over:
            res.add((s, e))
        elif all(s <= a and b <= e for a, b in over) and (e - s) > max(b - a for a, b in over):
            res -= over
            res.add((s, e))
    return res


def evaluate(data_dir: Path, model: Path, dict_fn, splits: list[str]) -> tuple[dict, dict, list]:
    tagger = CrfJargonTagger(model)
    table: dict = {}
    fails: dict = {}
    lat: list[float] = []
    for sp in splits:
        rows = load(data_dir, sp)
        systems: dict[str, list] = {}
        for r in rows:
            text = r["text"]
            gold = {(s, e) for s, e, *_ in r["spans"]}
            dspans = dict_fn(text)
            dset = {(s.start, s.end) for s in dspans}
            t0 = time.perf_counter()
            cands = tagger.candidates(text)
            lat.append((time.perf_counter() - t0) * 1000)
            raw = {(c.start, c.end) for c in cands}
            conf = {(c.start, c.end) for c in cands if c.confidence >= THRESHOLD}
            gated = {(c.start, c.end) for c in cands if c.confidence >= THRESHOLD and acceptable(text, c.start, c.end)}
            per = {
                "dict": dset,
                "crf": raw,
                "crf_gated0.9": gated,
                "hybridC_longest_conf0.9": longest(dset, conf),
            }
            nostop = add_model_spans(text, dspans, cands, THRESHOLD, frozenset())
            per["server_hybrid_no_stoplist@0.9"] = {(s.start, s.end) for s in nostop}
            for tau in (0.5, 0.8, 0.9, 0.95):
                hs = add_model_spans(text, dspans, cands, tau)
                per[f"server_hybrid@{tau}"] = {(s.start, s.end) for s in hs}
            for name, pred in per.items():
                systems.setdefault(name, []).append((pred, gold))
                if name == "server_hybrid@0.9" and pred != gold:
                    ex = fails.setdefault(sp, [])
                    if len(ex) < 8:
                        ex.append({"text": text, "gold": [text[a:b] for a, b in sorted(gold)],
                                   "pred": [text[a:b] for a, b in sorted(pred)]})
        for name, pairs in systems.items():
            table.setdefault(name, {})[sp] = prf(pairs)
    for name in table:
        agg = {k: sum(table[name][s][k] for s in table[name] if s not in ("test_hardneg3", "test_fresh_neg")) for k in ("tp", "pred", "gold")}
        p = agg["tp"] / agg["pred"] if agg["pred"] else 0.0
        r = agg["tp"] / agg["gold"] if agg["gold"] else 0.0
        table[name]["ALL"] = {"P": round(p, 3), "R": round(r, 3), "F1": round(2 * p * r / (p + r), 3) if p + r else 0.0, **agg}
    return table, fails, lat


def to_markdown(table: dict, splits: list[str]) -> str:
    cols = [*splits, "ALL"]
    lines = ["| system | " + " | ".join(cols) + " |", "|---" * (len(cols) + 1) + "|"]
    for name, v in table.items():
        cells = []
        for c in cols:
            x = v.get(c)
            if x is None:
                cells.append("-")
            elif c in FP_SETS or c == "test_hardneg":
                cells.append(f"FP={x['pred']}")
            else:
                cells.append(f"{x['F1']:.3f} (P{x['P']:.2f}/R{x['R']:.2f})")
        lines.append(f"| {name} | " + " | ".join(cells) + " |")
    return "\n".join(lines)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--replicate", action="store_true", help="gen.py 데이터(train_v3)로 REPORT §3-1 재현")
    ap.add_argument("--export", action="store_true", help="서버 모델·메타데이터를 덮어쓴다")
    a = ap.parse_args()
    OUT.mkdir(exist_ok=True)
    if a.replicate:
        import score  # 실험 사전(dictionary.json) 트라이

        dic = json.load(open(DATA / "dictionary.json", encoding="utf-8"))
        trie = score.Trie(dic.keys())

        class _S:
            def __init__(self, s: int, e: int) -> None:
                self.start, self.end = s, e

        def dict_fn(text: str):
            return [_S(s, e) for s, e in trie.find(text, True)]

        rows = load(DATA, "train_v3")
        model = OUT / "replicate_crf.crfsuite"
        took = train(rows, model)
        table, fails, lat = evaluate(DATA, model, dict_fn, [t for t in TESTS if t != "test_fresh_neg"])
        name = "replicate"
    else:
        data_dir = DATA / "server"
        stats = build_server_data(data_dir)
        print(json.dumps(stats, ensure_ascii=False))
        model = OUT / "server_crf.crfsuite"
        took = train(load(data_dir, "train"), model)
        d = server_dictionary()
        table, fails, lat = evaluate(data_dir, model, d.spans, TESTS)
        name = "server"
    lat.sort()
    timing = {
        "train_sec": round(took, 1),
        "infer_p50_ms": round(statistics.median(lat), 3),
        "infer_p95_ms": round(lat[int(len(lat) * 0.95) - 1], 3),
        "model_bytes": model.stat().st_size,
    }
    print(to_markdown(table, TESTS))
    print(json.dumps(timing))
    json.dump({"table": table, "timing": timing}, open(OUT / f"{name}_scores.json", "w"), ensure_ascii=False, indent=1)
    json.dump(fails, open(OUT / f"{name}_failures.json", "w"), ensure_ascii=False, indent=1)
    if a.export and not a.replicate:
        EXPORT_DIR.mkdir(parents=True, exist_ok=True)
        dst = EXPORT_DIR / "jargon_crf.crfsuite"
        shutil.copyfile(model, dst)
        def compact(v: dict) -> str:
            return f"F1 {v['F1']:.3f} P {v['P']:.3f} R {v['R']:.3f} pred {v['pred']} gold {v['gold']}"

        shown = ("dict", "crf", "server_hybrid_no_stoplist@0.9", "server_hybrid@0.9")
        meta = {
            "feature_version": FEATURE_VERSION,
            "threshold": THRESHOLD,
            "seed": SEED,
            "params": PARAMS,
            "trainer": f"python-crfsuite {version('python-crfsuite')}",
            "data": "synthetic only (ml/pangyo-tagger/train_crf.py, server_terms.py), ADR-0008",
            "sha256": sha256(dst),
            "bytes": dst.stat().st_size,
            "metrics": {n: {k: compact(v) for k, v in table[n].items()} for n in shown},
        }
        (EXPORT_DIR / "jargon_crf.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print("exported", dst, meta["bytes"], meta["sha256"])


if __name__ == "__main__":
    main()
