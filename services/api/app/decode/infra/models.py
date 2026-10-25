"""decode 컨텍스트 테이블: terms, term_examples, translations, translation_actions,
translation_terms (dbml v1.0)."""

from datetime import datetime
from decimal import Decimal

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, BigIntPK, now

TermCategory = sa.Enum("WORK", "DATA", "DEV", "ORG", "MEETING", "ETC", name="term_category")
TermStatus = sa.Enum("APPROVED", "HIDDEN", name="term_status")
TranslationDirection = sa.Enum("JARGON_TO_PLAIN", "PLAIN_TO_JARGON", name="translation_direction")
SourceType = sa.Enum("MESSAGE", "MEETING_NOTE", name="source_type")
InputSource = sa.Enum("TYPED", "SCREENSHOT", "RECORDING", "EXTENSION", name="input_source")
IntentType = sa.Enum("REQUEST", "DECISION", "DECLINE", "SHARE", "QUESTION", name="intent_type")


class Term(Base):
    __tablename__ = "terms"
    __table_args__ = (
        sa.Index("ix_terms_term_ko", "term_ko"),
        sa.Index("ix_terms_status_category", "status", "category"),
        sa.Index("ix_terms_created_by", "created_by"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    slug: Mapped[str] = mapped_column(sa.String(100), unique=True)
    term_ko: Mapped[str] = mapped_column(sa.String(100))
    origin_en: Mapped[str | None] = mapped_column(sa.String(100))
    plain_ko: Mapped[str] = mapped_column(sa.String(200))
    meaning: Mapped[str] = mapped_column(sa.String(1000))
    category: Mapped[str] = mapped_column(TermCategory, server_default="ETC")
    status: Mapped[str] = mapped_column(TermStatus, server_default="APPROVED")
    created_by: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("users.id"))
    reviewed_by: Mapped[int | None] = mapped_column(sa.BigInteger(), sa.ForeignKey("users.id"))
    reviewed_at: Mapped[datetime | None] = mapped_column(sa.DateTime())
    view_count: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("0"))
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), server_default=now())
    updated_at: Mapped[datetime] = mapped_column(
        sa.DateTime(), server_default=now(), onupdate=sa.func.now()
    )


class TermExample(Base):
    __tablename__ = "term_examples"
    __table_args__ = (sa.Index("ix_term_examples_term", "term_id"),)

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    term_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("terms.id"))
    sentence_jargon: Mapped[str] = mapped_column(sa.String(500))
    sentence_plain: Mapped[str] = mapped_column(sa.String(500))
    created_by: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), server_default=now())


class Translation(Base):
    __tablename__ = "translations"
    __table_args__ = (
        sa.Index("ix_translations_user_time", "user_id", "created_at"),
        sa.Index("ix_translations_project_meeting", "project_id", "meeting_id", "created_at"),
        sa.Index("ix_translations_meeting", "meeting_id"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("users.id"))
    project_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("projects.id"))
    meeting_id: Mapped[int | None] = mapped_column(sa.BigInteger(), sa.ForeignKey("meetings.id"))
    direction: Mapped[str] = mapped_column(TranslationDirection)
    source_type: Mapped[str] = mapped_column(SourceType, server_default="MESSAGE")
    source_text: Mapped[str] = mapped_column(sa.String(5000))
    input_source: Mapped[str] = mapped_column(InputSource, server_default="TYPED")
    source_image_url: Mapped[str | None] = mapped_column(sa.String(500))
    ocr_confidence: Mapped[Decimal | None] = mapped_column(sa.Numeric(4, 3))
    result_text: Mapped[str] = mapped_column(sa.String(2000))
    summary: Mapped[str | None] = mapped_column(sa.String(1000))
    jargon_count: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("0"))
    intent_type: Mapped[str | None] = mapped_column(IntentType)
    nuance_note: Mapped[str | None] = mapped_column(sa.String(500))
    nuance_tip: Mapped[str | None] = mapped_column(sa.String(300))
    nuance_confidence: Mapped[Decimal | None] = mapped_column(sa.Numeric(4, 3))
    ai_model: Mapped[str] = mapped_column(sa.String(50))
    latency_ms: Mapped[int | None] = mapped_column(sa.Integer())
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), server_default=now())


class TranslationAction(Base):
    __tablename__ = "translation_actions"
    __table_args__ = (
        sa.Index("ux_actions_translation_order", "translation_id", "sort_order", unique=True),
        sa.Index("ix_actions_checked", "is_checked", "created_at"),
        sa.Index("ix_actions_due_alert", "alert_enabled", "due_at"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    translation_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("translations.id"))
    sort_order: Mapped[int] = mapped_column(sa.Integer())
    action_text: Mapped[str] = mapped_column(sa.String(300))
    due_hint: Mapped[str | None] = mapped_column(sa.String(100))
    is_checked: Mapped[bool] = mapped_column(sa.Boolean(), server_default=sa.text("0"))
    alert_enabled: Mapped[bool] = mapped_column(sa.Boolean(), server_default=sa.text("1"))
    due_at: Mapped[datetime | None] = mapped_column(sa.DateTime())
    checked_at: Mapped[datetime | None] = mapped_column(sa.DateTime())
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), server_default=now())


class TranslationTerm(Base):
    __tablename__ = "translation_terms"
    __table_args__ = (
        sa.Index("ix_tt_translation", "translation_id"),
        sa.Index("ix_tt_term", "term_id"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    translation_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("translations.id"))
    term_id: Mapped[int | None] = mapped_column(sa.BigInteger(), sa.ForeignKey("terms.id"))
    ai_term_ko: Mapped[str | None] = mapped_column(sa.String(100))
    ai_plain_ko: Mapped[str | None] = mapped_column(sa.String(200))
    matched_text: Mapped[str] = mapped_column(sa.String(100))
    start_index: Mapped[int] = mapped_column(sa.Integer())
    end_index: Mapped[int] = mapped_column(sa.Integer())
    confidence: Mapped[Decimal] = mapped_column(sa.Numeric(4, 3))
