"""문맥 판교어 탐지기(글자 CRF, ADR-0023): 특징·스팬 복원·관문·병합·모델 로드·API 통합."""

import json
import logging
import shutil
import threading
import unicodedata
from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.core.settings import settings
from app.decode.domain.jargon_features import (
    FEATURE_VERSION,
    LABEL_B,
    LABEL_I,
    LABEL_O,
    Candidate,
    acceptable,
    add_model_spans,
    decode,
    features,
    positions,
)
from app.decode.domain.model import Span
from app.decode.infra import jargon_model
from tests.conftest import FakeApple, login

NEW_SPELLING = (
    "이번 주에 싱크업 한번 하시죠"  # 사전엔 '싱크'만 있다(끝 경계 때문에 '싱크업'은 못 잡음)
)
NEW_TERM = "어카운터빌리티가 아직 부족해요"  # 사전에도 학습에도 없는 말
ORDINARY = [
    "오늘 회의록이랑 이메일 확인하고 마우스 바꿔 주세요",
    "마우스를 정리해서 올려주세요",
    "오늘 점심 뭐 드실래요?",
    "주방 싱크대가 막혀서 관리실에 연락했어요.",
    "align this with the team please",
]


@pytest.fixture(scope="module")
def tagger() -> jargon_model.CrfJargonTagger:
    t = jargon_model.load()
    assert t is not None, "커밋된 모델 파일이 있어야 한다"
    return t


# ---------- 순수 부분 ----------


@pytest.mark.parametrize("text", ["", "   ", "싱크업 해요", "😀👍🏽 R&R 정리\n해요", "가" * 500])
def test_one_token_per_non_space_scalar(text: str) -> None:
    pos = positions(text)
    assert pos == [i for i, c in enumerate(text) if not c.isspace()]
    assert len(features(text)) == len(pos)


def test_decode_bio_to_scalar_spans() -> None:
    text = "트레이드 오프가 큰 디벨롭"
    pos = positions(text)
    labels = [LABEL_O] * len(pos)
    for k, i in enumerate(pos):
        if i < 7:
            labels[k] = LABEL_B if i == 0 else LABEL_I
        if i >= 11:
            labels[k] = LABEL_I  # B 없이 시작한 I 도 스팬
    probs = [0.99] * len(pos)
    probs[2] = 0.7
    got = decode(pos, labels, probs)
    assert [(text[c.start : c.end], c.confidence) for c in got] == [
        ("트레이드 오프", 0.7),  # 공백을 건너 이어지고, 확신도 = 최솟값
        ("디벨롭", 0.99),
    ]


@pytest.mark.parametrize(
    ("text", "start", "end", "ok"),
    [
        ("싱크업해서 공유", 0, 3, True),
        ("주방 싱크대가", 3, 5, False),  # "싱크대"의 앞 두 글자: 끝 경계 위반
        ("디벨롭먼트 일정", 0, 3, False),  # 낱말 중간에서 끝남
        ("오버디벨롭 일정", 2, 5, False),  # 낱말 중간에서 시작
        ("핑 주세요", 0, 1, False),  # 한 글자
        ("2026 계획", 0, 4, False),  # 숫자만
        ("😀싱크업 해요", 0, 4, False),  # 이모지가 끼면 버린다
        ("마우스를 주세요", 0, 3, False),  # 평범한 말 목록
        ("트레이드 오프가 커요", 0, 7, True),  # 낱말 사이 한 칸은 된다
        ("트레이드\n오프가 커요", 0, 7, False),  # 줄바꿈을 건너면 안 된다
        ("ㅋㅋ 해요", 0, 2, False),  # 자모만
        ("MOUSE를 주세요", 0, 5, True),
    ],
)
def test_acceptable_gate(text: str, start: int, end: int, ok: bool) -> None:
    assert acceptable(text, start, end) is ok


def test_threshold_and_overlap_rules() -> None:
    text = "얼라인업 하고 싱크업 해요"
    dictionary = [Span(1, "얼라인", "방향 맞추기", "얼라인", 0, 3, 0.95)]
    cands = [Candidate(0, 4, 0.99), Candidate(8, 11, 0.9), Candidate(8, 11, 0.8999)]
    got = add_model_spans(text, dictionary, cands, 0.9)
    assert [(s.term_id, s.matched_text, s.start, s.end, s.confidence) for s in got] == [
        (1, "얼라인", 0, 3, 0.95),  # 사전 스팬은 그대로(겹치는 모델 스팬이 더 길어도 버린다)
        (None, "싱크업", 8, 11, 0.9),  # 임계값과 같으면 통과, 바로 아래는 버린다
    ]
    assert got[1].term_ko == "싱크업" and got[1].plain_ko == ""
    assert add_model_spans(text, dictionary, cands, 0.95) == dictionary


# ---------- 모델 ----------


def test_catches_new_spelling_and_new_term(tagger: jargon_model.CrfJargonTagger) -> None:
    for text, word in ((NEW_SPELLING, "싱크업"), (NEW_TERM, "어카운터빌리티")):
        got = add_model_spans(text, [], tagger.candidates(text), 0.9)
        assert [(s.matched_text, s.start) for s in got] == [(word, text.index(word))]
        assert got[0].term_id is None and 0.9 <= got[0].confidence <= 1.0


@pytest.mark.parametrize("text", ORDINARY)
def test_ordinary_sentences_are_not_flagged(
    tagger: jargon_model.CrfJargonTagger, text: str
) -> None:
    assert add_model_spans(text, [], tagger.candidates(text), 0.9) == []


def test_threshold_changes_output(tagger: jargon_model.CrfJargonTagger) -> None:
    cands = tagger.candidates(NEW_SPELLING)
    best = max(c.confidence for c in cands)
    assert add_model_spans(NEW_SPELLING, [], cands, best)
    assert add_model_spans(NEW_SPELLING, [], cands, min(1.0, best + 1e-6)) == []


def test_indices_are_unicode_scalars(tagger: jargon_model.CrfJargonTagger) -> None:
    text = "👍🏽 " + NEW_SPELLING  # 이모지 + 피부색 수식자 = 스칼라 2개
    got = [c for c in tagger.candidates(text) if text[c.start : c.end] == "싱크업"]
    assert [c.start for c in got] == [text.index("싱크업")] == [9]


def test_thread_safe(tagger: jargon_model.CrfJargonTagger) -> None:
    texts = [NEW_SPELLING, NEW_TERM, *ORDINARY] * 20
    want = [tagger.candidates(t) for t in texts]
    got: list[list[Candidate]] = [[] for _ in texts]

    def run(k: int) -> None:
        for i in range(k, len(texts), 8):
            got[i] = tagger.candidates(texts[i])

    threads = [threading.Thread(target=run, args=(k,)) for k in range(8)]
    for th in threads:
        th.start()
    for th in threads:
        th.join()
    assert got == want


def test_unusable_model_files_mean_no_model(tmp_path: Path) -> None:
    model, meta = tmp_path / "m.crfsuite", tmp_path / "m.json"
    assert jargon_model.load(model, meta) is None  # 파일 없음
    shutil.copyfile(jargon_model.MODEL_PATH, model)
    good = json.loads(jargon_model.META_PATH.read_text(encoding="utf-8"))
    meta.write_text(json.dumps({**good, "feature_version": "old"}), encoding="utf-8")
    assert jargon_model.load(model, meta) is None
    meta.write_text(json.dumps({**good, "sha256": "0" * 64}), encoding="utf-8")
    assert jargon_model.load(model, meta) is None
    meta.write_text(json.dumps(good), encoding="utf-8")
    assert jargon_model.load(model, meta) is not None
    assert good["feature_version"] == FEATURE_VERSION


# ---------- API ----------


@pytest.fixture
def model_on(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    monkeypatch.setattr(settings, "jargon_model", True)
    jargon_model.reset()
    yield
    jargon_model.reset()


def _post(client: TestClient, h: dict[str, str], text: str) -> dict[str, object]:
    r = client.post(
        "/api/translations", json={"sourceText": text, "direction": "JARGON_TO_PLAIN"}, headers=h
    )
    assert r.status_code == 201, r.text
    body: dict[str, object] = r.json()
    return body


def test_api_adds_model_span_with_null_term_id(
    client: TestClient, fake_apple: FakeApple, model_on: None
) -> None:
    h = login(client, fake_apple)
    text = "R&R 정리하고 " + NEW_SPELLING
    body = _post(client, h, text)
    terms = body["detectedTerms"]
    assert isinstance(terms, list)
    got = [(d["termId"] is None, d["matchedText"], d["startIndex"], d["endIndex"]) for d in terms]
    at = text.index("싱크업")
    assert got == [(False, "R&R", 0, 3), (True, "싱크업", at, at + 3)]
    model = terms[1]
    assert model["termKo"] == "싱크업" and model["plainKo"] == ""
    assert 0.9 <= model["confidence"] <= 1.0 and model["inMyCards"] is False
    assert body["jargonCount"] == 2
    assert (
        body["resultText"] == "역할과 책임 정리하고 " + NEW_SPELLING
    )  # 뜻 모르는 말은 그대로 둔다
    got_body = client.get(f"/api/translations/{body['translationId']}", headers=h).json()
    assert got_body == body  # 다시 읽지 않고 만든 응답 = GET


def test_api_nfd_input_indices_follow_stored_nfc_text(
    client: TestClient, fake_apple: FakeApple, model_on: None
) -> None:
    h = login(client, fake_apple)
    body = _post(client, h, unicodedata.normalize("NFD", "👍🏽 " + NEW_SPELLING))
    source = body["sourceText"]
    assert isinstance(source, str) and source == "👍🏽 " + NEW_SPELLING
    terms = body["detectedTerms"]
    assert isinstance(terms, list)
    for d in terms:
        assert source[d["startIndex"] : d["endIndex"]] == d["matchedText"]


def test_flag_off_restores_dictionary_only(
    client: TestClient, fake_apple: FakeApple, monkeypatch: pytest.MonkeyPatch
) -> None:
    h = login(client, fake_apple)
    monkeypatch.setattr(settings, "jargon_model", False)
    body = _post(client, h, "R&R 정리하고 " + NEW_SPELLING)
    terms = body["detectedTerms"]
    assert isinstance(terms, list)
    assert [d["matchedText"] for d in terms] == ["R&R"]


def test_missing_model_restores_dictionary_only(
    client: TestClient,
    fake_apple: FakeApple,
    model_on: None,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    h = login(client, fake_apple)
    monkeypatch.setattr(jargon_model, "load", lambda: None)  # 파일 없음·버전·해시 불일치와 같다
    body = _post(client, h, "R&R 정리하고 " + NEW_SPELLING)
    terms = body["detectedTerms"]
    assert isinstance(terms, list)
    assert [d["matchedText"] for d in terms] == ["R&R"]


def test_model_failure_keeps_dictionary_result_and_hides_text(
    client: TestClient,
    fake_apple: FakeApple,
    model_on: None,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    h = login(client, fake_apple)
    tagger = jargon_model.shared()
    assert tagger is not None

    def boom(text: str) -> list[Candidate]:
        raise RuntimeError(text)  # 예외 메시지에 원문이 실려도 로그로 새지 않아야 한다

    monkeypatch.setattr(tagger, "candidates", boom)
    caplog.set_level(logging.INFO)
    secret = "카나리-91b2 " + NEW_SPELLING
    body = _post(client, h, secret)
    terms = body["detectedTerms"]
    assert isinstance(terms, list) and terms == []
    assert any(r.getMessage() == "jargon_model_failed" for r in caplog.records)
    for rec in caplog.records:
        assert "카나리-91b2" not in rec.getMessage() and rec.exc_info is None
