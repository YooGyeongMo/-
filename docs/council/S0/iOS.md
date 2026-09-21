# iOS 파트장 결정서 — 협의체 1차 세션 (2026-09-19)

> 범위: 과제 A (REQ-02 iOS 17+/macOS 14+ 폴백 설계, T-C2 폐기), 과제 B (REQ-22 `MwonmalUI/Motion`), 과제 C (REQ-03 최소~최대 화면 규칙).
> 근거 문서: `docs/REQUIREMENTS.md`, `docs/design/12_앱_아키텍처_설계.md`(이하 12번), `docs/design/15_기술_트레이드오프_결정기록.md` T-C·T-D(이하 15번), `docs/design/05_디자인시스템.md`(이하 05번), `apps/ios-macos/Project.swift`, `apps/ios-macos/Tuist/Package.swift`.
> Apple API 최소 OS는 전부 `mcp__sosumi__fetchAppleDocumentation`(developer.apple.com 원문)으로 확인했고, 확인 못 한 것은 **확인 필요**로 표기했다. 저장소 파일은 수정하지 않았다.

---

## 0. 한 장 요약

1. **최소 OS = iOS 17.0 / iPadOS 17.0 / macOS 14.0.** 18·26 전용 API는 **세 곳에서만** 게이트한다: ① `Platform`(프로토콜 구현체 교체), ② `MwonmalUI/Compat`(뷰 모디파이어 내부 `#available`), ③ `Composition/AppContainer`(구현체 선택). Presentation·Domain·Navigation에는 `#available` 금지(SwiftLint로 강제).
2. 12번 v2가 쓰기로 한 API 중 **실제로 폴백이 필요한 것은 7개뿐**이다: SpeechAnalyzer(26), Foundation Models(26), `sidebarAdaptable`+`Tab`(18), Liquid Glass 계열(26), `navigationTransition(.zoom)`(18), `Synchronization.Mutex`(18), `.lineHeight`(26). 나머지(`@Entry`, `onGeometryChange`, `.spring(duration:bounce:)`, `@Observable`, `NavigationStack`, Live Activity, `scrollTargetBehavior`, `ContentUnavailableView`, `PhaseAnimator/KeyframeAnimator`, `ViewThatFits`…)는 17 이하에서 이미 된다.
3. **REQ-14 불변식이 폴백 설계를 좌우한다.** `SFSpeechRecognizer` 폴백은 `requiresOnDeviceRecognition = true`를 **강제**하고, 온디바이스가 불가하면 미리보기를 끈다(오디오가 Apple 서버로도 나가면 안 되므로). 온디바이스 해석(Foundation Models)은 v1.1이며 v1.0은 전 OS가 서버 라우터를 탄다.
4. Motion 모듈은 **값 타입 토큰 + 프리셋 스펙 + 환경 주입(`@Entry var mwMotion`)**. 애니메이션 수치를 View에 직접 쓰는 것을 SwiftLint로 막고, Catalog `MotionLab`에서 슬라이더로 튜닝해 Swift 리터럴로 복사한다.
5. 화면 규칙: **고정 높이 금지 → `minHeight`**, 버튼 행·메타 행은 `ViewThatFits`, Dynamic Type `xxxLarge`부터 카드 4블록을 세로 단일 열로, 넓은 화면은 읽기 폭 680pt 상한. 스냅샷은 Tier 1(PR: SE iOS 17, iPhone 17 iOS 26, Mac) / Tier 2(야간: iPad·6K·가로·AX3 전부).

---

## 과제 A. REQ-02 — iOS 17+/macOS 14+ 지원 폴백 설계 (T-C2 폐기)

### 결정 iOS-A1. 최소 OS는 iOS 17.0 / iPadOS 17.0 / macOS 14.0, 게이트는 세 층에서만

1. **의도**
   REQ-02("도달 범위, 다 대비해")를 만족하면서 12번의 구조(MVVM-C + Clean, 8모듈, "ViewModel에 `#if os()` 금지")를 깨지 않는다. 15번 T-C2의 "26 only" 근거였던 차별점(온디바이스 미리보기·OCR·비용 0)은 **26 기기에서는 그대로 살리고**, 17~25 기기에서는 같은 화면·같은 ViewModel로 "미리보기 없음 / 서버 해석" 상태를 보여 준다.

2. **비용**
   - 돈: 0. (무료 티어·시뮬레이터만. iOS 17 시뮬레이터 런타임 다운로드는 무료.)
   - 시간: 폴백 구현체 4개(STT, 루트 레이아웃, 글래스 서피스, 3열 분기) ≈ 3~4일. 기존 30일 계획(16번) Day 2(Tuist 그래프)·Day 19(Speech)·Day 31~(S6 스냅샷)에 흡수. 1인 기준 **+10%**.
   - 복잡도: `#available` 분기가 **세 파일군에만** 생긴다(Platform 구현체, MwonmalUI/Compat, Composition). 화면 코드에는 분기 0.
   - 유지보수: CI 시간 ×2(iOS 17·26 두 시뮬레이터). 스냅샷 파일이 OS별로 갈린다(§A-5).
   - 무료 한도: GitHub Actions hosted macOS 러너는 분당 10배 과금이라 **self-hosted Mac을 기본**(16번 ADR-0002 그대로), hosted는 폴백.

3. **대안**
   - ① **26 only 유지(T-C2)**: 폴백 0, 하지만 REQ-02 위반. 출시 첫해 미업데이트 기기·사내 관리 기기(MDM으로 업데이트 지연되는 판교 회사 다수) 배제. **탈락(REQ 위반)**.
   - ② **iOS 18 / macOS 15 최소**: `sidebarAdaptable`·`Tab`·`Mutex`·`RecognizeTextRequest`·`navigationTransition(.zoom)` 폴백이 사라져 분기가 7→3개. 그러나 REQ-02가 17을 명시했고, iPhone XS·XR 등 17까지만 받는 기기가 있다(확인 필요: 실제 iOS 18 지원 기기 목록). **탈락(REQ 명시값과 다름)**. 단, "되돌리는 조건"으로 남긴다.
   - ③ **iOS 17 / macOS 14 최소 + 세 층 게이트 (채택)**.
   - ④ iOS 16 이하: `@Observable`(17)·`PhaseAnimator`(17)·`ContentUnavailableView`(17)·`AVAudioApplication`(17)이 전부 사라져 12번 D-15 ViewModel 계약을 다시 써야 한다. **탈락(구조 비용 과대)**.

4. **왜**
   17은 `@Observable`·`#Preview`·`PhaseAnimator`·`scrollTargetBehavior`·`ContentUnavailableView`·`AVAudioApplication`이 모두 들어온 첫 버전이라, 12번이 전제한 코드 관용구(D-15 `@MainActor @Observable`, `.task(id:)`, `RouteHost`)가 **한 줄도 안 바뀐다**. 폴백이 필요한 7개는 모두 "플랫폼 서비스" 아니면 "표면 스타일"이라 Platform과 MwonmalUI 안에 가둘 수 있고, Presentation은 프로토콜과 환경 값만 본다. 그래서 REQ-02를 지키면서 12번 D-15("ViewModel에 `#if os()` 금지")의 정신을 `#available`까지 확장하는 것이 가장 싸다.

5. **영향 파일/문서**
   - 15번 T-C2: "**폐기(2026-09-19) → iOS-A1로 재결정**". J표 "iOS 26 only" 행 삭제, 리스크표 #9 삭제.
   - 12번 머리말 "기준: iOS 26 / macOS 26" → "최소 iOS 17 / macOS 14, 26 전용 기능은 게이트". §7(SpeechAnalyzer → `TranscribingService` 구현체 2개), §8 루트 뷰 문단, §9 `Layout/AdaptiveRoot` 설명, §14 "하지 않는 것"에 "Presentation·Domain·Navigation의 `#available`" 추가, §16 단계 0 게이트에 "iOS 17 시뮬레이터에서도 뜸".
   - `apps/ios-macos/Project.swift`: 전 타깃 `deploymentTargets`(§A-3).
   - `.swiftlint.yml`(16번 D-4의 custom_rules 옆): `available_only_in_gates` 규칙(§A-2).
   - 14번 §15 온디바이스 문단: "iOS 26 + Apple Intelligence 기기에서만, 아니면 서버" 명시.

6. **검증 방법**
   - `tuist generate` 후 **iPhone SE(3rd gen) iOS 17.x 시뮬레이터**와 **iPhone 17 iOS 26 시뮬레이터**에서 빈 앱이 뜬다(16번 Day 2 게이트에 추가).
   - SwiftLint `available_only_in_gates` 0건.
   - 단계 3(회의) 완료 기준에 "iOS 17 시뮬에서 녹음 → 미리보기 없음 상태 → 서버 결과 표시"를 추가.
   - 스냅샷 매트릭스 §A-5 통과.

7. **리스크와 되돌리는 조건**
   - 리스크: (a) `SFSpeechRecognizer` ko-KR 온디바이스 미지원 기기에서 미리보기가 사라져 W-02 체감이 떨어진다 → D-7이 이미 "받아쓰기 준비 중" 상태를 정의했으므로 UX 규격 내. (b) 17·26 렌더링 차이로 스냅샷 유지비 증가 → OS별 스냅샷 폴더. (c) Xcode 26에서 iOS 17 런타임 지원 여부(**확인 필요**; Xcode 16은 iOS 15+ 런타임을 지원했음) — 불가하면 CI에서 iOS 18 런타임을 최저로 쓰고 17은 실기기 수동 검증.
   - 되돌리는 조건: 출시 후 6개월 Amplitude OS 분포에서 iOS 17 < 3% **그리고** 18 전용 폴백 유지비가 스프린트당 반나절을 넘으면 최소 18로 올린다(대안 ②). 26 only로는 돌아가지 않는다(REQ-02).

### A-2. 게이트 규칙 (어디에 `#available`을 써도 되는가)

| 층 | 허용 | 방식 | 예 |
|---|---|---|---|
| `Platform/` | O | Domain 프로토콜의 **구현체를 OS별로 2개** 둔다. 구현체 자체에 `@available(iOS 26, macOS 26, *)` | `SpeechAnalyzerTranscriber` / `SFSpeechTranscriber` (둘 다 `TranscribingService`) |
| `Composition/AppContainer` | O | `if #available` 로 구현체 **선택**만 한다. 로직 없음 | `transcriber = if #available(iOS 26, macOS 26, *) { SpeechAnalyzerTranscriber() } else { SFSpeechTranscriber() }` |
| `MwonmalUI/Compat/` | O | `ViewModifier` 내부에서만. 이름은 `mw` 접두 + 의도 | `.mwGlassSurface()`, `.mwZoomTransition(id:in:)`, `.mwTabBarMinimize()` |
| `MwonmalUI/Layout/AdaptiveRoot` | O | 루트 컨테이너 분기(18 `sidebarAdaptable` vs 17 `NavigationSplitView`) | §A-4 행 3 |
| `Presentation/`, `Navigation/`, `Domain/`, `Data/`, `MwonmalAPI/` | **X** | SwiftLint `custom_rules: available_only_in_gates` (정규식 `#available|@available` 를 `Platform/|MwonmalUI/Compat/|MwonmalUI/Layout/AdaptiveRoot|Composition/` 밖에서 금지) | — |

원칙: **폴백은 "같은 상태를 덜 화려하게"이지 "다른 화면"이 아니다.** 화면 ID(A-xx/W-xx)와 ViewModel `Phase`는 OS와 무관하게 동일해야 한다(12번 D-15의 확장).

### A-3. `Project.swift` `deploymentTargets` 변경안

현재 모든 타깃이 `.multiplatform(iOS: "26.0", macOS: "26.0")`, 앱 타깃은 `.iOS("26.0")` / `.macOS("26.0")` (Project.swift 24~231행). 변경안:

```swift
// Project.swift 상단에 상수 하나 (한 곳만 고치면 되게)
/// REQ-02: 최소 iOS 17 / macOS 14. 26 전용 API는 Platform·MwonmalUI/Compat·Composition에서만 게이트(협의체 iOS-A1).
let minimumOS: DeploymentTargets = .multiplatform(iOS: "17.0", macOS: "14.0")

// 모든 프레임워크·테스트 타깃
deploymentTargets: minimumOS,

// 앱 타깃
// MwonmalIOS
deploymentTargets: .iOS("17.0"),
// MwonmalMac
deploymentTargets: .macOS("14.0"),
// MwonmalUICatalog (iOS·macOS 둘 다)
deploymentTargets: minimumOS,
```

추가 설정(권장):
```swift
settings: .settings(base: [
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    // 26 전용 심볼을 게이트 없이 쓰면 경고가 아니라 에러로 잡히게
    "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",          // 확인 필요: 생성 코드(MwonmalAPI)의 경고가 걸리면 그 타깃만 NO
    "OTHER_SWIFT_FLAGS": "$(inherited) -warnings-as-errors -Xfrontend -warn-long-expression-type-checking=200",
])
```
- Live Activity(T-D1)는 iOS 앱 타깃 `infoPlist`에 `"NSSupportsLiveActivities": true` 추가(현재 없음). ActivityKit은 iOS 16.1+이므로 17에서 게이트 불필요(출처: developer.apple.com/documentation/activitykit/activity — iOS 16.1+, iPadOS 16.1+; macOS 없음 → Mac 타깃은 링크하지 않음).
- `Tuist/Package.swift`의 주석대로 외부 의존성(swift-openapi-runtime 등)은 iOS 17에서 문제없음(swift-openapi-runtime 최소 iOS 13 — **확인 필요**: 최신 1.x 매니페스트).

### A-4. 기능별 폴백 표 (12번 v2가 쓰기로 한 API 전수)

표기: **최소 OS**는 sosumi(developer.apple.com) 원문 "Available on" 값. 폴백 "—"는 17/14에서 그대로 동작한다는 뜻.

| # | 기능 (12번 절) | 26·18 API | 최소 OS (출처) | 17~25 / 14~25 폴백 | 게이트 위치 | 테스트 |
|---|---|---|---|---|---|---|
| 1 | **실시간 받아쓰기 미리보기** (§7 D-7, T-D3) | `SpeechAnalyzer` + `SpeechTranscriber` + `AssetInventory` | iOS 26 / macOS 26 (speech/speechanalyzer, speechtranscriber, assetinventory) | `SFSpeechRecognizer(locale: ko_KR)` + `SFSpeechAudioBufferRecognitionRequest` (iOS 10 / macOS 10.15, speech/sfspeechrecognizer). **`requiresOnDeviceRecognition = true` 강제**(iOS 13, sfspeechrecognitionrequest/requiresondevicerecognition). `supportsOnDeviceRecognition == false`면 미리보기 **끔** → D-7 "받아쓰기 준비 중" 상태 재사용(REQ-14: 오디오는 Apple 서버로도 안 나감). 1분 제한(문서 "Plan for a one-minute limit") → 55초마다 request 재생성, 누적 텍스트는 `RecordingSession`이 이어 붙임. ko-KR 온디바이스 지원 기기·OS: **확인 필요** | `Platform/Speech/`: `SpeechAnalyzerTranscriber`(@available 26), `SFSpeechTranscriber`. 둘 다 Domain `TranscribingService`. 선택은 `AppContainer` | 프로토콜 Fake로 VM 테스트(OS 무관). Platform 단위: `SFSpeechURLRecognitionRequest`로 고정 wav → 텍스트(시뮬레이터 마이크 불필요). 26 시뮬: `SpeechTranscriber.supportedLocales`에 ko 포함 확인. 실기기: SE(17)·iPhone 17(26) 각 1회 |
| 2 | **온디바이스 해석** (14번 §15, REQ-10 ②) | `FoundationModels.SystemLanguageModel` guided generation | iOS 26 / macOS 26 **+ Apple Intelligence 기기·지역** (foundationmodels/systemlanguagemodel: "Model availability depends on whether the device and region supports Apple Intelligence") | **서버 라우터**(14번 §15). 26이어도 `model.availability != .available`이면 서버. v1.0은 **전 OS 서버**(14번 §15 "v1.1 후보" 유지) | `Data/Repositories/TranslationRepository` 앞에 `OnDeviceTranslationDecorator`(@available 26) — Composition이 감쌀지 결정. Domain `TranslateUseCase` 불변 | Fake `LanguageModelClient`로 데코레이터 단위 테스트(폴백 경로: unavailable → 서버 호출 1회). 평가셋(14번 §15) 온디바이스 vs 서버 점수 비교는 26 실기기에서만 |
| 3 | **루트 내비** (§8 "루트 뷰는 하나") | `TabView` + `.tabViewStyle(.sidebarAdaptable)` + `Tab(value:)` | iOS 18 / macOS 15 (swiftui/tabviewstyle/sidebaradaptable, swiftui/tab) | iPhone(compact): `TabView(selection:)` + `.tabItem`(iOS 13). iPad regular·Mac: `NavigationSplitView`(iOS 16 / macOS 13, swiftui/navigationsplitview) — sidebar `List(selection: $coordinator.selectedTab)`, detail = 선택 탭의 `NavigationStack(path:)`. **`TabCoordinator` 상태(`selectedTab`, `paths`) 동일**. 26 추가 옵션 `.tabBarMinimizeBehavior(.onScrollDown)`(iOS 26, swiftui/view/tabbarminimizebehavior) | `MwonmalUI/Layout/AdaptiveRoot` 내부 `if #available(iOS 18, macOS 15, *)` | Navigation 순수 함수 테스트(OS 무관). 스냅샷: 루트 4장(iPhone 17·26, iPad 17·26, Mac 14·26). 시트 체이닝(§8-1)은 두 컨테이너에서 XCUITest 1흐름 |
| 4 | **환경 값 정의** (§1-2 D-3 `@Entry var mwStyle`) | `@Entry` | **iOS 13 / macOS 10.15** (swiftui/entry() — 매크로가 `EnvironmentKey` 코드를 생성하므로 back-deploy) | — (폴백 불필요). Xcode 16+ 툴체인만 필요 | 없음 | 컴파일 |
| 5 | **ViewModel** (§6 D-15) | `@Observable` | iOS 17 / macOS 14 (observation/observable()) | — | 없음 | 기존 계획 |
| 5b | 관찰 스트림 | `Observations` AsyncSequence | **iOS 26** (observation/observations) | **쓰지 않는다**. VM→actor 통신은 `AsyncStream`(12번 §7 `updates()`) | — | — |
| 6 | **테스트** (§11, T-C12) | Swift Testing | Xcode 16+ 툴체인. 라이브러리가 테스트 번들에 내장되어 iOS 17 시뮬레이터에서 실행 가능(**정확한 최소 런타임 수치는 확인 필요**) | — | — | CI에서 iOS 17 시뮬로 `xcodebuild test` 1회 통과 확인(단계 0 게이트) |
| 7 | **경로** (§8) | `NavigationStack(path:)`, `navigationDestination(for:)` | iOS 16 / macOS 13 | — | — | — |
| 8 | **녹음 중 잠금화면** (T-D1) | ActivityKit `Activity.request` | iOS 16.1 (activitykit/activity), macOS 없음 | — (iOS만). `Info.plist NSSupportsLiveActivities` | Platform `LiveActivityService`(iOS 전용 파일 `#if os(iOS)`는 Platform이라 허용) | 실기기 수동 + Maestro |
| 9 | **스크롤** (§1-1 온보딩 "한 장에 질문 하나", 복습 카드 넘김) | `.scrollTargetBehavior(.paging/.viewAligned)`, `.scrollTargetLayout`, `.scrollPosition(id:)`, `.safeAreaPadding`, `.containerRelativeFrame` | 전부 iOS 17 / macOS 14 (각 swiftui/view/… 페이지) | — | — | 스냅샷 |
| 10 | **빈 상태** (§5 `emptyState`) | `ContentUnavailableView` | iOS 17 / macOS 14 (swiftui/contentunavailableview) | — | — | 스냅샷 "빈 상태" |
| 11 | **텍스트 26 신규** (§9 규칙 6·9, 05번 §2 행간) | `.lineHeight(_:)`(26), `TextEditor(text: Binding<AttributedString>, selection:)`(26), `AttributedTextSelection`(26) | iOS 26 (swiftui/view/lineheight(_:), swiftui/texteditor/init(text:selection:)) | 행간: `.lineSpacing(행간 − 글자크기)`(iOS 13) — 05번 §2 표(예: body 17/26 → `lineSpacing(9)`)를 `MwFont` 토큰에 넣는다. 26에서는 같은 토큰을 `.lineHeight(.exact(points:))`로 변환(**확인 필요**: `AttributedString.LineHeight` 케이스 이름). 입력창: `TextEditor(text: Binding<String>)`(iOS 14) — 형광펜은 입력이 아니라 결과 `Text(AttributedString)`(iOS 15)에만 그린다(D-7과 일치). `typesettingLanguage(.init(languageCode: .korean))`(iOS 17) OK. keep-all U+2060 헬퍼(§9 Typography) OK | `MwonmalUI/Typography/MwFont.lineHeight` 모디파이어 내부 | 스냅샷 행간 비교(17 vs 26은 OS별 기준 이미지) |
| 12 | **리퀴드 글래스** (05번 §4.1 `.glass`, `.tabbar`) | `.glassEffect(_:in:)`, `GlassEffectContainer`, `.buttonStyle(.glass)`, `.scrollEdgeEffectStyle`, `.backgroundExtensionEffect` | 전부 iOS 26 / macOS 26 (swiftui/view/glasseffect(_:in:), scrolledgeeffectstyle(_:for:), backgroundextensioneffect()) | `.background(.ultraThinMaterial, in: RoundedRectangle(26))`(iOS 15) + `.overlay(stroke 1px white .75)` + 05번 `--paper-2` 그림자 — 즉 05번 §4.1의 CSS 값을 머티리얼로 그대로 옮긴다. 탭바: 17은 시스템 탭바 그대로(05번 "iOS 26 플로팅 탭바"는 26 전용 장식으로 격하). `.scrollEdgeEffectStyle` 폴백 없음(무시) | `MwonmalUI/Compat/MwSurface.swift`: `.mwGlass(_ strength: .regular/.strong/.dark)` 하나 | 스냅샷 `MwCard.glass` 3변형 × OS 2 |
| 13 | **지오메트리 관찰** (Waveform 폭, 카드 크기) | `onGeometryChange(for:of:action:)` | **iOS 16 / macOS 13** (swiftui/view/ongeometrychange(for:of:action:) — back-deploy 확인) | — . `onScrollGeometryChange`(iOS 18)는 쓰지 않고 `onGeometryChange` + `.scrollView` 좌표계로 대체 | — | — |
| 14 | **적응 레이아웃** (§9, 과제 C) | `ViewThatFits` | iOS 16 / macOS 13 (swiftui/viewthatfits) | — | — | 과제 C |
| 15 | **애니메이션** (REQ-22, 과제 B) | `PhaseAnimator`, `KeyframeAnimator`, `withAnimation(completionCriteria:completion:)`, `.symbolEffect(.pulse/.bounce)`, `.sensoryFeedback` | 전부 iOS 17 / macOS 14 (swiftui/phaseanimator, keyframeanimator, withanimation(_:completioncriteria:_:completion:), view/symboleffect(_:options:isactive:), view/sensoryfeedback(_:trigger:)) ; `.spring(duration:bounce:)`, `.smooth/.snappy/.bouncy` **iOS 13**(swiftui/animation/spring(duration:bounce:blendduration:), animation/smooth, animation/bouncy) | — . 18 신규 심볼 효과(`.wiggle/.breathe/.rotate`)와 26 `.drawOn/.drawOff`는 **쓰지 않는다**(폴백 = `.pulse`, 검증 안 함) | `MwonmalUI/Motion` | 과제 B |
| 16 | **줌 전환** (카드 → 상세, W-05 → A-04) | `.navigationTransition(.zoom(sourceID:in:))` + `.matchedTransitionSource` | iOS 18 / macOS 15 (swiftui/view/navigationtransition(_:), matchedtransitionsource(id:in:)) | 기본 push 전환(폴백에서 아무것도 안 함) | `MwonmalUI/Compat/.mwZoomTransition(id:in:)` / `.mwZoomSource(id:in:)` (17에서는 `self` 반환) | 스냅샷 대상 아님(전환). Catalog 수동 |
| 17 | **퇴근길 그라디언트** (05번 §1.3 dusk) | `MeshGradient` | iOS 18 / macOS 15 (swiftui/meshgradient) | 05번 dusk는 4색 **선형** 그라디언트라 `LinearGradient`(iOS 13)로 충분. Mesh는 쓰지 않음 | — | 스냅샷 A-03 |
| 18 | **OCR** (§2-1 D-6) | `RecognizeTextRequest`(Swift API) | iOS 18 / macOS 15 (vision/recognizetextrequest) | **v1은 전 OS `VNRecognizeTextRequest`만 쓴다**(iOS 13 / macOS 10.15, vision/vnrecognizetextrequest) — 18 API의 이점(Sendable 구조체)이 분기 비용보다 작다. `recognitionLanguages = ["ko-KR","en-US"]`, revision 3. ko 지원 OS 하한: **확인 필요**(`supportedRecognitionLanguages()`로 런타임 확인 후 미지원이면 `NO_TEXT_DETECTED`와 같은 `emptyState`) | Platform `VisionOcrService` 하나 | 고정 PNG 3장(한글/영문/혼합) → 텍스트 단위 테스트, iOS 17·26 시뮬 둘 다 |
| 19 | **소셜 로그인 웹세션** (§2-1 D-9) | `ASWebAuthenticationSession(url:callback:completionHandler:)` + `.Callback.customScheme` | iOS 17.4 / macOS 14.4 (authenticationservices/aswebauthenticationsession/callback) | 17.0~17.3 / 14.0~14.3: `init(url:callbackURLScheme:completionHandler:)`(iOS 12). 동작 동일 | Platform `OAuthWebSession` 내부 `#available(iOS 17.4, macOS 14.4, *)` | 콜백 URL 파싱은 순수 함수 테스트. 실기기 17.x 1회 |
| 20 | **마이크 권한** (§7) | `AVAudioApplication.requestRecordPermission` | iOS 17 / macOS 14 (avfaudio/avaudioapplication) | — | — | — |
| 21 | **동기화 프리미티브** (T-C6 strict, §3 `LevelsCache` actor 등) | `Synchronization.Mutex`, `Atomic` | **iOS 18 / macOS 15** (synchronization/mutex) | **actor**(기본) 또는 `OSAllocatedUnfairLock`(iOS 16 / macOS 13, os/osallocatedunfairlock). 12번은 이미 actor 위주라 실사용 0건 예상 | 코드 리뷰 + SwiftLint `Synchronization` import 금지 | 컴파일(17 타깃에서 `import Synchronization` 시 에러) |
| 22 | **즉시 시작 Task** | `Task.immediate` | iOS 26 (swift/task/immediate(...)-9bghc) | 쓰지 않음. D-15 `submit()`은 `Task { }` 유지 | — | — |
| 23 | **AsyncSequence 타입드 throws** (`AsyncSequence<Element, Failure>`) | SE-0421 | 런타임 iOS 18 추정 (**확인 필요**) | `AsyncThrowingStream<T, any Error>` / `AsyncStream` 만 사용(12번 §7 시그니처 그대로) | — | 컴파일 |
| 24 | **W-01 입력** (§8-3) | `.dropDestination(for:isEnabled:action:)` (DropSession, 26) | 26 (dropdestination(for:action:istargeted:) 페이지가 26에서 deprecated 표시) | `.dropDestination(for:action:isTargeted:)`(iOS 16 / macOS 13) 유지, deprecation 경고는 `MwonmalUI/Compat` 파일에서 `#available`로 분기해 흡수. `.onPasteCommand`(macOS 10.15), `PhotosPicker`(iOS 16, photosui/photospicker) OK | `MwonmalUI/Compat/.mwImageDrop` | macOS 14·26 수동 |
| 25 | **클립보드 감지** (T-D2) | `UIPasteboard.detectPatterns(for:)` | iOS 14 (**확인 필요**: sosumi 경로 미해결) | — . 실제 문자열은 사용자 "붙여넣기" 버튼 뒤에서만 읽음(T-D2 그대로) | Platform `ClipboardHintService` | 단위 테스트 불가(시스템). 수동 |
| 26 | **시트** (§8-1) | `presentationDetents`, `interactiveDismissDisabled`, `inspector` | iOS 16 / iOS 15 / iOS 17·macOS 14 (view/presentationdetents(_:), view/inspector(ispresented:content:)) | — | — | — |
| 27 | **macOS 창·메뉴** (§8-3) | `WindowGroup.defaultSize`, `Settings`, `CommandGroup` | macOS 13 / 11 / 11 | — | — | — |
| 28 | **프리뷰** | `#Preview`, `@Previewable` | iOS 17 (swiftui/previewable()) | — | — | — |
| 29 | **녹음 중 전역 인디케이터** (§7) | `.tabViewBottomAccessory`(26) 후보 | iOS 26 (tabbarminimizebehavior 페이지의 `TabViewBottomAccessoryPlacement` 참조) | `.safeAreaInset(edge: .bottom)` 배너(iOS 15) — **전 OS 이 방식으로 통일**(26 전용 장식 안 함, "접지 않는 것" 규칙은 배너로 충족) | — | 스냅샷 "녹음 중" 상태 |
| 30 | **폰트** (§9 규칙 8) | `CTFontManagerRegisterFontsForURL`, `Font.custom(_:size:relativeTo:)` | iOS 14 | — | — | — |

정리: **26 전용 = 1·2·11·12·22 / 18 전용 = 3·16·17·18·21·23 / 17.4 = 19.** 이 중 실제로 두 구현을 유지하는 것은 1·3·11·12·16·19 (그리고 v1.1에 2). 나머지는 "낮은 쪽 API 하나로 통일"이 결정이다(17·18·21·22·23·24·29).

### A-5. Swift 6 strict concurrency를 iOS 17에서 유지할 때 주의점

| 주제 | 내용 | 조치 |
|---|---|---|
| `Mutex`/`Atomic` 없음 | `Synchronization` 모듈은 iOS 18+ (표 #21) | actor 우선. 락이 정말 필요하면 `OSAllocatedUnfairLock`(iOS 16). `import Synchronization` SwiftLint 금지 |
| `SFSpeechRecognizer` 콜백이 non-Sendable | `recognitionTask(with:resultHandler:)`의 `SFSpeechRecognitionResult`는 `Sendable` 아님, 핸들러는 임의 큐 | 핸들러 **안에서** `String(result.bestTranscription.formattedString)`과 `isFinal`만 뽑아 `AsyncStream<TranscriptChunk>.Continuation`(Sendable)으로 yield. `SFSpeechRecognizer` 인스턴스는 `SFSpeechTranscriber` actor가 소유. 12번 §7 "탭 밖으로 버퍼를 넘기지 않는다"와 같은 규칙을 결과에도 적용 |
| `AVAudioEngine` 탭 버퍼 | 12번 §7 그대로(두 갈래 복사) | 변화 없음. 17에서는 `SFSpeechAudioBufferRecognitionRequest.append(buffer)`가 탭 콜백 안에서 직접 호출되므로 request 객체를 `nonisolated(unsafe) let`으로 탭에 캡처(문서화된 스레드 안전 API) |
| `deinit`에서 isolated 멤버 접근 | D-15 `deinit { inflight?.cancel() }`. `isolated deinit`(SE-0371)은 런타임 요구 OS가 있어(**확인 필요**, 18.4 추정) 쓰지 않는다 | 저장 프로퍼티 읽기 + `Task.cancel()`(Sendable)만. `deinit`에서 다른 `@MainActor` 메서드 호출 금지 |
| 타입드 throws AsyncSequence | 표 #23 | `AsyncThrowingStream<_, any Error>` |
| `Task.immediate`, `Observations` | 26 | 쓰지 않음 |
| SwiftUI `View`의 `@MainActor` 추론 | Xcode 16+에서 `View.body`는 `@MainActor`. 17 런타임 무관 | — |
| `@retroactive`, `sending`, `nonisolated(unsafe)`, `#isolation` | 컴파일러 기능, 런타임 무관 | 자유 |
| Xcode 버전 | 26 전용 심볼을 컴파일하려면 **Xcode 26** 필요. hosted `macos-15` 이미지의 Xcode 16으로는 `SpeechAnalyzer` 코드가 컴파일되지 않음 | CI 기본 = self-hosted Mac(Xcode 26). hosted 폴백은 `macos-26` 이미지(**확인 필요**: 2026-09 시점 존재 여부) |

### A-6. 스냅샷·CI 시뮬레이터 매트릭스

**러너·런타임**
| 러너 | Xcode | 시뮬레이터 런타임 | 역할 |
|---|---|---|---|
| self-hosted Mac (macOS 26) | 26 | iOS 17.5(다운로드, **확인 필요**: Xcode 26이 17.x 런타임 허용하는지 — 아니면 18.x 최저), iOS 26, iPadOS 26 | PR 기본 |
| hosted `macos-14` (GitHub) | 15.x/16.x (**확인 필요**) | — (macOS 14 네이티브) | **macOS 14 폴백 검증** 전용(`NavigationSplitView` 루트, `.ultraThinMaterial`). 야간만(과금) |
| hosted `macos-26` (**확인 필요**) | 26 | iOS 26 | self-hosted 다운 시 폴백 |

**스냅샷 기기 매트릭스** (swift-snapshot-testing, `precision: 0.98`, `perceptualPrecision: 0.98`; 기준 이미지는 `__Snapshots__/{os}{major}/` 로 OS별 분리 — 렌더링 차이를 diff로 흡수하지 않는다)

| Tier | 기기 (시뮬 이름) | OS | 크기·클래스 | Dynamic Type | 무엇을 검증 |
|---|---|---|---|---|---|
| 1 (PR) | iPhone SE (3rd generation) | iOS 17.x | 375×667, compact | L, AX3 | REQ-03 최소 화면 + 17 폴백(탭바·머티리얼·행간) |
| 1 (PR) | iPhone 17 | iOS 26 | 402×874(**확인 필요** 정확 pt), compact | L, AX3 | 26 경로(글래스·sidebarAdaptable 탭바) |
| 1 (PR) | Mac (러너 OS) | macOS 26 | 창 1000×700(최소, D-20) / 1440×900 | 시스템 | 사이드바 접힘·펼침, 3열 |
| 2 (야간) | iPad Pro 13-inch (M4) | iPadOS 26 | 1032×1376 세로·가로, regular | L, xxxLarge, AX3 | 3열, `sidebarAdaptable` 사이드바 |
| 2 (야간) | iPad (10th generation) | iPadOS 17 | 820×1180, regular | L, AX3 | `NavigationSplitView` 폴백 |
| 2 (야간) | iPad Pro 13 — Split View 1/3 | iPadOS 26 | 폭 375 compact(트레이트로 강제) | L | REQ-01 "iPad 멀티태스킹" = compact 규칙 |
| 2 (야간) | iPhone SE 가로 | iOS 17 | 667×375 | L | 시트 `.large` 강제, 키보드 |
| 2 (야간) | Mac 6K | macOS 26 | 3008×1692 (NSHostingView 크기 지정) | 시스템 | 읽기 폭 680 상한, 3열 max |
| 2 (야간) | Mac | macOS 14 (hosted) | 1000×700, 1440×900 | 시스템 | 14 폴백 |

- 흐름(12번 §11 "흐름 4개") × 상태(빈·에러·로딩·완료) × 위 Tier 1 = 4×4×(2 기기×2 DT + Mac 2 창) ≈ **96장/PR**. Tier 2 전체 ≈ 400장/야간. 1인 유지 가능 범위(기준 이미지 갱신은 `SNAPSHOT_RECORD=1` 잡 하나).
- E2E(Maestro, 16번) 4흐름은 **iPhone SE iOS 17 + iPhone 17 iOS 26** 둘 다 야간에 돈다.
- 12번 §11 표 Snapshot 행을 위 매트릭스로 교체, §15 CI `test` job에 `-destination` 2개 추가.

---

## 과제 B. REQ-22 — `MwonmalUI/Motion` 모듈 API 설계

### 결정 iOS-B1. Motion은 "값 토큰 + 프리셋 스펙 + 환경 주입", 수치는 View에 못 쓴다

1. **의도**
   REQ-22 "타이밍 곡선·물리·지속시간까지 손댈 수 있고 튜닝 가능한 모듈, 하드코딩 금지". 05번 §3 "모션: 말풍선 한 겹씩 벗겨지는 전환 · 카드 뒤집기 · 알림 글래스 slide-down. **과한 바운스 금지**"를 코드 불변식으로 만든다. SDK 규칙 2(상태·문자열 없음)와 5(`reduceMotion` 시 정지)를 어기지 않는다.

2. **비용**
   - 돈 0. 외부 라이브러리 없음(D-24: Lottie 안 씀).
   - 시간: 토큰·프리셋·모디파이어 ≈ 1.5일, Catalog `MotionLab` ≈ 1일, 테스트 0.5일. 16번 S2(Day 15 결과 화면)·S4(Day 22 ReviewCard) 앞에 토큰만 먼저(Day 3 Catalog 골격에 포함).
   - 복잡도: 타입 8개, 파일 6개. Presentation은 `.mwCardFlip(isFlipped:)` 같은 모디파이어만 호출.
   - 유지보수: 프리셋 추가 = 스펙 구조체 1개 + 모디파이어 1개 + 불변식 테스트 1줄.

3. **대안**
   - ① **뷰마다 `.animation(.spring(...))` 직접 작성**: 빠르지만 REQ-22 위반, 튜닝 시 전수 검색. **탈락**.
   - ② **Lottie/Rive 애셋**: 디자이너 툴 친화적이나 D-24가 배제했고, 코어 물리(스프링)를 코드에서 못 만진다. macOS 렌더 품질 편차. **탈락**.
   - ③ **`Animation`만 토큰화(프리셋 없음)**: 구성이 단순하지만 카드 뒤집기·스태거처럼 "여러 속성+순서"가 있는 모션은 결국 뷰에 로직이 남는다. **탈락(반쪽)**.
   - ④ **토큰 + 프리셋 스펙 + `@Entry` 환경 테마 (채택)**.

4. **왜**
   SwiftUI 애니메이션은 `Animation` 값 하나로 곡선·물리·지속시간이 다 표현되므로(`.spring(response:dampingFraction:)`이 iOS 13부터), **값 타입 스펙 → `Animation` 변환 함수**만 SDK가 소유하면 REQ-22의 "코어까지 손댈 수 있음"이 충족된다. 프리셋을 `Hashable & Codable` 구조체로 두면 Catalog 슬라이더 → JSON/Swift 리터럴 → 코드 복사가 자연스럽고, 환경 주입은 D-3의 "Environment 방식(값만)"과 같은 규칙이라 예외가 생기지 않는다.

5. **영향 파일/문서**
   - 12번 §9 트리에 `Motion/` 폴더 추가, SDK 규칙 **10** 신설: "애니메이션 수치는 `MwonmalUI/Motion` 토큰만. View에서 `.animation(.easeInOut(duration:))`류 직접 호출 금지(SwiftLint `motion_tokens_only`)". §16 단계 0 게이트에 "Motion 토큰 + Catalog MotionLab".
   - 05번 §3 "모션" 행에 토큰 이름 병기(`paper`, `snappy`, `soft`).
   - `.swiftlint.yml` custom rule.
   - `MwonmalUICatalog/MotionLab`.

6. **검증 방법**: §B-6.

7. **리스크와 되돌리는 조건**
   - 리스크: 시스템이 소유하는 전환(`.sheet`, `NavigationStack` push, `TabView` 전환)은 타이밍을 못 바꾼다 → `sheetPresent` 프리셋은 **앱이 그리는 오버레이**(클립보드 배너, macOS 용어 팝오버 대체 카드, W-02 준비 중 카드)에만 적용하고 문서에 명시. 시스템 시트는 그대로.
   - 되돌리는 조건: 프리셋이 15개를 넘거나 디자이너가 애셋 기반 모션을 요구하면 Rive 검토(Lottie 아님).

### B-1. 타입 설계 (실제 시그니처)

```swift
// MwonmalUI/Motion/MwMotionTokens.swift
import SwiftUI

/// 스프링 물리. response·dampingFraction은 iOS 13+ `Animation.spring(response:dampingFraction:blendDuration:)`에 그대로 들어간다.
public struct MwSpring: Hashable, Codable, Sendable {
    public var response: Double          // 초. 0.15 … 0.8
    public var dampingFraction: Double   // 0.6 … 1.0 (05번 "과한 바운스 금지" → 기본 토큰은 ≥ 0.8)
    public var blendDuration: Double

    public init(response: Double, dampingFraction: Double, blendDuration: Double = 0) { … }

    public static let paper  = MwSpring(response: 0.38, dampingFraction: 0.86)   // 종이 한 겹 벗겨짐
    public static let snappy = MwSpring(response: 0.26, dampingFraction: 0.92)   // 체크·칩 토글
    public static let soft   = MwSpring(response: 0.55, dampingFraction: 0.95)   // 시트·배너
}

public enum MwCurve: Hashable, Codable, Sendable {
    case linear, easeIn, easeOut, easeInOut
    case spring(MwSpring)
}

/// 곡선 + 지속시간 + 지연. spring이면 duration은 무시(response가 지속시간을 정한다).
public struct MwTiming: Hashable, Codable, Sendable {
    public var curve: MwCurve
    public var duration: Double     // 초
    public var delay: Double        // 초

    public init(curve: MwCurve, duration: Double = 0.24, delay: Double = 0) { … }

    public static let instant    = MwTiming(curve: .linear,   duration: 0)
    public static let quick      = MwTiming(curve: .easeOut,  duration: 0.16)   // 눌림, 하이라이트
    public static let standard   = MwTiming(curve: .easeInOut, duration: 0.24)  // 대부분의 상태 변화
    public static let paper      = MwTiming(curve: .spring(.paper))
    public static let snappy     = MwTiming(curve: .spring(.snappy))
    public static let soft       = MwTiming(curve: .spring(.soft))

    /// SwiftUI Animation으로. reduceMotion이면 지연·스프링을 없애고 짧은 크로스페이드로 바꾼다.
    public func animation(reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeInOut(duration: min(duration, 0.15)) }
        let base: Animation = switch curve {
        case .linear:            .linear(duration: duration)
        case .easeIn:            .easeIn(duration: duration)
        case .easeOut:           .easeOut(duration: duration)
        case .easeInOut:         .easeInOut(duration: duration)
        case .spring(let s):     .spring(response: s.response, dampingFraction: s.dampingFraction, blendDuration: s.blendDuration)
        }
        return delay > 0 ? base.delay(delay) : base
    }
}

/// 목록·계단 스태거. 총 지연이 `cap`을 넘지 않게 index를 잘라 준다.
public struct MwStagger: Hashable, Codable, Sendable {
    public var interval: Double     // 항목 간 초
    public var maxItems: Int        // 이 개수 이후는 같은 지연
    public var cap: Double          // 총 지연 상한(초)

    public init(interval: Double = 0.035, maxItems: Int = 8, cap: Double = 0.3) { … }
    public func delay(for index: Int) -> Double { min(Double(min(index, maxItems)) * interval, cap) }

    public static let list  = MwStagger()
    public static let steps = MwStagger(interval: 0.06, maxItems: 6, cap: 0.36)
    public static let none  = MwStagger(interval: 0, maxItems: 0, cap: 0)
}
```

```swift
// MwonmalUI/Motion/MwMotionPresets.swift

/// 프리셋 = "무엇을 어떻게 움직이는가"의 순수 스펙. 뷰·문자열·상태 없음.
public struct MwCardFlipSpec: Hashable, Codable, Sendable {
    public var timing: MwTiming = .paper
    public var perspective: Double = 0.55          // rotation3DEffect perspective
    public var axis: Axis = .horizontal            // 복습 카드는 세로축 회전(y) = .horizontal 스와이프 느낌
    public var liftScale: Double = 1.03            // 회전 중 살짝 들림
    public var reducedTiming: MwTiming = .standard // reduceMotion: 회전 없이 크로스페이드
}

public struct MwLevelStepSpec: Hashable, Codable, Sendable {   // LevelStairs 등급 계단 오르기
    public var timing: MwTiming = .snappy
    public var stagger: MwStagger = .steps
    public var riseOffset: Double = 14
    public var currentPulse: MwTiming = MwTiming(curve: .easeInOut, duration: 0.9)   // 현재 칸 숨쉬기
}

public struct MwDecodingPulseSpec: Hashable, Codable, Sendable { // W-04 "해석 중" 종이 겹 맥동
    public var period: Double = 1.4
    public var opacityPhases: [Double] = [0.35, 1.0, 0.35]
    public var scalePhases: [Double] = [0.98, 1.0, 0.98]
    public var reduced: Bool = true    // reduceMotion: ProgressView + 정지 이미지 (앱이 라벨 전달)
}

public struct MwSheetPresentSpec: Hashable, Codable, Sendable {  // 앱이 그리는 오버레이 카드·배너 전용 (시스템 .sheet 아님)
    public var timing: MwTiming = .soft
    public var edge: Edge = .bottom
    public var dimOpacity: Double = 0.28
    public var travel: Double = 24     // 슬라이드 거리(pt)
}

public struct MwListInsertSpec: Hashable, Codable, Sendable {   // 해석 목록·회의 목록 항목 등장
    public var timing: MwTiming = .paper
    public var stagger: MwStagger = .list
    public var offsetY: Double = 10
    public var startScale: Double = 0.98
}

/// 테마 = 프리셋 묶음. 앱은 이 값 하나만 환경에 넣는다.
public struct MwMotionTheme: Hashable, Codable, Sendable {
    public var cardFlip = MwCardFlipSpec()
    public var levelStep = MwLevelStepSpec()
    public var decodingPulse = MwDecodingPulseSpec()
    public var sheetPresent = MwSheetPresentSpec()
    public var listInsert = MwListInsertSpec()
    public static let `default` = MwMotionTheme()
}

extension EnvironmentValues {
    @Entry public var mwMotion: MwMotionTheme = .default     // @Entry: iOS 13+ (표 #4). D-3 Environment 방식
}
```

```swift
// MwonmalUI/Motion/MwMotion+View.swift — Presentation이 부르는 표면

public extension View {
    /// 앞/뒤 두 면을 가진 카드 뒤집기. isFlipped만 넘기면 된다. (ReviewCard 내부에서 사용, 앱도 직접 가능)
    func mwCardFlip(isFlipped: Bool) -> some View
    /// 목록 항목 등장. index로 스태거.
    func mwListInsert(index: Int) -> some View
    /// 해석 중 맥동. isActive=false면 즉시 정지.
    func mwDecodingPulse(isActive: Bool) -> some View
    /// 등급 계단 한 칸. index·isCurrent·isReached는 Presentation이 값으로 넘김(D-21: 등급 판단은 SDK 밖).
    func mwLevelStep(index: Int, isCurrent: Bool, isReached: Bool) -> some View
    /// 앱 오버레이 카드/배너 전환.
    func mwSheetTransition() -> some View
    /// 테마 교체(Catalog·테스트용). 앱 루트에서 한 번.
    func mwMotionTheme(_ theme: MwMotionTheme) -> some View
}
```

구현 메모(공개 API 아님):
- `mwCardFlip`: `@Environment(\.mwMotion)`, `@Environment(\.accessibilityReduceMotion)`. 회전은 `rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis:, perspective:)` + `withAnimation(spec.timing.animation(reduceMotion:))`. reduceMotion이면 `opacity` 크로스페이드만.
- `mwDecodingPulse`: `PhaseAnimator(spec.opacityPhases.indices, trigger: isActive)`(iOS 17). reduceMotion이면 phase 고정.
- `mwLevelStep`: `KeyframeAnimator`(iOS 17)로 `riseOffset → 0` + 현재 칸 `currentPulse` 반복. `.symbolEffect(.pulse)`는 `isCurrent`일 때만.
- `mwListInsert`: `.transition(.asymmetric(insertion: .offset(y:) .combined(with: .opacity).combined(with: .scale(startScale)), removal: .opacity))` + `.animation(spec.timing.animation(reduceMotion:).delay(spec.stagger.delay(for: index)), value:)`.
- 모든 모디파이어는 **내부 `@State`가 애니메이션 위상만** 가진다. 비즈니스 상태 없음(SDK 규칙 2는 "도메인 상태·문자열"을 뜻한다고 12번 §9에 각주).

### B-2. `reduceMotion` 대응 (SDK 규칙 5 구체화)

| 프리셋 | 기본 | `accessibilityReduceMotion == true` |
|---|---|---|
| cardFlip | 3D 회전 + 들림 | 회전 없음, 0.15s 크로스페이드 |
| levelStep | 스태거 상승 + 현재 칸 맥동 | 스태거 0, 상승 없음, 맥동 없음(현재 칸은 테두리·라벨로만 — 규칙 3 "색만으로 뜻 전달 금지") |
| decodingPulse | 맥동 | 정지 + `ProgressView`(라벨은 앱이 전달) |
| sheetPresent | 슬라이드 + 딤 | 페이드만 |
| listInsert | 오프셋+스케일+스태거 | 페이드, 스태거 0 |
| `MwTiming.animation(reduceMotion:)` | 곡선 그대로 | `easeInOut ≤ 0.15s`, delay 0 |

환경 값 출처: `\.accessibilityReduceMotion` iOS 13+ (swiftui/environmentvalues/accessibilityreducemotion).

### B-3. SwiftUI API 대응

| 필요 | 사용 API | 최소 OS |
|---|---|---|
| 곡선·스프링 | `Animation.spring(response:dampingFraction:blendDuration:)`, `.easeInOut(duration:)` | 13 |
| 위상 반복(맥동) | `PhaseAnimator` / `.phaseAnimator(_:trigger:)` | 17 |
| 다속성 키프레임(계단 상승) | `KeyframeAnimator`, `SpringKeyframe`, `CubicKeyframe` | 17 |
| 완료 콜백(뒤집힌 뒤 자기평가 버튼 노출) | `withAnimation(_:completionCriteria:_:completion:)` | 17 |
| 심볼 맥동 | `.symbolEffect(.pulse)` | 17 |
| 햅틱(정답/오답, 카드 저장) | `.sensoryFeedback(.success/.error, trigger:)` | 17 (macOS 14도 컴파일, 효과 없음) |
| 숫자 전환(등급 점수) | `.contentTransition(.numericText())` | 16 |

18·26 신규(`.wiggle`, `.drawOn`, `navigationTransition(.zoom)`)는 Motion 토큰이 아니라 `MwonmalUI/Compat`의 선택적 장식(표 #15·16)으로 분리한다 — Motion 모듈은 **전 OS 동일 동작**을 보장한다.

### B-4. 튜닝 방법 — Catalog `MotionLab`

- 화면: 좌측 프리셋 선택(5개), 중앙 미리보기(실제 `ReviewCard`, `LevelStairs`, 목록 8행, 오버레이 카드), 우측 슬라이더.
- 슬라이더: `response 0.1~1.0`, `dampingFraction 0.5~1.0`, `duration 0~1.0`, `delay 0~0.5`, `stagger.interval 0~0.12`, `stagger.cap 0~0.6`, `perspective 0.2~1.0`, `travel 0~48`. "다시 재생" 버튼(trigger 토글), "Reduce Motion 미리보기" 토글(환경 값 오버라이드 `.environment(\.accessibilityReduceMotion, true)`).
- 출력: "Swift로 복사" → `MwMotionTheme` 리터럴 텍스트(예: `cardFlip: .init(timing: .init(curve: .spring(.init(response: 0.41, dampingFraction: 0.84)), …))`), "JSON으로 복사"(`Codable`) → 디자이너 공유·Figma 노트. 붙여넣는 곳은 `MwonmalUI/Motion/MwMotionPresets.swift` 기본값 한 곳.
- 저장: Catalog 앱만 `@AppStorage("motionlab.theme")`에 JSON 보관(SDK에는 상태 없음).
- 불변식 위반(예: damping < 0.8)은 슬라이더 옆에 경고 라벨("05번: 과한 바운스 금지") — 값은 허용하되 테스트가 막는다.

### B-5. SDK 규칙과의 관계

- 규칙 1(인자 1개): `mwCardFlip(isFlipped:)`, `mwListInsert(index:)` — 옵션은 테마(환경)로.
- 규칙 2(상태·문자열 없음): 프리셋은 `Codable` 값. "해석 중…" 같은 라벨은 앱이 `Text`로 전달. 내부 `@State`는 애니메이션 위상 전용(문서에 각주).
- 규칙 3(색만으로 뜻 전달 금지): reduceMotion 폴백이 색 변화만 남기지 않도록 각 프리셋 표에 라벨/아이콘 경로 명시.
- 규칙 5(reduceMotion 정지): §B-2.
- D-21(Domain 모름): `mwLevelStep(index:isCurrent:isReached:)` — 판단은 Presentation.
- 신설 규칙 10: 애니메이션 수치는 Motion 토큰만. SwiftLint `motion_tokens_only`: `Presentation/`·`MwonmalUI/(Components|Primitives)/`에서 정규식 `\.(spring|easeIn|easeOut|easeInOut|linear|smooth|snappy|bouncy)\(` 및 `\.animation\(\.` 금지.

### B-6. 스냅샷·테스트

| 층 | 무엇 | 방법 |
|---|---|---|
| 토큰 불변식 (Swift Testing, 파라미터) | 기본 테마 전 프리셋: `dampingFraction ≥ 0.8`, `response ≤ 0.8`, `duration ≤ 0.6`, `stagger.delay(for: 100) ≤ cap`, `delay(for:)` 단조 증가, `reduceMotion` 변환 결과에 `.spring` 없음·delay 0 | `MwMotionTheme.default` 의 프리셋을 `arguments:`로 순회 |
| Codable 왕복 | JSON → 테마 → JSON 동일 | 1 테스트 |
| 진행률 순수 함수 | 각 스펙에 `func value(at progress: Double)`(예: `MwCardFlipSpec.angle(at:)`, `MwListInsertSpec.offset(at:)`) 를 두고 0·0.5·1에서 값 검증 | 애니메이션 시간을 테스트가 못 돌리므로 수학만 검증 |
| 스냅샷 (swift-snapshot-testing) | **끝 상태만**: `isFlipped` false/true, reduceMotion on/off, `mwListInsert` 8행 완료 상태, decodingPulse active/inactive(reduceMotion) | `UIView.setAnimationsEnabled(false)` / `withTransaction(Transaction(animation: nil))`. 중간 프레임 스냅샷은 하지 않는다(플레이키) |
| Catalog 수동 | MotionLab에서 5 프리셋 × reduceMotion 토글, 실기기 60/120Hz 육안 | S6 체크리스트 |
| 접근성 | Accessibility Inspector "Reduce Motion" 켠 상태 스냅샷 4장 | 릴리스 체크리스트(12번 §15) |

---

## 과제 C. REQ-03 — 최소~최대 화면 규칙 (SDK 규칙 6 확장)

### 결정 iOS-C1. 고정 높이 금지, 두 단계 레이아웃 클래스, 읽기 폭 상한 680pt

1. **의도**
   REQ-03 "iPhone SE 4.7"부터 Mac 6K·iPad 13"까지, 고정 px 금지". REQ-01 "iPad = macOS와 같은 넓은 레이아웃, iPhone은 세로 접기". 05번 §3의 픽셀 값(버튼 56, 시트 radius 32, "시트 높이 명시")을 **디자인 캡처용 값과 코드 규칙으로 분리**한다.

2. **비용**
   - 돈 0. 시간: 규칙 자체는 0.5일(SDK 규칙 문서 + SwiftLint), 카드 4블록 적응 레이아웃 1일, FlowLayout(칩 줄바꿈) 0.5일, 스냅샷 매트릭스 확장은 §A-6에 포함.
   - 복잡도: 환경 값 `mwLayoutClass` 하나 추가. `ViewThatFits` 사용처 3곳(결과 카드 버튼 행, 회의 행 메타, 온보딩 선택지).
   - 유지보수: 스냅샷 Tier 2가 커진다(야간만).

3. **대안**
   - ① **`horizontalSizeClass`만으로 분기**: iPad Split View 1/3에서 compact가 되어 REQ-01 "iPad = 넓은 레이아웃"과 충돌하는 것처럼 보이지만, 실제로는 좁아진 iPad는 접는 것이 맞다. 그러나 Mac에는 sizeClass가 없어(항상 nil/regular) 별도 처리 필요. **부분 채택**(compact/regular 결정의 입력값으로만).
   - ② **기기 종류(`UIDevice.userInterfaceIdiom`)로 분기**: iPad Split View·Stage Manager를 무시하게 됨. **탈락**.
   - ③ **`GeometryReader` 폭 임계값**: 뷰마다 숫자가 흩어져 REQ-03 "고정 px 금지" 정신과 어긋남. **탈락**(단, `AdaptiveRoot` 한 곳에서 폭 임계값 1개(700pt)를 sizeClass 보조로 쓰는 것은 허용).
   - ④ **환경 값 `mwLayoutClass`(compact/regular) = sizeClass + 플랫폼 + 창 폭을 `AdaptiveRoot` 한 곳에서 계산 (채택)**.

4. **왜**
   SwiftUI에서 "고정 높이 금지"는 `frame(height:)` 대신 `frame(minHeight:)`와 `fixedSize` 미사용으로 거의 자동 달성되고, 남는 문제는 (a) 가로 공간이 모자랄 때(SE, AX 글자)와 (b) 너무 넓을 때(6K)의 두 극단뿐이다. (a)는 `ViewThatFits`(16)와 Dynamic Type 임계값으로, (b)는 읽기 폭 상한과 3열 `navigationSplitViewColumnWidth(min:ideal:max:)`로 닫힌다. 분기 입력을 환경 값 하나로 모으면 12번 D-15 "플랫폼 분기는 View의 레이아웃만"이 그대로 유지된다.

5. **영향 파일/문서**
   - 12번 §9 SDK 규칙 6을 아래 §C-1 규칙표로 교체, §11 Snapshot 행을 §A-6 매트릭스로. §8 "루트 뷰" 문단에 `mwLayoutClass` 계산 규칙. §1-1 D-2 "macOS(넓은 화면)" → "regular 레이아웃 클래스(iPad·Mac)".
   - 05번 §3 "시트 **높이 명시**" 옆에 "(Figma 캡처용, 코드는 `presentationDetents`)" 주석, §5 기기 표에 SE 375×667 행 추가.
   - `MwonmalUI/Layout/`: `MwLayoutClass`, `MwFlowLayout`, `MwReadableWidth`.
   - `.swiftlint.yml`: `no_fixed_height`(정규식 `\.frame\((width|height): ?\d`, `\.frame\(height:` 를 `MwonmalUI/Primitives/MwAvatar`·아이콘 예외 목록 외 금지).

6. **검증 방법**: §C-3 매트릭스 + 규칙별 스냅샷. Accessibility Inspector "Dynamic Type AX5"에서 잘림 0건(릴리스 체크리스트).

7. **리스크와 되돌리는 조건**
   - 리스크: `ViewThatFits`는 후보를 전부 측정해 큰 목록에서 비용이 있다 → 목록 행에는 쓰지 않고(행은 항상 세로 안전 레이아웃), 카드·헤더에만.
   - AX5에서 `TranslationResultCard` 4블록이 한 화면을 넘는다 → 스크롤이 답이며 "첫 스크롤에 Primary 1개"(D-1)는 Dynamic Type ≥ AX1에서 "첫 스크롤" 대신 "첫 블록"으로 완화(문서화).
   - 되돌리는 조건: Stage Manager·창 크기 변화가 잦아 `mwLayoutClass` 재계산으로 레이아웃이 튀면 `AdaptiveRoot`의 폭 임계값에 히스테리시스(±40pt) 추가.

### C-1. 규칙표 (SDK 규칙 6 확장판)

| # | 규칙 | 코드 | 예외 |
|---|---|---|---|
| 6-1 | **높이 고정 금지.** 버튼 56·입력 56·셀 20 radius 등 05번 값은 `minHeight`로 | `MwButton`: `.frame(maxWidth: .infinity, minHeight: 56)`; `.fixedSize` 금지(12번 규칙 6 그대로) | 아바타·아이콘·체크박스(26×26)·스위치는 고정 허용(`@ScaledMetric`로 스케일) |
| 6-2 | **폭 고정 금지, 비율·상한만** | `.frame(maxWidth: 680)`(읽기 폭), `containerRelativeFrame(.horizontal, count:span:)`(17) | 사이드바 264(05번, `navigationSplitViewColumnWidth(min: 220, ideal: 264, max: 320)`) |
| 6-3 | **가로가 모자라면 세로로**: 버튼 2개 행, 출처 칩+날짜, 온보딩 선택지 2열 | `ViewThatFits(in: .horizontal) { HStack{…}; VStack{…} }` | 목록 행은 처음부터 세로 안전 배치(측정 비용) |
| 6-4 | **Dynamic Type 임계값**: `dynamicTypeSize >= .xxxLarge`(또는 `.isAccessibilitySize`)에서 카드 4블록(05번 §4.3) HStack 요소 전부 VStack, 칩은 `MwFlowLayout`(줄바꿈), 아이콘+라벨은 `Label` 세로 | `@Environment(\.dynamicTypeSize)`; `MwFlowLayout: Layout`(iOS 16 `Layout` 프로토콜) | 일러스트·장식 텍스트는 `.dynamicTypeSize(...(.xxLarge))`로 **상한**(본문은 상한 금지) |
| 6-5 | **텍스트 상한 금지, 줄 수 제한 금지**(제목 1줄 `lineLimit(1)` 금지) | `lineLimit(nil)`; 요약 행만 `lineLimit(2, reservesSpace: false)` 허용 | MeetingRow 제목 2줄 |
| 6-6 | **간격·아이콘은 `@ScaledMetric`** | `@ScaledMetric(relativeTo: .body) var gap = 8` | — |
| 6-7 | **읽기 폭 상한 680pt**(본문·결과 카드·복습 카드), 6K에서도 중앙 정렬 | `MwReadableWidth` 컨테이너(`.frame(maxWidth: 680).frame(maxWidth: .infinity)`) | 목록·표(회의 목록)는 상한 없음 |
| 6-8 | **레이아웃 클래스는 환경 값 하나** | `@Entry var mwLayoutClass: MwLayoutClass = .compact`; `AdaptiveRoot`가 계산: macOS → `.regular`; iOS/iPadOS → `horizontalSizeClass == .regular && width ≥ 700 ? .regular : .compact` | View는 `#if os()`·`UIDevice` 안 봄(Presentation의 유일한 분기 입력) |
| 6-9 | **시트**: 높이 값 대신 detent | `.presentationDetents([.medium, .large])`; 가로 SE(667×375)·AX 글자에서는 `.large`만 | W-02a 동의 시트는 `.large` + `interactiveDismissDisabled` |
| 6-10 | **최소 창(Mac) 1000×700**(D-20 유지) ; 그 이하에서는 3열 → 2열(`columnVisibility = .doubleColumn`) | `.frame(minWidth: 1000, minHeight: 700)` | 13" MacBook Air 1470×956에서 1000은 안전 |
| 6-11 | **키보드·세이프에어리어**: SE에서 W-01 입력 + 버튼이 키보드 위로 | `.safeAreaInset(edge: .bottom)`에 CTA, `ScrollView` + `.scrollDismissesKeyboard(.interactively)`(16) | — |

### C-2. Dynamic Type XXXL·AX에서 카드 레이아웃 (TranslationResultCard, ReviewCard)

- **L~xxLarge**: 05번 §4.3 그대로(라벨 행 = 라벨 + 오른쪽 메타 HStack, 칩 가로 나열 wrap).
- **xxxLarge~AX2**: 라벨 행 세로(`ViewThatFits` 자동), 칩 `MwFlowLayout`(줄바꿈), 할 일 행 = 체크 위 / 텍스트 아래 / 마감 태그 아래(3단), "모두 복습 카드로" 버튼 전폭.
- **AX3~AX5**: 카드 패딩 20→16(`@ScaledMetric` 역방향 아님 — 고정 16), 블록 사이 구분선으로 경계 강조, ReviewCard 앞면 단어는 `minimumScaleFactor` 금지 → 여러 줄, 뒷면 "들은 문장"은 `lineLimit(nil)`; 카드 자체가 화면보다 커지면 카드 안이 아니라 **화면이 스크롤**(카드 높이 고정 금지 규칙 6-1의 귀결). 뒤집기 모션은 유지(reduceMotion 별도).
- macOS: 시스템 글자 크기만(12번 규칙 6) — 단 Mac에서도 `dynamicTypeSize` 환경은 존재하므로 같은 코드가 돈다.

### C-3. 스냅샷 기기 매트릭스 (REQ-03 관점, §A-6와 동일 기기 + Dynamic Type 축)

| 축 | 값 | 이유 |
|---|---|---|
| 최소 | iPhone SE 3 (375×667), iOS 17 | REQ-03 하한. 세로/가로 |
| 기준 | iPhone 17, iOS 26 | 05번 §5 기준 393×852 대체(현행 기기) |
| iPad regular | iPad Pro 13" 세로·가로, iPadOS 26 ; iPad 10th, iPadOS 17 | 3열, 폴백 |
| iPad compact | Split View 1/3 (폭 375) | REQ-01 멀티태스킹 |
| Mac | 1000×700(최소), 1440×900(05번 §5), 3008×1692(6K) | 상한. 6K는 읽기 폭 680 검증 |
| Dynamic Type | L(기본), xxxLarge(6-4 임계), AX3, AX5(야간) | 임계값 양쪽 + 극단 |
| 상태 | 빈·에러·로딩·완료 + "녹음 중" 배너 | 12번 §11 |
| 언어 | ko-KR 고정(12번 규칙 2) | — |

Tier 1(PR) = {SE-17 L/AX3, iPhone17-26 L/AX3, Mac 1440} ; Tier 2(야간) = 전부. 기준 이미지 OS별 폴더(§A-6).

---

## 부록. 확인 필요 목록 (출처를 못 찾았거나 문서에 수치가 없음)

| 항목 | 왜 필요한가 | 확인 방법 |
|---|---|---|
| Xcode 26에서 iOS 17.x 시뮬레이터 런타임 설치 가능 여부 | CI Tier 1 | `xcodebuild -downloadPlatform iOS` / Xcode › Settings › Components |
| Swift Testing 라이브러리의 최소 실행 OS | iOS 17 시뮬에서 테스트 실행 | 단계 0에서 실제 실행 |
| `SFSpeechRecognizer` ko-KR `supportsOnDeviceRecognition` 기기·OS 범위 | 미리보기 가용 범위 안내 문구 | SE(17) 실기기 + `supportedLocales()` 로그 |
| `VNRecognizeTextRequest` ko 지원 하한 OS·revision | D-6 OCR 폴백 | `supportedRecognitionLanguages()` 런타임 확인 |
| `AttributedString.LineHeight` 케이스(`.exact`/`.multiple`) 이름 | 표 #11 26 경로 | Xcode 26 헤더 |
| `UIPasteboard.detectPatterns` 최소 OS(14 추정) | T-D2 클립보드 감지 | 문서 페이지 경로 재검색 |
| SE-0421 타입드 throws AsyncSequence 런타임 요구 OS | 표 #23 | swift.org 릴리스 노트 |
| `isolated deinit` 런타임 요구 OS | §A-5 | Swift 6.1 릴리스 노트 |
| GitHub hosted `macos-26` 이미지 존재·Xcode 버전, `macos-14` 이미지의 Xcode | §A-6 러너 | actions/runner-images README |
| swift-openapi-runtime/urlsession 최소 iOS | Package.swift | 각 Package.swift `platforms` |
| iPhone 17 논리 해상도(pt) | 스냅샷 이름 | 시뮬레이터 `UIScreen.main.bounds` |
| iOS 18 미지원 기기 목록(17 최소의 실익) | iOS-A1 되돌리는 조건 | Apple 호환성 문서 |
