"""(대기 중) v1.1 학습(카드·복습·퀴즈) 5테이블 — 기능이 열릴 때 `migrations/versions/` 로 옮겨 새
리비전으로 붙인다.

테이블 정의는 contracts/db.dbml v1.0 그대로(cards, review_sessions, review_logs, quiz_sessions,
quiz_questions). 옮길 때 할 일:
1. 이 파일을 versions/ 로 복사하고 revision·down_revision 을 채운다.
2. `app/core/schema.py` ACTIVE_TABLES 에 테이블 이름을 더한다(앱 코드의 해당 기능이 켜진다).
3. `uv run pytest` — test_migrations 가 모델과 차이 0 을 확인한다.

추가만 하므로 기존 테이블·데이터는 바뀌지 않는다. 내릴 때(downgrade)도 이 테이블들만 지운다.
"""

import sqlalchemy as sa
from alembic import op

revision: str = "TBD-learning"
down_revision: str | None = None  # 옮길 때 마지막 리비전으로


def upgrade() -> None:
    op.create_table(
        "quiz_sessions",
        sa.Column(
            "id",
            sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
            autoincrement=True,
            nullable=False,
        ),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("question_count", sa.Integer(), server_default=sa.text("5"), nullable=False),
        sa.Column("correct_count", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("score", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("level_code", sa.String(length=20), nullable=True),
        sa.Column(
            "started_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False
        ),
        sa.Column("finished_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(
            ["level_code"], ["levels.code"], name=op.f("fk_quiz_sessions_level_code")
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name=op.f("fk_quiz_sessions_user_id")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_quiz_sessions")),
    )
    op.create_index("ix_quiz_user_time", "quiz_sessions", ["user_id", "started_at"], unique=False)
    op.create_table(
        "review_sessions",
        sa.Column(
            "id",
            sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
            autoincrement=True,
            nullable=False,
        ),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("target_count", sa.Integer(), nullable=False),
        sa.Column("completed_count", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("good_count", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column(
            "started_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False
        ),
        sa.Column("finished_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name=op.f("fk_review_sessions_user_id")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_review_sessions")),
    )
    op.create_index(
        "ix_review_sessions_user_time", "review_sessions", ["user_id", "started_at"], unique=False
    )
    op.create_table(
        "quiz_questions",
        sa.Column(
            "id",
            sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
            autoincrement=True,
            nullable=False,
        ),
        sa.Column("quiz_session_id", sa.BigInteger(), nullable=False),
        sa.Column("term_id", sa.BigInteger(), nullable=False),
        sa.Column("question_text", sa.String(length=300), nullable=False),
        sa.Column("choices", sa.JSON(), nullable=False),
        sa.Column("answer_index", sa.Integer(), nullable=False),
        sa.Column("selected_index", sa.Integer(), nullable=True),
        sa.Column("is_correct", sa.Boolean(), server_default=sa.text("0"), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(
            ["quiz_session_id"],
            ["quiz_sessions.id"],
            name=op.f("fk_quiz_questions_quiz_session_id"),
        ),
        sa.ForeignKeyConstraint(["term_id"], ["terms.id"], name=op.f("fk_quiz_questions_term_id")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_quiz_questions")),
    )
    op.create_index("ix_quiz_q_term", "quiz_questions", ["term_id"], unique=False)
    op.create_index(
        "ux_quiz_q_order", "quiz_questions", ["quiz_session_id", "sort_order"], unique=True
    )
    op.create_table(
        "cards",
        sa.Column(
            "id",
            sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
            autoincrement=True,
            nullable=False,
        ),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("term_id", sa.BigInteger(), nullable=False),
        sa.Column("source_translation_id", sa.BigInteger(), nullable=True),
        sa.Column(
            "status",
            sa.Enum("LEARNING", "MASTERED", "PAUSED", name="card_status"),
            server_default="LEARNING",
            nullable=False,
        ),
        sa.Column("memo", sa.String(length=300), nullable=True),
        sa.Column("interval_days", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column(
            "ease_factor",
            sa.Numeric(precision=4, scale=2),
            server_default=sa.text("2.50"),
            nullable=False,
        ),
        sa.Column("repetition_count", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("lapse_count", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column("due_date", sa.Date(), nullable=False),
        sa.Column("last_reviewed_at", sa.DateTime(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False
        ),
        sa.ForeignKeyConstraint(
            ["source_translation_id"],
            ["translations.id"],
            name=op.f("fk_cards_source_translation_id"),
        ),
        sa.ForeignKeyConstraint(["term_id"], ["terms.id"], name=op.f("fk_cards_term_id")),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name=op.f("fk_cards_user_id")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_cards")),
    )
    op.create_index("ix_cards_due", "cards", ["user_id", "due_date"], unique=False)
    op.create_index("ix_cards_source_translation", "cards", ["source_translation_id"], unique=False)
    op.create_index("ix_cards_status", "cards", ["user_id", "status"], unique=False)
    op.create_index("ux_cards_user_term", "cards", ["user_id", "term_id"], unique=True)
    op.create_table(
        "review_logs",
        sa.Column(
            "id",
            sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
            autoincrement=True,
            nullable=False,
        ),
        sa.Column("review_session_id", sa.BigInteger(), nullable=False),
        sa.Column("card_id", sa.BigInteger(), nullable=False),
        sa.Column(
            "rating", sa.Enum("AGAIN", "HARD", "GOOD", "EASY", name="review_rating"), nullable=False
        ),
        sa.Column("prev_interval", sa.Integer(), nullable=False),
        sa.Column("next_interval", sa.Integer(), nullable=False),
        sa.Column("elapsed_ms", sa.Integer(), nullable=True),
        sa.Column(
            "reviewed_at",
            sa.DateTime(),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["card_id"], ["cards.id"], name=op.f("fk_review_logs_card_id")),
        sa.ForeignKeyConstraint(
            ["review_session_id"],
            ["review_sessions.id"],
            name=op.f("fk_review_logs_review_session_id"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_review_logs")),
    )
    op.create_index("ix_review_logs_card", "review_logs", ["card_id"], unique=False)
    op.create_index("ix_review_logs_session", "review_logs", ["review_session_id"], unique=False)


def downgrade() -> None:
    op.drop_table("quiz_questions")
    op.drop_table("quiz_sessions")
    op.drop_table("review_logs")
    op.drop_table("review_sessions")
    op.drop_table("cards")
