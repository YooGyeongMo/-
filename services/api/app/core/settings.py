from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """환경 변수로 주입. 시크릿은 코드·로그에 절대 없다 (13번 §8)."""

    model_config = SettingsConfigDict(env_prefix="MWONMAL_", env_file=".env", extra="ignore")

    env: str = "local"
    contract_path: str = "../../contracts/openapi.yml"
    # 로컬 Compose 기본값. prod 는 sops 로 주입한다.
    database_url: str = "mysql+aiomysql://root:local@127.0.0.1:3306/mwonmal?charset=utf8mb4"
    # 연결 풀(프로세스당). 블루·그린 5프로세스 × (10+10) = 100 < MySQL max_connections 151.
    # 해석 요청은 AI 호출(최대 12초) 동안 연결을 쥔다(요청 = 트랜잭션 하나) → 여유를 크게, 대기도
    # AI 타임아웃보다 길게. 연결을 AI 호출 전에 돌려주는 것은 #(v1.1 백로그, ADR-0021 §성능).
    db_pool_size: int = 10
    db_max_overflow: int = 10
    db_pool_timeout_sec: float = 15.0
    db_pool_recycle_sec: int = 1800  # MySQL wait_timeout(8h)·프록시 유휴 끊김보다 먼저 새 연결로

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
