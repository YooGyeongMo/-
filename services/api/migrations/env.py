"""Alembic 환경 (async). 메타데이터 = app.all_models (dbml v1.0 과 1:1, 테스트로 강제)."""

import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import create_async_engine

from app.all_models import metadata
from app.core.settings import settings

config = context.config
if config.config_file_name is not None:
    # 이미 만들어진 앱 로거(app.*, mwonmal.*)를 끄지 않는다(테스트에서 카나리·감사 로그가 사라졌다).
    fileConfig(config.config_file_name, disable_existing_loggers=False)

URL = config.attributes.get("database_url") or settings.database_url


def run_migrations_offline() -> None:
    context.configure(url=URL, target_metadata=metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


def _run(connection: Connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=metadata,
        compare_type=True,
        compare_server_default=True,
        render_as_batch=connection.dialect.name == "sqlite",
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    engine = create_async_engine(URL)
    async with engine.connect() as conn:
        await conn.run_sync(_run)
    await engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
