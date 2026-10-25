"""notify 컨텍스트 테이블: notifications (dbml v1.0)."""

from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, BigIntPK, now

NotificationType = sa.Enum(
    "REVIEW_REMINDER", "ACTION_DUE", "DECODE_DONE", "LEVEL_UP", name="notification_type"
)


class Notification(Base):
    __tablename__ = "notifications"
    __table_args__ = (sa.Index("ix_noti_user_time", "user_id", "scheduled_at"),)

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(sa.BigInteger(), sa.ForeignKey("users.id"))
    type: Mapped[str] = mapped_column(NotificationType)
    title: Mapped[str] = mapped_column(sa.String(100))
    body: Mapped[str] = mapped_column(sa.String(300))
    target_id: Mapped[int | None] = mapped_column(sa.BigInteger())
    scheduled_at: Mapped[datetime] = mapped_column(sa.DateTime())
    sent_at: Mapped[datetime | None] = mapped_column(sa.DateTime())
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), server_default=now())
