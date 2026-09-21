# ADR-0005: 최소 OS는 iOS 17.0 / iPadOS 17.0 / macOS 14.0, 18·26 전용 API는 세 곳에서만 게이트한다

| 항목 | 값 |
|---|---|
| 상태 | 채택 (2026-09-21) |
| 관련 REQ | REQ-02(최소 OS), REQ-01·03(화면), REQ-10(온디바이스 AI 트랙) |
| 관련 결정 | 15번 T-C2 **폐기**(26 only → 17+), 12번 D-3 유지, D-7·T-D3(미리보기 v1.1), FD-1, iOS-A1·A-2·A-4, MI-5, RT-A-08·09, RT-B-02·06 |
| 출처 | `council/S0/iOS.md` §A, `council/S0/macOS_iPad.md` §0·MI-5, `council/S0/REDTEAM_A.md` §B(Apple 문서 검증 표), `council/S0/PM.md` PM-2 |

## 1. 의도
REQ-02("도달 범위, 다 대비해")를 지키면서 12번의 구조(MVVM-C + Clean, 8모듈, "ViewModel에 `#if os()` 금지")를 깨지 않는다. 26 기기에서는 26 전용 기능을 살리고, 17~25 기기에서는 **같은 화면·같은 ViewModel**로 "덜 화려한 같은 상태"를 보여 준다. 분기 지점을 세 곳으로 봉인해 화면 코드에는 `#available`이 한 줄도 없게 한다.

## 2. 비용
- 돈: 0. 시뮬레이터 런타임(iOS 17.0은 개발 Mac에 이미 설치, BRIEF 사용자 답변 2026-09-19)과 공개 저장소 hosted 러너(ADR-0011)만 쓴다.
- 시간: `Project.swift` 전 타깃 값 치환 + 빌드 2회 + 이 ADR = 0.5일(PM S0-A). 루트 2벌은 ADR-0006에서 1.0일. iOS 17 스냅샷 서브셋 1.0일(S6).
- 복잡도: 두 구현을 유지하는 API는 실제로 소수다(§4). 나머지는 "낮은 쪽 API 하나로 통일".
- 유지보수: 스냅샷 기준 이미지가 OS별 폴더로 갈린다(`__Snapshots__/{os}{major}/`). CI 시간은 PR 기준 불변(iOS 17 축은 야간, ADR-0011).

## 3. 대안
| 대안 | 탈락 이유 |
|---|---|
| ① 26 only 유지(T-C2 원안) | REQ-02 위반. 출시 첫해 미업데이트 기기·MDM으로 업데이트가 늦는 사내 관리 기기 배제 |
| ② iOS 18 / macOS 15 최소 | `sidebarAdaptable`·`Mutex`·`navigationTransition(.zoom)` 분기가 사라지지만 REQ-02가 17/14를 명시. iOS 17 런타임이 이미 설치되어 있어(BRIEF) PM-2의 되돌림 트리거("런타임 설치 불가")도 소멸(RT-B-06) |
| ③ iOS 16 이하 | `@Observable`·`PhaseAnimator`·`ContentUnavailableView`·`AVAudioApplication`(전부 17)이 사라져 12번 D-15 ViewModel 계약을 다시 써야 함. 구조 비용 과대 |
| ④ 게이트를 화면마다 허용 | `#available`이 Presentation에 흩어져 D-15의 정신("플랫폼 분기는 View의 레이아웃만")이 깨지고 스냅샷 경우의 수가 폭증 |
| **⑤ 17/14 최소 + 세 층 게이트 (채택)** | — |

## 4. 왜
17은 `@Observable`·`#Preview`·`PhaseAnimator`·`scrollTargetBehavior`·`ContentUnavailableView`·`AVAudioApplication`이 모두 들어온 첫 버전이라 12번이 전제한 코드 관용구(D-15, `.task(id:)`, `RouteHost`)가 한 줄도 안 바뀐다(iOS.md iOS-A1 §4). Apple 문서로 확인한 결과(REDTEAM_A §B, 2026-09-19) 12번 v2가 쓰기로 한 API 중 **실제로 폴백이 필요한 것은 7개뿐**이고 전부 "플랫폼 서비스" 아니면 "표면 스타일"이라 Platform과 MwonmalUI 안에 가둘 수 있다.

**사실 정정**: T-C2 표의 "17+면 `@Entry`를 잃는다"는 오류다. `@Entry`는 iOS 13.0+ / macOS 10.15+(back-deploy, Xcode 16 툴체인)이므로 D-3 Environment 방식을 그대로 유지한다. `onGeometryChange`(16/13)·`spring(duration:bounce:)`(13)·`PhaseAnimator`(17)·`ViewThatFits`(16)·`ContentUnavailableView`(17)도 17에서 사용 가능하다.

**폴백 7개(FD-1, iOS.md A-4 기준)**

| API (최소 OS) | v1.0 처리 |
|---|---|
| `SpeechAnalyzer` (26) | v1.0 미포함. 미리보기 자체가 v1.1(FD-8). 17~26 전 OS "받아쓰기 준비 중" 상태(D-7) + 파형만. `SFSpeechRecognizer` 폴백도 v1.0 안 함(MI-5) |
| Foundation Models (26) | ADR-0007의 진입 조건 통과 시 미리보기 엔진, 아니면 v1.1. 게이트는 `#available` + `availability == .available` + `supportsLocale()` 세 겹 |
| `sidebarAdaptable` + `Tab` (18) | 쓰지 않는다(ADR-0006). iPadOS에선 "상단 탭바가 사이드바로 접히는" 모양이라 REQ-01과도 안 맞음 |
| Liquid Glass `glassEffect` 계열 (26) | 머티리얼로 통일(`.ultraThinMaterial` + 1px stroke). v1.0에 글래스 없음(FD-8, U-13) |
| `navigationTransition(.zoom)` (18) | 기본 push 전환. `MwonmalUI/Compat/.mwZoomTransition`이 17에서는 `self` 반환 |
| `Synchronization.Mutex` (18) | actor 기본, 락이 필요하면 `OSAllocatedUnfairLock`(16/13). `import Synchronization` SwiftLint 금지 |
| `.lineHeight` (26) | `lineSpacing(행간 − 글자크기)`를 `MwFont` 토큰에. 26 경로의 `AttributedString.LineHeight` 케이스 이름은 **확인 필요** |

**게이트 규칙(어디에 `#available`을 써도 되는가)**

| 층 | 허용 | 방식 |
|---|---|---|
| `Platform/` | O | Domain 프로토콜의 구현체를 OS별로 둔다. 구현체 자체에 `@available` |
| `MwonmalUI/Compat/` | O | `ViewModifier` 내부에서만. 이름은 `mw` 접두 + 의도(`.mwGlassSurface()`, `.mwZoomTransition(id:in:)`) |
| `Composition/AppContainer` | O | `if #available`로 구현체 **선택**만. 로직 없음(`any Protocol` 타입 주석 필요 — RT-A §C-4 경미) |
| `Presentation/`, `Navigation/`, `Domain/`, `Data/`, `MwonmalAPI/` | **X** | SwiftLint custom rule `no_available_in_core` |

iOS.md A-2가 허용했던 `MwonmalUI/Layout/AdaptiveRoot`는 **허용 목록에서 제외**한다 — MwonmalUI는 Navigation을 import할 수 없어 루트 래퍼가 거기 있을 수 없다(RT-A-09, ADR-0006).

## 5. 영향 파일·문서
- `apps/ios-macos/Project.swift`: 전 타깃(테스트·Catalog 포함) `.multiplatform(iOS: "17.0", macOS: "14.0")` 상수 하나(`minimumOS`), 앱 타깃 `.iOS("17.0")` / `.macOS("14.0")`. Domain만 `watchOS: "10.0"` 추가(ADR-0010). `SWIFT_TREAT_WARNINGS_AS_ERRORS`는 Day 2에 넣지 않고 Day 3 생성 코드 컴파일 후 타깃별로(RT-A-24).
- `.swiftlint.yml`: `no_available_in_core`, `import Synchronization` 금지.
- 15번 T-C2: "폐기(2026-09-21) → ADR-0005". J표 "iOS 26 only" 행·리스크표 #9 삭제.
- 12번 머리말 "기준: iOS 26 / macOS 26" → "최소 iOS 17 / macOS 14, 26 전용은 게이트". §7(`TranscribingService` 구현체 0 + nil, 미리보기 v1.1), §8 루트 문단(ADR-0006), §14 "하지 않는 것"에 "Presentation·Domain·Navigation의 `#available`" 추가, §16 단계 0 게이트에 "iOS 17 시뮬에서 뜸".
- 05번 `.modal`/사이드바 "글래스" → "머티리얼(26 글래스는 v1.1)".
- 14번 §15 온디바이스 문단: "iOS 26 + Apple Intelligence 기기에서만, 아니면 서버".
- 이슈 #2(견적 M→L), #10, #19(스텁·상태만).

## 6. 검증
- `tuist generate` 후 iPhone SE(3rd gen) iOS 17.0 시뮬레이터와 iPhone 17 iOS 26.4 시뮬레이터, Mac 26에서 빈 앱이 뜬다(Day 2 게이트).
- 컴파일 게이트: deployment target 17/14로 빌드되면 `@available` 누락은 컴파일러가 잡는다(QA-1 build-test 1단계).
- SwiftLint `no_available_in_core` 0건. `scripts/available-audit.sh`: `@available` 분기 목록 = 폴백 테스트 목록(diff 0, 릴리스 체크 A-13).
- 스냅샷 Tier1(PR) = iPhone SE 3세대 iOS 17.0 + iPhone 17 iOS 26.4 + Mac 26. Tier2(야간) = iPad 11"/13" 세로·가로·Split 1/2, Mac 14(self-hosted), 6K, Dynamic Type AX3, reduceMotion(ADR-0011 매트릭스).
- 단계 3(회의) 완료 기준: iOS 17 시뮬에서 녹음 → "받아쓰기 준비 중" → 서버 결과 표시.

## 7. 리스크와 되돌리는 조건
- 리스크: 17·26 렌더링 차이로 스냅샷 유지비 증가 → OS별 폴더로 흡수. iOS 17 사용자는 W-02 미리보기가 없어 "차별점" 체감이 준다(T-C2의 원래 우려) → D-7이 정의한 상태 안. macOS 14 실행 검증은 hosted 이미지가 11/2 폐기되므로 self-hosted 야간(ADR-0011).
- 되돌리는 조건: 출시 6개월 뒤 Amplitude OS 분포에서 iOS 17 < 3% **그리고** 18 전용 폴백 유지비가 스프린트당 반나절을 넘으면 최소 18/15로 올린다(대안 ②). 26 only로는 돌아가지 않는다(REQ-02). 26 비율 > 90%가 6개월 지속되면 REQ-02 재협의를 협의체에 올린다(MI-5).
