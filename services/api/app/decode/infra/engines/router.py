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
        """(결과, 지연 ms)."""
        started = time.perf_counter()
        ext = self._external
        skip = self._skip_reason(consent)
        if skip is None and ext is not None:
            if not await ext.breaker.allow():
                skip = "BREAKER_OPEN"
            elif not await ext.quota.take():
                skip = "QUOTA_SKIP"
            else:
                try:
                    result = await ext.engine.decode(request)
                except EngineError as e:
                    await ext.breaker.failure()
                    _record(ext.engine.name, ext.model, f"error:{e.reason}", started)
                    if not self._allow_degraded:
                        raise DomainError(
                            ErrorCode.AI_UNAVAILABLE,
                            "해석 엔진이 잠깐 멍때리는 중이에요. 다시 시도해 주세요.",
                        ) from None
                else:
                    await ext.breaker.success()
                    return result, _record(ext.engine.name, ext.model, "ok", started)
        result = await self._fallback.decode(request)
        return result, _record(self._fallback.name, "dictionary", f"ok skip={skip}", started)

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
