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

    # 로컬·테스트 전용 가짜 로그인(code="dev:<이름>"). local·test 밖에서 켜면 기동
    # 거부(security.check_keys).
    # 시뮬레이터 E2E·계약 검사(#110)가 Apple 키 없이 성공 경로를 돌게 한다.
    dev_login: bool = False

    # Redis(한도 카운터·브레이커 공유). 비면 프로세스 메모리(local·test 만, 워커 1개).
    redis_url: str = ""

    # AI 라우터 (ADR-0008, 14번 §15-3). 기본은 외부 전송 꺼짐 → 사전만(none).
    ai_external_text: bool = False
    router_allow_degraded: bool = True
    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.5-flash"
    gemini_rpm: int = 10
    gemini_rpd: int = 250
    gemini_timeout_sec: float = 12.0


settings = Settings()
