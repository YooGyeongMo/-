"""learning 컨텍스트 테이블: levels, cards, review_sessions, review_logs, quiz_sessions,
quiz_questions (dbml v1.0)."""

from datetime import date, datetime
from decimal import Decimal
from typing import Any

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, BigIntPK, now

CardStatus = sa.Enum("LEARNING", "MASTERED", "PAUSED", name="card_status")
ReviewRating = sa.Enum("AGAIN", "HARD", "GOOD", "EASY", name="review_rating")


class Level(Base):
    __tablename__ = "levels"

    code: Mapped[str] = mapped_column(sa.String(20), primary_key=True)
    name: Mapped[str] = mapped_column(sa.String(30))
    min_score: Mapped[int] = mapped_column(sa.Integer())
    max_score: Mapped[int] = mapped_column(sa.Integer())
    badge_image_url: Mapped[str | None] = mapped_column(sa.String(500))
    sort_order: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("0"))


class Card(Base):
    __tablename__ = "cards"
    __table_args__ = (
        sa.Index("ux_cards_user_term", "user_id", "term_id", unique=True),
        sa.Index("ix_cards_due", "user_id", "due_date"),
        sa.Index("ix_cards_status", "user_id", "status"),
        sa.Index("ix_cards_source_translation", "source_translation_id"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("users.id"))
    term_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("terms.id"))
    source_translation_id: Mapped[int | None] = mapped_column(
        sa.BigInteger(), sa.ForeignKey("translations.id")
    )
    status: Mapped[str] = mapped_column(CardStatus, server_default="LEARNING")
    memo: Mapped[str | None] = mapped_column(sa.String(300))
    interval_days: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("0"))
    ease_factor: Mapped[Decimal] = mapped_column(sa.Numeric(4, 2), server_default=sa.text("2.50"))
    repetition_count: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("0"))
    lapse_count: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("0"))
    due_date: Mapped[date] = mapped_column(sa.Date())
    last_reviewed_at: Mapped[datetime | None] = mapped_column(sa.DateTime())
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), server_default=now())


class ReviewSession(Base):
    __tablename__ = "review_sessions"
    __table_args__ = (sa.Index("ix_review_sessions_user_time", "user_id", "started_at"),)

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("users.id"))
    target_count: Mapped[int] = mapped_column(sa.Integer())
    completed_count: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("0"))
    good_count: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("0"))
    started_at: Mapped[datetime] = mapped_column(sa.DateTime(), server_default=now())
    finished_at: Mapped[datetime | None] = mapped_column(sa.DateTime())


class ReviewLog(Base):
    __tablename__ = "review_logs"
    __table_args__ = (
        sa.Index("ix_review_logs_session", "review_session_id"),
        sa.Index("ix_review_logs_card", "card_id"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    review_session_id: Mapped[int] = mapped_column(
        sa.BigInteger(), sa.ForeignKey("review_sessions.id")
    )
    card_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("cards.id"))
    rating: Mapped[str] = mapped_column(ReviewRating)
    prev_interval: Mapped[int] = mapped_column(sa.Integer())
    next_interval: Mapped[int] = mapped_column(sa.Integer())
    elapsed_ms: Mapped[int | None] = mapped_column(sa.Integer())
    reviewed_at: Mapped[datetime] = mapped_column(sa.DateTime(), server_default=now())


class QuizSession(Base):
    __tablename__ = "quiz_sessions"
    __table_args__ = (sa.Index("ix_quiz_user_time", "user_id", "started_at"),)

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("users.id"))
    question_count: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("5"))
    correct_count: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("0"))
    score: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("0"))
    level_code: Mapped[str | None] = mapped_column(sa.String(20), sa.ForeignKey("levels.code"))
    started_at: Mapped[datetime] = mapped_column(sa.DateTime(), server_default=now())
    finished_at: Mapped[datetime | None] = mapped_column(sa.DateTime())


class QuizQuestion(Base):
    __tablename__ = "quiz_questions"
    __table_args__ = (
        sa.Index("ux_quiz_q_order", "quiz_session_id", "sort_order", unique=True),
        sa.Index("ix_quiz_q_term", "term_id"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    quiz_session_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("quiz_sessions.id"))
    term_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("terms.id"))
    question_text: Mapped[str] = mapped_column(sa.String(300))
    choices: Mapped[list[Any]] = mapped_column(sa.JSON())
    answer_index: Mapped[int] = mapped_column(sa.Integer())
    selected_index: Mapped[int | None] = mapped_column(sa.Integer())
    is_correct: Mapped[bool] = mapped_column(sa.Boolean(), server_default=sa.text("0"))
    sort_order: Mapped[int] = mapped_column(sa.Integer())
