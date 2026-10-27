"""해석·할 일·용어·프로젝트 API (#11·#12) + 라우터 사슬 + 원문 무유출 카나리 (REQ-14)."""

import json
import logging
import re
from collections.abc import Iterator
from datetime import datetime
from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core import security
from app.core.kv import MemoryKV
from app.core.settings import settings
from app.decode.api.routes import engine_router
from app.decode.domain.model import EngineError, EngineRequest, EngineResult, NewTerm, Nuance
from app.decode.infra.engines.gemini import GeminiEngine, build_prompt
from app.decode.infra.engines.guards import Breaker, Quota
from app.decode.infra.engines.none_engine import NoneEngine
from app.decode.infra.engines.router import EngineRouter, ExternalEngine
from app.main import app
from tests.conftest import FakeApple, login

EXAMPLE = "이번 스프린트 스코프 아웃하고 넥스트로 밀죠. 그 전에 R&R 정리해서 얼라인 쳐주세요"
CANARY = "카나리-7f3a9c 원문은 절대 로그에 남지 않는다 얼라인"
AI_MODEL_RE = re.compile(r"^[a-z_]+/[A-Za-z0-9._-]+#p\d+$")  # 14번 §15-4 규약


def post(client: TestClient, headers: dict[str, str], text: str, **extra: Any) -> httpx.Response:
    r: httpx.Response = client.post(
        "/api/translations",
        json={"sourceText": text, "direction": "JARGON_TO_PLAIN", **extra},
        headers=headers,
    )
    return r


@pytest.fixture
def auth(client: TestClient, fake_apple: FakeApple) -> dict[str, str]:
    return login(client, fake_apple, "u1")


# ---------- 해석 만들기 ----------


def test_contract_example_offsets_and_dictionary_result(
    client: TestClient, auth: dict[str, str]
) -> None:
    r = post(client, auth, EXAMPLE)
    assert r.status_code == 201, r.text
    body = r.json()
    spans = [(d["matchedText"], d["startIndex"], d["endIndex"]) for d in body["detectedTerms"]]
    assert spans == [
        ("스코프 아웃", 8, 14),
        ("넥스트", 17, 20),
        ("R&R", 31, 34),
        ("얼라인", 40, 43),
    ]
    assert all(d["termId"] is not None and d["inMyCards"] is False for d in body["detectedTerms"])
    assert body["jargonCount"] == 4
    assert body["resultText"].startswith("이번 스프린트 작업 범위에서 제외하고 다음 차례로 밀죠.")
    assert body["intentType"] == "DECISION"
    assert body["nuance"]["note"].startswith('"밀죠"')
    assert body["actionItems"][0]["actionText"] == "역할과 책임 정리해서 방향 맞추기"
    assert body["aiModel"] == "none/dictionary#p1"
    assert AI_MODEL_RE.match(body["aiModel"])
    assert body["projectName"] == "내 프로젝트"
    assert body["meetingId"] is None and body["sourceType"] == "MESSAGE"
    assert body["inputSource"] == "TYPED"
    me = client.get("/api/users/me", headers=auth).json()
    assert me["currentProjectId"] == body["projectId"]


def test_clean_korean_has_no_terms(client: TestClient, auth: dict[str, str]) -> None:
    body = post(client, auth, "오늘 점심 뭐 드실래요?").json()
    assert body["jargonCount"] == 0 and body["detectedTerms"] == []
    assert body["resultText"] == "오늘 점심 뭐 드실래요?"
    assert body["actionItems"] == [] and body["nuance"] is None


def test_same_text_within_ten_minutes_is_reused(client: TestClient, auth: dict[str, str]) -> None:
    a = post(client, auth, EXAMPLE).json()["translationId"]
    b = post(client, auth, EXAMPLE).json()["translationId"]
    assert a == b
    assert client.get("/api/translations", headers=auth).json()["totalElements"] == 1


@pytest.mark.parametrize("text", ["   ", "\n\t"])
def test_blank_text_is_400(client: TestClient, auth: dict[str, str], text: str) -> None:
    r = post(client, auth, text)
    assert r.status_code == 400
    assert r.json()["code"] == "INVALID_INPUT" and r.json()["field"] == "sourceText"


def test_too_long_text_is_400(client: TestClient, auth: dict[str, str]) -> None:
    r = post(client, auth, "가" * 501)
    assert r.status_code == 400 and r.json()["field"] == "sourceText"


def test_needs_login(client: TestClient) -> None:
    r = client.post("/api/translations", json={"sourceText": "a", "direction": "JARGON_TO_PLAIN"})
    assert r.status_code == 401 and r.json()["code"] == "UNAUTHORIZED"


def test_unknown_project_and_meeting(client: TestClient, auth: dict[str, str]) -> None:
    assert post(client, auth, "a", projectId=999).json()["code"] == "PROJECT_NOT_FOUND"
    pid = post(client, auth, "얼라인").json()["projectId"]
    r = post(client, auth, "b", projectId=pid, meetingId=5)
    assert r.status_code == 404 and r.json()["code"] == "MEETING_NOT_FOUND"
    r = post(client, auth, "c", projectId=2**63)
    assert r.status_code == 400


def test_other_users_project_and_translation(
    client: TestClient, fake_apple: FakeApple, auth: dict[str, str]
) -> None:
    mine = post(client, auth, EXAMPLE).json()
    other = login(client, fake_apple, "u2")
    r = post(client, other, "x", projectId=mine["projectId"])
    assert r.status_code == 403 and r.json()["code"] == "NOT_OWNER"
    tid = mine["translationId"]
    assert client.get(f"/api/translations/{tid}", headers=other).status_code == 403
    assert client.delete(f"/api/translations/{tid}", headers=other).status_code == 403
    aid = mine["actionItems"][0]["actionId"]
    r = client.patch(
        f"/api/translations/{tid}/actions/{aid}", json={"isChecked": True}, headers=other
    )
    assert r.status_code == 403
    assert client.get("/api/translations", headers=other).json()["totalElements"] == 0
    assert client.get("/api/actions", headers=other).json()["totalElements"] == 0
    assert client.get(f"/api/projects/{mine['projectId']}", headers=other).status_code == 403


# ---------- 목록·단건·삭제 ----------


def test_list_and_get(client: TestClient, auth: dict[str, str]) -> None:
    ids = [
        post(client, auth, f"{i}번째 싱크 내일까지 부탁드려요").json()["translationId"]
        for i in range(3)
    ]
    page = client.get("/api/translations?size=2", headers=auth).json()
    assert page["totalElements"] == 3 and page["totalPages"] == 2 and page["page"] == 1
    assert [c["translationId"] for c in page["content"]] == ids[::-1][:2]
    first = page["content"][0]
    assert first["actionCount"] == 1 and first["openActionCount"] == 1
    assert first["title"].startswith("2번째 싱크")
    assert client.get("/api/translations?meetingId=none", headers=auth).json()["totalElements"] == 3
    assert client.get("/api/translations?meetingId=7", headers=auth).json()["totalElements"] == 0
    assert client.get("/api/translations?meetingId=abc", headers=auth).json()["totalElements"] == 0
    one = client.get(f"/api/translations/{ids[0]}", headers=auth).json()
    assert one["sourceText"] == "0번째 싱크 내일까지 부탁드려요"
    assert client.get("/api/translations/424242", headers=auth).json()["code"] == (
        "TRANSLATION_NOT_FOUND"
    )


def test_delete(client: TestClient, auth: dict[str, str]) -> None:
    tid = post(client, auth, EXAMPLE).json()["translationId"]
    assert client.delete(f"/api/translations/{tid}", headers=auth).status_code == 204
    assert client.get(f"/api/translations/{tid}", headers=auth).status_code == 404
    assert client.delete(f"/api/translations/{tid}", headers=auth).status_code == 404


# ---------- 할 일 ----------


def test_action_check_and_list(client: TestClient, auth: dict[str, str]) -> None:
    t = post(client, auth, "내일까지 디자인 시안 공유해 주세요").json()
    a = t["actionItems"][0]
    assert a["dueHint"] == "내일까지" and a["isChecked"] is False and a["alertEnabled"] is True
    url = f"/api/translations/{t['translationId']}/actions/{a['actionId']}"
    r = client.patch(url, json={"isChecked": True}, headers=auth)
    assert r.status_code == 200 and r.json()["isChecked"] is True and r.json()["checkedAt"]
    assert client.get("/api/actions", headers=auth).json()["totalElements"] == 0
    done = client.get("/api/actions?checked=true", headers=auth).json()
    assert done["content"][0]["sourceText"] == "내일까지 디자인 시안 공유해 주세요"
    assert done["content"][0]["projectName"] == "내 프로젝트"
    r = client.patch(url, json={"isChecked": False, "alertEnabled": False}, headers=auth)
    assert r.json()["checkedAt"] is None and r.json()["alertEnabled"] is False
    assert client.patch(url, json={}, headers=auth).status_code == 400
    bad = f"/api/translations/{t['translationId']}/actions/999"
    assert client.patch(bad, json={"isChecked": True}, headers=auth).json()["code"] == (
        "ACTION_NOT_FOUND"
    )


# ---------- 용어·프로젝트 ----------


def test_term_detail(client: TestClient, auth: dict[str, str]) -> None:
    term_id = post(client, auth, EXAMPLE).json()["detectedTerms"][3]["termId"]
    r = client.get(f"/api/terms/{term_id}")
    assert r.status_code == 200
    body = r.json()
    assert body["termKo"] == "얼라인" and body["slug"] == "align" and body["category"] == "WORK"
    assert body["examples"][0]["sentenceJargon"] == "이번 주까지 팀 간 얼라인 부탁드려요."
    assert body["myCard"] is None and body["inMyCards"] is False
    assert body["viewCount"] == 1
    assert client.get(f"/api/terms/{term_id}", headers=auth).json()["viewCount"] == 2
    assert client.get("/api/terms/999999").json()["code"] == "TERM_NOT_FOUND"
    assert (
        client.get(f"/api/terms/{term_id}", headers={"Authorization": "Bearer x"}).status_code
        == 401
    )


def test_projects(client: TestClient, auth: dict[str, str]) -> None:
    assert client.get("/api/projects", headers=auth).json()["totalElements"] == 0
    t = post(client, auth, EXAMPLE).json()
    page = client.get("/api/projects", headers=auth).json()
    p = page["content"][0]
    assert p["name"] == "내 프로젝트" and p["isDefault"] is True
    assert p["translationCount"] == 1 and p["openActionCount"] == 1 and p["meetingCount"] == 0
    assert (
        client.get(f"/api/projects/{t['projectId']}", headers=auth).json()["projectId"]
        == (t["projectId"])
    )
    assert client.get("/api/projects/9999", headers=auth).json()["code"] == "PROJECT_NOT_FOUND"


# ---------- 라우터 사슬 ----------


class FakeExternal:
    name = "gemini_free"

    def __init__(self, fail: bool = False) -> None:
        self.calls: list[EngineRequest] = []
        self.fail = fail

    async def decode(self, request: EngineRequest) -> EngineResult:
        self.calls.append(request)
        if self.fail:
            raise EngineError("http_500")
        return EngineResult(
            result_text="쉬운 말",
            intent="REQUEST",
            nuance=Nuance("숨은 뜻", "팁", 0.9),
            actions=(),
            ai_model="gemini_free/gemini-2.5-flash#p1",
            new_terms=(
                NewTerm("쳐주세요", "해 주세요", "쳐주세요"),
                NewTerm("없는말", "x", "없는말"),
            ),
        )


def make_router(ext: FakeExternal, *, enabled: bool = True, degraded: bool = True) -> EngineRouter:
    kv = MemoryKV()
    return EngineRouter(
        fallback=NoneEngine(),
        external=ExternalEngine(
            ext,
            Quota(kv, engine="gemini_free", model="m", rpm=100, rpd=100),
            Breaker(kv, "gemini_free"),
            "m",
        ),
        external_enabled=enabled,
        allow_degraded=degraded,
    )


@pytest.fixture
def use_router() -> Iterator[Any]:
    def install(r: EngineRouter) -> None:
        app.dependency_overrides[engine_router] = lambda: r

    yield install
    app.dependency_overrides.pop(engine_router, None)


def test_no_consent_never_calls_external(
    client: TestClient, auth: dict[str, str], use_router: Any
) -> None:
    ext = FakeExternal()
    use_router(make_router(ext))
    body = post(client, auth, EXAMPLE).json()
    assert ext.calls == [] and body["aiModel"].startswith("none/")
    body = post(client, {**auth, "X-Mw-AI-Consent": "true"}, EXAMPLE + "!").json()
    assert ext.calls == [], "헤더 값은 정확히 1 이어야 한다"


def test_external_off_never_calls_external(
    client: TestClient, auth: dict[str, str], use_router: Any
) -> None:
    ext = FakeExternal()
    use_router(make_router(ext, enabled=False))
    post(client, {**auth, "X-Mw-AI-Consent": "1"}, EXAMPLE)
    assert ext.calls == []


def test_consent_uses_external_and_places_new_terms(
    client: TestClient, auth: dict[str, str], use_router: Any
) -> None:
    ext = FakeExternal()
    use_router(make_router(ext))
    body = post(client, {**auth, "X-Mw-AI-Consent": "1"}, EXAMPLE).json()
    assert len(ext.calls) == 1
    assert body["aiModel"] == "gemini_free/gemini-2.5-flash#p1" and AI_MODEL_RE.match(
        body["aiModel"]
    )
    assert body["nuance"] == {"note": "숨은 뜻", "tip": "팁", "confidence": 0.9}
    new = [d for d in body["detectedTerms"] if d["termId"] is None]
    assert [(d["termKo"], d["startIndex"], d["endIndex"]) for d in new] == [("쳐주세요", 44, 48)]
    assert EXAMPLE[44:48] == "쳐주세요"


def test_external_failure_degrades_without_retry(
    client: TestClient, auth: dict[str, str], use_router: Any
) -> None:
    ext = FakeExternal(fail=True)
    use_router(make_router(ext))
    body = post(client, {**auth, "X-Mw-AI-Consent": "1"}, EXAMPLE).json()
    assert len(ext.calls) == 1, "재시도 없음"
    assert body["aiModel"] == "none/dictionary#p1"
    post(client, {**auth, "X-Mw-AI-Consent": "1"}, EXAMPLE + "?")
    post(client, {**auth, "X-Mw-AI-Consent": "1"}, EXAMPLE + "!")
    assert len(ext.calls) == 2, "두 번 실패하면 브레이커가 열려 세 번째는 안 부른다"


def test_failure_without_degrade_is_503(
    client: TestClient, auth: dict[str, str], use_router: Any
) -> None:
    use_router(make_router(FakeExternal(fail=True), degraded=False))
    r = post(client, {**auth, "X-Mw-AI-Consent": "1"}, EXAMPLE)
    assert r.status_code == 503 and r.json()["code"] == "AI_UNAVAILABLE"
    assert r.headers["Retry-After"] == "5"
    assert client.get("/api/translations", headers=auth).json()["totalElements"] == 0


def test_quota_exhausted_falls_back(
    client: TestClient, auth: dict[str, str], use_router: Any
) -> None:
    ext = FakeExternal()
    kv = MemoryKV()
    router = EngineRouter(
        fallback=NoneEngine(),
        external=ExternalEngine(
            ext, Quota(kv, engine="g", model="m", rpm=1, rpd=1), Breaker(kv, "g"), "m"
        ),
        external_enabled=True,
        allow_degraded=True,
    )
    use_router(router)
    body = post(client, {**auth, "X-Mw-AI-Consent": "1"}, EXAMPLE).json()
    assert ext.calls == [] and body["aiModel"].startswith("none/")  # 1 × 0.8 = 0 → 바로 none


# ---------- 프롬프트·카나리 ----------


def test_prompt_has_only_text_and_glossary() -> None:
    from app.decode.domain.model import Span

    req = EngineRequest(
        CANARY,
        "JARGON_TO_PLAIN",
        (Span(3, "얼라인", "방향 맞추기", "얼라인", 0, 3, 0.95),),
        datetime(2026, 1, 1),
    )
    prompt = build_prompt(req)
    assert CANARY in prompt and "- 얼라인: 방향 맞추기" in prompt
    # 빌더는 사용자·프로젝트·회의 정보를 인자로 받지 않는다.
    assert set(EngineRequest.__dataclass_fields__) == {"source_text", "direction", "spans", "now"}


def test_canary_never_logged(
    client: TestClient,
    auth: dict[str, str],
    use_router: Any,
    caplog: pytest.LogCaptureFixture,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    caplog.set_level(logging.INFO)  # 운영 로그 수준(드라이버 DEBUG 는 운영에서 꺼져 있다)
    # SQL 문 로그는 운영에서 바인드 값을 숨긴다(get_engine hide_parameters, test_hardening 이 확인).
    # 테스트 엔진은 그 설정이 없으므로 드라이버 로거는 여기서 끈다. 우리 코드의 로그만 본다.
    # caplog.set_level(logger=...) 은 캡처 핸들러 수준까지 올려 버리므로 로거 수준만 직접 바꾼다.
    for name in ("aiosqlite", "sqlalchemy"):
        monkeypatch.setattr(logging.getLogger(name), "level", logging.WARNING)
    use_router(make_router(FakeExternal(fail=True), degraded=False))
    post(client, {**auth, "X-Mw-AI-Consent": "1"}, CANARY)
    use_router(make_router(FakeExternal()))
    post(client, {**auth, "X-Mw-AI-Consent": "1"}, CANARY)
    assert caplog.records, "기록 자체는 남아야 한다(ai_usage)"
    for rec in caplog.records:
        assert "카나리-7f3a9c" not in rec.getMessage(), (rec.name, rec.levelname)


def test_gemini_adapter_parses_and_hides_provider_body() -> None:
    sent: list[dict[str, Any]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        sent.append(json.loads(request.content))
        assert request.headers["x-goog-api-key"] == "k"
        if "fail" in json.dumps(sent[-1], ensure_ascii=False):
            return httpx.Response(500, text="provider secret detail")
        data = {
            "resultText": "다음으로 미루죠",
            "intentType": "DECISION",
            "nuance": None,
            "actionItems": [{"actionText": "정리하기", "dueHint": "내일"}],
            "newTerms": [],
        }
        return httpx.Response(
            200, json={"candidates": [{"content": {"parts": [{"text": json.dumps(data)}]}}]}
        )

    engine = GeminiEngine(
        httpx.AsyncClient(transport=httpx.MockTransport(handler)), api_key="k", model="m", timeout=1
    )
    import anyio

    req = EngineRequest("넥스트로 밀죠", "JARGON_TO_PLAIN", (), datetime(2026, 10, 27, 1))
    result = anyio.run(engine.decode, req)
    assert result.result_text == "다음으로 미루죠" and result.ai_model == "gemini_free/m#p1"
    assert result.actions[0].due_at == datetime(2026, 10, 28, 9)
    assert sent[0]["generationConfig"]["responseMimeType"] == "application/json"
    with pytest.raises(EngineError) as e:
        anyio.run(engine.decode, EngineRequest("fail", "JARGON_TO_PLAIN", (), datetime(2026, 1, 1)))
    assert e.value.reason == "http_500" and "secret" not in str(e.value)


# ---------- 개발용 로그인 ----------


def test_dev_login_off_by_default(client: TestClient) -> None:
    r = client.post("/api/auth/oauth/apple", json={"code": "dev:alice", "redirectUri": "x"})
    assert r.status_code == 401


def test_dev_login_on(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "dev_login", True)
    r = client.post("/api/auth/oauth/apple", json={"code": "dev:alice", "redirectUri": "x"})
    assert r.status_code == 200 and r.json()["user"]["email"] == "alice@dev.mwonmal.invalid"
    bad = client.post("/api/auth/oauth/apple", json={"code": "dev:../x", "redirectUri": "x"})
    assert bad.status_code == 401


def test_dev_login_refused_outside_local(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "dev_login", True)
    monkeypatch.setattr(settings, "env", "prod")
    monkeypatch.setattr(settings, "redis_url", "redis://x")
    security._keys.cache_clear()
    monkeypatch.setattr(settings, "jwt_private_key", "")
    with pytest.raises(RuntimeError):
        security.check_keys()
    security._keys.cache_clear()
