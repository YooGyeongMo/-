"""모든 컨텍스트의 테이블을 한 메타데이터에 모은다. Alembic env 와 스키마 테스트만 쓴다.

컨텍스트끼리는 서로 import 하지 않는다(14번 §3).
FK 는 문자열("users.id")로 걸어서 import 가 필요 없다.
"""

from app.core.db import Base
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
