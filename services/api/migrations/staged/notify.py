"""(대기 중) v1.2 기기·알림 2테이블 — 기능이 열릴 때 `migrations/versions/` 로 옮겨 새 리비전으로
붙인다.

테이블 정의는 contracts/db.dbml v1.0 그대로(user_devices, notifications). 옮길 때 할 일:
1. 이 파일을 versions/ 로 복사하고 revision·down_revision 을 채운다.
2. `app/core/schema.py` ACTIVE_TABLES 에 테이블 이름을 더한다(앱 코드의 해당 기능이 켜진다).
3. `uv run pytest` — test_migrations 가 모델과 차이 0 을 확인한다.

추가만 하므로 기존 테이블·데이터는 바뀌지 않는다. 내릴 때(downgrade)도 이 테이블들만 지운다.
"""

import sqlalchemy as sa
from alembic import op

revision: str = "TBD-notify"
down_revision: str | None = None  # 옮길 때 마지막 리비전으로


def upgrade() -> None:
    op.create_table(
        "notifications",
        sa.Column(
            "id",
            sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
            autoincrement=True,
            nullable=False,
        ),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column(
            "type",
            sa.Enum(
                "REVIEW_REMINDER", "ACTION_DUE", "DECODE_DONE", "LEVEL_UP", name="notification_type"
            ),
            nullable=False,
        ),
        sa.Column("title", sa.String(length=100), nullable=False),
        sa.Column("body", sa.String(length=300), nullable=False),
        sa.Column("target_id", sa.BigInteger(), nullable=True),
        sa.Column("scheduled_at", sa.DateTime(), nullable=False),
        sa.Column("sent_at", sa.DateTime(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name=op.f("fk_notifications_user_id")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_notifications")),
    )
    op.create_index("ix_noti_user_time", "notifications", ["user_id", "scheduled_at"], unique=False)
    op.create_table(
        "user_devices",
        sa.Column(
            "id",
            sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
            autoincrement=True,
            nullable=False,
        ),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("platform", sa.Enum("IOS", "WEB", name="device_platform"), nullable=False),
        sa.Column("push_token", sa.String(length=255), nullable=True),
        sa.Column(
            "last_seen_at",
            sa.DateTime(),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column(
            "created_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name=op.f("fk_user_devices_user_id")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_user_devices")),
    )
    op.create_index(
        "ix_devices_user_platform", "user_devices", ["user_id", "platform"], unique=False
    )
    op.create_index("ux_devices_token", "user_devices", ["push_token"], unique=True)


def downgrade() -> None:
    op.drop_table("notifications")
    op.drop_table("user_devices")
