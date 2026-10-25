from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """환경 변수로 주입. 시크릿은 코드·로그에 절대 없다 (13번 §8)."""

    model_config = SettingsConfigDict(env_prefix="MWONMAL_", env_file=".env", extra="ignore")

    env: str = "local"
    contract_path: str = "../../contracts/openapi.yml"
    # 로컬 Compose 기본값. prod 는 sops 로 주입한다.
    database_url: str = "mysql+aiomysql://root:local@127.0.0.1:3306/mwonmal?charset=utf8mb4"


settings = Settings()
