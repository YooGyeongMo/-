"""시드 사전 넣기. Alembic 0002(운영 MySQL)와 로컬·테스트(SQLite)가 같은 함수를 쓴다.

여러 번 돌려도 같다(slug 가 이미 있으면 건너뛴다). 용어의 작성자·검수자는 시스템 계정이다.
"""

import sqlalchemy as sa

from app.core.time import utcnow
from app.decode.infra.seed_terms import TERMS

SYSTEM_EMAIL = "dictionary@mwonmal.invalid"

_users = sa.table(
    "users",
    sa.column("id"),
    sa.column("email"),
    sa.column("provider"),
    sa.column("provider_id"),
    sa.column("nickname"),
    sa.column("role"),
)
_terms = sa.table(
    "terms",
    sa.column("id"),
    sa.column("slug"),
    sa.column("term_ko"),
    sa.column("origin_en"),
    sa.column("plain_ko"),
    sa.column("meaning"),
    sa.column("category"),
    sa.column("status"),
    sa.column("created_by"),
    sa.column("reviewed_by"),
    sa.column("reviewed_at"),
)
_examples = sa.table(
    "term_examples",
    sa.column("term_id"),
    sa.column("sentence_jargon"),
    sa.column("sentence_plain"),
    sa.column("created_by"),
)


def system_user_id(conn: sa.Connection) -> int:
    found = conn.execute(sa.select(_users.c.id).where(_users.c.email == SYSTEM_EMAIL)).scalar()
    if found is not None:
        return int(found)
    conn.execute(
        _users.insert().values(
            email=SYSTEM_EMAIL,
            provider="APPLE",
            provider_id="system:dictionary",
            nickname="뭔말인교",
            role="ADMIN",
        )
    )
    return int(
        conn.execute(sa.select(_users.c.id).where(_users.c.email == SYSTEM_EMAIL)).scalar_one()
    )


def seed(conn: sa.Connection) -> int:
    """넣은 용어 수를 돌려준다."""
    owner = system_user_id(conn)
    existing: set[str] = set(map(str, conn.execute(sa.select(_terms.c.slug)).scalars()))
    now = utcnow()
    added = 0
    for t in TERMS:
        if t.slug in existing:
            continue
        conn.execute(
            _terms.insert().values(
                slug=t.slug,
                term_ko=t.ko,
                origin_en=t.en,
                plain_ko=t.plain,
                meaning=t.meaning,
                category=t.category,
                status="APPROVED",
                created_by=owner,
                reviewed_by=owner,
                reviewed_at=now,
            )
        )
        added += 1
        if t.example is not None:
            term_id: int = conn.execute(
                sa.select(_terms.c.id).where(_terms.c.slug == t.slug)
            ).scalar_one()
            conn.execute(
                _examples.insert().values(
                    term_id=term_id,
                    sentence_jargon=t.example[0],
                    sentence_plain=t.example[1],
                    created_by=owner,
                )
            )
    return added
