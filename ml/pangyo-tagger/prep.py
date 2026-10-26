"""토큰화 2가지 + BIO 라벨 → Swift 학습 입력(JSON). 스팬 복원 함수는 score.py 가 같이 씀.

C(글자) : 공백 아닌 유니코드 스칼라 1개 = 토큰 1개, 어절 첫 글자엔 '▁' 접두. 토큰 i ↔ 스칼라 인덱스 1:1 → 스팬 복원이 정확.
W(어절) : 공백 + 문자 종류 경계(한글/라틴·숫자/기호)로 자름 (NLTokenizer 와 비슷, 단 R&R 은 유지).
          '얼라인을' 은 토큰 1개라 용어 끝은 접미(조사·하다 활용) 규칙으로 잘라냄.
"""
import json, os, re, sys

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
SPLITS = ["train", "train_v2", "test_hardneg", "train_v3", "test_hardneg3", "test_seen", "test_unseen_tpl", "test_novel_spelling", "test_new_terms", "test_novel_x_unseen_tpl", "test_new_x_unseen_tpl", "test_traps"]


def load(split):
    return [json.loads(l) for l in open(os.path.join(D, f"{split}.jsonl"))]


# ---------- C ----------
def char_tokens(text):
    toks, offs = [], []
    for i, ch in enumerate(text):
        if ch.isspace():
            continue
        prev_space = i == 0 or text[i - 1].isspace()
        toks.append(("▁" if prev_space else "") + ch)
        offs.append((i, i + 1))
    return toks, offs


# ---------- W ----------
def cls(ch):
    if "가" <= ch <= "힣" or "ㄱ" <= ch <= "ㅣ":
        return "H"
    if ch.isalnum() or ch in "&/-:":   # R&R, A/B, kick-off, 1:1 은 한 덩어리
        return "L"
    return "P"


def word_tokens(text):
    toks, offs = [], []
    i = 0
    while i < len(text):
        if text[i].isspace():
            i += 1
            continue
        c = cls(text[i])
        j = i + 1
        while j < len(text) and not text[j].isspace() and cls(text[j]) == c and c != "P":
            j += 1
        toks.append(text[i:j])
        offs.append((i, j))
        i = j
    return toks, offs


def bio(offs, spans):
    labels = ["O"] * len(offs)
    for s, e, *_ in spans:
        first = True
        for k, (a, b) in enumerate(offs):
            if a < e and b > s:   # 겹치면
                labels[k] = "B-T" if first else "I-T"
                first = False
    return labels


JOSA = sorted(["을", "를", "은", "는", "이", "가", "으로", "로", "이랑", "랑", "도", "에서", "만", "까지", "부터", "의",
               "에", "와", "과", "이에요", "예요", "이고", "인데", "처럼"], key=len, reverse=True)
HADA_START = set("하해했할한합되돼됐함")


def strip_suffix(tok):
    """'싱크해서' → '싱크', '얼라인을' → '얼라인'. 반환: 남길 길이"""
    if cls(tok[0]) != "H":
        return len(tok)
    for k in range(1, len(tok)):          # 가장 앞쪽 '하다' 활용 시작점
        if tok[k] in HADA_START and k >= 1:
            return k
    for j in JOSA:
        if tok.endswith(j) and len(tok) > len(j):
            return len(tok) - len(j)
    return len(tok)


def decode(labels, offs, toks, scheme):
    spans, cur = [], None
    for k, lab in enumerate(labels):
        a, b = offs[k]
        if lab == "B-T" or (lab == "I-T" and cur is None):
            if cur:
                spans.append(cur)
            cur = [a, b, k]
        elif lab == "I-T":
            cur[1] = b
            cur[2] = k
        else:
            if cur:
                spans.append(cur)
            cur = None
    if cur:
        spans.append(cur)
    out = []
    for s, e, last in spans:
        if scheme == "W":
            keep = strip_suffix(toks[last])
            e = offs[last][0] + keep
        out.append((s, e))
    return out


def main():
    stats = {}
    for sp in SPLITS:
        rows = load(sp)
        for scheme, fn in (("C", char_tokens), ("W", word_tokens)):
            out, oracle_bad = [], 0
            for r in rows:
                toks, offs = fn(r["text"])
                labs = bio(offs, r["spans"])
                out.append({"id": r["id"], "tokens": toks, "labels": labs})
                gold = {(s, e) for s, e, *_ in r["spans"]}
                if set(decode(labs, offs, toks, scheme)) != gold:
                    oracle_bad += 1
            json.dump(out, open(os.path.join(D, f"{sp}.{scheme}.json"), "w"), ensure_ascii=False)
            stats[f"{sp}.{scheme}.oracle_sentence_err"] = oracle_bad
            stats[f"{sp}.{scheme}.avg_tokens"] = round(sum(len(x["tokens"]) for x in out) / len(out), 1)
    print(json.dumps(stats, ensure_ascii=False, indent=1))
    json.dump(stats, open(os.path.join(D, "prep_stats.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
