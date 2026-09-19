# 뭔말인교? (Mwonmal)

판교어와 회의 맥락을 AI가 쉬운 말로 풀어 주는 iOS·macOS 앱과 서버. 모노레포.

| 폴더 | 내용 |
|---|---|
| `contracts/` | `openapi.yml`(43 API), `db.dbml`(17 테이블). 단일 원본 |
| `apps/ios-macos/` | Tuist 프로젝트. 모듈 8개 + 앱 2개 + Catalog |
| `services/` | `api`(FastAPI), `worker`(ARQ), `scheduler` |
| `packages/` | `py-common`, `test-vectors`(Swift·Python 공용 정답) |
| `infra/` | Docker Compose, Caddy, 블루그린 스크립트, Terraform |
| `docs/` | 설계(`design/`), 결정(`adr/`), 일별 로그(`log/`), 실행 계획 |

시작: `docs/16_실행계획.md` → `CONTRIBUTING.md`.
