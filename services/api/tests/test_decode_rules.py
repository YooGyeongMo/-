"""decode 순수 규칙: 사전 매칭(공용 벡터), 조사 고치기, 간이 해석 규칙, 한도·브레이커."""

import json
from datetime import UTC, datetime
from pathlib import Path

import pytest

from app.core.kv import MemoryKV
from app.decode.domain import rules
from app.decode.domain.matching import Match, Trie, fix_josa, substitute
from app.decode.infra.engines.guards import Breaker, Quota
from app.decode.infra.seed_terms import TERMS

VECTORS = Path(__file__).resolve().parents[3] / "packages/test-vectors/jargon_match.json"


def test_match_vectors_shared_with_app() -> None:
    v = json.loads(VECTORS.read_text(encoding="utf-8"))
    trie = Trie(v["dictionary"])
    for case in v["cases"]:
        got = [[m.start, m.end, m.key] for m in trie.find(case["text"])]
        assert got == case["spans"], case["text"]


def test_seed_dictionary_rules() -> None:
    assert len(TERMS) >= 100
    slugs = [t.slug for t in TERMS]
    assert len(slugs) == len(set(slugs))
    for t in TERMS:
        assert len(t.ko) >= 2, f"한 글자 용어는 오탐이 많다: {t.ko}"
        assert t.category in {"WORK", "DATA", "DEV", "ORG", "MEETING", "ETC"}
        assert len(t.plain) <= 200 and len(t.meaning) <= 1000 and len(t.ko) <= 100
    # 계약 예시 용어는 사전에 있다.
    kos = {t.ko for t in TERMS}
    assert {"스코프 아웃", "넥스트", "R&R", "얼라인", "챌린지", "팔로업"} <= kos


@pytest.mark.parametrize(
    ("replacement", "following", "fixed"),
    [
        ("방향 맞추기", "을 해요", "를"),
        ("역할과 책임", "가 정해요", "이"),
        ("다음 차례", "으로 밀죠", "로"),
        ("여유 시간", "로 두죠", "으로"),
        ("작업 범위", "은 넓어요", "는"),
        ("방향 맞춤", "는 끝났어요", "은"),
        ("방향 맞추기", "이에요", ""),  # '이에요'의 '이'는 조사가 아니다
        ("API", "를", ""),  # 한글이 아니면 손대지 않는다
    ],
)
def test_fix_josa(replacement: str, following: str, fixed: str) -> None:
    assert fix_josa(replacement, following) == fixed


def test_substitute_contract_example() -> None:
    text = "이번 스프린트 스코프 아웃하고 넥스트로 밀죠. 그 전에 R&R 정리해서 얼라인 쳐주세요"
    matches = [
        Match(8, 14, "a", "스코프 아웃"),
        Match(17, 20, "b", "넥스트"),
        Match(31, 34, "c", "R&R"),
        Match(40, 43, "d", "얼라인"),
    ]
    plain = {"a": "작업 범위에서 제외", "b": "다음 차례", "c": "역할과 책임", "d": "방향 맞추기"}
    assert substitute(text, matches, plain) == (
        "이번 스프린트 작업 범위에서 제외하고 다음 차례로 밀죠. "
        "그 전에 역할과 책임 정리해서 방향 맞추기 해 주세요"
    )


NOW = datetime(2026, 10, 27, 1, 0)  # 화요일 10:00 KST


def test_actions_and_due() -> None:
    a = rules.actions("내일까지 디자인 시안 공유해 주세요. 오늘 점심 뭐 드실래요?", NOW)
    assert len(a) == 1
    assert a[0].text == "내일까지 디자인 시안 공유하기"
    assert a[0].due_hint == "내일까지"
    assert a[0].due_at == datetime(2026, 10, 28, 9, 0)  # 수 18:00 KST = 09:00 UTC


@pytest.mark.parametrize(
    ("hint", "expected"),
    [
        ("오늘", datetime(2026, 10, 27, 9, 0)),
        ("EOD", datetime(2026, 10, 27, 9, 0)),
        ("이번 주", datetime(2026, 10, 30, 9, 0)),  # 금요일
        ("다음 주", datetime(2026, 11, 2, 9, 0)),  # 월요일
        ("금요일까지", datetime(2026, 10, 30, 9, 0)),
        ("3시까지", datetime(2026, 10, 27, 6, 0)),  # 15:00 KST
        ("나중에", None),
        (None, None),
    ],
)
def test_due_at(hint: str | None, expected: datetime | None) -> None:
    assert rules.due_at(hint, NOW) == expected


def test_due_at_in_the_past_is_dropped() -> None:
    late = datetime(2026, 10, 27, 10, 0)  # 19:00 KST
    assert rules.due_at("오늘", late) is None


@pytest.mark.parametrize(
    ("text", "intent"),
    [
        (
            "이번 스프린트 스코프 아웃하고 넥스트로 밀죠. 그 전에 R&R 정리해서 얼라인 쳐주세요",
            "DECISION",
        ),
        ("그건 좀 챌린지가 있을 것 같은데요. 일단 팔로업할게요", "DECLINE"),
        ("오늘 점심 뭐 드실래요?", "QUESTION"),
        ("내일까지 자료 보내 주세요", "REQUEST"),
        ("배포 완료했습니다", "SHARE"),
    ],
)
def test_intent(text: str, intent: str) -> None:
    assert rules.intent(text, bool(rules.actions(text, NOW))) == intent


@pytest.mark.anyio
async def test_quota_soft_cap_and_windows() -> None:
    kv = MemoryKV()
    t = datetime(2026, 10, 27, 1, 0, tzinfo=UTC)
    q = Quota(kv, engine="g", model="m", rpm=5, rpd=100, now=lambda: t)
    assert [await q.take() for _ in range(5)] == [True, True, True, True, False]  # 5 × 0.8 = 4
    assert q.keys() == ("ai:quota:g:m:rpm:202610270100", "ai:quota:g:m:rpd:20261027")


@pytest.mark.anyio
async def test_quota_daily_cap() -> None:
    kv = MemoryKV()
    minute = [0]

    def now() -> datetime:
        return datetime(2026, 10, 27, 1, minute[0], tzinfo=UTC)

    q = Quota(kv, engine="g", model="m", rpm=100, rpd=10, now=now)
    took = 0
    for i in range(20):
        minute[0] = i
        took += await q.take()
    assert took == 8


@pytest.mark.anyio
async def test_breaker_transitions() -> None:
    clock = [0.0]
    kv = MemoryKV(clock=lambda: clock[0])
    b = Breaker(kv, "g")
    assert await b.state() == "CLOSED"
    t = await b.allow()
    assert t is not None and not t.probe
    await b.failure(t)
    assert await b.state() == "CLOSED"
    await b.failure(t)  # 30초 안 2번 → OPEN 60초
    assert await b.state() == "OPEN"
    assert await b.allow() is None
    clock[0] = 61
    assert await b.state() == "HALF_OPEN"
    probe = await b.allow()
    assert probe is not None and probe.probe
    assert await b.allow() is None  # 두 번째는 막힌다(락)
    await b.failure(probe)  # 프로브 실패 → 120초 OPEN
    assert await b.state() == "OPEN"
    clock[0] = 61 + 121
    probe = await b.allow()
    assert probe is not None and probe.probe
    await b.success(probe)
    assert await b.state() == "CLOSED"


@pytest.mark.anyio
async def test_breaker_failures_spread_out_do_not_open() -> None:
    clock = [0.0]
    kv = MemoryKV(clock=lambda: clock[0])
    b = Breaker(kv, "g")
    t = await b.allow()
    assert t is not None
    await b.failure(t)
    clock[0] = 31
    await b.failure(t)
    assert await b.state() == "CLOSED"


@pytest.mark.anyio
async def test_breaker_concurrent_failures_open_once_for_60s() -> None:
    """레드팀 M-2: 동시 실패 5건이 OPEN 을 480초까지 키우면 안 된다."""
    clock = [0.0]
    kv = MemoryKV(clock=lambda: clock[0])
    b = Breaker(kv, "g")
    tickets = [await b.allow() for _ in range(5)]
    for t in tickets:
        assert t is not None
        await b.failure(t)
    clock[0] = 61
    assert await b.state() == "HALF_OPEN"


@pytest.mark.anyio
async def test_breaker_late_success_does_not_close_open() -> None:
    clock = [0.0]
    kv = MemoryKV(clock=lambda: clock[0])
    b = Breaker(kv, "g")
    slow = await b.allow()
    t = await b.allow()
    assert slow is not None and t is not None
    await b.failure(t)
    await b.failure(t)
    await b.success(slow)  # 열리기 전에 출발한 느린 성공
    assert await b.state() == "OPEN"


@pytest.mark.anyio
async def test_breaker_release_frees_probe_without_counting() -> None:
    clock = [0.0]
    kv = MemoryKV(clock=lambda: clock[0])
    b = Breaker(kv, "g")
    t = await b.allow()
    assert t is not None
    await b.failure(t)
    await b.failure(t)
    clock[0] = 61
    probe = await b.allow()
    assert probe is not None
    await b.release(probe)
    assert await b.state() == "HALF_OPEN"
    assert await b.allow() is not None
