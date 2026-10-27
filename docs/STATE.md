# 현재 상태 (STATE) — 세션을 껐다 켰을 때 여기부터 읽는다

> **이 파일이 "지금 어디까지 왔고 다음에 뭘 하는지"의 단일 원본이다.**
> 대화 기록은 길어지면 자동 요약되어 세부가 날아간다. 그래서 중요한 것은 전부 여기와 `docs/` 아래, 그리고 GitHub 이슈에 있다.
> 세션이 끝날 때마다 이 파일을 갱신한다(`/mw-save`). 새 세션은 `/mw` 로 이 파일부터 읽는다.

**마지막 갱신**: 2026-10-27 · **main**: #114·#116 머지됨, DB 단계화·성능·면접 문서 PR 진행 · **CI**: PR에서 확인 후 머지

---

## 1. 지금 단계 — 한 문장

**v1.0 해석(11/20) Day 1~15 분량 완료(로컬 E2E 통과), 계획보다 약 2주 앞섬.** 남은 v1.0: 실서버(OCI) 배포 Day 16~17, TestFlight Day 18, 실기기 QA Day 19. Apple 키(.p8)가 있어야 실로그인.

| 릴리스 | 마감 | 마일스톤 |
|---|---|---|
| v1.0 해석 | 11/20(금) | iPhone, Apple 로그인 → 붙여넣기 → 해석 → 기록 → 설정, OCI + TestFlight 내부 |
| v1.1 복습 | 12/3(목) | 온보딩·카드·복습·퀴즈·Motion + App Intents(#100)·계정 삭제(#102)·FM 미리보기(#72)·판교어 탐지 모델 실험(#101) |
| v1.2 회의 | 12/24(목) | 녹음 → 받아쓰기 → 해석, 알림, PCC 검토(#103) |
| v1.3 iPad | 2027-01-08(금) | iPad 넓은 레이아웃 |
| v1.4 macOS | 2027-01-19(화) | macOS TestFlight |

플랫폼 순서: **iPhone → iPad → macOS**. 공개 출시 목표(마케팅 문서): 2027-02-22.

## 2. 🚨 지금 막혀 있는 것 / 사용자 결정

- **사용자 작업 D — Apple 로그인 키 (실로그인 전 필수)**: Apple Developer → Keys에서 "Sign in with Apple" 키(.p8) 생성, App ID `kr.mwonmal.app`에 Sign in with Apple 켜기. Team ID·Key ID·.p8은 **커밋하지 말고** `services/api/.env`에(키 이름은 `.env.example`). 없으면 서버는 로그인을 401로 거절한다. #9(S-01)의 "로컬 서버 실로그인"이 이것만 기다린다.
- **PO 결정 2건 (Day 12 전까지)**: ① 결과 카드에 확신도 숫자(예: 88%) 노출? ② v1.0 다크 모드 노출? (값은 이미 4벌 있음, ADR-0017 결정 5)
- **PCC 전제**: App Store Small Business Program 가입 여부(#103, v1.2)
- **정리**: Docker Desktop이 멈춰 있었다. 재시작 후 `docker rm -f mw-mysql-redteam; docker rmi caddy:2`(레드팀 잔여물).
- 결정 B — GitHub Project 보드: `gh auth refresh -s project,read:project` (급하지 않음)

## 3. 끝난 것 (다시 안 해도 됨)

- **서버**: Day 1 DB 17테이블(#92), Day 2 Apple 로그인·JWT·`/users/me`(#94), **레드팀 3라운드**(#108: High 4건 수정, Critical·High 0, MySQL 경합 테스트 CI 실행, 실행 이미지에서 uv 제거 — Trivy 통과). 보고서 `docs/lessons/2026-10-26-server-redteam.md`
- **앱**
  - Day 3 MwonmalAPI(#97): swift-openapi-generator 1.14.2, 43 op, KST 날짜, 미들웨어 3개. **로컬 Swift 패키지**(`apps/ios-macos/Packages/MwonmalAPI`, 동적 라이브러리)
  - 모듈 전환(#106, ADR-0016): `Modules/Core/{Domain, DomainTesting, Platform, Data, MwonmalUI, Routing, FeatureKit, Composition}` + `Modules/Features/{Auth, Translate(+Example), Home, Settings}`. 의존 방향은 헬퍼 precondition + CI `scripts/check-module-deps.py`. 문구는 모듈별 String Catalog(ko+en) + CI `scripts/check-xcstrings.py`
  - Day 4 Apple 로그인(#107): Domain UseCase 3개, Keychain, `RemoteAuthRepository`, `APIEnvironment`(Composition은 MwonmalAPI를 모른다), `AppSession`
  - Day 5 S-01(#111): Figma 히어로 벡터 PDF, **색 토큰 22개 × 4벌**(라이트·다크·고대비), 공식 Apple 버튼, 대비 테스트(Asset Catalog 실제 값)
  - 테스트 기기: iPhone SE 3세대 **iOS 17.0**(최소 OS, Swift Testing 동작 확인) + iPhone 17 Pro iOS 26.4 + macOS. 로컬 시뮬레이터도 이 둘만 남김
- **결정 기록**: ADR-0015 온디바이스 AI(iOS 27 기준), 0016 MVVM-R·기능 모듈(TCA 320 / MVVM-C 405 / MV 340 / MVVM-R 440), 0017 디자인 시스템(시스템 글래스만, 콘텐츠 불투명), 0018 판교어 탐지 모델(사전+태거 F1 0.67→0.93, 오탐이 관문), 0019 `MwonmalIntelligence` 패키지(v1.0 링크 0)
- **조사 산출물**: `docs/bm/marketing-positioning-2026-10.md`(포지셔닝 "회사 말귀, 3초 만에 할 일로"), `ml/pangyo-tagger/`(재현 스크립트)

## 4. 절대 어기면 안 되는 것

- **계약 v1.0**(`contracts/openapi.yml`, `db.dbml`)은 제출본. 변경은 v1.1 백로그로만(#75, #104 enum 진화 규칙).
- **원문·받아쓰기·오디오는 밖으로 안 나간다**(REQ-14, ADR-0008). Gemini는 옵트인 텍스트만. **PCC도 원문이 나가므로 ADR-0008 개정 전엔 금지**(ADR-0015).
- **공개 저장소.** 시크릿·개인정보 커밋 금지(gitleaks).
- **커밋·PR에 AI 공동 저자 표기 금지.**
- 도구·SDK·AI 선택은 ADR 먼저(REQ-20). v1.1로 미룬 것은 삭제 금지(REQ-34).
- 머지는 Claude가 하되 PR 댓글 "머지 전 교차 확인" 5항목을 남긴 뒤(메모리 `mwonmal-merge-policy`).
- **디스크**: Xcode 빌드는 한 번에 하나만, DerivedData는 scratchpad에. 10GB 미만이면 먼저 알린다(2026-10-26 ENOSPC로 2시간 정지).

## 5. 어디에 뭐가 있나

| 궁금한 것 | 파일 |
|---|---|
| 요구사항 | `docs/REQUIREMENTS.md` |
| 왜 그렇게 정했나 | `docs/adr/0001~0022` (0021 DB 단계화·SQL 예산, 0022 앱 네트워크·캐시·실시간) |
| 면접 대비(코드 기준 Q&A) | `docs/interview/2026-10-27-ios-backend-interview.md` (+ 같은 이름 PDF) |
| 앱 구조 | ADR-0016 + `apps/ios-macos/Tuist/ProjectDescriptionHelpers/Module.swift` (12번 문서의 Coordinator 서술은 개정 전 기록) |
| 디자인 토큰·글래스 | ADR-0017, `Modules/Core/MwonmalUI/Resources/Colors.xcassets` |
| 디자인 시스템(Figma) | Figma 파일 Nid06Km1ATfAQxqgWdZ9tt 페이지 `DS · 개요 / 기초 / 커스텀 컴포넌트 / 아이콘·일러스트 / 네이티브` — 색 변수 "Mw Color" 38개×4모드(iOS 코드 문법 = MwColor.xxx), 그림자 스타일 5, 컴포넌트 16(변형 포함), 아이콘 29. 글자 스타일은 Pretendard를 원격 연결에서 못 불러 수치표만 |
| 서버·AI·비용 | `docs/design/14_시스템_설계서.md`, ADR-0015 |
| 일정 | `docs/16_실행계획.md` §0 (v3) |
| 일지 | `docs/log/2026-10-26.md` |
| 삽질 기록 | `docs/lessons/` |

## 6. 세션 재개 방법

```bash
claude --resume 3709399e-b05f-475b-94d3-f593771c009a   # 이 대화 이어가기
# 또는 새 대화에서:  /mw
```

## 6-1. 2026-10-27 한 것
- 서버 해석 API(PR #114), 앱 해석 화면 + E2E(PR #116). 레드팀 3라운드 기록 `docs/lessons/2026-10-27-decode-redteam.md`.
- 로컬 실행: `cd services/api && uv run python scripts/dev_server.py --fresh` → 앱 Debug 실행 인자 `-MWDevLogin <이름>`(+ `-MWResetSession`).
- E2E: `xcodebuild test -scheme MwonmalE2E`(서버 켜 둔 상태).
- **DB 단계화(ADR-0021)**: v1.0 DB는 8테이블. 나머지 9개는 `services/api/migrations/staged/`. 기능을 열 때 초안을 `versions/`로 옮기고 `app/core/schema.py` `ACTIVE_TABLES`에 이름 추가. 지연 표를 쓰는 코드는 `schema.has(...)` 게이트 필수.
- **성능**: 요청당 SQL POST 6·상세 3·목록 2·할 일 2·프로젝트 3·용어 3. 측정 `uv run python scripts/bench.py`.
- **앱**: `@ViewModelState`(화면 모델 한 번만 생성), 앱 전용 URLSession(캐시·쿠키 끔), `AppSession.endSession` 한 곳에서 로그아웃 정리.
- **열린 결정**: Alamofire 전송 교체 여부 — ADR-0022는 "현행 유지, 조건 오면 전송 계층만" 권고. 사용자 최종 결정 대기.

## 7. 다음 할 일 (v1.0, 16번 §0-2)

1. **사용자 작업 D**: Apple 키(.p8) → `services/api/.env` → 실로그인(#9 닫기)
2. **Day 16~17 (infra, #26 #30)**: OCI VM + Compose prod(caddy·mysql·redis) + 배포 스크립트, 앱 `.live` 연결
3. **Gemini 키 결정**: 운영에서 `MWONMAL_AI_EXTERNAL_TEXT=1` + 키(sops)를 켤지(켜지 않으면 모두 사전 간이 해석)
4. 레드팀 Low 잔여 #115, #4 잔여(`/levels`), #99 en 스냅숏
5. Day 18~19: TestFlight·실기기 QA(SE iOS 17 + 최신 iPhone)

열린 v1.0 후속: #4 잔여, #115 레드팀 잔여. 금요일 15분 회고 → `docs/log/`.
