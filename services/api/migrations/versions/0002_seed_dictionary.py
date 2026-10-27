"""시드 사전(검수 용어 134개) — 스키마 변경 없음, 데이터만 (#12).

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-27
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

from app.decode.infra.seed import SYSTEM_EMAIL, seed

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    seed(op.get_bind())


def downgrade() -> None:
    # 시드가 만든 것만 지운다. 카드·해석 기록이 시드 용어를 가리키면 그 전에 비워야 한다.
    bind = op.get_bind()
    owner = bind.execute(
        sa.text("SELECT id FROM users WHERE email = :e"), {"e": SYSTEM_EMAIL}
    ).scalar()
    if owner is None:
        return
    bind.execute(
        sa.text(
            "DELETE FROM term_examples"
            " WHERE term_id IN (SELECT id FROM terms WHERE created_by = :o)"
        ),
        {"o": owner},
    )
    bind.execute(sa.text("DELETE FROM terms WHERE created_by = :o"), {"o": owner})
    bind.execute(sa.text("DELETE FROM users WHERE id = :o"), {"o": owner})
