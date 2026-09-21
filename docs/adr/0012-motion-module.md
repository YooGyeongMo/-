# ADR-0012: 애니메이션은 `MwonmalUI/Motion`의 값 토큰 + 프리셋 스펙 + `@Entry var mwMotion` 환경 주입으로만, v1.0은 토큰 + 프리셋 3개 + `MotionLab` 최소

| 항목 | 값 |
|---|---|
| 상태 | 채택 (2026-09-21) |
| 관련 REQ | REQ-22(코어까지 튜닝 가능한 모듈, 하드코딩 금지), REQ-03, REQ-23 |
| 관련 결정 | 12번 §9 SDK 규칙 5(reduceMotion)·규칙 **10 신설**, D-3(Environment 방식), D-24(Lottie 안 씀), 05번 §3("과한 바운스 금지"), FD-10, iOS-B1, QA-3, PM S2-A·S2-B, RT-A §B #2·#12, RT-B-01 |
| 출처 | `council/S0/iOS.md` 과제 B, `council/S0/QA.md` §3, `council/S0/REDTEAM_A.md` §B |

## 1. 의도
REQ-22 "타이밍 곡선·물리·지속시간까지 손댈 수 있고 튜닝 가능한 모듈, 하드코딩 금지"와 05번 §3 "말풍선 한 겹씩 벗겨지는 전환 · 카드 뒤집기 · 알림 글래스 slide-down. 과한 바운스 금지"를 코드 불변식으로 만든다. SDK 규칙 2(상태·문자열 없음)와 5(`reduceMotion` 시 정지)를 어기지 않는다. 전 OS(17~26) 동일 동작을 보장한다.

## 2. 비용
- 돈: 0. 외부 라이브러리 없음.
- 시간(v1.0 범위 = **1.0일**, FD-10): 토큰 + 프리셋 3개(`cardFlip`, `decodingPulse`, `sheetPresent`) + 모디파이어 + 불변식 테스트 0.5일(S2 Day 13에 포함, PM S2-A), Catalog `MotionLab` 최소(프리셋 선택 + 슬라이더 + "Swift로 복사") 0.5일. iOS-B1 원안 3.0일(프리셋 5 + MotionLab 1.0)은 RT-B-01 재산정으로 축소. `levelStep`·`listInsert` 프리셋은 v1.1.
- 복잡도: 타입 6개(`MwSpring`, `MwCurve`, `MwTiming`, `MwStagger`, 스펙 3, `MwMotionTheme`), 파일 4개. Presentation은 `.mwCardFlip(isFlipped:)` 같은 모디파이어만 호출.
- 유지보수: 프리셋 추가 = 스펙 구조체 1개 + 모디파이어 1개 + 불변식 테스트 1줄.

## 3. 대안
| 대안 | 탈락 이유 |
|---|---|
| 뷰마다 `.animation(.spring(...))` 직접 작성 | REQ-22 위반, 튜닝 시 전수 검색 |
| Lottie/Rive 애셋 | D-24가 배제. 코어 물리(스프링)를 코드에서 못 만짐. macOS 렌더 품질 편차 |
| `Animation`만 토큰화(프리셋 없음) | 카드 뒤집기·스태거처럼 "여러 속성+순서"가 있는 모션은 결국 뷰에 로직이 남음(반쪽) |
| reduceMotion 대응을 `.environment(\.accessibilityReduceMotion, true)`로 테스트(iOS B-4 MotionLab 원안) | `accessibilityReduceMotion`은 **get-only**(Apple 문서 `var accessibilityReduceMotion: Bool { get }`, RT-A §B #12 확인) → 컴파일 불가. QA-3의 `\.mwMotion` 프로필 주입 방식 채택 |
| **토큰 + 프리셋 스펙 + `@Entry` 환경 테마 (채택)** | — |

## 4. 왜
SwiftUI 애니메이션은 `Animation` 값 하나로 곡선·물리·지속시간이 다 표현되고 `.spring(response:dampingFraction:blendDuration:)`·`.smooth/.snappy/.bouncy`가 iOS 13부터 있으므로(Apple 문서, RT-A §B #2 확인) **값 타입 스펙 → `Animation` 변환 함수**만 SDK가 소유하면 REQ-22의 "코어까지 손댈 수 있음"이 충족된다. 프리셋을 `Hashable & Codable` 구조체로 두면 Catalog 슬라이더 → Swift 리터럴 복사가 자연스럽고, 환경 주입은 D-3의 "Environment 방식(값만)"과 같은 규칙이라 예외가 없다. `@Entry`는 iOS 13+ back-deploy(ADR-0005)라 폴백 불필요. `PhaseAnimator`·`KeyframeAnimator`·`withAnimation(completionCriteria:)`·`.symbolEffect(.pulse)`·`.sensoryFeedback`은 전부 iOS 17 / macOS 14(확인)라 최소 OS 안. 18·26 신규(`.wiggle`, `.drawOn`, `navigationTransition(.zoom)`)는 Motion 토큰이 아니라 `MwonmalUI/Compat`의 선택적 장식으로 분리한다.

### 4-1. 타입(iOS-B1 §B-1 채택, v1.0 부분)
- `MwSpring(response, dampingFraction, blendDuration)` — 기본 토큰 `paper`(0.38/0.86), `snappy`(0.26/0.92), `soft`(0.55/0.95). 05번 "과한 바운스 금지" → 기본 토큰은 `dampingFraction ≥ 0.8`.
- `MwCurve` = `linear | easeIn | easeOut | easeInOut | spring(MwSpring)`.
- `MwTiming(curve, duration, delay)` — `instant`, `quick`(0.16), `standard`(0.24), `paper`, `snappy`, `soft`. `animation(reduceMotion:)`: reduceMotion이면 `easeInOut(≤ 0.15s)`, delay 0, 스프링 없음.
- `MwStagger(interval, maxItems, cap)` — v1.1 `listInsert`·`levelStep`용. 타입은 v1.0에 두되 프리셋은 v1.1.
- 프리셋 스펙(v1.0 3개): `MwCardFlipSpec`(timing `.paper`, perspective 0.55, liftScale 1.03, reducedTiming `.standard`), `MwDecodingPulseSpec`(period 1.4, opacity/scale phases), `MwSheetPresentSpec`(timing `.soft`, edge, dimOpacity 0.28, travel 24 — **앱이 그리는 오버레이 전용**, 시스템 `.sheet` 아님).
- `MwMotionTheme`(프리셋 묶음, `Codable`) + `extension EnvironmentValues { @Entry public var mwMotion: MwMotionTheme = .default }`. `MwMotionTheme.reduced` 프로필(QA-3)을 Composition이 시스템 `accessibilityReduceMotion`을 읽어 주입.
- 표면 API: `.mwCardFlip(isFlipped:)`, `.mwDecodingPulse(isActive:)`, `.mwSheetTransition()`, `.mwMotionTheme(_:)`. v1.1: `.mwListInsert(index:)`, `.mwLevelStep(index:isCurrent:isReached:)`.
- 모든 모디파이어의 내부 `@State`는 애니메이션 위상만(SDK 규칙 2 각주). 비즈니스 상태 없음.

### 4-2. reduceMotion(SDK 규칙 5 구체화)
| 프리셋 | 기본 | reduced |
|---|---|---|
| cardFlip | 3D 회전 + 들림 | 회전 없음, 0.15s 크로스페이드 |
| decodingPulse | 맥동 | 정지 + `ProgressView`(라벨은 앱이 전달) |
| sheetPresent | 슬라이드 + 딤 | 페이드만 |

## 5. 영향 파일·문서
- `Modules/MwonmalUI/Sources/Motion/{MwMotionTokens.swift, MwMotionPresets.swift, MwMotion+View.swift, MotionProfile.swift}`, `MwonmalUICatalog/MotionLab`.
- `.swiftlint.yml`: `no_inline_animation_literal`(FD-10 이름; QA `hardcoded_animation` 정규식 채택 — `Presentation/`·`MwonmalUI/Sources/` 중 `Motion/` 제외에서 `withAnimation(.spring…)`·`.animation(.easeInOut…)`·`duration: <숫자>` 금지, `disable_without_reason` 동반).
- 12번 §9 트리에 `Motion/`, SDK 규칙 10 신설("애니메이션 수치는 `MwonmalUI/Motion` 토큰만"), 규칙 5·6에 "테스트 주입 경로(`\.mwMotion`)" 한 줄, §16 단계 0 게이트에 "Motion 토큰 + MotionLab".
- 05번 §3 "모션" 행에 토큰 이름 병기(`paper`, `snappy`, `soft`).
- 이슈 #13(+Motion 코어 0.5), #22·#23(ReviewCard·LevelStairs·StreakBadge에 토큰만 — 체크리스트 항목).

## 6. 검증
- Swift Testing 파라미터 테스트: 기본 테마 전 프리셋 `dampingFraction ≥ 0.8`, `response ≤ 0.8`, `duration ≤ 0.6`, `stagger.delay(for: 100) ≤ cap`, `delay(for:)` 단조 증가, reduceMotion 변환 결과에 `.spring` 없음·delay 0.
- Codable 왕복 1건. 진행률 순수 함수(`MwCardFlipSpec.angle(at:)` 0·0.5·1).
- 스냅샷 **끝 상태만**: `isFlipped` false/true × `mwMotion` `.standard/.reduced`, decodingPulse active/inactive. `UIView.setAnimationsEnabled(false)` / `Transaction(animation: nil)`. 중간 프레임 스냅샷은 하지 않는다(플레이키).
- 린트 `no_inline_animation_literal` 0건(S1까지 warning, S2 Day 13부터 error). 릴리스 체크 A-14.
- Catalog 수동: MotionLab에서 3 프리셋 × reduceMotion 토글, 실기기 60/120Hz 육안(S6).

## 7. 리스크와 되돌리는 조건
- 리스크: 시스템이 소유하는 전환(`.sheet`, `NavigationStack` push, `TabView`)은 타이밍을 못 바꾼다 → `sheetPresent`는 앱 오버레이(클립보드 배너, 준비 중 카드)에만 적용하고 문서에 명시. 규칙이 컴포넌트 작성 속도를 늦추면(하루 disable 주석 5개 이상) 해당 규칙만 warning으로 강등하고 토큰 보강.
- 되돌리는 조건: 프리셋이 15개를 넘거나 디자이너가 애셋 기반 모션을 요구하면 Rive 검토(Lottie 아님).
