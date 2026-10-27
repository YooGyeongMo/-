"""작은 공유 저장소: 한도 카운터·브레이커 상태 (#36).

블루·그린 두 색 × 워커 여러 개가 같은 한도와 브레이커를 봐야 하므로 운영은 Redis 다(ADR-0003).
local·test 는 Redis 없이 프로세스 메모리로 돈다(워커 1개). 키에 앱 버전을 넣지 않는다(B-6 ⑤).
값에 원문·사용자 식별자를 넣지 않는다(REQ-14).
"""

import time
from collections.abc import Callable
from functools import lru_cache
from typing import Protocol

from app.core.settings import settings


class KeyValue(Protocol):
    async def incr(self, key: str, ttl_sec: int) -> int:
        """1 늘리고 새 값을 돌려준다. 처음 만들 때만 만료를 건다."""
        ...

    async def get(self, key: str) -> str | None: ...
    async def set(self, key: str, value: str, ttl_sec: int) -> None: ...
    async def set_nx(self, key: str, value: str, ttl_sec: int) -> bool:
        """없을 때만 쓴다(프로브 락). 썼으면 True."""
        ...

    async def delete(self, key: str) -> None: ...


class MemoryKV:
    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self._data: dict[str, tuple[str, float]] = {}
        self._clock = clock

    def _live(self, key: str) -> str | None:
        item = self._data.get(key)
        if item is None:
            return None
        if item[1] <= self._clock():
            del self._data[key]
            return None
        return item[0]

    async def incr(self, key: str, ttl_sec: int) -> int:
        current = self._live(key)
        if current is None:
            self._data[key] = ("1", self._clock() + ttl_sec)
            return 1
        value = int(current) + 1
        self._data[key] = (str(value), self._data[key][1])
        return value

    async def get(self, key: str) -> str | None:
        return self._live(key)

    async def set(self, key: str, value: str, ttl_sec: int) -> None:
        self._data[key] = (value, self._clock() + ttl_sec)

    async def set_nx(self, key: str, value: str, ttl_sec: int) -> bool:
        if self._live(key) is not None:
            return False
        await self.set(key, value, ttl_sec)
        return True

    async def delete(self, key: str) -> None:
        self._data.pop(key, None)


class RedisKV:
    def __init__(self, url: str) -> None:
        from redis.asyncio import Redis

        self._r = Redis.from_url(url, decode_responses=True, socket_timeout=1.0)

    async def incr(self, key: str, ttl_sec: int) -> int:
        async with self._r.pipeline(transaction=True) as p:
            p.incr(key)
            p.expire(key, ttl_sec, nx=True)
            value, _ = await p.execute()
        return int(value)

    async def get(self, key: str) -> str | None:
        value = await self._r.get(key)
        return None if value is None else str(value)

    async def set(self, key: str, value: str, ttl_sec: int) -> None:
        await self._r.set(key, value, ex=ttl_sec)

    async def set_nx(self, key: str, value: str, ttl_sec: int) -> bool:
        return bool(await self._r.set(key, value, ex=ttl_sec, nx=True))

    async def delete(self, key: str) -> None:
        await self._r.delete(key)


@lru_cache(maxsize=1)
def get_kv() -> KeyValue:
    return RedisKV(settings.redis_url) if settings.redis_url else MemoryKV()
