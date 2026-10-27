"""레드팀 1차(2026-10-27, PR #114) 재발 방지. 보고서의 재현 입력을 그대로 쓴다."""

import json
import threading
from datetime import datetime
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.decode.domain import rules
from app.decode.domain.matching import Trie, substitute
from app.decode.domain.model import EngineError, EngineRequest
from app.decode.infra.engines.gemini import parse
from app.decode.infra.repository import usable_surface
from app.decode.infra.seed_terms import TERMS
from tests.conftest import FakeApple, login

NOW = datetime(2026, 10, 27, 2, 29)  # 화 11:29 KST


def seed_trie() -> tuple[Trie, dict[str, str]]:
    surfaces: dict[str, str] = {}
    for t in TERMS:
        for s in (t.ko, t.en, *t.aliases):
            if s and usable_surface(s):
                surfaces.setdefault(s, t.slug)
    return Trie(surfaces), {t.slug: t.plain for t in TERMS}


TRIE, PLAIN = seed_trie()


@pytest.mark.parametrize(
    "text",
    [
        "머지않아 결과가 나와요",
        "싱크대에 물이 새요",
        "영상이 버퍼링 걸려요",
        "푸시업 30개",
        "데일리룩 공유",
        "드롭다운을 열어요",
        "공수표를 날렸어요",
        "special thanks",
        "specific한 이야기",
        "Next.js 프로젝트",
        "next week에 봬요",
        "TFT 패널",
        "Please hold the door",
        "drop my kids",
        "The input field",
        "호텔 프론트에 맡겼어요",
        "피벗 테이블",
        "미시적인 관점",
        "레트로 감성",
    ],
)
def test_no_false_positive(text: str) -> None:
    """H-1: 평범한 문장 속 낱말은 용어가 아니다(ADR-0018 오탐 관문)."""
    assert TRIE.find(text) == [], [m.matched_text for m in TRIE.find(text)]


@pytest.mark.parametrize(
    ("text", "matched"),
    [
        ("얼라인을 해요", ["얼라인"]),
        ("싱크해서 알려 주세요", ["싱크"]),
        ("R&R이 정해졌어요", ["R&R"]),
        ("P0예요", ["P0"]),
        ("align 부탁", ["align"]),
        ("asap으로", ["asap"]),
        ("KPI 공유", ["KPI"]),
        ("PoC 해 보죠", ["PoC"]),
        ("얼라인쳐 주세요", ["얼라인"]),
        ("런칭이라 바빠요", ["런칭"]),
    ],
)
def test_true_positives_survive(text: str, matched: list[str]) -> None:
    assert [m.matched_text for m in TRIE.find(text)] == matched


@pytest.mark.parametrize(
    ("text", "plain"),
    [
        ("런칭이에요", "출시예요"),
        ("모레 런칭이라 QA", "모레 출시라 QA"),
        ("P0예요", "가장 급한 일이에요"),
        ("얼라인쳐 주세요", "방향 맞추기 해 주세요"),
        ("금요일 EOD까지", "금요일 퇴근 전까지"),
        ("킥오프 미팅", "시작 미팅"),
        ("홀드합시다", "보류합시다"),
    ],
)
def test_plain_text_reads_naturally(text: str, plain: str) -> None:
    assert substitute(text, TRIE.find(text), PLAIN) == plain


@pytest.mark.parametrize(
    ("sentence", "kst"),
    [
        ("월요일 9시까지 자료 올려 주세요", (11, 2, 9, 0)),
        ("내일 오전 10시까지 피드백 주세요", (10, 28, 10, 0)),
        ("다음 주 금요일까지 정리해 주세요", (11, 6, 18, 0)),
        ("이번 주 수요일까지 보내 주세요", (10, 28, 18, 0)),
        ("오늘 밤 11시까지 공유해 주세요", (10, 27, 23, 0)),
        ("공수 산정해서 내일 오전까지 주세요", (10, 28, 12, 0)),
        ("3시 반까지 보내 주세요", (10, 27, 15, 30)),
    ],
)
def test_due_combines_date_and_time(sentence: str, kst: tuple[int, int, int, int]) -> None:
    """H-2: 날짜와 시각을 합치고 오전·오후·주(週) 수식을 지킨다."""
    hint = rules.due_hint(sentence)
    due = rules.due_at(hint, NOW)
    assert due is not None, hint
    local = due.replace(hour=(due.hour + 9) % 24)
    day = due.day + (1 if due.hour + 9 >= 24 else 0)
    assert (due.month, day, local.hour, local.minute) == kst, hint


@pytest.mark.parametrize(
    "sentence",
    ["오전 7시까지 출근해 주세요", "1시간 정도 걸리니 해 주세요", "8시까지 와 주세요"],
)
def test_due_not_in_past_or_from_duration(sentence: str) -> None:
    """오전 7시는 19시가 아니고(이미 지남), "1시간"은 시각이 아니다."""
    assert rules.due_at(rules.due_hint(sentence), NOW) is None


@pytest.mark.parametrize(
    ("text", "todo"),
    [
        ("다음 주 수요일까지 목업 공유해 주세요 🙏", "다음 주 수요일까지 목업 공유하기"),
        ("리스크 관리 잘 부탁드려요 ㅎㅎ", "리스크 관리"),
        ("피드백은 오늘 중으로 주시면 감사하겠습니다", "피드백은 오늘 중으로"),
        ("파일 알려 주세요", "파일 알리기"),
        ("문서 만들어 주세요", "문서 만들기"),
        ("내일까지 해야 합니다", "내일까지 하기"),
        ("천천히 해 주세요", "천천히 하기"),
        ("API를 바꾸지 마세요", "API를 바꾸지 않기"),
    ],
)
def test_actions_from_tails_and_verbs(text: str, todo: str) -> None:
    """H-4: 이모지·ㅎㅎ·^^ 꼬리가 있어도 요청을 놓치지 않는다. 할 일 문구는 ~기 꼴."""
    got = rules.actions(text, NOW)
    assert [a.text for a in got] == [todo]
    assert rules.intent(text, True) == "REQUEST"


def test_actions_skip_non_todo_and_duplicates() -> None:
    assert rules.actions("참고 부탁드려요", NOW) == ()
    assert len(rules.actions("자료 보내 주세요. 자료 보내 주세요.", NOW)) == 1


@pytest.mark.parametrize(
    ("text", "intent"),
    [("놀러 가죠?", "QUESTION"), ("하기로 했어요?", "QUESTION"), ("아직 확정 아니에요", "SHARE")],
)
def test_question_beats_decision(text: str, intent: str) -> None:
    assert rules.intent(text, False) == intent


def test_nuance_particle_follows_batchim() -> None:
    n = rules.nuance("확정했습니다", "DECISION")
    assert n is not None and n.note.startswith('"확정"은')


# ---------- Gemini 응답 모양 (M-1, M-3) ----------

REQ = EngineRequest("넥스트로 밀죠", "JARGON_TO_PLAIN", (), NOW)


def _payload(data: Any, finish: str | None = None) -> dict[str, Any]:
    cand: dict[str, Any] = {"content": {"parts": [{"text": json.dumps(data)}]}}
    if finish:
        cand["finishReason"] = finish
    return {"candidates": [cand]}


@pytest.mark.parametrize(
    "data",
    [
        {"resultText": "a", "intentType": "SHARE", "actionItems": ["do it"], "newTerms": []},
        {"resultText": "a", "intentType": "SHARE", "actionItems": [], "newTerms": ["x"]},
        ["not", "an", "object"],
    ],
)
def test_odd_shapes_are_engine_errors_or_ignored(data: Any) -> None:
    try:
        result = parse(_payload(data), REQ, "m")
    except EngineError as e:
        assert e.counts_as_failure
    else:
        assert result.actions == () and result.new_terms == ()


def test_nan_confidence_is_clamped() -> None:
    data = {
        "resultText": "a",
        "intentType": "SHARE",
        "nuance": {"note": "n", "tip": "t", "confidence": "NaN"},
        "actionItems": [],
        "newTerms": [],
    }
    nuance = parse(_payload(data), REQ, "m").nuance
    assert nuance is not None and nuance.confidence == 0.5


def test_safety_block_does_not_count_as_failure() -> None:
    with pytest.raises(EngineError) as e:
        parse({"candidates": [{"finishReason": "SAFETY"}]}, REQ, "m")
    assert not e.value.counts_as_failure
    with pytest.raises(EngineError) as e:
        parse({"promptFeedback": {"blockReason": "SAFETY"}}, REQ, "m")
    assert not e.value.counts_as_failure


# ---------- API (H-3, M-5, L-1~L-4) ----------


def test_concurrent_first_translations_make_one_project(
    client: TestClient, fake_apple: FakeApple
) -> None:
    """H-3: 첫 해석을 동시에 여러 번 보내도 500 이 나지 않고 프로젝트는 하나."""
    auth = login(client, fake_apple, "race")
    codes: list[int] = []

    def send(i: int) -> None:
        r = client.post(
            "/api/translations",
            json={"sourceText": f"{i}번 얼라인", "direction": "JARGON_TO_PLAIN"},
            headers=auth,
        )
        codes.append(r.status_code)

    threads = [threading.Thread(target=send, args=(i,)) for i in range(6)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert codes == [201] * 6
    assert client.get("/api/projects", headers=auth).json()["totalElements"] == 1


def test_reuse_respects_input_source_and_consent(client: TestClient, fake_apple: FakeApple) -> None:
    auth = login(client, fake_apple, "reuse")
    body = {"sourceText": "얼라인 부탁", "direction": "JARGON_TO_PLAIN"}
    a = client.post("/api/translations", json=body, headers=auth).json()["translationId"]
    shot = {**body, "inputSource": "SCREENSHOT", "sourceImageUrl": "https://cdn.example/a.png"}
    b = client.post("/api/translations", json=shot, headers=auth).json()["translationId"]
    assert a != b
    c = client.post(
        "/api/translations", json=body, headers={**auth, "X-Mw-AI-Consent": "1"}
    ).json()["translationId"]
    assert c != a, "동의를 새로 켰으면 지난 사전 결과를 다시 쓰지 않는다"


@pytest.mark.parametrize("raw", ["01", "%201", "%D9%A1", "%EF%BC%91", "1.0"])
def test_path_ids_must_be_plain_ascii_digits(
    client: TestClient, fake_apple: FakeApple, raw: str
) -> None:
    auth = login(client, fake_apple, "ids")
    client.post(
        "/api/translations",
        json={"sourceText": "얼라인", "direction": "JARGON_TO_PLAIN"},
        headers=auth,
    )
    r = client.get(f"/api/translations/{raw}", headers=auth)
    assert r.status_code == 404


@pytest.mark.parametrize(
    "extra",
    [
        {"projectId": True},
        {"projectId": "1"},
        {"projectId": 1.0},
        {"sourceImageUrl": "javascript:alert(1)"},
        {"sourceImageUrl": "file:///etc/passwd"},
    ],
)
def test_body_types_are_strict(
    client: TestClient, fake_apple: FakeApple, extra: dict[str, Any]
) -> None:
    auth = login(client, fake_apple, "strict")
    r = client.post(
        "/api/translations",
        json={"sourceText": "얼라인", "direction": "JARGON_TO_PLAIN", **extra},
        headers=auth,
    )
    assert r.status_code == 400


def test_action_flag_must_be_bool(client: TestClient, fake_apple: FakeApple) -> None:
    auth = login(client, fake_apple, "flag")
    t = client.post(
        "/api/translations",
        json={"sourceText": "자료 보내 주세요", "direction": "JARGON_TO_PLAIN"},
        headers=auth,
    ).json()
    url = f"/api/translations/{t['translationId']}/actions/{t['actionItems'][0]['actionId']}"
    assert client.patch(url, json={"isChecked": "yes"}, headers=auth).status_code == 400


@pytest.mark.parametrize("text", ["​", "​‍ ", "﻿"])
def test_invisible_only_text_is_400(client: TestClient, fake_apple: FakeApple, text: str) -> None:
    auth = login(client, fake_apple, "zw")
    r = client.post(
        "/api/translations", json={"sourceText": text, "direction": "JARGON_TO_PLAIN"}, headers=auth
    )
    assert r.status_code == 400


def test_nfd_input_is_normalized_and_matched(client: TestClient, fake_apple: FakeApple) -> None:
    import unicodedata

    auth = login(client, fake_apple, "nfd")
    text = unicodedata.normalize("NFD", "얼라인 부탁드려요")
    body = client.post(
        "/api/translations", json={"sourceText": text, "direction": "JARGON_TO_PLAIN"}, headers=auth
    ).json()
    assert body["sourceText"] == "얼라인 부탁드려요"
    assert [d["matchedText"] for d in body["detectedTerms"]] == ["얼라인"]


def test_ai_usage_is_logged_through_configured_handler(capsys: pytest.CaptureFixture[str]) -> None:
    """M-4: 운영 로그에 ai_usage 가 실제로 나온다(루트 WARNING 에 버려지지 않는다)."""
    import logging

    from app.main import configure_logging

    configure_logging()
    configure_logging()  # 두 번 불러도 핸들러는 하나
    logging.getLogger("mwonmal.ai").info("ai_usage engine=none")
    err = capsys.readouterr().err
    assert err.count("ai_usage engine=none") == 1
