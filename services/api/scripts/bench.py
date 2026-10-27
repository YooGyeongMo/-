"""API 성능 기준선: 요청당 SQL 문 수와 지연(p50·p95·rps). 결과는 표로 찍는다.

앱을 프로세스 안(ASGI)에서 직접 부른다 → 네트워크·uvicorn 비용을 빼고 우리 코드 + DB 만 잰다.
DB 는 SQLite 파일(로컬). 운영 MySQL 수치와 다르지만 "요청당 SQL 문 수"는 같고,
그게 운영 지연(왕복 1회 ≈ 0.3~1ms)을 가장 크게 바꾼다.

    uv run python scripts/bench.py [--requests 600] [--concurrency 20] [--rounds 3]
"""

import argparse
import asyncio
import itertools
import os
import statistics
import sys
import tempfile
import time
from pathlib import Path


async def main(requests: int, concurrency: int, rounds: int) -> None:
    tmp = Path(tempfile.mkdtemp()) / "bench.db"
    os.environ["MWONMAL_ENV"] = "test"
    os.environ["MWONMAL_DEV_LOGIN"] = "1"
    os.environ["MWONMAL_DATABASE_URL"] = f"sqlite+aiosqlite:///{tmp}"
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

    import httpx
    import sqlalchemy as sa
    from sqlalchemy.ext.asyncio import create_async_engine

    try:
        from app.all_models import active_metadata  # 단계화 뒤
    except ImportError:  # 단계화 전 main 과 비교할 때(17테이블)
        from app.all_models import metadata

        def active_metadata() -> sa.MetaData:
            return metadata

    from app.core.db import get_engine
    from app.decode.infra.seed import seed
    from app.main import app

    setup = create_async_engine(os.environ["MWONMAL_DATABASE_URL"])
    async with setup.begin() as conn:
        await conn.run_sync(active_metadata().create_all)
        await conn.run_sync(seed)
    await setup.dispose()

    statements = 0

    def count(*_: object) -> None:
        nonlocal statements
        statements += 1

    sa.event.listen(get_engine().sync_engine, "before_cursor_execute", count)

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://bench") as client:
        r = await client.post(
            "/api/auth/oauth/apple", json={"code": "dev:bench", "redirectUri": "x"}
        )
        auth = {"Authorization": f"Bearer {r.json()['accessToken']}"}
        texts = [
            f"{i}번 이번 스프린트 스코프 아웃하고 넥스트로 밀죠. "
            "그 전에 R&R 정리해서 내일까지 얼라인 쳐주세요"
            for i in range(30)
        ]
        ids = []
        for t in texts:
            ids.append(
                (
                    await client.post(
                        "/api/translations",
                        json={"sourceText": t, "direction": "JARGON_TO_PLAIN"},
                        headers=auth,
                    )
                ).json()["translationId"]
            )

        async def measure(name: str, call: object) -> tuple[str, float, float, float, float]:
            sem = asyncio.Semaphore(concurrency)
            lat: list[float] = []

            async def one(i: int) -> None:
                async with sem:
                    start = time.perf_counter()
                    resp = await call(i)  # type: ignore[operator]
                    lat.append((time.perf_counter() - start) * 1000)
                    if resp.status_code >= 300:
                        raise SystemExit(f"{name}: {resp.status_code} {resp.text[:200]}")

            async def round_() -> tuple[float, float, float, float]:
                nonlocal statements
                lat.clear()
                statements = 0
                began = time.perf_counter()
                await asyncio.gather(*(one(next(seq)) for _ in range(requests)))
                took = time.perf_counter() - began
                lat.sort()
                return (
                    statements / requests,
                    statistics.median(lat),
                    lat[int(len(lat) * 0.95) - 1],
                    requests / took,
                )

            await round_()  # 데우기(캐시·임포트·JIT 없는 첫 호출 비용 제외)
            results = [await round_() for _ in range(rounds)]
            return (name, *(statistics.median(r[k] for r in results) for k in range(4)))  # type: ignore[return-value]

        seq = itertools.count()
        rows = [
            await measure(
                "POST /translations",
                lambda i: client.post(
                    "/api/translations",
                    json={
                        "sourceText": f"새 문장 {i} 싱크해서 공유해 주세요",  # 매번 새 문장
                        "direction": "JARGON_TO_PLAIN",
                    },
                    headers=auth,
                ),
            ),
            await measure(
                "GET /translations/{id}",
                lambda i: client.get(f"/api/translations/{ids[i % 30]}", headers=auth),
            ),
            await measure(
                "GET /translations", lambda i: client.get("/api/translations?size=20", headers=auth)
            ),
            await measure(
                "GET /actions", lambda i: client.get("/api/actions?size=20", headers=auth)
            ),
            await measure("GET /projects", lambda i: client.get("/api/projects", headers=auth)),
            await measure(
                "GET /terms/{id}", lambda i: client.get(f"/api/terms/{1 + i % 50}", headers=auth)
            ),
        ]
    print(f"{'요청':<26}{'SQL/요청':>9}{'p50 ms':>9}{'p95 ms':>9}{'rps':>8}")
    for name, sql, p50, p95, rps in rows:
        print(f"{name:<26}{sql:>9.1f}{p50:>9.2f}{p95:>9.2f}{rps:>8.0f}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--requests", type=int, default=600)
    p.add_argument("--concurrency", type=int, default=20)
    p.add_argument("--rounds", type=int, default=3, help="데우기 1회 뒤 이만큼 돌려 중앙값")
    a = p.parse_args()
    asyncio.run(main(a.requests, a.concurrency, a.rounds))
