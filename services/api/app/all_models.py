"""모든 컨텍스트의 테이블을 한 메타데이터에 모은다. Alembic env 와 스키마 테스트만 쓴다.

컨텍스트끼리는 서로 import 하지 않는다(14번 §3).
FK 는 문자열("users.id")로 걸어서 import 가 필요 없다.
"""

import sqlalchemy as sa

from app.core.db import Base
from app.core.schema import ACTIVE_TABLES
from app.decode.infra import models as decode_models
from app.identity.infra import models as identity_models
from app.learning.infra import models as learning_models
from app.notify.infra import models as notify_models
from app.workspace.infra import models as workspace_models

__all__ = [
    "Base",
    "decode_models",
    "identity_models",
    "learning_models",
    "notify_models",
    "workspace_models",
]
metadata = Base.metadata


def active_metadata() -> sa.MetaData:
    """지금 DB 에 만드는 테이블만 담은 사본(ADR-0021). 아직 없는 표를 가리키는 외래 키는 뺀다
    (예: translations.meeting_id → meetings). MySQL 은 없는 표를 가리키는 FK 를 만들 수 없다.

    테스트·개발 서버·벤치가 마이그레이션과 같은 모양의 DB 를 만들 때 쓴다.
    """
    out = sa.MetaData(naming_convention=metadata.naming_convention)
    for table in metadata.tables.values():
        table.to_metadata(out)  # 일단 전부 복사해야 외래 키가 서로를 찾는다
    for name, table in list(out.tables.items()):
        if name not in ACTIVE_TABLES:
            continue
        for fk in table.foreign_key_constraints.copy():
            if fk.referred_table.name not in ACTIVE_TABLES:
                table.constraints.discard(fk)
                for elem in fk.elements:
                    elem.parent.foreign_keys.discard(elem)
                    table.foreign_keys.discard(elem)
    for name in [n for n in out.tables if n not in ACTIVE_TABLES]:
        out.remove(out.tables[name])
    return out
