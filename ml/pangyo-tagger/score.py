"""스팬 exact-match P/R/F1 (start,end 둘 다 일치 = eval/run.py score_term_spans 와 같은 규칙, 단 문장 평균이 아니라 micro).
베이스라인: 사전 트라이 최장 일치(naive / 어절 시작 경계). 하이브리드: 사전 우선 + 모델 보충(겹치면 사전 승).
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prep import load, char_tokens, word_tokens, decode, cls  # noqa: E402

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
O = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
TESTS = ["test_seen", "test_unseen_tpl", "test_novel_spelling", "test_new_terms", "test_novel_x_unseen_tpl", "test_new_x_unseen_tpl", "test_traps", "test_hardneg", "test_hardneg3"]


class Trie:
    def __init__(self, words):
        self.root = {}
        for w in words:
            n = self.root
            for ch in w.lower():
                n = n.setdefault(ch, {})
            n["$"] = w

    def find(self, text, boundary):
        low, out, i = text.lower(), [], 0
        while i < len(low):
            if boundary and i > 0 and not text[i - 1].isspace() and cls(text[i - 1]) == cls(text[i]):
                i += 1
                continue
            n, j, best = self.root, i, None
            while j < len(low) and low[j] in n:
                n = n[low[j]]
                j += 1
                if "$" in n:
                    best = j
            if best:
                out.append((i, best))
                i = best
            else:
                i += 1
        return out


def prf(pairs):
    tp = sum(len(p & g) for p, g in pairs)
    pn = sum(len(p) for p, _ in pairs)
    gn = sum(len(g) for _, g in pairs)
    P = tp / pn if pn else 0.0
    R = tp / gn if gn else 0.0
    F = 2 * P * R / (P + R) if P + R else 0.0
    return {"P": round(P, 3), "R": round(R, 3), "F1": round(F, 3), "tp": tp, "pred": pn, "gold": gn}


def model_spans(name, split, rows):
    scheme = name.split("_")[1]
    path = os.path.join(O, f"{name}.{split}.pred.json")
    if not os.path.exists(path):
        return None
    preds = {p["id"]: p["pred"] for p in json.load(open(path))}
    fn = char_tokens if scheme == "C" else word_tokens
    out = {}
    for r in rows:
        toks, offs = fn(r["text"])
        out[r["id"]] = set(decode(preds[r["id"]], offs, toks, scheme))
    return out


def hybrid(dic_sp, mod_sp):
    res = set(dic_sp)
    for s, e in mod_sp:
        if not any(s < b and e > a for a, b in dic_sp):
            res.add((s, e))
    return res


def hybrid_longest(dic_sp, mod_sp):
    """겹치면 더 긴 쪽 (모델이 '얼라인업' 처럼 사전 표기를 포함한 새 표기를 잡으면 모델 승)."""
    res = set(dic_sp)
    for s, e in mod_sp:
        over = {(a, b) for a, b in res if s < b and e > a}
        if not over:
            res.add((s, e))
        elif all(s <= a and b <= e for a, b in over) and (e - s) > max(b - a for a, b in over):
            res -= over
            res.add((s, e))
    return res


TAU = 0.9  # 사전에 정한 값 (테스트로 튜닝 안 함)


def conf_spans(name, split, rows, ms):
    """모델 스팬 중 토큰 최소 확률 >= TAU 인 것만."""
    path = os.path.join(O, f"{name}.{split}.conf.json")
    if not os.path.exists(path):
        return None
    conf = {}
    for d in json.load(open(path)):
        (k, v), = d.items()
        conf[k] = [max(h.values()) for h in v]
    scheme = name.split("_")[1]
    fn = char_tokens if scheme == "C" else word_tokens
    out = {}
    for r in rows:
        _, offs = fn(r["text"])
        keep = set()
        for s, e in ms[r["id"]]:
            c = min(conf[r["id"]][k] for k, (a, b) in enumerate(offs) if a < e and b > s)
            if c >= TAU:
                keep.add((s, e))
        out[r["id"]] = keep
    return out


def veto_conf(name, split, rows):
    """토큰별 (top label, prob) — 사전 매칭 거부(동음이의 '싱크대')용."""
    path = os.path.join(O, f"{name}.{split}.conf.json")
    if not os.path.exists(path):
        return None
    out = {}
    for d in json.load(open(path)):
        (k, v), = d.items()
        out[k] = [max(h.items(), key=lambda x: x[1]) for h in v]
    return out


def hybrid_veto(dic_sp, add_sp, conf, offs):
    """사전 스팬이라도 모델이 그 토큰 전부를 O(확률 >= TAU)로 보면 버림. 나머지는 hybrid_longest."""
    kept = set()
    for a, b in dic_sp:
        toks = [conf[k] for k, (x, y) in enumerate(offs) if x < b and y > a]
        if toks and all(l == "O" and p >= TAU for l, p in toks):
            continue
        kept.add((a, b))
    return hybrid_longest(kept, add_sp)


def main():
    dic = json.load(open(os.path.join(D, "dictionary.json")))
    trie = Trie(dic.keys())
    models = sorted({f.split(".")[0] for f in os.listdir(O) if f.endswith(".pred.json")})
    table, fails = {}, {}
    for sp in TESTS:
        rows = load(sp)
        gold = {r["id"]: {(s, e) for s, e, *_ in r["spans"]} for r in rows}
        systems = {"dict_naive": {r["id"]: set(trie.find(r["text"], False)) for r in rows},
                   "dict_boundary": {r["id"]: set(trie.find(r["text"], True)) for r in rows}}
        for m in models:
            ms = model_spans(m, sp, rows)
            if ms is None:
                continue
            systems[m] = ms
            systems["hybridA_dictwins+" + m] = {i: hybrid(systems["dict_boundary"][i], ms[i]) for i in ms}
            systems["hybridB_longest+" + m] = {i: hybrid_longest(systems["dict_boundary"][i], ms[i]) for i in ms}
            cs = conf_spans(m, sp, rows, ms)
            if cs is not None:
                systems["hybridC_longest_conf0.9+" + m] = {i: hybrid_longest(systems["dict_boundary"][i], cs[i]) for i in cs}
                vc = veto_conf(m, sp, rows)
                fn = char_tokens if m.split("_")[1] == "C" else word_tokens
                systems["hybridD_veto+" + m] = {r["id"]: hybrid_veto(systems["dict_boundary"][r["id"]], cs[r["id"]], vc[r["id"]], fn(r["text"])[1]) for r in rows}
        for name, sysp in systems.items():
            table.setdefault(name, {})[sp] = prf([(sysp[r["id"]], gold[r["id"]]) for r in rows])
            ex = []
            for r in rows:
                p, g = sysp[r["id"]], gold[r["id"]]
                if p != g and len(ex) < 6:
                    t = r["text"]
                    ex.append({"text": t, "gold": [t[a:b] for a, b in sorted(g)], "pred": [t[a:b] for a, b in sorted(p)]})
            fails.setdefault(name, {})[sp] = ex
    # 합계 (traps 포함 전체)
    for name in table:
        agg = {k: sum(table[name][s][k] for s in table[name] if not s.startswith("test_hardneg")) for k in ("tp", "pred", "gold")}
        P = agg["tp"] / agg["pred"] if agg["pred"] else 0
        R = agg["tp"] / agg["gold"] if agg["gold"] else 0
        table[name]["ALL"] = {"P": round(P, 3), "R": round(R, 3), "F1": round(2 * P * R / (P + R), 3) if P + R else 0, **agg}
    json.dump(table, open(os.path.join(O, "scores.json"), "w"), ensure_ascii=False, indent=1)
    json.dump(fails, open(os.path.join(O, "failures.json"), "w"), ensure_ascii=False, indent=1)
    cols = TESTS + ["ALL"]
    print("| system | " + " | ".join(cols) + " |")
    for name, v in table.items():
        cells = []
        for c in cols:
            x = v.get(c)
            if c in ("test_traps", "test_hardneg", "test_hardneg3"):
                cells.append(f"FP={x['pred']}" if x else "-")
            else:
                cells.append(f"{x['F1']:.3f} (P{x['P']:.2f}/R{x['R']:.2f})" if x else "-")
        print(f"| {name} | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main()
