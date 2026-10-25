"""시간 규칙 (계약 v1.0, 14번 §7).

DB 는 UTC naive 로 저장하고, API 는 KST 오프셋 없는 ISO 8601 로 낸다.
"""

from datetime import UTC, datetime, timedelta, timezone

KST = timezone(timedelta(hours=9))


def utcnow() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


def to_api(dt: datetime) -> str:
    """UTC naive → KST naive ISO 문자열 (예: 2026-09-17T13:30:00)."""
    return dt.replace(tzinfo=UTC).astimezone(KST).replace(tzinfo=None).isoformat(timespec="seconds")


def api_now() -> str:
    return to_api(utcnow())
