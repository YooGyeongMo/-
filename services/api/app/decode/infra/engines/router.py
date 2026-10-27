"""EngineRouter (14번 §15-3, ADR-0008, #36·#11).

사슬(prod): gemini_free(옵트인 && 외부 전송 켜짐 && 키 있음 && 브레이커 닫힘 && 한도 남음) → none.
- 옵트인 = 요청 헤더 `X-Mw-AI-Consent: 1`. 헤더가 없으면 원문은 절대 밖으로 나가지 않는다.
- 외부 엔진이 실패하면 재시도하지 않고 바로 none 으로 강등한다(ROUTER_ALLOW_DEGRADED, U-9).
  강등을 끄면 503 AI_UNAVAILABLE + Retry-After.
- 기록(recorder): 엔진·결과·지연만 남긴다. 원문·사용자 ID 는 남기지 않는다. ai_usage 테이블은
  v1.1(0002 계약) →
  지금은 로그 sink.
"""

import logging
import time
from collections.abc import Awaitable
from dataclasses import dataclass

from app.core.errors import DomainError, ErrorCode
from app.decode.domain.model import Engine, EngineError, EngineRequest, EngineResult
from app.decode.infra.engines.guards import Breaker, Quota

log = logging.getLogger("mwonmal.ai")


@dataclass
class ExternalEngine:
    engine: Engine
    quota: Quota
    breaker: Breaker
    model: str


class EngineRouter:
    def __init__(
        self,
        *,
        fallback: Engine,
        external: ExternalEngine | None,
        external_enabled: bool,
        allow_degraded: bool,
    ) -> None:
        self._fallback = fallback
        self._external = external
        self._external_enabled = external_enabled
        self._allow_degraded = allow_degraded

    async def decode(self, request: EngineRequest, *, consent: bool) -> tuple[EngineResult, int]:
        """(결과, 지연 ms). 외부 엔진에서 무슨 일이 나도 500 이 아니라 강등(또는 503)이다(레드팀
        M-1)."""
        started = time.perf_counter()
        ext = self._external
        skip = self._skip_reason(consent)
        if skip is None and ext is not None:
            ticket = None
            try:
                ticket = await ext.breaker.allow()
                has_quota = ticket is not None and await ext.quota.take()
            except Exception as e:  # noqa: BLE001 - Redis 장애 등: 외부 엔진만 건너뛴다
                log.warning("ai_guard_unavailable type=%s", type(e).__name__)
                if ticket is not None:
                    await self._safely(ext.breaker.release(ticket))
                ticket, has_quota, skip = None, False, "GUARD_DOWN"
            if ticket is None:
                skip = skip or "BREAKER_OPEN"
            elif not has_quota:
                skip = "QUOTA_SKIP"
                await self._safely(ext.breaker.release(ticket))
            else:
                try:
                    result = await ext.engine.decode(request)
                except Exception as e:  # noqa: BLE001 - 제공자 쪽 무엇이든 실패로 센다
                    reason = e.reason if isinstance(e, EngineError) else f"bug:{type(e).__name__}"
                    counts = not isinstance(e, EngineError) or e.counts_as_failure
                    await self._safely(
                        ext.breaker.failure(ticket) if counts else ext.breaker.release(ticket)
                    )
                    _record(ext.engine.name, ext.model, f"error:{reason}", started)
                    if not self._allow_degraded:
                        raise DomainError(
                            ErrorCode.AI_UNAVAILABLE,
                            "해석 엔진이 잠깐 멍때리는 중이에요. 다시 시도해 주세요.",
                        ) from None
                else:
                    await self._safely(ext.breaker.success(ticket))
                    return result, _record(ext.engine.name, ext.model, "ok", started)
        result = await self._fallback.decode(request)
        return result, _record(self._fallback.name, "dictionary", f"ok skip={skip}", started)

    @staticmethod
    async def _safely(op: Awaitable[None]) -> None:
        try:
            await op
        except Exception as e:  # noqa: BLE001 - 보고 실패로 사용자 요청을 깨지 않는다
            log.warning("ai_guard_report_failed type=%s", type(e).__name__)

    def can_use_external(self, consent: bool) -> bool:
        """이번 요청에 외부 엔진을 쓸 수 있는 조건인지(동의·설정·키). 브레이커·한도는 보지
        않는다."""
        return self._skip_reason(consent) is None

    def _skip_reason(self, consent: bool) -> str | None:
        if not consent:
            return "NO_CONSENT"
        if not self._external_enabled:
            return "EXTERNAL_OFF"
        if self._external is None:
            return "NOT_CONFIGURED"
        return None


def _record(engine: str, model: str, outcome: str, started: float) -> int:
    latency = int((time.perf_counter() - started) * 1000)
    log.info(
        "ai_usage engine=%s model=%s outcome=%s latency_ms=%d", engine, model, outcome, latency
    )
    return latency
