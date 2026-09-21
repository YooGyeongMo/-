# 요구사항 대장 (REQ Registry)

> 이 파일은 잊으면 안 되는 것의 단일 목록이다. 모든 이슈·PR·ADR은 여기 ID(`REQ-xx`)를 참조한다.
> 상태: 확정 / 협의 중 / 폐기. 바뀌면 줄을 지우지 않고 상태와 날짜를 바꾼다. "왜"가 없는 요구사항은 등록하지 않는다.
> 2026-09-21 협의체 1차 세션(`docs/council/S0.md`) 결과로 상태·영향 칸을 갱신했다. 기존 행은 지우지 않았다. 사용자 지시: **"하나도 빠짐없이 기억하고 기록"** — v1.1로 이관한 것은 F절에 전부 남긴다(REQ-34).

## A. 제품·플랫폼
| ID | 요구사항 | 왜 (사용자 의도) | 상태 | 영향 결정 |
|---|---|---|---|---|
| REQ-01 | 앱은 **iPhone, iPad, macOS** 세 폼팩터. iPad는 macOS와 같은 넓은 레이아웃(사이드바·세 열), iPhone은 세로 접기 | 회의실에서 iPad, 자리에서 Mac, 이동 중 iPhone | 확정 2026-09-19 → 결정 2026-09-21 | D-0 수정, D-2 확장(iPad = 넓은 화면) → **ADR-0006**(분기 축 = `h == .regular && v == .regular`, 루트 2벌 `AdaptiveRoot`는 Navigation 모듈, `sidebarAdaptable` 미사용) |
| REQ-02 | 최소 지원 **iOS 17 / iPadOS 17 / macOS 14**. iOS 26 전용 기능은 `@available` 게이트 + 폴백 | 도달 범위. "다 대비해" | 확정 2026-09-19 → 결정 2026-09-21 | 15번 T-C2 **폐기** → **ADR-0005**(전 타깃 17.0/14.0, 게이트 3곳 Platform·MwonmalUI/Compat·Composition, 린트 `no_available_in_core`, 폴백 7개 표, `@Entry`는 13+ 정정). Domain만 watchOS 10.0(ADR-0010) |
| REQ-03 | UI는 가장 작은 화면(iPhone SE 4.7")부터 가장 큰 화면(Mac 6K, iPad 13")까지 대응. 고정 px 금지 | 모든 기기 | 확정 → 결정 2026-09-21 | SDK 규칙 6 확장 → **ADR-0006**(`minHeight`, `ViewThatFits`, 읽기 폭 680, Mac 최소 창 1000×700, 린트 `no_fixed_height`). 스냅샷 매트릭스 → **ADR-0011** |
| REQ-04 | 알림은 이후 **watchOS**에도 붙인다. 지금부터 알림 payload·딥링크·복습 카드 모델을 워치가 쓸 수 있게 설계 | 손목에서 퇴근길 복습 알림 | 확정(설계만 v1, 구현 v2) → **설계 완료 2026-09-21(ADR-0010)** | `contracts/push-payload.schema.json`(`aps` + `mw`, `deepLink` 유일 계약, body에 원문·할 일 문장 없음), `DeepLink`·`StreakStatus`는 Domain, Domain watchOS 데스티네이션, 워치 v1 앱 없음(포워딩) |
| REQ-05 | 웹 브라우저 클라이언트는 v1 범위 밖(계약은 유지) | 한 스택 | 확정 | D-0 |

## B. AI (핵심 기능 "해석하기")
| ID | 요구사항 | 왜 | 상태 | 영향 |
|---|---|---|---|---|
| REQ-10 | 해석 엔진 후보를 **전부** 비교한다: ① 외부 API(OpenAI, Gemini, Claude) ② 온디바이스 Apple Foundation Models(iOS 26+) ③ 로컬 LLM **Apple MLX**(Mac, 4B~8B 양자화) ④ 자체 소형 모델(Karpathy식 nanoGPT/파인튜닝 sLLM) | 최고 성능과 BM을 둘 다 잡기 위해 선택지를 닫지 않는다 | 확정 → 결정 2026-09-21 | 14번 §15 재작성 → **ADR-0007**(평가셋 200문장 합성, S2 1.5일 타임박스 4행 측정, Foundation Models 진입 조건 = Mac·iPhone 26 실기 둘 다 서버 최고의 80% & p50 ≤ 3s → 미리보기 엔진, 아니면 v1.1; MLX 실험 플래그; nanoGPT 1일 실험, LoRA S4 이후) |
| REQ-11 | 테스트·개발 단계는 **무료 티어만**(Gemini 무료, OpenAI·Claude는 사용자 제공 키, 크레딧 없으면 무료 모델). 유료 결제 없음 | 비용 0으로 검증 | 확정 → 해석 확정 2026-09-21 | 라우터 설정, 키 관리 → **ADR-0008**. 각주: (1) Gemini 무료 티어는 입력을 제품 개선·인간 검토에 쓰며 기밀 제출 금지(약관, ADR-0008 부록 A) → 실사용자 원문은 옵트인만. (2) "사용자 제공 키" = **평가셋 전용 운영자 키**(prod 사슬 제외). 최종 사용자 BYOK는 v1.2 이후 |
| REQ-12 | 배포 시 성능(품질·지연)과 **BM**(MAU당 원가)을 같이 고려한 라우팅 | 서비스 유지 가능성 | 확정 → 결정 2026-09-21 | 비용 모델 REQ-13 → **ADR-0007** 점수표 "원가/건" 열 + **ADR-0009**("무료 한도 소진 MAU"가 첫 유료 전환 지표). BM 가설은 `docs/bm/early-strategy.md` |
| REQ-13 | **MAU당 월 비용을 자동 산정**하는 계산기(입력: MAU, 1인당 해석·녹음·복습 수, 모델 단가 → 출력: 월 원가, 손익분기 가격). 코드로, 수치는 측정값 갱신 | "예측 돈 한 달에 MAU마다 얼마" | 확정 → 결정 2026-09-21 | `eval/cost_model.py`(루트, 표준 라이브러리만, `pricing.toml`·`usage.toml`) + Grafana `usage_daily` 패널 → **ADR-0009**. 실측 `eval/measured/`는 비공개 |
| REQ-14 | 검수된 사전이 AI보다 우선, 인덱스는 서버 재계산, 원문은 SDK로 안 나감 | 품질·기밀 | 확정(기존) → 확장 해석 2026-09-21 | 14번 §5-1, 12번 §10 → 온디바이스 결과는 정본이 될 수 없음(ADR-0007), 외부 AI·STT·APNs body·백업까지 확장(**ADR-0008**·ADR-0010, REQ-33) |

## C. 엔지니어링 원칙
| ID | 요구사항 | 왜 | 상태 | 영향 |
|---|---|---|---|---|
| REQ-20 | 모든 도구·SDK·라이브러리·AI 선택은 **의도 → 비용 → 대안 → 왜** 순서로 먼저 적고 나서 쓴다. 코드보다 문서가 먼저 | 취업 시 설명 가능해야, 나중에 Git Wiki | 확정 (최우선) | ADR 필수, PR 템플릿 "의도" 항목. 협의체 7항목 형식(의도→비용→대안≥2→왜→영향→검증→리스크·되돌림), 형식 미달 결정은 무효(`docs/council/README.md`). ADR-0005~0012는 이 순서 |
| REQ-21 | 트레이드오프와 배운 점을 매번 기록(ADR + `docs/lessons/`) → Git Wiki로 이관 | 포트폴리오 | 확정 | 16번 §2. `docs/lessons/YYYY-MM-DD-*.md` 스프린트마다 ≥ 1(첫 파일 `2026-09-21-council-first-session.md`), Wiki 이관은 S6 |
| REQ-22 | 애니메이션은 코어(타이밍 곡선·물리·지속시간)까지 손댈 수 있고 튜닝 가능한 **모듈**(`MwonmalUI/Motion`)로. 하드코딩 금지 | 디자인 품질 통제 | 확정 → 결정 2026-09-21 | SDK 컴포넌트 → **ADR-0012**(값 토큰 + 프리셋 스펙 + `@Entry var mwMotion`, v1.0 = 토큰 + 프리셋 3 + MotionLab 최소, 린트 `no_inline_animation_literal`) |
| REQ-23 | 구현 전 Swift/Apple 공식 API를 먼저 찾고(문서 MCP), 있는 것을 쓴다. 최적화가 필요해지면 **사용자에게 먼저 말한다** | 바퀴 재발명 금지 | 확정 | 16번 §1-3. 적용 사례: 창 폭 임계값 대신 사이즈 클래스(ADR-0006), 자체 YAML 파서 대신 `tomllib`(ADR-0009) |
| REQ-24 | 구조·흐름·결정은 **archify 그림**으로 기록(`docs/diagrams/`) | 시각화로 이해 | 확정 | 이슈마다 그림 1장 이상(해당 시). 원본 `docs/diagrams/*.json`, 산출 html+png 커밋, 야간 `validate`. 1차 3장: module-graph(완료), layout-branching, ai-routing. 2차: push-payload, cost-flow |
| REQ-25 | 역할별 에이전트 협의체(PM, PO, AI, iOS, macOS·iPad, Backend, QA)가 결정을 만들고 **레드팀**이 검증한 뒤 착수 | 결정을 더 터프하게 | 확정 → 운영 규칙 확정 2026-09-21 | 매 스프린트 마지막 날 오후 + 설계 변경 + 데모 실패 시 소집. `docs/council/S{n}.md` + `S{n}-redteam.md`, 치명 0이어야 킥오프, 사람 시간 1.5h 상한, 2회 초과 시 격주(그때 이 칸 갱신). 규칙: `docs/council/README.md`. 1차 세션 = `S0.md` |
| REQ-26 | 반복되는 것은 모듈·SDK로, Tuist로 강제 | 재사용 | 확정(기존) | ADR-0001(2026-09-21 개정: Domain watchOS) |
| REQ-27 | 커밋에 AI 공동 저자 표기 없음, 시크릿·개인정보 커밋 금지(공개 저장소) | | 확정 | gitleaks. 공개 저장소 전제로 CI 무료(ADR-0011), 실측 usage 비공개(ADR-0009) |

## D. 운영·비용
| ID | 요구사항 | 왜 | 상태 | 영향 |
|---|---|---|---|---|
| REQ-30 | 무중단 CI/CD(블루·그린), GitHub Projects 스프린트·마일스톤·일별 이슈, 릴리스 노트 자동 | | 확정 | ADR-0002·0003. 러너 전략은 **ADR-0011**(PR hosted `macos-26` Xcode 26.4, self-hosted는 main·schedule·dispatch만). 보드는 REQ-35 |
| REQ-31 | Sentry(깨짐·지연)와 Amplitude(사용·리텐션)의 목적을 분리하고, 붙이는 이유·비용·PII 정책을 먼저 적는다 | | 확정 → 범위 조정 2026-09-21 | 16번 §1-2. v1.0: Amplitude 이벤트 15 → 6(PO §4-2 5개 + 옵트아웃), autocapture OFF, Sentry 성능 트랜잭션 제거·첨부 OFF(ADR-0008), 대시보드 4 → 2. 원복은 F절 |
| REQ-32 | 클라우드는 무료 티어 우선(OCI Free, AWS 무료 12개월, R2), Terraform | | 확정 → 범위 조정 2026-09-21 | 14번 §14. v1.0 prod = **OCI Always Free만**, Terraform은 OCI만. AWS prod는 v1.1(F절). 초과 시 다음 컷 1순위가 Terraform(→ 수동 cloud-init) |
| **REQ-33** | **실사용자 원문·오디오의 외부 전송 정책**: 외부 AI(무료 Gemini)에 실사용자 텍스트를 보내는 것은 앱에서 고지문을 읽고 **옵트인**한 사용자만(서버 기본 `AI_EXTERNAL_TEXT=off`, 헤더 `X-Mw-AI-Consent: 1`). 미동의는 사전·규칙 "간이 해석". 오디오는 서버 `whisper_local`만, 외부 STT 0. 운영자 유료 키는 prod 사슬에 없음 | 무료 티어 약관("기밀 제출 금지·개선에 사용·인간 검토")과 REQ-14의 충돌을 사용자 결정 "A"로 닫음 | **확정 2026-09-21** | **ADR-0008**, 12번 §12 "AI 제공자" 열, 서버 설정·assert·카나리 테스트, App Privacy 라벨, 계약 v1.1 `User.aiConsent`. 베타 ≤ 50명 |
| **REQ-34** | **v1.1 이관 목록은 삭제 금지, 상태로만 관리.** 컷된 항목은 이 파일 F절과 이슈(`sprint:v1.1` 라벨, 마일스톤 해제)에 "v1.1" 상태로 남긴다. 닫지 않는다 | 사용자: "하나도 빠짐없이 기억하고 기록" | **확정 2026-09-21** | F절, PM 이슈 변경표, GitHub Project #2 뷰 |
| **REQ-35** | **GitHub Project #2 = 단일 작업 보드**(https://github.com/users/YooGyeongMo/projects/2). 칸반·스프린트·로드맵 뷰. 모든 이슈(v1.1 이관 포함)는 보드에 있어야 한다 | 사용자: 시각화 세팅 | **확정 2026-09-21** | 16번 §2-1 프로젝트 필드(Status/Sprint/Area/Size/Day), 이슈 템플릿, PM이 세션 당일 `gh`로 반영 |

## E. 재결정 완료 (REQ 변경으로 흔들린 기존 결정 → 2026-09-21 협의체 1차 세션에서 결정)
| 기존 결정 | 흔든 REQ | 결정(ADR) | 요지 |
|---|---|---|---|
| 15번 T-C2 "iOS 26 only" | REQ-02 | **ADR-0005** (FD-1) | 폐기. 17.0/14.0, 게이트 3곳, 폴백 7개. SpeechAnalyzer 미리보기·Foundation Models(조건부)·`sidebarAdaptable`은 v1.0 미사용, `@Entry`는 back-deploy라 폴백 불필요. 스냅샷 Tier1/Tier2 |
| 12번 D-0 "웹 → macOS" | REQ-01 | **ADR-0006** (FD-2) | 분기 축 `h == .regular && v == .regular`, 루트 2벌(Navigation `AdaptiveRoot`), iPad 멀티태스킹은 사이즈 클래스가 유일한 진실, 창 폭 하드코딩 금지 |
| 14번 §15 AI 라우터 | REQ-10~13 | **ADR-0007**·**ADR-0009** (FD-5·6·7) | 평가셋 → 라우터 → 온디바이스 순서 유지, 4트랙 S2 측정, 서버 2사슬 라우터, `aiModel` 규약, 비용 모델 TOML |
| 12번 D-19 알림 | REQ-04 | **ADR-0010** (FD-3) | `aps` + `mw` 단일 스키마, `deepLink` 유일 계약, macOS 로컬 알림은 v1.1, Domain watchOS |
| 12번 §9 SDK 규칙 6 Dynamic Type | REQ-03 | **ADR-0006**·**ADR-0011** (FD-2·9) | 규칙표 6-1~6-11, 린트, 스냅샷 매트릭스(PR Tier1 / 야간 Tier2) |
| ADR-0002 §러너 | REQ-27·30 | **ADR-0011** (FD-9) | PR hosted `macos-26` Xcode 26.4, self-hosted는 main·schedule·dispatch만 |
| REQ-11 "사용자 제공 키"·무료 티어 원문 | REQ-11·14 | **ADR-0008** (FD-4), REQ-33 | 옵트인만 외부 AI, 오디오 외부 0, 키 = 평가 전용 |
| REQ-22 Motion | REQ-22 | **ADR-0012** (FD-10) | 토큰 + 프리셋 3 + MotionLab 최소 |
| PM 재산정(RT-B-01) | 일정 | FD-8 (합산표 1장은 PM이 재작성 예정) | 9/22~11/6 평일 34일, 공휴일 전부 근무(사용자), v1.0 버퍼 0. 초과 시 다음 컷: Terraform → 오답 규칙 문구 간소화 → Mac XCUITest 접근성 감사만 |

## F. v1.1 이관 목록 (FD-8, 사용자 승인 컷 — 삭제 금지, REQ-34)
> 사용자 지시 원문: 범위 컷 승인, 단 **"하나도 빠짐없이 기억하고 기록"** + GitHub Project #2 시각화 세팅. 아래 항목은 이슈를 닫지 않고 `sprint:v1.1` 라벨 + 마일스톤 해제로 보드에 남긴다. 이슈 번호는 2026-09-21 반영(#62~#81 v1.1 백로그, #61 v1.0.1).

| # | 항목 | 원래 결정 ID | 이관 이유 | 되살리는 조건 | 이슈 번호 |
|---|---|---|---|---|---|
| F-1 | Vision OCR(이미지 → 텍스트, W-01 드롭·스크린샷) | 12번 D-6, T-D2 | 붙여넣기 + 클립보드 감지가 가치 70%(T-D2). 절약 0.5일 → `eval/run.py` 어댑터 자리 | S2 말 누적 지연 0이면 Day 14에 복귀. 아니면 v1.1 첫 이슈 | #62 |
| F-2 | SpeechAnalyzer 실시간 받아쓰기 미리보기(iOS 26) | 12번 D-7, 15번 T-D3 | 17~25 사용자는 어차피 못 봄, D-7상 진실은 서버 transcript. 미리보기 자체가 v1.1(구현체 0 + "받아쓰기 준비 중"). 절약 1.0일 | v1.1 착수 시 iOS 26 게이트로 구현체 1개. `SFSpeechRecognizer` 폴백은 ko-KR 온디바이스 확인 후 별도 판단 | #63 |
| F-3 | 라이브 액티비티(녹음 중 잠금화면) | 15번 T-D1 | 백그라운드 audio 모드 + 인앱 ● 표시로 녹음은 계속됨. 절약 0.5일. `NSSupportsLiveActivities` Info.plist도 v1.1 | 심사에서 "녹음 중 표시" 요구 시 즉시 복귀(iPad도 16.1+ 확인됨) | #64 |
| F-4 | `@SceneStorage` 씬 복원(`paths`·`selectedTab`·사이드바 가시성) | 12번 §8 | 절약 0.5일. `NavigationSplitViewVisibility`는 `RawRepresentable`이 아니라 String(JSON) 래퍼 필요(RT-A-10). v1.0은 `TabCoordinator` `@State`(창 수명)로 충분 | v1.1에서 String 래퍼로 구현 | #65 |
| F-5 | macOS 로컬 알림(할 일 마감 30분 전 `UNCalendarNotificationTrigger`) | 12번 D-19 | 계약 v1.1 `MACOS` 등록과 함께 APNs로 한 번에. 절약 0.5일 | 계약 v1.1 배포 시 APNs `MACOS`로 대체(로컬 알림 자체는 되살리지 않음) | #66 |
| F-6 | AWS prod(t4g.small 12개월 무료) + Terraform AWS 모듈 | REQ-32, 14번 §14 | v1.0 prod = OCI Always Free(0원). Terraform은 OCI만. 절약 0.5일 | OCI A1 CPU가 STT·해석 부하를 못 버티면(14번 §12 확장 트리거) | #67 |
| F-7 | 퀴즈 오답 AI 생성(Flash-Lite 캐시) | 14번 §15 표 "실력 테스트 오답" | 규칙(사전 다른 뜻 섞기)을 1순위로. 무료 한도 절약 부수효과. 절약 0.5일 | 규칙 오답의 정답률 편차(너무 쉬움)가 Amplitude `quiz_finished`에서 확인되면 | #68 |
| F-8 | Amplitude 이벤트 15 → 6(PO §4-2 5개 + 옵트아웃) | 12번 §10, REQ-31 | 절약 0.75일(Sentry 포함). 비용 입력은 DB가 진실이라 무사 | v1.1 대시보드 5개 복원 시 나머지 9개 | #69 |
| F-9 | Sentry 성능 트랜잭션 4개 제거(크래시 + 에러만) | 16번 §1-2 | 위와 같음 | p95 지연 대시보드가 필요해지면 `tracesSampleRate 0.1`로 | #69 |
| F-10 | 관측 대시보드 4 → 2(크래시율·p95) | 16번 §3 Day 30 | 절약 0.25일 | v1.1 | #69 |
| F-11 | Maestro E2E 4흐름 → 2흐름(로그인→해석, 녹음→결과) | 16번 §1-1 | 절약 0.5일 | v1.1에 복습·테스트 흐름 추가 | #70 |
| F-12 | macOS XCUITest 2흐름(사이드바·메뉴·드롭) → 접근성 감사만 | 16번 §1-1, PM S6 ② | 절약 0.5일. 다음 컷 3순위는 "접근성 감사만"으로 더 축소 | v1.1 | #70 |
| F-13 | iPad 카메라 OCR(촬영 → Vision, `NSCameraUsageDescription`) | macOS_iPad MI-4 (신규 제안) | 신규 기능·권한 문구·심사 변수(U-12). F-1과 같은 파이프라인 | F-1과 함께 v1.1 | #62 |
| F-14 | Liquid Glass(`glassEffect`, 플로팅 탭바, 05번 `.modal`·사이드바 글래스) | 05번 §4.1, iOS A-4 #12 | v1.0은 머티리얼 통일(스냅샷 두 벌 회피, 라이트 고정 D-23과 정합). U-13 | v1.1 D-23 다크와 함께 재검토 | #71 |
| F-15 | Foundation Models 온디바이스(FD-5 진입 조건 미통과 시) | REQ-10 ②, AI-5 | Mac·iPhone 26 실기 둘 다 80% & p50 ≤ 3s 미달이면 사용자 경로 없음, `eval/` 점수표만 | 조건 통과 시 v1.0 미리보기 엔진(ADR-0007 §8에 판정 기록). v1.1 `clientHints`/`engineHint`·사전 스냅샷 op와 함께 분업 | #72 |
| F-16 | MLX 프로덕션(macOS 로컬 엔진) | REQ-10 ③, AI-6 | v1.0은 숨은 실험 플래그·점수표만. MAS 샌드박스·모델 다운로드 정책 확인 필요 | 점수표 ③ 행이 게이트 통과 + MAS 정책 확인 후 별도 ADR | #73 |
| F-17 | k6 부하 테스트 반복·복구 연습 런북 → S6 1회만 | 16번 §1-1, PM S6 ③ | 출시 필수 아님. S6에 1시나리오(해석 30rps, AI 스텁) 1회 | v1.1 정기화 | #78 |
| F-18 | Motion 프리셋 `levelStep`·`listInsert`, MotionLab 전체(슬라이더 8종·JSON 복사) | iOS-B1, FD-10 | v1.0 = 토큰 + 프리셋 3 + MotionLab 최소(1.0일) | S4 LevelStairs 구현 시 `levelStep`부터 | #74 |
| F-19 | `SFSpeechRecognizer` 폴백(17~25 미리보기, `requiresOnDeviceRecognition`) | iOS A-4 #1 | v1.0 안 함(MI-5). ko-KR 온디바이스 지원 확인 필요, +1.0일 | F-2와 함께, 실기기 `supportsOnDeviceRecognition` 확인 후 | #63 |
| F-20 | 사용자 일 한도 429 `TOO_MANY_REQUESTS`, `STT_UNAVAILABLE` 코드 | Backend B-4·B-5 #14 | 계약 v1.0 `Error.code`에 없음(RT-A-17). v1.0은 30/분 + 503 | 계약 v1.1 | #75 |
| F-21 | 계약 v1.1 통합 백로그 15건 + `User.aiConsent` + `engine` 객체 + `PushPayload` + `plan`(FREE\|PRO) | Backend B-5, FD-7·11, ADR-0008·0010 | v1.0 계약은 제출본. 전부 하위 호환 추가만 | S5 Day 30 초안 PR | #75 |
| F-22 | 최종 사용자 BYOK(OpenAI·Claude 키) | REQ-11 해석, AI-2 | 시크릿 저장·삭제 API·약관 필요 → **v1.2 이후** | 기업 고객 문의 발생 시 | #77 |
| F-23 | 외부 STT(Groq Whisper·Gemini 오디오) | Backend B-4 | 약관 미확인. ADR-0008 부록에 첨부 전엔 어떤 사슬에도 없음 | 약관 확인·첨부 + 협의체 승인 | #76 |
| F-24 | 워치 앱(복습 카드 4버튼)·컴플리케이션·WatchConnectivity | 15번 T-D4, MN-4 | **v2**. 화면 설계 없음, refresh 토큰 전제 | 포워딩 알림에서 액션이 안 뜨면 v1.1에 알림 인터페이스만 최소 | #81 |
| F-25 | 잠금화면 할 일 문장 미리보기(ACTION_DUE body) | Backend B-3, U-10 | v1.0 body = "할 일 1건 마감 30분 전" | v1.1 사용자 옵트인 설정 | #75 |
| F-26 | 오늘 복습 위젯(iOS) | 15번 T-D4 | 기존 v1.1 유지 | v1.1 | #79 |
| F-27 | macOS TestFlight → 11/13(`app/v1.0.1`) 분리 (v1.1이 아니라 **릴리스 분리**) | PM-4, U-4 | S6 1.0일 확보. 11/6 = iOS·iPad TestFlight + 서버 v1.0. 커밋 해시 동일 증명. App Store 제출은 `DELETE /users/me`(v1.1) 이후 | S5까지 여유 1.0일 이상이면 11/6 동시 배포로 복귀 | #61 |

**유지(컷 안 함, 사용자 결정)**: 카카오 로그인 v1.0(PM 다음 컷 1순위였으나 사용자 결정 (3)으로 유지).
