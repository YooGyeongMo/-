from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """환경 변수로 주입. 시크릿은 코드·로그에 절대 없다 (13번 §8)."""

    model_config = SettingsConfigDict(env_prefix="MWONMAL_", env_file=".env", extra="ignore")

    env: str = "local"
    contract_path: str = "../../contracts/openapi.yml"


settings = Settings()
