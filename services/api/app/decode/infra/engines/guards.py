"""무료 한도 카운터와 서킷 브레이커 (#36, 14번 §15-3, RT-B-03·04).

- 한도: 분·일 두 창을 다 센다(RPD×30 월 평균은 RT-B-08로 탈락). 공급자 한도의 80%에서
  멈춘다(소프트 상한).
  일 창은 UTC 날짜(공급자 리셋 기준). 키: `ai:quota:{engine}:{model}:{rpm|rpd}:{window}`.
- 브레이커: 30초 안에 2번 실패 → OPEN 60초 → HALF_OPEN(프로브 1개만 통과, 락) → 성공이면 CLOSED,
  실패면 다시 OPEN(2배, 최대 10분). 상태는 공유 저장소에 둔다(프로세스 메모리 브레이커 탈락:
  블루·그린 5프로세스).
"""

from collections.abc import Callable
from datetime import UTC, datetime

from app.core.kv import KeyValue

SOFT_CAP = 0.8
FAIL_WINDOW_SEC = 30
FAILS_TO_OPEN = 2
OPEN_SEC = 60
MAX_OPEN_SEC = 600
PROBE_LOCK_SEC = 15


class Quota:
    def __init__(
        self,
        kv: KeyValue,
        *,
        engine: str,
        model: str,
        rpm: int,
        rpd: int,
        now: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        self._kv = kv
        self._prefix = f"ai:quota:{engine}:{model}"
        self._rpm_cap = int(rpm * SOFT_CAP)
        self._rpd_cap = int(rpd * SOFT_CAP)
        self._now = now

    def keys(self) -> tuple[str, str]:
        t = self._now()
        return (f"{self._prefix}:rpm:{t:%Y%m%d%H%M}", f"{self._prefix}:rpd:{t:%Y%m%d}")

    async def take(self) -> bool:
        """한 번 쓸 자리를 잡는다. 상한을 넘으면 False(이번 호출은 다른 엔진으로)."""
        if self._rpm_cap <= 0 or self._rpd_cap <= 0:
            return False
        rpm_key, rpd_key = self.keys()
        # 일 창을 먼저 본다: 분 창이 차서 거절된 호출이 일 한도를 먹지 않게.
        if int(await self._kv.get(rpd_key) or 0) >= self._rpd_cap:
            return False
        if await self._kv.incr(rpm_key, 120) > self._rpm_cap:
            return False
        return await self._kv.incr(rpd_key, 26 * 3600) <= self._rpd_cap


class Breaker:
    def __init__(self, kv: KeyValue, engine: str) -> None:
        self._kv = kv
        base = f"ai:breaker:{engine}"
        self._fails = f"{base}:fails"
        self._open = f"{base}:open"
        self._backoff = f"{base}:backoff"
        self._probe = f"{base}:probe"

    async def state(self) -> str:
        if await self._kv.get(self._open) is not None:
            return "OPEN"
        if await self._kv.get(self._backoff) is not None:
            return "HALF_OPEN"
        return "CLOSED"

    async def allow(self) -> bool:
        state = await self.state()
        if state == "OPEN":
            return False
        if state == "HALF_OPEN":
            return await self._kv.set_nx(self._probe, "1", PROBE_LOCK_SEC)
        return True

    async def success(self) -> None:
        for key in (self._fails, self._open, self._backoff, self._probe):
            await self._kv.delete(key)

    async def failure(self) -> None:
        backoff = await self._kv.get(self._backoff)
        if backoff is not None:  # HALF_OPEN 프로브 실패 → 더 길게 연다
            seconds = min(int(backoff) * 2, MAX_OPEN_SEC)
            await self._trip(seconds)
            return
        if await self._kv.incr(self._fails, FAIL_WINDOW_SEC) >= FAILS_TO_OPEN:
            await self._trip(OPEN_SEC)

    async def _trip(self, seconds: int) -> None:
        await self._kv.set(self._open, "1", seconds)
        # backoff 키는 OPEN 보다 오래 살아 HALF_OPEN 을 표시한다(MAX 뒤엔 저절로 CLOSED).
        await self._kv.set(self._backoff, str(seconds), seconds + MAX_OPEN_SEC)
        await self._kv.delete(self._fails)
        await self._kv.delete(self._probe)
