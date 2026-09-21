# 협의체 1차 세션 레드팀 판정 요약 — 2026-09-19 판정, 2026-09-21 해소

> 원문: `S0/REDTEAM_A.md`(기술 타당성·아키텍처, Apple 문서 재검증) · `S0/REDTEAM_B.md`(일정·비용·프라이버시·운영, 계산기 직접 실행). 등급 기준은 PM §5 표(= `README.md` §5). 해소 방법의 FD는 `S0.md` §5, ADR은 `docs/adr/`.

## 1. 등급별 개수
| 레드팀 | 치명 | 중요 | 경미 | 착수 판정(당시) |
|---|---|---|---|---|
| A | 3 (RT-A-01~03) | 13 (RT-A-04~16) | 8 (RT-A-17~24) | 조건부 불가 — S0 Day 2~5는 착수 가능, Day 11·14·18은 치명 해소 전 불가 |
| B | 5 (RT-B-01·02·10·11·12) | 14 (RT-B-03~09·13~19) | 8 (RT-B-20~27) | 불가(치명 5) — S0 뼈대 3일만 조건부 착수 |
| 합 | **8**(중복 제외 5 주제) | 27 | 16 | **2026-09-21 사용자 결정 4건 + FD-1~14로 치명 0 → 킥오프** |

## 2. 치명 항목 전부와 해소
| ID | 문제(한 줄) | 해소 |
|---|---|---|
| RT-A-01 / RT-B-10 | 무료 Gemini에 실사용자 원문을 보내는지가 세 파트에서 세 상태이고 Backend 기본 사슬은 이미 "보낸다". AI가 확인한 약관("기밀 제출 금지·개선에 사용·인간 검토")을 PO는 미확인으로 되돌리고 PM은 Day 11 1순위로 | **FD-4 / ADR-0008**: 사용자 결정 "A". 서버 기본 `AI_EXTERNAL_TEXT=off`, 옵트인 헤더 `X-Mw-AI-Consent: 1`만 외부 AI, 미동의는 `none` 간이 해석. 12번 §12 "AI 제공자" 열. 약관 인용·URL·확인일 부록. REQ-33 신설 |
| RT-A-02 / RT-B-02(FM 행) | 온디바이스 Foundation Models가 v1.0 사용자 경로에 있는지가 AI(포함)·iOS·PM(미포함)에서 다르고, AI-2의 "오프라인 임시 해석"은 사전 우선·인덱스 재계산(REQ-14)을 만족 못 함(앱은 사전 전체가 없음) | **FD-5 / ADR-0007 §4-3**: 사용자 결정 (1) → 진입 조건(Mac·iPhone 26 실기 둘 다 서버 최고의 80% & p50 ≤ 3s) 통과 시 **미리보기 엔진만**(정본은 항상 서버), 오프라인 임시 해석 없음. 미통과면 v1.1(F-15). `clientHints`는 v1.1 |
| RT-A-03 / RT-B-19 | `contracts/push-payload.json` 하나에 스키마 3개(MN-1 중첩 `mw`, Backend 평면, PO 평면), ACTION_DUE body에 `action_text`, `interruption-level` 불일치 | **FD-3 / ADR-0010**: MN-1 채택(`aps` + `mw` + `deepLink` 필수), JSON Schema + 픽스처 4개 단일 파일. body는 제목·개수만(사용자 U-10), `time-sensitive` v1.1 |
| RT-B-01 | 파트 메모 v1.0 작업량 합(≈ 28~31일)이 PM 견적(+10.5일)의 2.5배 | **FD-8**: 사용자 승인 컷(F절 27항목). PM이 파트별 Day 매핑 합산표 1장을 재작성해 "순증 ≤ 감축" 증명(다음 세션 입력). 초과 시 다음 컷 순서 확정 |
| RT-B-02 | FM·17~25 받아쓰기 미리보기·OCR의 v1.0 포함 여부가 파트마다 반대 | **FD-1·5·8**: FM 조건부(위), SpeechAnalyzer 미리보기 v1.1(구현체 0 + "준비 중"), `SFSpeechRecognizer` 폴백 v1.0 안 함, Vision OCR·iPad 카메라 OCR v1.1 |
| RT-B-11 | 회의 오디오 전체를 Groq(약관 미확인)·Gemini 오디오로 보내는 설계 | **FD-4 / ADR-0008**: 오디오는 서버 `whisper_local`만. 외부 STT는 약관 확인 결과를 부록에 첨부하기 전엔 어떤 사슬에도 없음(F-23) |
| RT-B-12 / RT-A-12 | "사용자 제공 키"가 세 뜻(운영자 `.env` / 최종 사용자 BYOK / 평가 전용). Backend는 운영자 유료 키를 prod 1순위 = 결제 발생 경로 | **FD-4 / ADR-0008**: 평가셋 전용 운영자 키로 확정(U-8), prod 사슬에서 `anthropic_key`·`openai_key` 제거 + `APP_ENV=prod` 기동 assert. BYOK는 v1.2 이후(F-22) |

## 3. 중요 항목
| ID | 문제 | 해소(FD/ADR) |
|---|---|---|
| RT-A-04 / RT-B-17 | `aiModel` 규약 3개, PO 측정식이 `IS NULL`(dbml `not null`) 전제 | ADR-0007 §4-5: `{track}/{model}#p{ver}` 하나, 앱 v1.0 미파싱, `dictionary_only_rate`는 `none/` 비율 |
| RT-A-05 | 라우터 작업 단위(4작업 / 2사슬 / 4출력 1호출)가 파트마다 다름 | ADR-0007 §4-4: Backend 2사슬 고정, "분할 호출"은 실험 열 |
| RT-A-06 | 평가셋 파일·스키마·위치 네 벌, QA `TO_PLAIN`은 enum에 없음 | ADR-0007 §4-1: 루트 `eval/`, AI §2-2 스키마 하나, `direction`은 yml enum, 소유자 AI |
| RT-A-07 / RT-A-21 | 비용 계산기 두 파트 설계, 자체 YAML 파서(REQ-23 위반) | ADR-0009: PO 계산 + Backend `usage_daily` 입력, `tomllib` |
| RT-A-08 | 넓은 화면 판정 환경값 이름 3·식 3, 같은 기기에서 반대 결과 | ADR-0006: MI-1 식 채택, 폭 임계값 없음 |
| RT-A-09 | 루트 구현 개수(2 vs 3)·위치(MwonmalUI vs Composition), MwonmalUI는 Navigation import 불가 | ADR-0006: 경로 2, `AdaptiveRoot`는 Navigation, `sidebarAdaptable` 미사용 |
| RT-A-10 | `@SceneStorage` + `NavigationSplitViewVisibility`는 컴파일 불가 | ADR-0006: v1.0 `@State`, v1.1 String 래퍼(F-4) |
| RT-A-11 / RT-B-05 | PM 재산정이 파트 요구를 미반영, 스냅샷 매트릭스 4벌 | FD-8 컷 + QA 단일 소유(ADR-0011 매트릭스) |
| RT-A-13 | 오디오 → Groq 결정에 데이터 흐름·약관·REQ-20 없음 | ADR-0008(외부 STT 제외), `faster-whisper` CPU 실시간 S2 실측 |
| RT-A-14 / RT-B-23 | AI-5·6, MN-3·4, B-6 ②, QA §2-2/2-3/§4가 7항목 미달 | FD-14: ADR-0007 §4-6·4-7, ADR-0010 §4-2·4-4·4-5, QA 항목은 ADR-0007·0008·0011에 흡수 |
| RT-A-15 / RT-B-13 | 무료 호출 예산을 세 파트가 각자 잡아 합계 초과, RPD 가정 4벌(250/20/500/1,500) | ADR-0007·0008: AI Studio 캡처를 S0 Day 1 게이트로, `eval/limits.md` 단일 출처, CI 외부 호출 0, 야간만 |
| RT-A-16 | 마이그레이션 0001에 `MACOS`·`WATCHOS` 미리 포함 = dbml v1.0 변경 | ADR-0010 §4-2: 0001은 v1.0 그대로, 0002에서 append |
| RT-B-03 | Day 11 하루에 어댑터 5종 + 마이그레이션 + 통합 테스트 불가 | ADR-0007: Day 11 = `gemini_free` + `none` + 브레이커 + 레코더, 0002는 Day 12 |
| RT-B-04 | AI §7 "S0·S1 자투리" 2.5일에 자리가 없음 | ADR-0007: S0에는 한도 캡처·스키마·v0만, 나머지는 S2 이슈 |
| RT-B-06 | 사용자 답변 3건 반영 후 PM 문서 미갱신 | S0.md §4에 답변 원문, ADR-0005 대안 ②·ADR-0011 런타임 17.0 |
| RT-B-07 | v1.0 정의(양 플랫폼 TestFlight)를 PM 단독 변경 | 사용자 승인(FD-8) → F-27 |
| RT-B-08 | 무료 한도 RPD×30 월 평균화 → 소진 MAU 1.5배 과대·피크 RPM 과소 | ADR-0009: RPD × active_days + 피크 RPM 둘 다 |
| RT-B-09 | STT 원가 가정이 PO(유료 단가)·Backend(무료 사슬) 정반대 → PO-2 근거 붕괴 | ADR-0009·`docs/bm/early-strategy.md`: 가설로 강등, STT 실측 전 주의 문구 |
| RT-B-14 | 온디바이스 비율 두 번 적용 | ADR-0009: 한 번만 |
| RT-B-15 | 고정비 t4g.small 15$이 PM(OCI Free) 결정과 불일치 | ADR-0009: OCI 0원 기본, AWS 옵션 |
| RT-B-16 | Guest 호출·페르소나·피크 가정이 PRD와 불일치 | ADR-0009: `guest_translations_per_day`, 피크 2.5(근무 10h) |
| RT-B-18 | Amplitude autocapture 끄는 결정 없음 | FD-10 / ADR-0008: autocapture OFF, 야간 카나리 "버튼 라벨" 케이스 |
| RT-B-20 | self-hosted를 PR 기본으로 → fork PR 코드가 개발 Mac에서 실행 | ADR-0011: PR hosted만, self-hosted는 main·schedule·dispatch |
| RT-B-21 | hosted `macos-26` GA 등이 출처 없이 단정, Xcode 핀 26.5 ≠ 보유 26.4, 런타임 17.5 ≠ 17.0 | ADR-0011: 26.4 핀, 17.0, F-1·F-2는 "출처·확인일 필요" 표기 유지 |
| RT-B-22 | 현재 `app.yml`(`macos-15`·`latest-stable`)과 결정의 괴리, CI 변경 이슈 없음 | ADR-0011: Day 2 `[S0][infra]` 이슈 0.5일 |

경미(RT-A-17~24, RT-B-20~27 중 경미로 분류된 것): 429 코드 v1.1(F-20), Amplitude 이벤트 목록 교체(ADR-0009), Mac 창 1000×700 유지(ADR-0006), Xcode 핀(ADR-0011), LEVEL_UP 검증 3종(ADR-0010), 스토어 제출 = v1.1 이후(F-27), warnings-as-errors는 Day 3 이후(ADR-0005), Sentry 첨부 OFF·평가셋 v2 비공개·HF 텔레메트리·백업 암호화(ADR-0008).

## 4. Apple 문서 검증 결과 (REDTEAM_A §B, sosumi/developer.apple.com, 2026-09-19)
| # | 주장(파트) | 결과 | 판정 |
|---|---|---|---|
| 1 | `horizontalSizeClass` iOS 13 / macOS 10.15, macOS 항상 `.regular`(macOS_iPad) / "Mac에는 sizeClass 없음(nil)"(iOS) | 존재하며 regular | macOS_iPad **정확**, iOS.md **오류** |
| 2 | `.spring(duration:bounce:)`, `.smooth/.snappy/.bouncy` iOS 13 | iOS 13.0+ | 정확 |
| 3 | `onPasteCommand` macOS 11 전용 | macOS 11.0+만 | 정확 |
| 4 | `sidebarAdaptable` iOS 18 / macOS 15, iPadOS는 상단 탭바 | 문서 일치 | 정확 |
| 5 | `@Entry` iOS 13 back-deploy, T-C2 "17+면 손실"은 오류 | iOS 13.0+ | 정확(T-C2 정정) |
| 6 | `Generable` watchOS 27.0+ | 일치 | 정확 |
| 7 | `onGeometryChange` iOS 16 / macOS 13 | 일치 | 정확 |
| 8 | `Synchronization.Mutex` iOS 18 / macOS 15 | 일치 | 정확 |
| 9 | `PasteButton` iOS 16 / macOS 10.15 | 일치 | 정확 |
| 10 | `Settings` 씬 macOS 전용 — 확인 필요 | macOS 11.0+만 | **해소** |
| 11 | `hoverEffect` iOS 13.4+, macOS 없음 | 일치 | 정확 |
| 12 | `accessibilityReduceMotion` get-only(QA) | `{ get }` | 정확 → iOS MotionLab 환경 오버라이드 컴파일 불가, QA 주입 방식 채택 |
| 13 | `dropDestination(for:isEnabled:action:)` 최소 버전 — 확인 필요 | iOS 26.0+ | **해소**(iOS.md 정확) |
| 14 | `LanguageModelSession.GenerationError` deprecated, Xcode 27 필요 | 일치 | 정확 |
| 15 | `ASWebAuthenticationSession.Callback` iOS 17.4 / macOS 14.4 | 일치 | 정확 |
| 16 | `NavigationSplitView` iOS 16 / macOS 13 / watchOS 9, compact에서 가시성 무시 | 일치 | 정확 |
| 17 | `WKApplication.registerForRemoteNotifications()` watchOS 7, 동일 payload 하나만 표시 | 일치 | 정확 |
| 18 | `Observations` iOS 26 | 일치 | 정확 |
| 19 | `.lineHeight(_:)` iOS 26 | 일치 | 정확 |
| 20 | `TabSection`, `presentationSizing` iOS 18 / macOS 15 | 일치 | 정확 |
| 21 | `tabBarMinimizeBehavior`, `TabViewBottomAccessoryPlacement` iOS 26 | 일치 | 정확 |
| 22 | `contextSize` 26.4 이전 backDeployed | 일치 | 정확 |
| 23 | `requiresOnDeviceRecognition` iOS 13, `supportsOnDeviceRecognition` true일 때만 존중 | 일치 | 정확(게이트 필수) |
| 24 | 라이브 액티비티 iPad — 확인 필요 | iPadOS 16.1+ | **해소** |
| 25 | `performAccessibilityAudit` 최소 OS — 확인 필요 | iOS 17.0+ / macOS 14.0+, Xcode 16.3+ | **해소** |
| 26 | `@SceneStorage` + `NavigationSplitViewVisibility`(MI-2) | `RawRepresentable` 아님, `SceneStorage.init`은 RawRepresentable(Int/String) 요구 | **오류**(RT-A-10) |
| 27 | `SpeechAnalyzer` iOS 26 / macOS 26, watchOS 없음 | 일치 | 정확 |
| 28 | `UIPasteboard.detectPatterns` 최소 버전 | 심볼 존재 확인, 본문 미취득 | **미해소**(iOS 14 추정, 착수 전 재확인) |

**집계**: 28건 중 정확 22 · 오류 2(#1 iOS.md, #26) · 확인 필요 → 해소 4(#10·13·24·25) · 미해소 1(#28). Apple 외 주장(QA F-1/F-2/F-3, Gemini 모델·단가·약관, Groq 한도, PO 단가 전부)은 이 도구로 검증 불가 — 각 ADR에 "확인 필요"·출처·확인일로 표기.

## 5. 사용자 결정 목록(U-1~U-20)의 처리
| U | 항목 | 결정 |
|---|---|---|
| U-1·U-2 | BM(무료+구독 4,900원, 녹음 유료, 무료 30분), REQ-15 신설 | 가설로만(FD-11), REQ 신설 없음, 무료 30분은 가설 표에만 |
| U-3 | 카카오 로그인 컷 | **유지**(사용자) |
| U-4 | macOS TestFlight 11/13 분리 | 승인(F-27) |
| U-5 | v1.1 이관 8건 | 승인 + "하나도 빠짐없이"(F절 27항목) |
| U-6·U-7·U-8·U-9 | 무료 티어 실원문 / 오디오 외부 STT / 키의 뜻 / 강등 허용 | "A": 옵트인만 / 외부 0 / 평가 전용 / 강등 허용(배지) — ADR-0008 |
| U-10 | 잠금화면 할 일 문장 | 비노출(ADR-0010) |
| U-11 | Mac 최소 창 | 1000×700 유지 |
| U-12·U-13 | iPad 카메라 OCR / Liquid Glass | v1.1(F-13·F-14) |
| U-14 | Foundation Models v1.0 | 조건부(FD-5) |
| U-15 | CI 전략·Xcode 핀 | hosted `macos-26` 26.4(ADR-0011) |
| U-16·U-17 | `eval/` 위치 / Domain watchOS | 루트 / 추가 |
| U-18·U-19 | 실측 usage 공개 / 베타 상한 | 비공개 / 50명 |
| U-20 | 협의체 격주 완화 | 2회 연속 1.5h 초과 시(README §6) |
