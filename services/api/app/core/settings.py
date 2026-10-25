from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """환경 변수로 주입. 시크릿은 코드·로그에 절대 없다 (13번 §8)."""

    model_config = SettingsConfigDict(env_prefix="MWONMAL_", env_file=".env", extra="ignore")

    env: str = "local"
    contract_path: str = "../../contracts/openapi.yml"
    # 로컬 Compose 기본값. prod 는 sops 로 주입한다.
    database_url: str = "mysql+aiomysql://root:local@127.0.0.1:3306/mwonmal?charset=utf8mb4"

    # 우리 액세스 토큰 (RS256). 비어 있으면 local·test 만 임시 키.
    jwt_private_key: str = ""
    jwt_kid: str = "local-1"

    # Sign in with Apple (네이티브 앱 code 교환). client_id = 번들 ID, 키 = .p8 (ES256).
    apple_client_id: str = "kr.mwonmal.app"  # ADR-0004
    apple_team_id: str = ""
    apple_key_id: str = ""
    apple_private_key: str = ""


settings = Settings()
