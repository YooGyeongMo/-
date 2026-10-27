"""지금 DB 에 실제로 있는 테이블(ADR-0021 단계 마이그레이션).

모델(app.*.infra.models)은 contracts/db.dbml v1.0 17테이블 전부를 그대로 정의한다(계약과 1:1,
테스트로 강제).
마이그레이션은 기능이 열린 테이블만 만든다. 기능이 열리면 `migrations/staged/*.py` 를 새
리비전으로 옮기고
여기에 이름을 더한다 — 그러면 그 테이블을 쓰는 코드 경로가 켜진다. 추가만 하므로 이미 있는
데이터에 영향이 없다.
"""

V1_0_TABLES: frozenset[str] = frozenset(
    {
        "levels",
        "users",
        "projects",
        "terms",
        "term_examples",
        "translations",
        "translation_actions",
        "translation_terms",
    }
)

# 단계별 대기 테이블(정의는 모델·migrations/staged 에 있다).
STAGED: dict[str, frozenset[str]] = {
    "learning": frozenset(
        {"cards", "review_sessions", "review_logs", "quiz_sessions", "quiz_questions"}
    ),
    "meetings": frozenset({"meetings", "meeting_recordings"}),
    "notify": frozenset({"user_devices", "notifications"}),
}

ACTIVE_TABLES: frozenset[str] = V1_0_TABLES


def has(table: str) -> bool:
    """그 테이블이 지금 DB 에 있는지(기능 경로 켜고 끄기용)."""
    return table in ACTIVE_TABLES
