"""decode 도메인 값. 프레임워크·DB를 모른다."""

from dataclasses import dataclass, field
from datetime import datetime
from typing import Protocol


@dataclass(frozen=True)
class DictTerm:
    """사전 용어 한 개(검수됨, status=APPROVED)."""

    id: int
    slug: str
    ko: str
    plain: str


@dataclass(frozen=True)
class Span:
    """원문에서 찾은 용어 자리. term_id 가 None 이면 사전에 없는 새 말(AI가 찾음)."""

    term_id: int | None
    term_ko: str
    plain_ko: str
    matched_text: str
    start: int
    end: int
    confidence: float


@dataclass(frozen=True)
class ActionDraft:
    text: str
    due_hint: str | None = None
    due_at: datetime | None = None  # UTC naive


@dataclass(frozen=True)
class Nuance:
    note: str
    tip: str
    confidence: float


@dataclass(frozen=True)
class NewTerm:
    """AI가 찾은, 사전에 없는 말. 서버가 원문에서 위치를 다시 찾는다(AI가 준 인덱스는 믿지
    않는다)."""

    term_ko: str
    plain_ko: str
    matched_text: str


@dataclass(frozen=True)
class EngineRequest:
    source_text: str
    direction: str  # JARGON_TO_PLAIN | PLAIN_TO_JARGON
    spans: tuple[Span, ...]  # 사전 매칭 결과(엔진 공통 입력)
    now: datetime  # UTC naive. 기한 힌트 → 시각 계산 기준


@dataclass(frozen=True)
class EngineResult:
    result_text: str
    intent: str | None
    nuance: Nuance | None
    actions: tuple[ActionDraft, ...]
    ai_model: str  # "<engine>/<model>#p<prompt>" (14번 §15-4)
    new_terms: tuple[NewTerm, ...] = field(default_factory=tuple)


class EngineError(Exception):
    """엔진 실패. 제공자 응답 본문·원문은 절대 싣지 않는다(REQ-14). reason 은 짧은 기술 코드."""

    def __init__(self, reason: str, *, counts_as_failure: bool = True) -> None:
        super().__init__(reason)
        self.reason = reason
        # 안전 필터 차단처럼 제공자가 멀쩡한 경우는 브레이커에 세지 않는다(한 사용자가 모두를 막지
        # 않게).
        self.counts_as_failure = counts_as_failure


class Engine(Protocol):
    name: str

    async def decode(self, request: EngineRequest) -> EngineResult: ...
