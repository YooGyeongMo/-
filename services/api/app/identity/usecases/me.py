"""GET /users/me."""

from app.core.errors import DomainError, ErrorCode
from app.identity.domain.model import Account, AccountRepository


async def get_me(*, user_id: int, repo: AccountRepository) -> Account:
    account = await repo.by_id(user_id)
    if account is None:
        # 토큰은 유효한데 계정이 없다 = 삭제된 계정. 다시 로그인하게 401.
        raise DomainError(ErrorCode.UNAUTHORIZED, "로그인이 필요한 기능이에요.")
    return account
