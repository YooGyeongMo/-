# 현재 상태 (STATE) — 세션을 껐다 켰을 때 여기부터 읽는다

> **이 파일이 "지금 어디까지 왔고 다음에 뭘 하는지"의 단일 원본이다.**
> 대화 기록은 길어지면 자동 요약되어 세부가 날아간다. 그래서 중요한 것은 전부 여기와 `docs/` 아래, 그리고 GitHub 이슈에 있다.
> 세션이 끝날 때마다 이 파일을 갱신한다(`/mw-save`). 새 세션은 `/mw` 로 이 파일부터 읽는다.

**마지막 갱신**: 2026-10-02 · **main**: `be22f63` · **CI**: 3개 워크플로 전부 초록

---

## 1. 지금 단계 — 한 문장

설계·기록·골격은 다 끝났고, **실제 기능 코드는 아직 0줄**이다. 하루 2~3시간이라는 실제 가용 시간에 맞춰 **범위를 다시 정하는 결정**만 내리면 바로 착수한다.

## 2. 🚨 지금 막혀 있는 것 (사용자 결정 대기)

**결정 A — 롤링 릴리스 로드맵으로 갈 것인가?** (가장 중요, 이것부터)

| 사실 | 값 |
|---|---|
| 사용자 실제 가용 시간 | **하루 2~3시간** (2026-09-27 본인 확인) |
| 11/6까지 남은 평일 (10/5 기준) | 25일 → **50~75시간** |
| 기존 계획이 요구하는 양 | **264시간** |
| 격차 | **3~4배**. 범위 컷(15h)으로는 해결 불가 |

제안(승인 대기): 한 번에 다 내지 않고 매달 하나씩 낸다. 요구사항은 **삭제하지 않고 날짜만 배정**(REQ-34).

| 릴리스 | 날짜 | 내용 | 예산 |
|---|---|---|---|
| **v1.0** | 11/6 | iPhone만. Apple 로그인 → 붙여넣기 → **해석**(검수 사전 + Gemini 무료, 용어 하이라이트, 결과 카드) → 설정. 서버 배포 + TestFlight | 60h |
| v1.1 | 11월 말 | 복습 (SM-2, 카드 뒤집기, 등급) | 25h |
| v1.2 | 12월 중순 | 회의 녹음 → 받아쓰기 → 해석 | 45h |
| v1.3 | 1월 중순 | iPad 넓은 레이아웃 + macOS 출시 + 알림 | 35h |

v1.0에서 빠지는 것(→ 위 표로 이동): 녹음, 복습, macOS·iPad 넓은 레이아웃(iPad는 아이폰 레이아웃으로 그냥 동작), 알림, 카카오·Google 로그인(Apple만), Motion 모듈, Sentry·Amplitude, AI 4트랙 측정(Gemini만 + 평가셋 50문장).

대안: 전체를 다 넣으려면 날짜를 **2027년 2월 말**로 옮겨야 한다(264h ÷ 2.5h = 평일 106일). 비추천.

> 승인되면 할 일: `docs/16_실행계획.md` 재작성 → 이슈 78건 마일스톤 재배치 → v1.0 Day 1 착수.

**결정 B — GitHub Project 보드** (사용자가 명령 1줄 실행해야 함)
```bash
gh auth refresh -s project,read:project
```
현재 토큰 스코프에 `project`가 없어 보드를 못 만든다. 실행해 주면 Project #2(https://github.com/users/YooGyeongMo/projects/2)에 이슈 78건 + 칸반·스프린트·로드맵·영역별 4개 뷰를 세팅한다.

**결정 C — 3차 컷 6건** (2.5일치). 결정 A가 승인되면 자동으로 의미가 없어진다.

## 3. 끝난 것 (다시 안 해도 됨)

- **제출물**: SKALA 미니프로젝트 9/17 제출 완료(발표 27p, 기술서 46p, API 43개, DB 17테이블)
- **저장소 골격**: Tuist 8모듈(Domain·Data·MwonmalAPI·Platform·MwonmalUI·Presentation·Navigation·Composition), iOS 17.0 / macOS 14.0, Domain은 watchOS 10.0도. 빌드·테스트 통과(iPhone SE iOS 17.0 포함)
- **CI**: `app`·`server`·`contracts` 3개 워크플로 main에서 전부 초록. hosted `macos-26` + Xcode 26.4 핀
- **계약**: `contracts/openapi.yml`(43 ops, v1.0 **수정 금지**), `contracts/db.dbml`(17테이블), `push-payload.schema.json` + 예시 4개
- **서버 뼈대**: FastAPI `/health` `/ready`, 원본 yml 서빙, pytest·ruff·mypy 통과, Docker Compose(caddy·mysql·redis·minio·prism), 블루그린 스크립트
- **`eval/`**: `cost_model.py`(표준 라이브러리만, tomllib), `pricing.toml`(전부 unverified), `run.py` 뼈대, 테스트 20개 통과
- **문서**: REQUIREMENTS 35개 + v1.1 이관 27항목, ADR 0001~0012, 설계문서 12·13·14·15, 실행계획 v2, 협의체 기록(`docs/council/`), 배운 점 2건, BM 전략, archify 그림 3장
- **GitHub**: 이슈 78건(S0~S6 57 + v1.0.1 1 + v1.1 백로그 20), 마일스톤 9개, 라벨 정리

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
| 왜 그렇게 정했나 | `docs/adr/0001~0012` |
| 협의체·레드팀이 뭘 찾았나 | `docs/council/S0.md`, `S0-redteam.md`, `S0/` (파트 메모 원문 9개) |
| 앱 구조 | `docs/design/12_앱_아키텍처_설계.md`, 그림 `docs/diagrams/module-graph.png` |
| 서버·AI·비용 | `docs/design/14_시스템_설계서.md` (§15 AI, §19 비용 집계) |
| 일정 | `docs/16_실행계획.md` (⚠️ 결정 A 승인 시 재작성 대상) |
| 삽질 기록 | `docs/lessons/` |
| 돈 계산 | `make cost MAU=1000` → `eval/cost_model.py` |

## 6. 세션 재개 방법

```bash
cd ~                 # 이 프로젝트는 항상 홈에서 띄운다 (메모리가 홈에 묶여 있음)
claude --resume d706151f-c3f9-42a5-992f-455277dca82f    # 기존 대화 이어가기
# 또는 새 대화에서:  /mw     ← 이 파일 + 메모리 + git 상태를 한 번에 읽어들임
```

세션 끝낼 때: **`/mw-save`** → 이 파일 갱신 + 메모리 갱신 + 커밋.

## 7. 결정 A가 승인되면 바로 할 일 (v1.0 Day 1)

1. `services/api` Alembic 마이그레이션 — v1.0에 필요한 테이블만(users, translations, terms, user_terms, levels)
2. Apple 로그인 code 교환 + JWT RS256 발급
3. 앱: `MwonmalAPI` 생성 코드로 `/auth/apple` 호출까지 연결

관련 이슈: #2(Tuist 타깃·CI), #4(서버 컨텍스트 폴더·ENUM), #7 계열(인증). 결정 A 승인 후 번호를 다시 정리한다.
