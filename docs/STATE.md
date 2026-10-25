# 현재 상태 (STATE) — 세션을 껐다 켰을 때 여기부터 읽는다

> **이 파일이 "지금 어디까지 왔고 다음에 뭘 하는지"의 단일 원본이다.**
> 대화 기록은 길어지면 자동 요약되어 세부가 날아간다. 그래서 중요한 것은 전부 여기와 `docs/` 아래, 그리고 GitHub 이슈에 있다.
> 세션이 끝날 때마다 이 파일을 갱신한다(`/mw-save`). 새 세션은 `/mw` 로 이 파일부터 읽는다.

**마지막 갱신**: 2026-10-25 · **main**: `198139a` · **CI**: server·secrets 초록(main, 테스트 81 통과·MySQL 포함)

---

## 1. 지금 단계 — 한 문장

**롤링 릴리스 확정(ADR-0013).** v1.0 해석 = **2026-11-20(금)**, 평일 하루 3h × 20일. **Day 1·2 완료(10/25에 당겨서, PR #92·#94)** → 다음은 **Day 3 앱 API 생성(#3)**. 계획보다 2일 앞서 있다. 일정의 단일 원본 = `docs/16_실행계획.md` §0.

| 릴리스 | 마감 | 마일스톤 |
|---|---|---|
| v1.0 해석 | 11/20(금) | iPhone, Apple 로그인 → 붙여넣기 → 해석 → 기록 → 설정, OCI + TestFlight 내부 |
| v1.1 복습 | 12/3(목) | 온보딩·카드·복습·퀴즈·Motion |
| v1.2 회의 | 12/24(목) | 녹음 → 받아쓰기 → 해석, 알림 |
| v1.3 iPad | 2027-01-08(금) | iPad 넓은 레이아웃, 알림·딥링크 |
| v1.4 macOS | 2027-01-19(화) | macOS TestFlight, Mac 창·메뉴 |

플랫폼 순서: **iPhone → iPad → macOS** (iPad·macOS를 한 릴리스에 묶지 않는다).

## 2. 🚨 지금 막혀 있는 것

- **결정 A — 승인됨 (2026-10-25)**: "조금 미루는데 그 대신 빡빡하게" → ADR-0013. 옛 S0~S6·v1.0.1 마일스톤은 비웠고, 이슈 79건을 새 마일스톤 4개 + `백로그`로 재배치했다.
- **결정 B — GitHub Project 보드** (사용자가 명령 1줄 실행해야 함, 급하지 않음)
```bash
gh auth refresh -s project,read:project
```
- 결정 C(3차 컷) — 폐기. 결정 A로 의미 없어짐.
- **사용자 작업 D — Apple 로그인 키 (Day 5 실제 로그인 전까지)**: Apple Developer → Certificates, IDs & Profiles → Keys 에서 "Sign in with Apple" 키(.p8) 생성, App ID `kr.mwonmal.app`에 Sign in with Apple 켜기. Team ID·Key ID·.p8 내용은 **커밋하지 말고** `services/api/.env`(무시됨)에 → 키 이름은 `services/api/.env.example`. 없으면 서버는 로그인을 401로 거절한다(ADR-0014).

## 3. 끝난 것 (다시 안 해도 됨)

- **제출물**: SKALA 미니프로젝트 9/17 제출 완료(발표 27p, 기술서 46p, API 43개, DB 17테이블)
- **저장소 골격**: Tuist 8모듈(Domain·Data·MwonmalAPI·Platform·MwonmalUI·Presentation·Navigation·Composition), iOS 17.0 / macOS 14.0, Domain은 watchOS 10.0도. 빌드·테스트 통과(iPhone SE iOS 17.0 포함)
- **CI**: `app`·`server`·`contracts` 3개 워크플로 main에서 전부 초록. hosted `macos-26` + Xcode 26.4 핀
- **계약**: `contracts/openapi.yml`(43 ops, v1.0 **수정 금지**), `contracts/db.dbml`(17테이블), `push-payload.schema.json` + 예시 4개
- **서버 뼈대**: FastAPI `/health` `/ready`, 원본 yml 서빙, pytest·ruff·mypy 통과, Docker Compose(caddy·mysql·redis·minio·prism), 블루그린 스크립트
- **`eval/`**: `cost_model.py`(표준 라이브러리만, tomllib), `pricing.toml`(전부 unverified), `run.py` 뼈대, 테스트 20개 통과
- **문서**: REQUIREMENTS 35개 + v1.1 이관 27항목, ADR 0001~0012, 설계문서 12·13·14·15, 실행계획 v2, 협의체 기록(`docs/council/`), 배운 점 2건, BM 전략, archify 그림 3장
- **GitHub**: 이슈 79건 → 마일스톤 `v1.0 해석`·`v1.1 복습`·`v1.2 회의`·`v1.3 iPad`·`v1.4 macOS`·`백로그` (2026-10-25 재배치). `sprint:S*` 라벨은 옛 기록으로 남아 있다

## 4. 절대 어기면 안 되는 것

- **계약 v1.0**(`contracts/openapi.yml`, `db.dbml`)은 제출본. 변경은 v1.1 백로그로만.
- **원문·받아쓰기·오디오는 밖으로 안 나간다**(REQ-14). 무료 Gemini는 **옵트인한 베타 사용자 텍스트만**(기본 `AI_EXTERNAL_TEXT=off`), 오디오는 서버 `whisper_local`만. 대여 API 키는 평가 전용, prod 사슬 제외 → ADR-0008
- **공개 저장소.** 시크릿·개인정보 커밋 금지(gitleaks 게이트). 실측 사용량(`eval/measured/`)은 `.gitignore`
- **커밋에 AI 공동 저자 표기 금지**
- 모든 도구·SDK·AI 선택은 **의도 → 비용 → 대안 → 왜** 순으로 ADR 먼저(REQ-20, 최우선)
- v1.1로 미룬 것은 **삭제하지 않고 상태로만 관리**(REQ-34)

## 5. 어디에 뭐가 있나

| 궁금한 것 | 파일 |
|---|---|
| 잊으면 안 되는 요구사항 전부 | `docs/REQUIREMENTS.md` (REQ-01~35, F절 = v1.1 이관) |
| 왜 그렇게 정했나 | `docs/adr/0001~0013` (0013 = 롤링 릴리스) |
| 협의체·레드팀이 뭘 찾았나 | `docs/council/S0.md`, `S0-redteam.md`, `S0/` (파트 메모 원문 9개) |
| 앱 구조 | `docs/design/12_앱_아키텍처_설계.md`, 그림 `docs/diagrams/module-graph.png` |
| 서버·AI·비용 | `docs/design/14_시스템_설계서.md` (§15 AI, §19 비용 집계) |
| 일정 | `docs/16_실행계획.md` **§0 (v3)** — §4·§5는 폐기 기록 |
| 삽질 기록 | `docs/lessons/` |
| 돈 계산 | `make cost MAU=1000` → `eval/cost_model.py` |

## 6. 세션 재개 방법

```bash
cd ~                 # 이 프로젝트는 항상 홈에서 띄운다 (메모리가 홈에 묶여 있음)
claude --resume d706151f-c3f9-42a5-992f-455277dca82f    # 기존 대화 이어가기
# 또는 새 대화에서:  /mw     ← 이 파일 + 메모리 + git 상태를 한 번에 읽어들임
```

세션 끝낼 때: **`/mw-save`** → 이 파일 갱신 + 메모리 갱신 + 커밋.

## 7. 다음 할 일 (v1.0, 16번 §0-2)

1. ~~Day 1 (#4) 17테이블 마이그레이션 + `/ready` DB ping~~ → PR #92. #4 잔여: `/levels`, schemathesis `|| true` 제거
2. ~~Day 2 (#6) Apple 로그인 + JWT RS256 + `/users/me`~~ → PR #94, ADR-0014. 계약과 알려진 차이 3건(ADR-0014 §5)
3. **Day 3 (app, #3)**: swift-openapi-generator 활성화, 43 op 생성·컴파일, KST DateTranscoder
4. Day 4 (app, #8): Sign in with Apple(네이티브) + Keychain TokenStore

같이 고친 것: gitleaks가 `contracts/**` 변경 때만 돌던 구멍 → `secrets.yml`(PR #95, lessons 2026-10-25). httpx로 들어온 certifi CRITICAL → 2026.10.23.

금요일마다 15분 회고 → `docs/log/`. 2일 이상 밀리면 ADR-0013 §7 컷 순서 발동.
