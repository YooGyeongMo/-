"""로컬·CI 용 서버: SQLite 에 테이블(dbml 17개) + 시드 사전을 만들고 개발용 로그인을 켠 채 띄운다.

Docker·MySQL 없이 앱 E2E(시뮬레이터)와 계약 검사(#110)를 돌리기 위한 것. 운영과 다른 점:
DB 가 SQLite, JWT 키가 임시, `dev:<이름>` 로그인이 켜짐
(local·test 에서만 허용 — 운영 설정이면 기동 거부).

    uv run python scripts/dev_server.py [--db /tmp/mw.db] [--port 8080] [--fresh]
"""

import argparse
import asyncio
import os
import sys
from pathlib import Path


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument(
        "--db", default=str(Path(__file__).resolve().parent.parent / ".local" / "dev.db")
    )
    p.add_argument("--port", type=int, default=8080)
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--fresh", action="store_true", help="DB 파일을 지우고 새로 만든다")
    args = p.parse_args()

    db = Path(args.db)
    db.parent.mkdir(parents=True, exist_ok=True)
    if args.fresh and db.exists():
        db.unlink()
    os.environ.setdefault("MWONMAL_ENV", "local")
    os.environ["MWONMAL_DEV_LOGIN"] = "1"
    os.environ["MWONMAL_DATABASE_URL"] = f"sqlite+aiosqlite:///{db}"

    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    import uvicorn
    from sqlalchemy.ext.asyncio import create_async_engine

    from app.all_models import metadata
    from app.decode.infra.seed import seed

    async def prepare() -> int:
        engine = create_async_engine(os.environ["MWONMAL_DATABASE_URL"])
        async with engine.begin() as conn:
            await conn.run_sync(metadata.create_all)
            added: int = await conn.run_sync(seed)
        await engine.dispose()
        return added

    added = asyncio.run(prepare())
    print(f"dev db={db} seeded_terms+={added} dev_login=on", flush=True)
    uvicorn.run("app.main:app", host=args.host, port=args.port, workers=1, log_level="info")


if __name__ == "__main__":
    main()
