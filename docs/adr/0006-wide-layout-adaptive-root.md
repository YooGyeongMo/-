# ADR-0006: 넓은 레이아웃의 분기 축은 사이즈 클래스 두 개, 루트는 `AdaptiveRoot`(compact `TabView` / wide `NavigationSplitView`) 둘

| 항목 | 값 |
|---|---|
| 상태 | 채택 (2026-09-21) |
| 관련 REQ | REQ-01(iPad = 넓은 레이아웃), REQ-03(최소~최대 화면, 고정 px 금지), REQ-02 |
| 관련 결정 | 12번 D-0·D-2 **개정**, D-17 교체("루트 뷰는 하나" → "루트 래퍼 하나, 구현 둘"), D-20 유지, D-21, FD-2, MI-1·2·3·6, iOS-C1, PM S1-A·S1-B, RT-A-08·09·10·19, RT-B-05 |
| 출처 | `council/S0/macOS_iPad.md` §0·MI-1~MI-6, `council/S0/iOS.md` 과제 C, `council/S0/REDTEAM_A.md` RT-A-08~10·§B #1·#4·#16·#26 |

## 1. 의도
iPad 13"·11" 가로/세로, iPadOS 26 창 모드, Split View, Slide Over, Mac 창 크기 변화를 **하나의 규칙**으로 처리한다. iPhone Pro Max 가로에서 사이드바가 튀어나오는 사고를 막는다. compact↔wide 전환 시 `[AppRoute]`·`selectedTab`·시트가 그대로 살아남고 딥링크 순수 함수(12번 §8-2)가 레이아웃과 무관하게 동일하게 유지된다. REQ-03 "고정 px 금지"를 코드 리뷰가 아니라 린트가 지킨다.

## 2. 비용
- 돈: 0.
- 시간: 환경값 + 루트 2종 + `ListDetail` 2·3열 컨테이너 ≈ 1.0일(PM S1-A, 3경로였던 원안보다 작다 — RT-A-09). 규칙·린트 0.5일, 카드 4블록 적응 레이아웃 1일(iOS-C1).
- 복잡도: 루트 뷰 2종(약 80줄), 환경값 1개(`mwLayout`), `ViewThatFits` 사용처 3곳.
- 유지보수: 화면 View는 `mwLayout`만 읽고 자기 내부 배치를 바꾼다. 라우팅 코드는 손대지 않는다. 스냅샷 Tier2(야간)가 커진다.

## 3. 대안
**분기 축**
| 대안 | 탈락 이유 |
|---|---|
| `UIDevice.userInterfaceIdiom == .pad` | Slide Over·1/3 Split에서 iPad가 compact가 되는데 사이드바를 그리면 깨진다. HIG(iPadOS 26 멀티태스킹, 2025-06-09 개정) "Apps don't control multitasking configurations". Mac에는 `UIDevice`도 없다 |
| 창 폭 임계값(≥ 700pt 등, iOS-C1 6-8·PM S1-B) | 기기·OS마다 사이즈 클래스 경계가 달라 Apple이 이미 계산해 준 값을 다시 만드는 바퀴 재발명(REQ-23). iOS-C1 식과 MI-1 식이 iPad 13" 1/2 Split(678pt)에서 반대 결과(RT-A-08) |
| `horizontalSizeClass`만 (PM `mwIsWide = h == .regular \|\| os(macOS)`) | iPhone Pro Max 가로가 h regular라 사이드바가 뜬다. REQ-01 "iPhone은 세로 접기" 위반 |
| **`horizontalSizeClass == .regular && verticalSizeClass == .regular` (채택)** | — |

**루트 구조**
| 대안 | 탈락 이유 |
|---|---|
| `TabView` + `.sidebarAdaptable` 하나(D-17 원안) | iOS 18 / macOS 15 최소(Apple 문서 확인)라 REQ-02 위반. iPadOS에서는 "상단 탭바가 사이드바로 접히는" 모양이라 REQ-01 "iPad = 사이드바 고정"과 맞지 않음 |
| `#available(iOS 18)` 이면 `sidebarAdaptable`, 아니면 2벌(iOS·PM 원안 = 경로 3개) | 위와 같은 이유로 18 경로의 이점이 없고 스냅샷 매트릭스만 키운다(RT-A-09) |
| 세 열 `NavigationSplitView(sidebar:content:detail:)`를 루트로 | `[AppRoute]`의 의미가 compact(스택)와 wide(열 선택+스택)에서 달라져 D-17 순수 함수·딥링크 규칙이 두 벌이 된다 |
| 항상 `NavigationSplitView`(compact에서 자동 스택) | iPhone에서 탭바가 사라지고 사이드바 목록이 첫 화면이 된다. 02번 v5.2의 A-01 홈(탭바)과 다름 |
| **compact `TabView` / wide 2열 `NavigationSplitView`, 상태는 `TabCoordinator` 하나 (채택)** | — |

## 4. 왜
`horizontalSizeClass`는 iOS 13 / macOS 10.15+에서 존재하며 "macOS·tvOS에서는 항상 `.regular`, watchOS는 항상 `.compact`, iPad Slide Over/Split View에 따라 바뀐다"(Apple 문서, REDTEAM_A §B #1 확인). 따라서 `h == .regular && v == .regular`면 wide(Mac 항상, iPad 전체화면·13" 1/2 Split 이상), 아니면 compact(iPhone 어느 방향이든 하나는 compact, iPad Slide Over·1/3)이고 Mac에 별도 분기가 필요 없다. iOS.md 대안 ①의 "Mac에는 sizeClass가 없어(항상 nil/regular)"는 부정확하다(존재하며 regular).

루트는 `TabCoordinator`(창 수명, 12번 §8-4)를 루트 switch **위**에 `@State`로 두고, compact 루트(`TabView(selection: $tc.selectedTab)` 안 `NavigationStack(path: $tc.paths[tab])`)와 wide 루트(`NavigationSplitView`의 사이드바 `List(selection: $tc.selectedTab)`, detail = 같은 `NavigationStack(path: $tc.paths[tab])`)가 **같은 바인딩**을 쓴다. 사이즈 클래스가 바뀌면 SwiftUI는 뷰 트리를 갈아 끼우지만 상태는 코디네이터에 있으므로 경로가 보존된다. "세 열 동시"(D-2 표의 Project·Meeting 행)는 A-11/W-00 라우트 View 내부에서 `mwLayout == .wide`일 때 `ListDetail` 3열로 그린다 — 라우트는 한 개, 열은 그 안의 레이아웃.

루트 래퍼 `AdaptiveRoot`의 위치는 **Navigation 모듈**이다. MwonmalUI는 SwiftUI만 import하고(D-21, `Project.swift` MwonmalUI `dependencies: []`) 루트는 `TabCoordinator`·`Tab`·`AppRoute`를 바인딩해야 하므로 12번 §9의 "`Layout/AdaptiveRoot`"는 컴파일될 수 없다(RT-A-09). `MwonmalUI/Layout/`에는 Domain을 모르는 `ListDetail`(2·3열)·`MwLayout` 환경값·`MwFlowLayout`·`MwReadableWidth`만 남긴다.

**화면 규칙(SDK 규칙 6 확장, iOS-C1 표 채택)**: 고정 높이 금지 → `minHeight`; 버튼·메타 행은 `ViewThatFits`; Dynamic Type `xxxLarge`↑ 카드 4블록 세로 단일 열(칩은 `MwFlowLayout`); 텍스트 상한·줄 수 제한 금지; 간격·아이콘은 `@ScaledMetric`; 넓은 화면 읽기 폭 상한 680pt(`MwReadableWidth`); 시트는 detent; Mac 최소 창 **1000×700**(D-20 유지, MI-6의 900×600 제안은 변경 근거 없어 탈락 — RT-A-19), 기본 1280×800; 폭 < 900이면 3열 → 2열+탭.

**iPad 입력(MI-3)**: 키보드 명령은 Mac과 같은 `Commands` 정의(⌘↩ 해석, ⌘N 새 회의, ⌘R 녹음, Esc, ⌘1~4 탭, Space 카드 뒤집기, 1~4 자기 평가). ⌘V는 `PasteButton`(iOS 16 / macOS 10.15) 공통 + Mac은 `onPasteCommand`(macOS 11 전용, 확인) 보조. 드롭은 구 시그니처 `dropDestination(for:action:isTargeted:)`(16/13) — 신 API는 iOS 26(확인). 포인터는 `hoverEffect`(iOS 13.4+, macOS 없음)를 프리미티브에만. iPad 카메라 OCR·Vision OCR은 v1.1(FD-8). ⌘R iPadOS 시스템 예약 여부 **확인 필요**.

**상태 복원**: `@SceneStorage`는 v1.1(FD-8). MI-2의 `@SceneStorage("mw.sidebar") var sidebar: NavigationSplitViewVisibility`는 컴파일되지 않는다 — `NavigationSplitViewVisibility`는 `Codable/Equatable/Sendable`만 채택하고 `RawRepresentable`이 아니며 `SceneStorage.init`은 Bool/Int/Double/String/URL/Data 또는 `RawRepresentable`(Int/String)만 받는다(Apple 문서, RT-A-10). v1.0은 사이드바 가시성을 `TabCoordinator`의 `@State`(창 수명)로만 보존하고, v1.1 씬 복원 시 `String`(JSON) 래퍼로 저장한다.

## 5. 영향 파일·문서
- 코드: `Modules/MwonmalUI/Sources/Layout/MwLayout.swift`(`enum MwLayout { case compact, wide }`, `@Entry var mwLayout`), `Layout/ListDetail.swift`, `Layout/MwFlowLayout.swift`, `Layout/MwReadableWidth.swift`; `Modules/Navigation/Sources/AdaptiveRoot.swift`(사이즈 클래스 읽어 환경 주입 + switch), `CompactRoot.swift`, `WideRoot.swift`; `Composition/AppCommands.swift`(`Commands` 1개, `FocusedValue` 2개); `Presentation/Translate/ComposeView.swift`(PasteButton·dropDestination).
- `.swiftlint.yml`: `no_fixed_height`(`.frame(height: <숫자>)`·`.frame(width:height:)` 리터럴 금지, 아이콘 크기는 토큰 상수만), `fixed_size_bare`, `hardcoded_font_size`, `hardcoded_spacing_literal`(S1까지 warning, S2 Day 13부터 error — QA §3-3).
- 12번: D-2 문구 "macOS(넓은 화면)는 펼치고" → "넓은 화면(`mwLayout == .wide`: iPad regular×regular, Mac)은 펼치고, 좁은 화면(iPhone, iPad Slide Over/1/3)은 접는다"; D-17 두 번째 불릿 교체; §8 "루트 뷰는 하나" → "루트 래퍼 하나(Navigation `AdaptiveRoot`), 구현 둘"; §8-3 절 제목 "창·메뉴·키보드(Mac·iPad 공유)"; §9 `Layout/` 설명 교체, SDK 규칙 6을 iOS-C1 규칙표로; §11 스냅샷 행을 ADR-0011 매트릭스로.
- 15번 T-E7에 "iPad 공유" 한 줄. 05번 §3 "시트 높이 명시" 옆에 "(Figma 캡처용, 코드는 `presentationDetents`)", §5 기기 표에 SE 375×667 행.
- 16번 Day 5·Day 10 "sidebarAdaptable 루트" → "AdaptiveRoot(compact·wide)". 이슈 #10(A-13/W-08은 Day 20으로 이동해 하루 유지 — PM).
- REQUIREMENTS E절 "12번 D-0 웹→macOS / REQ-01" 행 → ADR-0006.

## 6. 검증
- 단위: `MwLayout(h:v:)` 순수 함수 4조합 전수. Navigation 테스트 — `paths` 세팅 후 `mwLayout`을 compact→wide→compact로 바꿔도 `paths`·`selectedTab`·`sheet` 동일(코디네이터 단위).
- 스냅샷(ADR-0011 Tier2): iPhone Pro Max 가로(사이드바 없어야 함), iPad 11" 가로 1/2 Split(탭바), iPad 13" 가로 1/2 Split(사이드바), Slide Over(탭바), Mac 1000×700·1440×900·6K(읽기 폭 680 확인). 사이즈 클래스는 트레이트 오버라이드로 주입.
- XCUITest: iPad 시뮬레이터 Split View 진입 중 A-12 스택 유지 1개, 하드웨어 키보드 ⌘↩ → `translation_submitted` Spy.
- 린트 오탐률: 도입 첫 주 warning, disable 주석 ≤ 10개면 error 승격.
- Accessibility Inspector "Dynamic Type AX5"에서 잘림 0건(릴리스 체크리스트).
- iPad 13" vs 11" 1/2 Split 사이즈 클래스 표는 **확인 필요**(Apple 표) — 스냅샷 기대값 확정 전 재확인.

## 7. 리스크와 되돌리는 조건
- 리스크: 루트 트리 교체 순간 `RouteHost`의 `@State vm`이 재생성되어 화면 VM이 다시 로드된다(§8-4 수명 규칙과 일치, D-10 "서버가 진실"이라 refetch 허용). 단 **compact 시트로 열려 있던 W-01의 입력 중 텍스트는 iPad Split View 진입 순간 유실**된다(시트 VM은 시트 수명, RT-A §C-4) → W-01 초안을 `TabCoordinator`에 임시 보관하는 완화를 S2에서 검토. `ViewThatFits`는 후보를 전부 측정하므로 목록 행에는 쓰지 않는다. AX5에서 카드가 화면을 넘으면 화면이 스크롤(카드 높이 고정 금지의 귀결).
- 되돌리는 조건: Apple이 iPad에서 사이즈 클래스 의미를 바꾸면(현재 징후 없음) 창 폭 보조 규칙 추가. VM 재생성이 체감 깜빡임을 만들면 VM을 `TabCoordinator`의 라우트별 캐시로 올린다. iPad 사용 비율 < 5%(Amplitude platform)가 3개월이면 iPad 스냅샷을 야간으로만.
