"""합성 판교어 문장 생성기 (결정적, seed 고정). 실사용자 문장 0 (ADR-0008).

출력 data/*.jsonl: {"id","split","text","spans":[[start,end,surface,canonical]]}
인덱스 = 유니코드 스칼라 0-시작, end 미포함 (eval/dataset/README.md, REQ-14).
gold 스팬은 용어 표기만 (조사·'하다' 활용 제외): "싱크해서" -> "싱크".
"""
import json, os, random, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from terms import TERMS, HELDOUT_TERMS, TRAPS, NEG_NOUNS, NEG_VERBS, NEG_TRAIN_SET, NEG_TEST_SET  # noqa: E402

SEED = 20261026
rng = random.Random(SEED)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")

# ---------- 조사 ----------
def has_batchim(s: str) -> bool:
    c = s[-1]
    if "가" <= c <= "힣":
        return (ord(c) - 0xAC00) % 28 != 0
    if c.isdigit():
        return c in "013678"
    return c.lower() in "bklmnpt" or rng.random() < 0.5  # 영문은 발음 기준 대충 (실사용자도 섞어 씀)

def josa(word: str, kind: str) -> str:
    b = has_batchim(word)
    return {"obj": "을" if b else "를", "top": "은" if b else "는", "sub": "이" if b else "가",
            "dir": "으로" if b else "로", "and": "이랑" if b else "랑", "also": "도", "loc": "에서",
            "only": "만", "until": "까지", "from": "부터", "gen": "의", "none": ""}[kind]

HADA = ["해서", "하고", "해 주세요", "해주세요", "할게요", "했어요", "하면", "해야", "하는", "한", "하죠", "합시다",
        "해볼게요", "하셨나요", "하겠습니다", "됐어요", "되면", "해 두었어요", "하기", "해봐요", "했습니다", "할까요"]
HADA_TEST_ONLY = ["하려고요", "해놨는데", "해버렸어요", "하실래요", "해뒀습니다"]  # 새 활용형 (unseen 템플릿 쪽)

# ---------- 조각 (각 조각 고정 어절 ≤ 2) ----------
# {N}: 명사 슬롯 + 조사 지정, {V}: 하다 결합, {A}: 부사형
OPENERS = ["", "", "", "혹시", "그럼", "아 그리고", "다들", "팀장님", "오늘", "내일", "이번 주", "금요일까지",
           "회의 전에", "점심 이후에", "일단", "저번에 말씀하신", "참고로", "제 생각엔", "급하진 않은데", "네네",
           "PM님", "디자이너님", "개발팀", "다음 달에", "지난번처럼", "오전 중에", "주말 전에", "우선"]
OPENERS_TEST = ["월요일 아침에", "출장 다녀와서", "대표님 보고 전에", "분기 말이라", "솔직히 말하면", "번거로우시겠지만"]

NOUN_FRAG = [("{N:obj} 다시", "봐야겠어요"), ("{N:obj} 정리해서", "올려주세요"), ("{N:sub} 아직", "부족해요"),
             ("{N:top} 제가", "챙길게요"), ("{N} 관련해서", "여쭤볼게요"), ("{N:also} 같이", "봐주세요"),
             ("{N:gen} 기준이", "애매해요"), ("{N:obj} 공유드립니다", ""), ("{N} 쪽은", "괜찮나요"),
             ("{N:loc} 문제가", "생겼어요"), ("{N:dir} 정리할게요", ""), ("{N:until} 확인했어요", ""),
             ("{N:obj} 먼저", "잡아야죠"), ("{N:sub} 너무", "커요"), ("{N:obj} 문서에", "적어주세요"),
             ("{N:top} 다음 주에", "봐요"), ("{N:obj} 어떻게", "보세요"), ("{N:sub} 핵심이에요", ""),
             ("{N:and} 같이", "보면 좋겠어요"), ("{N:only} 남았어요", ""), ("{N:from} 보시죠", ""),
             ("{N:obj} 노션에", "남겼어요"), ("{N} 이야기", "나왔어요"), ("{N:sub} 바뀌었대요", "")]
NOUN_FRAG_TEST = [("{N:obj} 슬랙에", "박제했어요"), ("{N:sub} 흐려진", "느낌이에요"), ("{N:obj} 표로", "뽑아주실래요"),
                  ("{N:top} 아마", "그대로일걸요"), ("{N:gen} 숫자가", "튀네요"), ("{N:obj} 깃헙 티켓에", "달았어요")]
VERB_FRAG = [("{V}", ""), ("한번 {V}", ""), ("{N:obj} 먼저", "하죠"), ("{V} 부탁", "드려요"), ("빠르게 {V}", ""),
             ("{N} 일정", "잡을게요"), ("다 같이 {V}", ""), ("{V} 전에", "알려주세요"), ("{N:sub} 필요해요", ""),
             ("{N} 한번", "더 해요"), ("오늘 안에 {V}", ""), ("{N:obj} 진행할게요", ""), ("{V} 후에", "말씀드릴게요"),
             ("{N} 회의", "잡아주세요"), ("내일 {V}", ""), ("{N:dir} 가시죠", ""), ("간단히 {V}", "")]
VERB_FRAG_TEST = [("{VT}", ""), ("슬쩍 {V}", ""), ("{N:obj} 미리", "땡겨서 해요"), ("{N} 세션", "열어볼게요"),
                  ("퇴근 전에 {VT}", "")]
ADV_FRAG = [("{A:dir} 처리해", "주세요"), ("{A}하게 정리해", "주세요"), ("{A}하게 가시죠", ""), ("{A:dir} 부탁드려요", ""),
            ("{A}하게 봐주세요", ""), ("{A} 건이에요", ""), ("{A}하게 해봐요", ""), ("{A:dir} 할게요", "")]
ADV_FRAG_TEST = [("{A}하게 굴려봐요", ""), ("{A:dir} 쳐내 주세요", ""), ("최대한 {A}하게", "부탁해요")]
CLOSERS = ["", "", "", "~", "!", ".", "ㅎㅎ", "감사합니다.", "부탁드려요.", "확인 부탁드립니다.", "ㅠㅠ", "참고 부탁드려요.",
           "편하게 말씀 주세요.", "이따 봬요!"]
CLOSERS_TEST = ["넵 넵.", "고생 많으십니다.", "급한 건 아니에요!"]
CONNECT = ["그리고", "그 다음에", "그래서", "근데", "아니면", "또", "겸사겸사"]
CONNECT_TEST = ["그러고 나서", "덧붙여"]
PLAIN = ["점심 뭐 먹을까요", "회의실 예약했어요", "자료 첨부했어요", "오늘 비 온대요", "커피 사올게요",
         "일정 조금 밀렸어요", "내일 휴가예요", "문서 링크 드릴게요", "시간 괜찮으세요", "전화 주세요"]
PLAIN_TEST = ["택배 왔어요", "주차 자리 없어요", "엘리베이터 고장났대요"]

# 하드 네거티브: 같은 틀에 들어가는 '평범한 한국어' 명사·하다 명사 (판교어 아님). 학습용/테스트용 겹침 0.
PLAIN_N_TRAIN = ["보고서", "회의록", "예산", "일정표", "계약서", "견적서", "매출", "설문", "영수증", "출장비", "명함", "공지",
                 "주간 보고", "발표 자료", "고객 문의", "사진", "엑셀 파일", "회의실", "점심 메뉴", "택배", "휴가 계획"]
PLAIN_N_TEST = ["결재 서류", "인수인계서", "월급 명세서", "교육 일정", "보험 서류", "출근 기록", "기안서", "재고 목록", "현수막"]
PLAIN_V_TRAIN = ["정리", "확인", "검토", "보고", "준비", "연락", "수정", "공유", "요청", "결정", "점검", "작성"]
PLAIN_V_TEST = ["취합", "협의", "제출", "안내", "결재"]
NEG = {"p": 0.0, "test": False}

ALL = [t for t in TERMS]
CANON = {t[0]: t for t in TERMS}


def fill(frag, term, surface, hada):
    """조각 하나를 실현. 반환 (문자열, 조각 내부 스팬 [(s,e)])"""
    head, tail = frag
    out, spans = "", []
    i = 0
    while i < len(head):
        if head[i] == "{":
            j = head.index("}", i)
            slot = head[i + 1:j]
            kind, _, j_kind = slot.partition(":")
            s = len(out)
            out += surface
            spans.append((s, s + len(surface)))
            if kind in ("N", "A"):
                out += josa(surface, j_kind or "none")
            elif kind == "V":
                out += rng.choice(hada)
            elif kind == "VT":
                out += rng.choice(HADA_TEST_ONLY)
            i = j + 1
        else:
            out += head[i]
            i += 1
    if tail:
        out += " " + tail
    return out, spans


def pick_frag(pos, unseen):
    if pos == "n":
        pool = NOUN_FRAG_TEST if unseen else NOUN_FRAG
    elif pos == "v":
        pool = (VERB_FRAG_TEST if unseen else VERB_FRAG) + ([] if unseen else NOUN_FRAG[:8])
    else:
        pool = ADV_FRAG_TEST if unseen else ADV_FRAG
    return rng.choice(pool)


def surface_of(t, mode):
    canon, pos, var, novel = t
    if mode == "novel":
        return rng.choice(novel)
    return rng.choice([canon, canon] + var)


def make_sentence(term_pool, mode, unseen, k=None):
    """mode: train/seen/unseen/novel/new. 반환 (text, spans)"""
    if k is None:
        k = rng.choices([0, 1, 2, 3], weights=[8, 45, 32, 15])[0]
    ops = OPENERS + (OPENERS_TEST if unseen else [])
    cls = CLOSERS + (CLOSERS_TEST if unseen else [])
    con = CONNECT + (CONNECT_TEST if unseen else [])
    pl = PLAIN + (PLAIN_TEST if unseen else [])
    parts, spans = [], []
    text = rng.choice(ops)
    if unseen and rng.random() < 0.5:
        text = rng.choice(OPENERS_TEST)

    def add(piece, sp):
        nonlocal text
        if text and not text.endswith(" "):
            text += " "
        base = len(text)
        text += piece
        for s, e in sp:
            spans.append((base + s, base + e))

    if k == 0:
        add(rng.choice(pl), [])
        if rng.random() < 0.5:
            add(rng.choice(con), [])
            add(rng.choice(pl), [])
    for n in range(k):
        t = rng.choice(term_pool)
        surf = surface_of(t, "novel" if mode == "novel" else "x")
        is_neg = bool(NEG["p"]) and rng.random() < NEG["p"]
        if is_neg:
            big = NEG.get("big", False)
            side = NEG_TEST_SET if NEG["test"] else NEG_TRAIN_SET
            nn = [w for w in NEG_NOUNS if w in side] if big else (PLAIN_N_TEST if NEG["test"] else PLAIN_N_TRAIN)
            vv = [w for w in NEG_VERBS if w in side] if big else (PLAIN_V_TEST if NEG["test"] else PLAIN_V_TRAIN)
            if rng.random() < 0.5:
                t = (None, "n", [], []); surf = rng.choice(nn)
            else:
                t = (None, "v", [], []); surf = rng.choice(vv)
        fr = pick_frag(t[1], unseen and rng.random() < 0.8)
        piece, sp = fill(fr, t, surf, HADA + (HADA_TEST_ONLY if unseen else []))
        if is_neg:
            sp = []
        if n > 0:
            add(rng.choice(con), [])
        add(piece, [(s, e) for s, e in sp])
        if rng.random() < 0.15:
            add(rng.choice(pl), [])
    c = rng.choice(cls)
    if c:
        if c in "~!." or c.startswith("ㅎ") or c.startswith("ㅠ"):
            text += c
        else:
            add(c, [])
    return text.strip(), spans


def trigrams(text):
    w = text.split()
    return {tuple(w[i:i + 3]) for i in range(len(w) - 2)}


def rec(i, split, text, spans, canon_map):
    out = []
    for s, e in sorted(spans):
        out.append([s, e, text[s:e]])
    return {"id": f"{split}-{i:05d}", "split": split, "text": text, "spans": out}


def main():
    global rng
    os.makedirs(OUT, exist_ok=True)
    known = [t for t in ALL if t[0] not in HELDOUT_TERMS]
    new = [t for t in ALL if t[0] in HELDOUT_TERMS]
    tests = {}
    def gen(split, n, pool, mode, unseen):
        seen_txt, items = set(), []
        while len(items) < n:
            tx, sp = make_sentence(pool, mode, unseen)
            if tx in seen_txt:
                continue
            seen_txt.add(tx)
            items.append(rec(len(items), split, tx, sp, None))
        return items
    tests["test_seen"] = gen("test_seen", 500, known, "seen", False)
    tests["test_unseen_tpl"] = gen("test_unseen_tpl", 300, known, "seen", True)
    tests["test_novel_spelling"] = [r for r in gen("test_novel_spelling", 400, known, "novel", False) if r["spans"]][:200]
    tests["test_new_terms"] = [r for r in gen("test_new_terms", 300, new, "seen", False) if r["spans"]][:150]
    tests["test_novel_x_unseen_tpl"] = [r for r in gen("test_novel_x_unseen_tpl", 300, known, "novel", True) if r["spans"]][:150]
    tests["test_new_x_unseen_tpl"] = [r for r in gen("test_new_x_unseen_tpl", 300, new, "seen", True) if r["spans"]][:150]
    trap_test = TRAPS[1::2]
    tests["test_traps"] = [rec(i, "test_traps", t, [], None) for i, t in enumerate(trap_test)]
    test_tri, test_txt = set(), set()
    for v in tests.values():
        for r in v:
            test_tri |= trigrams(r["text"])
            test_txt.add(r["text"])
    # train: 3-gram 겹치면 버림
    train, dropped, seen_txt = [], 0, set()
    trap_train = TRAPS[0::2]
    while len(train) < 4000:
        if rng.random() < 0.02:
            tx, sp = rng.choice(trap_train), []
            tx = rng.choice(["", "오늘 ", "아 ", "근데 "]) + tx
        else:
            tx, sp = make_sentence(known, "train", False)
        if tx in seen_txt or tx in test_txt:
            continue
        if trigrams(tx) & test_tri:
            dropped += 1
            continue
        seen_txt.add(tx)
        train.append(rec(len(train), "train", tx, sp, None))
    with open(os.path.join(OUT, "train.jsonl"), "w") as f:
        for r in train:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    for k, v in tests.items():
        with open(os.path.join(OUT, f"{k}.jsonl"), "w") as f:
            for r in v:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
    # ---- v2: 하드 네거티브 (별도 rng, v1 산출물 불변) ----
    rng = random.Random(SEED + 1)
    NEG.update(p=1.0, test=True)
    hn = gen("test_hardneg", 150, known, "seen", False) + gen("test_hardneg", 150, known, "seen", True)
    for i, r in enumerate(hn):
        r["id"] = f"test_hardneg-{i:05d}"
    tests["test_hardneg"] = hn
    with open(os.path.join(OUT, "test_hardneg.jsonl"), "w") as f:
        for r in hn:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    hn_tri = set()
    for r in hn:
        hn_tri |= trigrams(r["text"])
    NEG.update(p=0.3, test=False)
    train2, seen2 = [], set()
    while len(train2) < 4000:
        if rng.random() < 0.02:
            tx, sp = rng.choice(["", "오늘 ", "아 ", "근데 "]) + rng.choice(trap_train), []
        else:
            tx, sp = make_sentence(known, "train", False)
        if tx in seen2 or tx in test_txt or trigrams(tx) & (test_tri | hn_tri):
            continue
        seen2.add(tx)
        train2.append(rec(len(train2), "train_v2", tx, sp, None))
    with open(os.path.join(OUT, "train_v2.jsonl"), "w") as f:
        for r in train2:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    # ---- v3: 큰 네거티브 어휘 (별도 rng) ----
    rng = random.Random(SEED + 2)
    NEG.update(p=1.0, test=True, big=True)
    hn3 = gen("test_hardneg3", 150, known, "seen", False) + gen("test_hardneg3", 150, known, "seen", True)
    for i, r in enumerate(hn3):
        r["id"] = f"test_hardneg3-{i:05d}"
    tests["test_hardneg3"] = hn3
    with open(os.path.join(OUT, "test_hardneg3.jsonl"), "w") as f:
        for r in hn3:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    for r in hn3:
        hn_tri |= trigrams(r["text"])
    NEG.update(p=0.4, test=False, big=True)
    train3, seen3 = [], set()
    while len(train3) < 5000:
        if rng.random() < 0.02:
            tx, sp = rng.choice(["", "오늘 ", "아 ", "근데 "]) + rng.choice(trap_train), []
        else:
            tx, sp = make_sentence(known, "train", False)
        if tx in seen3 or tx in test_txt or trigrams(tx) & (test_tri | hn_tri):
            continue
        seen3.add(tx)
        train3.append(rec(len(train3), "train_v3", tx, sp, None))
    with open(os.path.join(OUT, "train_v3.jsonl"), "w") as f:
        for r in train3:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    NEG.update(p=0.0, big=False)
    # 사전 (서버 사전 시뮬레이션: 신규 용어·새 표기 제외)
    dic = {}
    for canon, pos, var, novel in known:
        for s in [canon] + var:
            dic[s] = canon
    with open(os.path.join(OUT, "dictionary.json"), "w") as f:
        json.dump(dic, f, ensure_ascii=False, indent=0)
    tri_train = set()
    for r in train:
        tri_train |= trigrams(r["text"])
    stats = {"train": len(train), "train_dropped_3gram": dropped,
             "train_spans": sum(len(r["spans"]) for r in train),
             "dict_entries": len(dic), "known_terms": len(known), "heldout_terms": len(new),
             "trigram_overlap_test_train": len(tri_train & test_tri)}
    for k, v in tests.items():
        stats[k] = len(v)
        stats[k + "_spans"] = sum(len(r["spans"]) for r in v)
    json.dump(stats, open(os.path.join(OUT, "stats.json"), "w"), ensure_ascii=False, indent=1)
    print(json.dumps(stats, ensure_ascii=False))


if __name__ == "__main__":
    main()
