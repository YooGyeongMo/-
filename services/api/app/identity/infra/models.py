"""identity 컨텍스트 테이블: users, user_devices (dbml v1.0)."""

from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, BigIntPK, now

AuthProvider = sa.Enum("APPLE", "GOOGLE", "KAKAO", name="auth_provider")
UserRole = sa.Enum("MEMBER", "ADMIN", name="user_role")
DevicePlatform = sa.Enum("IOS", "WEB", name="device_platform")


class User(Base):
    __tablename__ = "users"
    __table_args__ = (
        sa.Index("ux_users_email", "email", unique=True),
        sa.Index("ux_users_nickname", "nickname", unique=True),
        sa.Index("ux_users_provider", "provider", "provider_id", unique=True),
        sa.Index("ix_users_level", "level_code"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    email: Mapped[str] = mapped_column(sa.String(255))
    provider: Mapped[str] = mapped_column(AuthProvider)
    provider_id: Mapped[str] = mapped_column(sa.String(255))
    profile_image_url: Mapped[str | None] = mapped_column(sa.String(500))
    nickname: Mapped[str] = mapped_column(sa.String(30))
    job_group: Mapped[str | None] = mapped_column(sa.String(30))
    onboarded_at: Mapped[datetime | None] = mapped_column(sa.DateTime())
    reminder_hour: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("18"))
    action_alert_enabled: Mapped[bool] = mapped_column(sa.Boolean(), server_default=sa.text("1"))
    role: Mapped[str] = mapped_column(UserRole, server_default="MEMBER")
    level_code: Mapped[str | None] = mapped_column(sa.String(20), sa.ForeignKey("levels.code"))
    best_score: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("0"))
    current_streak: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("0"))
    longest_streak: Mapped[int] = mapped_column(sa.Integer(), server_default=sa.text("0"))
    last_review_at: Mapped[date | None] = mapped_column(sa.Date())
    # users ↔ projects 순환 참조라 FK 는 테이블 생성 뒤 ALTER 로 붙인다.
    current_project_id: Mapped[int | None] = mapped_column(
        sa.BigInteger(), sa.ForeignKey("projects.id", use_alter=True)
    )
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), server_default=now())
    updated_at: Mapped[datetime] = mapped_column(
        sa.DateTime(), server_default=now(), onupdate=sa.func.now()
    )


class UserDevice(Base):
    __tablename__ = "user_devices"
    __table_args__ = (
        sa.Index("ix_devices_user_platform", "user_id", "platform"),
        sa.Index("ux_devices_token", "push_token", unique=True),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("users.id"))
    platform: Mapped[str] = mapped_column(DevicePlatform)
    push_token: Mapped[str | None] = mapped_column(sa.String(255))
    last_seen_at: Mapped[datetime] = mapped_column(sa.DateTime(), server_default=now())
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), server_default=now())
