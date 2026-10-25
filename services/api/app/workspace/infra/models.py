"""workspace 컨텍스트 테이블: projects, meetings, meeting_recordings (dbml v1.0)."""

from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, BigIntPK, now

RecordingStatus = sa.Enum(
    "RECORDING", "UPLOADED", "TRANSCRIBING", "DONE", "FAILED", name="recording_status"
)


class Project(Base):
    __tablename__ = "projects"
    __table_args__ = (sa.Index("ux_projects_user_name", "user_id", "name", unique=True),)

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("users.id"))
    name: Mapped[str] = mapped_column(sa.String(40))
    description: Mapped[str | None] = mapped_column(sa.String(60))
    color: Mapped[str] = mapped_column(sa.String(7), server_default="#2F6FD6")
    is_default: Mapped[bool] = mapped_column(sa.Boolean(), server_default=sa.text("0"))
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), server_default=now())
    updated_at: Mapped[datetime | None] = mapped_column(sa.DateTime())


class Meeting(Base):
    __tablename__ = "meetings"
    __table_args__ = (
        sa.Index("ix_meetings_project_time", "project_id", "held_at"),
        sa.Index("ix_meetings_user", "user_id"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    project_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("projects.id"))
    user_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("users.id"))
    title: Mapped[str] = mapped_column(sa.String(100))
    held_at: Mapped[datetime] = mapped_column(sa.DateTime())
    attendee_count: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("1"))
    agenda: Mapped[str | None] = mapped_column(sa.String(200))
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), server_default=now())


class MeetingRecording(Base):
    __tablename__ = "meeting_recordings"
    __table_args__ = (
        sa.Index("ix_recordings_user_time", "user_id", "created_at"),
        sa.Index("ix_recordings_meeting", "meeting_id"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("users.id"))
    meeting_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("meetings.id"))
    translation_id: Mapped[int | None] = mapped_column(
        sa.BigInteger(), sa.ForeignKey("translations.id"), unique=True
    )
    audio_url: Mapped[str | None] = mapped_column(sa.String(500))
    duration_sec: Mapped[int] = mapped_column(sa.Integer())
    consent_confirmed: Mapped[bool] = mapped_column(sa.Boolean())
    status: Mapped[str] = mapped_column(RecordingStatus, server_default="RECORDING")
    progress: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("0"))
    transcript: Mapped[str | None] = mapped_column(sa.Text())
    failure_reason: Mapped[str | None] = mapped_column(sa.String(200))
    expires_at: Mapped[datetime] = mapped_column(sa.DateTime())
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), server_default=now())
