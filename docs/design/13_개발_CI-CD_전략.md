# 13. 개발 전략과 CI/CD 전략 (앱 + 서버)

> 대상: 뭔말인교? iOS·macOS 앱(`12_앱_아키텍처_설계.md`)과 서버(`14_시스템_설계서.md`).
> 혼자 만들되 팀처럼 돌아가게. 규칙은 적게, 대신 전부 자동으로 강제한다.

---

## 1. 저장소와 브랜치

**결정 E-1. 모노레포 하나 (`mwonmal/`).** 앱·서버·계약·인프라를 한 저장소에 둔다. 근거: 계약(yml, dbml)이 단일 원본이 되어 같은 PR에서 서버 라우터·앱 생성 코드가 함께 바뀌고 CI가 셋을 한 번에 검사한다. 언어가 다른 앱(Swift)과 서버(Python)가 공유하는 것은 **계약과 테스트 벡터**뿐이라는 점을 분명히 한다(코드 공유는 없다). 구조는 `14_시스템_설계서.md` §16.

**브랜치**: trunk-based. `main` 하나 + 짧은 feature 브랜치(하루 이내) + PR 필수. 릴리스는 경로별 태그(`app/v1.2.0`, `server/v1.2.0`), CI는 `paths` 필터로 앱·서버 파이프라인을 분리. 장기 브랜치·develop 브랜치 없음.

**커밋**: Conventional Commits(`feat:`, `fix:`, `chore:`, `test:`). 스코프는 모듈명(`feat(Meeting): …`). PR 제목이 곧 CHANGELOG 줄. 커밋에 AI 공동 저자 표기는 하지 않는다.

**PR 규칙**: 300줄 이하 권장, 템플릿(무엇/왜/테스트/스크린샷/체크리스트), 셀프 리뷰 후 머지, CI 전부 초록. 화면 변경은 스냅샷 diff 첨부.

---

## 2. 환경

| 환경 | 서버 | 앱 스킴 | 데이터 |
|---|---|---|---|
| local | Docker Compose (api, worker, mysql, redis, minio) | `Mwonmal-Local` (`http://localhost:8080`, `NSAllowsLocalNetworking`) | 시드 = 발표 데모(루나, 스프린트 계획 회의) |
| dev | 단일 VM, `api-dev.mwonmal.app` | `Mwonmal-Dev` | 매주 리셋 |
| prod | 단일 VM(→ 필요 시 2대), `api.mwonmal.app` | `Mwonmal` | 백업 일 1회 |

앱의 `Environment.mock`(서버 없음)은 별도 스킴 `Mwonmal-Demo`. 데모·스크린샷·Catalog·스냅샷 테스트가 이걸 쓴다.

---

## 3. 개발 순서 (Progressive, 앱과 서버를 흐름 단위로 맞물려)

| 스프린트 | 앱 | 서버 | 계약 |
|---|---|---|---|
| S0 (1주) | 뼈대, 토큰, `TabCoordinator`, 코드 생성·컴파일, KST 날짜·30코드 테스트 | 뼈대, Compose, 마이그레이션 17테이블, `/levels`, 헬스체크, Prism 목 서버 | yml v1.0 고정 |
| S1 | 시작 흐름 (로그인·온보딩·홈) | Auth(code 교환 3종), User, Onboarding, Stats | |
| S2 | 해석 흐름 (Compose·결과·카드) | Translation(AI 연동), Term, Card | |
| S3 | 회의 흐름 (녹음·폴링·결과) | Recording 파이프라인(조각·STT·해석·알림) | `durationSec` 누적 합의 |
| S4 | 익히기 (복습·테스트·등급) | Review(SM-2), Quiz, Level | |
| S5 | live 연결, 알림 4종, Sentry·Amplitude | APNs, 스케줄러(알림·30일 삭제), 관측 | yml v1.1 (MACOS, refresh, Idempotency-Key…) |
| S6 | 마감(Catalog, 스냅샷, 접근성, TestFlight) | 부하 테스트, 백업 복구 연습, 런북 | |

규칙: 스프린트마다 **앱이 서버와 실제로 통신하는 데모**를 남긴다(짧은 영상). 서버가 늦으면 앱은 Prism 목 서버(yml 예시 응답)로 진행한다.

---

## 4. 품질 게이트 (머지 조건, 전부 자동)

앱
- `swiftlint --strict`, `swiftformat --lint` (별도 job, 빌드 플러그인 아님)
- Presentation 폴더 간 import 금지: SwiftLint `custom_rules` 정규식
- `swift build`(iOS 시뮬레이터 + macOS), 생성 코드 컴파일 포함 (`-skipPackagePluginValidation`)
- 테스트: Domain·Data·Presentation·Navigation 단위 + Contract(yml 예시 디코드) + 스냅샷
- 커버리지: 변경 라인 ≥ 80%, `Domain/Rules` 100% (`xccov`)
- 계약 해시: `Contracts/openapi.yml`의 SHA가 서버 태그의 것과 같은지

서버
- `ruff`, `mypy --strict`, `bandit`
- `pytest` (단위 + DB 통합은 testcontainers MySQL) 커버리지 ≥ 80%
- **계약 테스트**: `schemathesis`가 yml로 모든 엔드포인트에 요청을 생성해 응답 스키마·상태 코드 검증. 이게 앱과 서버를 묶는 가장 강한 게이트.
- 마이그레이션 검사: `alembic check`(모델과 마이그레이션 불일치 시 실패), 빈 DB에서 `upgrade head` → `downgrade base` 왕복
- 컨테이너 이미지 취약점 스캔(`trivy`), 시크릿 스캔(`gitleaks`)

---

## 5. CI/CD 파이프라인

### 5-1. 앱 (`mwonmal-app`, GitHub Actions, macOS 러너)

```
pull_request  ──▶ lint ──▶ build(iOS, macOS) ──▶ test(unit+contract) ──▶ snapshot
push main     ──▶ 위 전부 ──▶ TestFlight 내부 배포 (빌드 번호 = run number)
tag app/v*    ──▶ 위 전부 ──▶ TestFlight 외부 그룹 ──▶ (수동 승인) App Store 제출 (iOS + Mac App Store)
```
- 러너·Xcode 버전 고정(`macos-15`, Xcode 26.x) — 스냅샷 폰트 렌더 차이 방지.
- 캐시: DerivedData + `.build`, 키 = `Package.resolved` 해시 + yml 해시.
- 서명: fastlane `match`(암호화 저장소, 인증서·프로파일) + App Store Connect API Key `.p8` 하나. 시크릿 4개(`ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT, MATCH_PASSWORD`). 인증서를 base64로 시크릿에 넣지 않는다.
- 버전: `MARKETING_VERSION`은 태그에서, `CURRENT_PROJECT_VERSION`은 run number, iOS·macOS 동일.
- Sentry: 빌드 시 dSYM 업로드 + release 태그 `app@1.2.0+123`.
- macOS는 **Mac App Store**(샌드박스, TestFlight for Mac). Developer ID 공증 경로는 쓰지 않는다.

### 5-2. 서버 (`mwonmal-server`, GitHub Actions, ubuntu 러너)

```
pull_request  ──▶ lint/type ──▶ test(unit) ──▶ test(integration, testcontainers) ──▶ schemathesis ──▶ image build ──▶ trivy
push main     ──▶ 위 전부 ──▶ ghcr.io 이미지 push (sha 태그) ──▶ dev 배포 (SSH, compose pull && up) ──▶ smoke(/health, /levels)
tag server/v* ──▶ 위 전부 ──▶ prod 배포 (수동 승인 environment) ──▶ smoke ──▶ 실패 시 이전 이미지로 자동 롤백
```
- 배포 방식: 단일 VM에 Docker Compose, `docker compose pull && docker compose up -d --wait`. 무중단이 필요해지면 두 번째 VM + 로드밸런서(§14 확장 경로). 지금은 재시작 수 초 다운을 허용한다(앱은 GET 재시도, POST는 사용자 재시도).
- 마이그레이션은 배포 전 별도 job(`alembic upgrade head`), 실패하면 배포 중단. 파괴적 변경(컬럼 삭제)은 두 단계(코드 먼저, 다음 릴리스에 드롭).
- 시크릿: GitHub Environments(`dev`, `prod`)에 `DATABASE_URL, REDIS_URL, JWT_PRIVATE_KEY, APNS_KEY, ANTHROPIC_API_KEY, STT_API_KEY, S3_*`, OAuth 클라이언트 시크릿 3종. VM에는 `.env`를 `sops`로 암호화해 두고 배포 시 복호화.
- 이미지: 멀티스테이지, non-root, 고정 베이스 태그, SBOM 생성.

### 5-3. 계약 동기화 (앱 ↔ 서버, 모노레포)
- `contracts/openapi.yml`이 바뀌는 PR은 `contract` 라벨이 자동으로 붙고, 앱 코드 생성·컴파일과 서버 `schemathesis`가 **같은 PR에서** 돈다. 둘 중 하나가 깨지면 머지 불가.
- 계약 버전은 yml `info.version`. 앱은 `User-Agent: Mwonmal-iOS/1.2.0 contract/1.1`을 보내고 서버는 지원 범위 밖이면 426(v1.1).
- `packages/test-vectors/`의 SM-2·등급표·형광펜 정답 JSON을 Swift와 Python 테스트가 같이 읽는다. 규칙이 한쪽만 바뀌면 다른 쪽 테스트가 깨진다.

---

## 6. 릴리스

- 주기: 앱 2주(TestFlight는 머지마다), 서버는 머지마다 dev, 주 1회 prod.
- 앱 릴리스 체크리스트: 스킴 `.live` / ATS 예외 0 / Privacy 라벨 / Sentry release / 심사 노트(녹음 동의 스크린샷, 테스트 계정) / Accessibility Inspector / 스냅샷 전부 초록 / 양 플랫폼 빌드 번호 일치 / 계약 해시 일치.
- 서버 릴리스 체크리스트: 마이그레이션 왕복 / schemathesis 초록 / 백업 최신 / 롤백 이미지 태그 기록 / 런북 링크.
- 핫픽스: `main`에서 바로 태그(`v1.2.1`), 같은 파이프라인.

---

## 7. 관측과 운영 (개발 전략의 일부)

- 에러: Sentry(앱·서버 같은 조직, release 연결). 서버는 요청 ID를 응답 헤더 `X-Request-Id`로 돌려주고 앱 Sentry 이벤트에 붙인다 → 앱 크래시와 서버 로그를 한 ID로 잇는다.
- 로그: 서버 구조화 JSON(요청 ID, userId 해시, operationId, 지연). **원문·받아쓰기·오디오는 로그 금지**(앱 §10 불변식과 동일).
- 지표: `/metrics`(Prometheus) → Grafana 무료 클라우드. 대시보드 4개: 요청 지연 p50/p95, AI 호출 지연·실패율, 녹음 파이프라인 단계별 소요, 알림 발송 성공률.
- 알림(온콜): Sentry 알림 + Grafana 임계치(5xx > 1%, AI 실패율 > 5%, 큐 적체 > 100) → 슬랙.
- 런북: `runbooks/` 폴더에 "AI 장애", "STT 장애", "DB 복구", "롤백" 4개. 각 1쪽.

---

## 8. 의존성·보안 정책

- 앱: SPM만, 의존성 5개 이내(Sentry, Amplitude, openapi-generator/runtime/urlsession, snapshot-testing). 추가는 PR에 "왜" 한 문장.
- 서버: `uv`로 잠금, 월 1회 Dependabot 묶음 PR.
- 시크릿은 코드·로그·Sentry 어디에도 없다(`gitleaks` 게이트). 키 회전 절차를 런북에.
- 데이터 보존: 오디오 30일(서버 잡), 게스트 없음, 로그 14일, 백업 30일.

---

## 9. 하지 않는 것

- develop 브랜치, 릴리스 브랜치, 코드 프리즈.
- 수동 배포, SSH로 직접 고치기(전부 이미지 재배포).
- 빌드 플러그인 린트(느리고 CI 신뢰 프롬프트 문제).
- Kubernetes(v1 규모에 과함, 14번 §12 확장 경로에 조건 명시).
- 처음부터 MSA(14번 §17 분리 조건을 만족할 때 컨텍스트 하나씩).
