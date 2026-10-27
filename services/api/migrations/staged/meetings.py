"""(대기 중) v1.2 회의·녹음 2테이블 + translations.meeting_id 외래 키 — 기능이 열릴 때
`migrations/versions/` 로 옮겨 새 리비전으로 붙인다.

테이블 정의는 contracts/db.dbml v1.0 그대로(meetings, meeting_recordings). 옮길 때 할 일:
1. 이 파일을 versions/ 로 복사하고 revision·down_revision 을 채운다.
2. `app/core/schema.py` ACTIVE_TABLES 에 테이블 이름을 더한다(앱 코드의 해당 기능이 켜진다).
3. `uv run pytest` — test_migrations 가 모델과 차이 0 을 확인한다.

추가만 하므로 기존 테이블·데이터는 바뀌지 않는다. 내릴 때(downgrade)도 이 테이블들만 지운다.
"""

import sqlalchemy as sa
from alembic import op

revision: str = "TBD-meetings"
down_revision: str | None = None  # 옮길 때 마지막 리비전으로


def upgrade() -> None:
    op.create_table(
        "meetings",
        sa.Column(
            "id",
            sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
            autoincrement=True,
            nullable=False,
        ),
        sa.Column("project_id", sa.BigInteger(), nullable=False),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("title", sa.String(length=100), nullable=False),
        sa.Column("held_at", sa.DateTime(), nullable=False),
        sa.Column("attendee_count", sa.Integer(), server_default=sa.text("1"), nullable=False),
        sa.Column("agenda", sa.String(length=200), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False
        ),
        sa.ForeignKeyConstraint(
            ["project_id"], ["projects.id"], name=op.f("fk_meetings_project_id")
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name=op.f("fk_meetings_user_id")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_meetings")),
    )
    op.create_index("ix_meetings_project_time", "meetings", ["project_id", "held_at"], unique=False)
    op.create_index("ix_meetings_user", "meetings", ["user_id"], unique=False)
    op.create_table(
        "meeting_recordings",
        sa.Column(
            "id",
            sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
            autoincrement=True,
            nullable=False,
        ),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("meeting_id", sa.BigInteger(), nullable=False),
        sa.Column("translation_id", sa.BigInteger(), nullable=True),
        sa.Column("audio_url", sa.String(length=500), nullable=True),
        sa.Column("duration_sec", sa.Integer(), nullable=False),
        sa.Column("consent_confirmed", sa.Boolean(), nullable=False),
        sa.Column(
            "status",
            sa.Enum(
                "RECORDING", "UPLOADED", "TRANSCRIBING", "DONE", "FAILED", name="recording_status"
            ),
            server_default="RECORDING",
            nullable=False,
        ),
        sa.Column("progress", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("transcript", sa.Text(), nullable=True),
        sa.Column("failure_reason", sa.String(length=200), nullable=True),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False
        ),
        sa.ForeignKeyConstraint(
            ["meeting_id"], ["meetings.id"], name=op.f("fk_meeting_recordings_meeting_id")
        ),
        sa.ForeignKeyConstraint(
            ["translation_id"],
            ["translations.id"],
            name=op.f("fk_meeting_recordings_translation_id"),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_meeting_recordings_user_id")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_meeting_recordings")),
        sa.UniqueConstraint("translation_id", name=op.f("uq_meeting_recordings_translation_id")),
    )
    op.create_index("ix_recordings_meeting", "meeting_recordings", ["meeting_id"], unique=False)
    op.create_index(
        "ix_recordings_user_time", "meeting_recordings", ["user_id", "created_at"], unique=False
    )
    with op.batch_alter_table("translations") as batch:
        batch.create_foreign_key(
            op.f("fk_translations_meeting_id"), "meetings", ["meeting_id"], ["id"]
        )


def downgrade() -> None:
    with op.batch_alter_table("translations") as batch:
        batch.drop_constraint(op.f("fk_translations_meeting_id"), type_="foreignkey")
    op.drop_table("meeting_recordings")
    op.drop_table("meetings")
