# macOS·iPad 파트장 결정서 — 협의체 1차 (2026-09-19)

> 담당: macOS·iPad 파트장. 범위: REQ-01(iPad=넓은 레이아웃군), REQ-02(iOS 17/macOS 14 최소, macOS 관점), REQ-03(최소~최대 화면), REQ-04(워치 대비 알림·모델).
> 근거 문서: `docs/REQUIREMENTS.md`, `docs/design/12_앱_아키텍처_설계.md`(D-0·D-2·D-17·D-19·D-20·§8·§9·§13), `docs/design/02_UI흐름도.md`(v5.2 표), `docs/design/15_기술_트레이드오프_결정기록.md`(T-C2·T-D4·T-E1~E7), `docs/design/14_시스템_설계서.md`(§5-5·§11), `docs/design/05_디자인시스템.md`(166~167행 사이드바 264), `contracts/openapi.yml`(DevicePlatform 1822행, ReviewCard 2726행, /devices 1005행), `contracts/db.dbml`(user_devices 380행, notifications 395행), `apps/ios-macos/Project.swift`.
> Apple API 사실은 sosumi/apple-docs로 2026-09-19에 확인했다. 확인 못 한 것은 **확인 필요**로 표시했다.
> 결정 번호: `MI-n`(macOS·iPad 레이아웃), `MN-n`(알림·워치). 형식은 BRIEF의 7단계(의도→비용→대안→왜→영향→검증→리스크).

---

## 0. 먼저 확인한 Apple API 사실 (결정의 근거)

| API | 최소 버전 (확인) | 결정에 미치는 영향 |
|---|---|---|
| `TabViewStyle.sidebarAdaptable` | iOS 18 / macOS 15 | **iOS 17·macOS 14에서 없음.** 게다가 iPadOS에서는 "상단 탭바가 사이드바로 접히는" 모양이고 사이드바 고정이 아니다(문서 Discussion). REQ-01 "iPad = 사이드바·세 열"과 정확히 맞지 않음 → MI-1 |
| `NavigationSplitView` (+`columnVisibility`, `preferredCompactColumn`) | iOS 16 / macOS 13 / watchOS 9 | 17/14 최소에서 안전. compact에서는 스택으로 자동 접힘, "The split view ignores the visibility control when it collapses" |
| `EnvironmentValues.horizontalSizeClass` | iOS 13 / macOS 10.15 | macOS는 항상 `.regular`, watchOS는 항상 `.compact`, iPad Slide Over/Split View에 따라 바뀜(문서 명시) → 분기 축으로 적합 |
| `@Entry` 매크로 | iOS 13 / macOS 10.15 (back-deploy, Xcode 16 툴체인) | 15번 T-C2 표의 "17+면 `@Entry`를 잃는다"는 **오류**. D-3 Environment 방식 유지 가능 |
| `SpeechAnalyzer` | iOS 26 / macOS 26 | 17~25 폴백 필요 (D-7의 "받아쓰기 준비 중" 상태 재사용) |
| `SystemLanguageModel`(Foundation Models) | iOS 26 / macOS 26 | REQ-10 ② 트랙은 26+ 게이트 |
| `glassEffect(_:in:)` (Liquid Glass) | iOS 26 / macOS 26 | v1 미채택 (MI-5) |
| `onPasteCommand(of:perform:)` | **macOS 11 전용** | iPad ⌘V는 이걸로 안 됨 → `PasteButton`(iOS 16/macOS 10.15) |
| `dropDestination(for:action:isTargeted:)` | iOS 16 / macOS 13 (deprecated → `dropDestination(for:isEnabled:action:)` with `DropSession`; 새 API 최소 버전 **확인 필요**) | iPad·Mac 같은 코드. 17/14에서는 구 시그니처 사용 |
| `hoverEffect(_:)` | iOS 13.4+ (iPadOS 포인터), macOS 없음 | iPad 전용 포인터 효과 |
| `onHover(perform:)` | iOS 13.4 / macOS 10.15 | 양쪽 공통 |
| `keyboardShortcut(_:modifiers:)` | iOS 14 / macOS 11 | iPad 외장 키보드와 Mac 메뉴 공유 가능 |
| `TabSection`, `presentationSizing` | iOS 18 / macOS 15 | 17/14에서는 사용 불가 → 시트 크기는 `.frame(minWidth:)`로 |
| `Scene.windowResizability` | macOS 13 | 최소 창 크기 강제 가능 |
| `DataScannerViewController`(VisionKit) | iOS 16 / iPadOS 16, **macOS 없음** | iPad 카메라 OCR 후보(v1.1) |
| `UNUserNotificationCenter` | watchOS 3+ | 워치도 같은 카테고리·액션 모델 |
| `WKApplication.registerForRemoteNotifications()` | watchOS 7+ | 문서: "iOS 컴패니언이 있으면 **항상 워치와 iPhone 양쪽에 보내라. payload가 동일하면 시스템이 중복을 인식해 하나만 표시**" → MN-1 |
| Tuist `Destination.appleWatch` → `.watchOS`, `DeploymentTargets.multiplatform(iOS:macOS:watchOS:…)` | context7 `/tuist/tuist` | Domain을 워치 데스티네이션에 올릴 수 있음 → MN-2 |
| HIG Multitasking (2025-06-09 개정) | iPadOS 26 창 모드: 앱 창이 자유 크기, "Apps don't control multitasking configurations" | 폭 기준 하드코딩 금지, 사이즈 클래스가 유일한 진실 |

---

# 과제 A — REQ-01 iPad를 넓은 레이아웃군에 넣는 규칙

## MI-1. 레이아웃 분기 축은 "플랫폼"이 아니라 사이즈 클래스 두 개 모두 `.regular`

1. **의도**: iPad 13"·11" 가로/세로, iPad 창 모드(iPadOS 26), Split View, Slide Over, Mac 창 크기 변화를 **하나의 규칙**으로 처리한다. iPhone Pro Max 가로(가로 사이즈 클래스가 regular)에서 사이드바가 튀어나오는 사고를 막는다. REQ-01 "iPad = 사이드바·세 열, iPhone = 세로 접기"를 `#if os()` 없이 만족.
2. **비용**: 코드 — `MwonmalUI/Layout/AdaptiveRoot`에 환경값 하나(`@Entry var mwLayout: MwLayout`)와 루트 switch 1개. 시간 — S0 Day 5(TabCoordinator+루트) 안에서 +0.5일. 유지보수 — 화면마다 `mwLayout`만 읽으면 되므로 분기점이 한 곳. 돈 0.
3. **대안**:
   - (a) `UIDevice.current.userInterfaceIdiom == .pad`로 플랫폼 분기 — **탈락**: Slide Over/1/3 Split에서 iPad가 compact가 되는데 사이드바를 그리면 깨진다(HIG "앱은 멀티태스킹 구성을 알 수 없다"). Mac에는 `UIDevice`도 없다.
   - (b) 창 폭 임계값(예: ≥ 700pt면 넓은 레이아웃) — **탈락**: 기기·OS마다 사이즈 클래스 경계가 다르고(11" 1/2 Split은 compact, 13" 1/2는 regular — **확인 필요**, Apple 사이즈 클래스 표) Apple이 이미 계산해 준 값을 다시 만드는 바퀴 재발명(REQ-23).
   - (c) `horizontalSizeClass`만 — **탈락**: iPhone Pro Max 가로가 `.regular`라 사이드바가 뜬다. REQ-01 "iPhone은 세로 접기" 위반.
4. **왜**: `horizontalSizeClass == .regular && verticalSizeClass == .regular`이면 "넓은 화면"이다. iPad 전체화면·13" 1/2 Split·Mac은 둘 다 regular, iPhone은 어느 방향이든 하나는 compact, iPad Slide Over/1/3은 가로 compact. Apple 문서가 "Slide Over·Split View에 따라 바뀐다"고 보증하는 값이며, macOS는 항상 regular라 Mac에서 추가 분기가 필요 없다. 플랫폼 상수는 View 바깥에서 쓰지 않는다(D-15 "ViewModel에 `#if os()` 금지"와 같은 정신).
5. **영향 파일/문서**:
   - 12번 §1-1 D-2 "macOS(넓은 화면)는 펼치고" → "**넓은 화면(`mwLayout == .wide`: iPad regular×regular, Mac)** 은 펼치고, 좁은 화면(iPhone, iPad Slide Over/1/3 Split)은 접는다"로 문구 교체. 표 헤더 "macOS" → "넓은 화면(iPad·Mac)".
   - 12번 §8 D-17 "루트 뷰는 하나: iOS 26 `TabView` + `.sidebarAdaptable`" → **MI-2**로 교체.
   - 12번 §9 `Layout/AdaptiveRoot` 설명 갱신, `MwLayout` 환경값 추가.
   - 코드: `Modules/MwonmalUI/Sources/Layout/MwLayout.swift`(`enum MwLayout { case compact, wide }`, `@Entry var mwLayout`), `Modules/Composition/Sources/AppRootView.swift`(사이즈 클래스 읽어 환경 주입).
   - REQUIREMENTS E표 "12번 D-0 웹→macOS / REQ-01" 행 → "결정 MI-1·MI-2, 2026-09-19".
6. **검증 방법**: 스냅샷 매트릭스 MI-6의 iPhone Pro Max 가로(사이드바 없어야 함), iPad 11" 가로 1/2 Split(탭바), iPad 13" 가로 1/2 Split(사이드바), Slide Over(탭바). 단위 테스트: `MwLayout(h:v:)` 순수 함수 4조합 전수.
7. **리스크와 되돌리는 조건**: iPadOS 26 창 모드에서 아주 작은 창(세로 compact가 되는 경우가 있는지 **확인 필요**)이면 compact로 떨어져 탭바가 뜬다 — 의도된 동작. 되돌림: Apple이 iPad에서 사이즈 클래스 의미를 바꾸면(현재 징후 없음) 창 폭 보조 규칙 추가.

## MI-2. 루트는 두 개(compact `TabView`, wide 2열 `NavigationSplitView`), 상태는 `TabCoordinator` 하나가 소유 — "세 열"은 라우트 안에서 그린다

1. **의도**: compact↔wide 전환 시 `[AppRoute]`·`selectedTab`·시트가 **그대로 살아남고**, D-17 "탭당 경로 하나"와 딥링크 순수 함수(§8-2)가 레이아웃과 무관하게 동일하게 유지되도록 한다. `sidebarAdaptable`(iOS 18+) 의존을 제거해 REQ-02(17/14)를 만족한다.
2. **비용**: 루트 뷰 2종(약 80줄), `ListDetail`/3열 컨테이너 1개(이미 §9 계획에 있음). 사이드바 항목=`Tab` 4개 + 프로젝트 섹션(05번 167행 사이드바 구성) 매핑 코드. 시간 +1일(S0 Day 5 → Day 10 사이). 유지보수: 화면 View는 `mwLayout`만 보고 자기 내부 배치를 바꾸며 라우팅 코드는 손대지 않는다. 돈 0.
3. **대안**:
   - (a) `TabView` + `.sidebarAdaptable` 하나(원안 D-17) — **탈락**: iOS 18/macOS 15 최소라 REQ-02 위반. `@available` 분기로 두 루트를 어차피 써야 하므로 "루트 하나"의 장점이 사라진다. iPadOS에서 사이드바가 기본이 아니다(상단 탭바).
   - (b) 세 열 `NavigationSplitView(sidebar:content:detail:)`를 루트로 두고 `paths[.projects]`의 첫 요소를 content 열 선택으로 해석 — **탈락**: `[AppRoute]`의 의미가 compact(스택)와 wide(열 선택+스택)에서 달라져 D-17 순수 함수·`@SceneStorage` 복원·딥링크 교체 규칙이 두 벌이 된다. 1인 개발에서 가장 비싼 종류의 분기.
   - (c) 항상 `NavigationSplitView`(compact에서는 자동으로 스택으로 접힘) 하나 — 보류 후 **탈락**: iPhone에서 탭바가 사라지고 사이드바 목록이 첫 화면이 된다. 02번 v5.2의 A-01 홈(탭바) 설계와 다르다.
4. **왜**: `TabCoordinator`(창 수명, §8-4)를 루트 switch **위**에 `@State`로 만들고, compact 루트(`TabView(selection: $tc.selectedTab)` 안 `NavigationStack(path: $tc.paths[tab])`)와 wide 루트(`NavigationSplitView(columnVisibility:)`의 사이드바 `List(selection: $tc.selectedTab)`, detail = 같은 `NavigationStack(path: $tc.paths[tab])`)가 **같은 바인딩**을 쓴다. 사이즈 클래스가 바뀌면 SwiftUI는 뷰 트리를 갈아 끼우지만 상태는 코디네이터에 있으므로 경로가 보존된다. `.sheet(item: $tc.sheet)`와 `AppRootView`의 녹음 인디케이터도 switch 위에 붙여, 시트가 열린 채 Split View로 들어가도 시트가 닫히지 않는다. "세 열 동시"(D-2 표의 Project·Meeting 행)는 A-11/W-00 라우트 View 내부에서 `mwLayout == .wide`일 때 `ListDetail` 3열(회의 목록 | 할 일 | 모르는 말)로 그린다 — 라우트는 한 개, 열은 그 안의 레이아웃.
   - 탭→사이드바 매핑: 사이드바 = `Tab` 4개(홈·프로젝트·복습·MY) 고정 섹션 + "프로젝트" 섹션(`getProjects` 목록, 05번 167행). 프로젝트 항목 탭 = `selectedTab = .projects; paths[.projects] = [.project(id)]`(D-18 정신: 탭 넘는 push 없음). MY는 Mac에서 `Settings` 씬(D-20)이므로 Mac 사이드바에는 MY가 없고 iPad 사이드바에는 있다(`Settings` 씬은 macOS 전용 — Apple 문서 재확인 **확인 필요**).
   - 열 가시성: `@SceneStorage("mw.sidebar") var sidebar: NavigationSplitViewVisibility = .all`. compact로 접히면 무시되고(문서), 다시 wide가 되면 저장값으로 복원. 사이드바 폭 264 고정(05번 167행), `navigationSplitViewColumnWidth(264)`.
   - iPad `sidebarAdaptable` 스타일이 주는 "탭바→사이드바 사용자 토글"은 포기한다(iOS 18+ 전용이고 REQ-01은 사이드바 고정을 요구).
5. **영향 파일/문서**: 12번 §8 D-17 두 번째 불릿 전체 교체(위 문구), §8-4 수명표 "루트 View `@State`" 유지, §9 `Layout/AdaptiveRoot` → "compact/wide 루트 2종 + ListDetail(2·3열)". 코드: `Composition/AppRootView.swift`, `Composition/CompactRoot.swift`, `Composition/WideRoot.swift`, `MwonmalUI/Layout/ListDetail.swift`. 16번 Day 5·Day 10의 "sidebarAdaptable 루트" 문구 → "AdaptiveRoot(compact·wide)".
6. **검증 방법**: Navigation 테스트 — `paths` 세팅 후 `mwLayout`을 compact→wide→compact로 바꿔도 `paths`·`selectedTab`·`sheet` 동일(ViewInspector 없이 코디네이터 단위로). XCUITest(16번 §1-1 macOS 2흐름)에 "iPad 시뮬레이터 Split View 진입 중 A-12 스택 유지" 1개 추가. 스냅샷: 사이드바 접힘/펼침(12번 §11 기존).
7. **리스크와 되돌리는 조건**: 루트 트리 교체 순간 `RouteHost`의 `@State vm`이 재생성되어 화면 VM이 다시 로드된다(라우트 수명 규칙 §8-4와 일치, "서버가 진실"이라 refetch는 허용 D-10). 녹음 중이면 `RecordingSession`이 앱 수명 actor(D-16)라 유실 없음. 되돌림: VM 재생성이 체감 깜빡임을 만들면 VM을 `TabCoordinator`의 라우트별 캐시로 올린다(§8-4 수명표 한 줄 수정).

## MI-3. iPad 입력 장치: 키보드 명령은 Mac과 한 정의를 공유, 포인터·드롭·붙여넣기는 공통 API만

1. **의도**: 회의실 iPad(Magic Keyboard·트랙패드·Apple Pencil 드래그)에서 Mac과 같은 손맛. T-E7(⌘↩ 해석, ⌘N 새 회의, ⌘R 녹음, Esc)을 iPad에서 공짜로 얻는다.
2. **비용**: `Composition/AppCommands.swift`(`Commands` 1개, `FocusedValue` 2개) 양 앱 타깃에서 `.commands { AppCommands() }`. `PasteButton` 1개. `hoverEffect` 는 SDK 프리미티브에 `#if os(iOS)` 한 줄씩. 시간 +0.5일(S2 Day 14에 포함). 돈 0.
3. **대안**:
   - (a) iPad는 터치만, 단축키는 Mac 전용 — **탈락**: 같은 `CommandGroup`이 iPadOS에서 ⌘ 길게 누르기 오버레이·iPadOS 26 메뉴 막대(HIG 영상 "Elevate the design of your iPad app")에 그대로 뜬다. 안 하면 손해만.
   - (b) iPad에서 `onPasteCommand`로 ⌘V — **탈락**: macOS 11 전용 API(확인). 대신 `PasteButton(payloadType: Data.self)`(iOS 16/macOS 10.15)를 W-01에 두면 iPad·Mac 공통이고, iOS 17에서 클립보드 읽기 권한 배너를 피한다(T-D2의 "사용자 동작 뒤에서만 읽기"와 일치).
4. **왜**: SwiftUI 키보드 단축키 해석 규칙(문서: "macOS는 key window→main window→command groups, 다른 플랫폼은 active scene→command groups")이 같아서 정의 하나로 두 플랫폼이 동작한다. 드롭은 `dropDestination(for: Data.self)`가 iOS 16/macOS 13 공통이라 W-01의 "이미지→Vision OCR"(D-6) 경로가 iPad Split View에서 사진 앱 드래그로도 열린다. 포인터: `hoverEffect(.highlight)`는 iPad 전용, `onHover`는 공통 — 프리미티브(`MwButton`, `MeetingRow`, `MwChip`)에만 넣고 화면 코드에는 안 넣는다(SDK 규칙 1).
   - 단축키 표(공유): ⌘↩ 해석하기(W-01 포커스 시), ⌘N 새 회의(프로젝트 컨텍스트 있을 때), ⌘R 녹음 시작/정지(A-12/W-07), Esc 시트 닫기, ⌘1~4 탭 전환(사이드바 항목 순서, iPad·Mac 동일), Space 복습 카드 뒤집기(A-03), 1~4 자기 평가(A-04). 충돌 검토: ⌘R은 iPadOS 시스템 예약 아님(**확인 필요**).
5. **영향 파일/문서**: 12번 §8-3 "macOS 창·메뉴" → "창·메뉴·키보드(Mac·iPad 공유)"로 절 제목 변경, `.onPasteCommand`는 Mac 추가 경로로만 남기고 `PasteButton`을 공통으로 명시. 15번 T-E7에 "iPad 공유" 한 줄. 코드: `Composition/AppCommands.swift`, `Presentation/Translate/ComposeView.swift`(PasteButton·dropDestination), `MwonmalUI/Primitives/*`(hover).
6. **검증 방법**: XCUITest iPad 시뮬레이터에서 하드웨어 키보드 ⌘↩ → `translation_submitted` 이벤트 Spy. 드롭: 단위 테스트로 `Data → CGImage → OcrService` 경로(Fake). 스냅샷: 호버 상태는 스냅샷 제외(포인터 상태 재현 불가) — Catalog에서 수동.
7. **리스크와 되돌리는 조건**: `FocusedValue`로 "현재 회의/현재 입력창"을 노출해야 메뉴 활성화가 정확하다(T-E7 지적). 포커스가 없으면 ⌘↩이 무반응 — 메뉴 항목을 `disabled`로 보여 준다. 되돌림: 없음(공통 API만 사용).

## MI-4. iPad 고유: 회전·카메라 OCR·권한 문구·홈 사이즈 클래스 표

1. **의도**: iPad에서만 생기는 상황(녹음 중 회전, 카메라 있음, 창 모드)을 v1 범위 안에서 깨지지 않게 하되, 새 기능은 최소로.
2. **비용**: `NSCameraUsageDescription` 1줄(iOS 타깃), 카메라 캡처 시트 1개(`UIImagePickerController` 래핑 또는 `PhotosPicker`+카메라 소스 — 약 60줄), 회전 스냅샷 4장. 시간 +1일(S2 Day 14~15). 돈 0.
3. **대안**:
   - (a) 카메라 OCR을 `DataScannerViewController` 라이브 텍스트로 — **v1 탈락**: iOS 16+로 가능하지만 UIKit 컨트롤러 래핑·델리게이트·권한·macOS 부재로 v1 비용 대비 큼. v1.1 후보로 남긴다(T-D2 공유 익스텐션과 같은 칸).
   - (b) 카메라 없이 사진 앱 선택만 — **탈락**: 회의실 화이트보드·프로젝터 캡처가 iPad의 핵심 순간(REQ-01 "회의실에서 iPad"). 촬영→같은 Vision 파이프라인(D-6)이면 추가 경로가 아니라 입력 소스 하나 추가.
4. **왜**:
   - **녹음 중 회전**: `RecordingSession`이 앱 수명 actor(D-16)이고 화면은 `snapshot()`+`updates()`로 복원(§7)하므로 회전으로 View가 재구성돼도 상태 유실 없음. 회전 중 `Waveform`은 `fixedSize` 금지(SDK 규칙 6)와 `GeometryReader` 폭 기준 재샘플링만 지키면 된다. iPad는 세로 잠금이 없으므로 `UISupportedInterfaceOrientations~ipad` 4방향 유지(현재 기본값). 라이브 액티비티가 iPad에서 어느 버전부터 표시되는지 **확인 필요**(T-D1은 iPhone 기준).
   - **카메라 OCR**: 입력 소스는 계약 그대로 `inputSource: SCREENSHOT`, `sourceImageUrl: null`(D-6). 촬영 이미지는 메모리에서 Vision 처리 후 폐기(§12 위협 모델 "캡처 이미지" 행 그대로). Mac은 v1에 카메라 없음(Continuity Camera **확인 필요**, v1.1).
   - **권한 문구**: 마이크·음성인식은 현재 `Project.swift`의 문구가 iPhone·iPad·Mac 공통으로 적절("회의를 녹음해 받아쓰기와 해석에 씁니다."). 추가: `NSCameraUsageDescription: "회의실 화이트보드나 화면을 찍어 글자를 읽어 해석에 씁니다. 사진은 기기 밖으로 나가지 않습니다."` — iOS 타깃에만. `NSPhotoLibraryUsageDescription`은 `PhotosPicker`가 권한 없이 동작하므로 불필요(**확인 필요**: iOS 17 PhotosPicker 무권한 동작).
   - **A-01 홈 사이즈 클래스 표** (규칙 MI-1 적용 결과):

   | 환경 | h | v | `mwLayout` | A-01 홈 모양 |
   |---|---|---|---|---|
   | iPhone 세로 (SE 4.7" 포함) | C | R | compact | 탭바, 세로 카드 스택(D-2 iPhone 열) |
   | iPhone 가로 (Pro Max 포함) | R 또는 C | C | compact | 탭바, 가로는 2열 카드까지만 |
   | iPad 세로 전체화면 (11"/13") | R | R | wide | 사이드바 264 + 오늘 요약 전부(D-2 macOS 열) |
   | iPad 가로 전체화면 | R | R | wide | 같음 + 프로젝트 섹션 펼침 |
   | iPad Split View 2/3 (주 앱) | R | R | wide | 같음 |
   | iPad Split View 1/2 — 13" | R (**확인 필요**) | R | wide | 사이드바 접힘 기본(`.detailOnly` 저장값) |
   | iPad Split View 1/2 — 11" | C (**확인 필요**) | R | compact | 탭바 |
   | iPad Split View 1/3, Slide Over | C | R | compact | 탭바 |
   | iPadOS 26 창 모드 (자유 크기) | 창 폭 따라 | R | 사이즈 클래스 따라 | 위 규칙 자동 |
   | Mac 900×600 ~ 6K | R(항상) | R(항상) | wide | 사이드바 + 최대 콘텐츠 폭 1120(05번 규칙) 가운데 정렬 |
5. **영향 파일/문서**: `apps/ios-macos/Project.swift` MwonmalIOS `infoPlist`에 `NSCameraUsageDescription` 추가(저장소 수정은 협의 후). 12번 §7에 "iPad 회전: 상태는 actor, View는 재구성" 한 줄, §8-3에 "iOS(iPhone·iPad)는 `PhotosPicker` + 카메라 촬영 + 공유 시트". 12번 §12 위협 모델 "캡처 이미지" 행에 "카메라 촬영 포함". 02번 W-01 행 🟦에 "iPad·iPhone 카메라 촬영 가능".
6. **검증 방법**: 스냅샷 MI-6의 iPad 가로/세로 W-02 녹음 화면. XCUITest iPad: 녹음 시작 → 회전 → 경과 시간 연속성(정지 버튼 존재). 카메라는 시뮬레이터 불가 → 실기기 체크리스트(`docs/qa/`).
7. **리스크와 되돌리는 조건**: 카메라 촬영 이미지 해상도가 커서 Vision 지연 > 2초면 `VNImageRequestHandler` 전 다운샘플(긴 변 2048). 되돌림: 촬영 OCR 오인식률이 높으면 v1.1 `DataScannerViewController` 라이브 텍스트로 교체(같은 `OcrService` 프로토콜 뒤).

## MI-5. macOS 14 / iOS 17 최소에서 사라지는 것과 폴백 (T-C2 재결정 지원 표)

1. **의도**: REQ-02를 지키면서 26 전용 기능은 `@available` 게이트 + 폴백으로. "무엇을 잃고 무엇으로 대신하나"를 표로 고정해 T-C2 폐기 후 빈자리를 메운다.
2. **비용**: 게이트 5곳, 폴백 상태 1개(D-7 재사용), 스냅샷 OS 축 1개 추가(러너에 iOS 17 시뮬레이터 1종). CI 시간 +약 3분/PR(**측정 후 확정**). 돈 0(무료 GitHub Actions 한도 내, self-hosted 러너 우선 16번 §1).
3. **대안**:
   - (a) 26 only 유지(T-C2 원안) — **탈락**: REQ-02가 확정.
   - (b) iOS 18/macOS 15 최소(중간안) — **탈락**: REQ-02가 17/14를 명시. `sidebarAdaptable`·`presentationSizing`·`TabSection`을 얻지만 MI-2로 이미 불필요.
4. **왜 / 표**:

   | 잃는 것 (최소 버전) | 어디서 쓰였나 | 17/14 폴백 | 비고 |
   |---|---|---|---|
   | `sidebarAdaptable` (18/15) | D-17 루트 | MI-2 `NavigationSplitView`(16/13) + `TabView` | 폴백이 아니라 대체. 게이트 불필요 |
   | `TabSection` (18/15) | 사이드바 섹션 | `List` `Section` | 게이트 불필요 |
   | `presentationSizing` (18/15) | W-06·W-02a 시트 폭 520(05번 126행) | 시트 콘텐츠 `.frame(minWidth: 520)` (Mac), iPad는 기본 form sheet | 게이트 불필요 |
   | `glassEffect` / Liquid Glass (26/26) | 05번 `.modal` 글래스, 사이드바 "글래스"(05번 167행) | **v1 미채택**: `.regularMaterial` 또는 크림 종이 단색. 라이트 고정(D-23)·팔레트 전제와 맞고 스냅샷 두 벌을 피함 | v1.1 D-23 다크와 함께 재검토 |
   | `SpeechAnalyzer` (26/26) | D-7 W-02 실시간 미리보기 | `if #available(iOS 26, macOS 26, *)` 아니면 미리보기 없이 파형만 + "실시간 받아쓰기는 iOS 26부터" 한 줄(D-7 "받아쓰기 준비 중" 상태 재사용). `SFSpeechRecognizer` 폴백은 v1에 **안 함**(ko-KR 온디바이스 품질·인터럽션 처리 두 벌) — **확인 필요**: `SFSpeechRecognizer` ko-KR `supportsOnDeviceRecognition` | Platform `TranscribingService` 구현체 2개가 아니라 1개 + `nil` |
   | Foundation Models (26/26) | REQ-10 ② 트랙 | 서버 라우터(14번 §15). `SystemLanguageModel.default.availability` 확인 후에만 사용 | AI 파트 결정과 연동 |
   | `@Entry` | D-3 | **잃지 않음**(back-deploy 확인). T-C2 표 정정 | Xcode 16+ |
   | Swift Testing | 12번 §11 | iOS 17 시뮬레이터에서 실행 가능 여부 **확인 필요**(Xcode 16 번들) | 불가 시 XCTest 브리지 |
   | iOS 26 클립보드 감지(T-D2 "권한 팝업 회피") | W-01 배너 | `UIPasteboard.detectPatterns`(iOS 16+, **확인 필요**)로 내용 안 읽고 패턴만 감지, 붙여넣기는 `PasteButton` | |
   | `dropDestination(for:isEnabled:action:)` 신 API | W-01 드롭 | 구 시그니처 `dropDestination(for:action:isTargeted:)`(16/13) 사용, deprecation 경고는 허용 목록 | 신 API 최소 버전 **확인 필요** |
   | 라이브 액티비티 iPad 표시 | T-D1 | **확인 필요** | iPhone은 16.1+ |
   | `symbolEffect`, `ContentUnavailableView`, `@Observable`, `.onChange(of:initial:)`, `inspector` (17/14) | 곳곳 | 최소 버전 안 — 사용 가능 | |
5. **영향 파일/문서**: 15번 T-C2 결정문 교체("17+ 지원, 26 기능은 게이트") + 표의 `@Entry` 정정. 12번 머리말 "기준: iOS 26 / macOS 26" → "iOS 17 / macOS 14 최소, 26 기능은 `@available`". 12번 D-7에 폴백 상태 문구. 12번 §11 스냅샷 행에 OS 축. `Project.swift` 전 타깃 `deploymentTargets` 17.0/14.0(BRIEF 지시). 05번 `.modal`/사이드바 "글래스" → "머티리얼(26에서 글래스, v1.1)".
6. **검증 방법**: CI `test` job 매트릭스에 iOS 17.x 시뮬레이터 1종 + macOS 러너의 최소 OS는 러너 OS 한계(macOS 14 러너는 hosted `macos-14` 존재 **확인 필요**). 게이트마다 "미지원 경로" 단위 테스트(Fake `TranscribingService` = nil → W-02 파형만).
7. **리스크와 되돌리는 조건**: iOS 17 사용자에게 W-02 미리보기가 없어 "차별점" 체감이 줄어든다(T-C2의 원래 우려). 스토어 OS 분포로 26 비율 > 90%가 6개월 지속되면 최소 버전을 올리는 역방향 되돌림을 REQ-02 재협의로 올린다.

## MI-6. 넓은 레이아웃에서 달라지는 화면 목록(32장) + 스냅샷 매트릭스

**화면 32장 = iOS 22(O-1~3, S-01, S-00-1~5, A-01~13) + 웹 10(W-08, W-00, W-06, W-07, W-01, W-02a, W-02, W-04, W-03, W-05)** (02번 v5.2 표). 공용 화면은 D-15 규칙대로 두 ID 병기.

| 화면 ID | compact(iPhone·iPad 좁음) | wide(iPad·Mac) | iPad만 다른 것 |
|---|---|---|---|
| O-1~3, S-01, S-00-1~5 | 전체 화면 한 장에 질문 하나 | 창 가운데 카드 폭 560(D-2 "창 가운데 카드") | 없음 |
| A-01 홈 (= W-08 요약 역할) | 탭바 + 세로 스택 | 사이드바 + 오늘 요약 전부, 프로젝트 칩 대신 사이드바 프로젝트 섹션 | 터치 타깃 44pt 유지(포인터 있어도) |
| A-13 프로젝트 목록 / W-08 | 프로젝트 탭 첫 화면 | **화면이 사라지고 사이드바 섹션**이 됨(05번 167행). detail은 선택 프로젝트 A-11/W-00 | 없음 |
| A-10 프로젝트 시트 | 바텀 시트 | 사이드바 "현재 프로젝트 카드(전환)"로 흡수, 시트 없음 | iPad wide에서도 시트 대신 사이드바 카드(팝오버 아님) |
| A-11 / W-00 프로젝트 | 회의 목록 + 버튼 2개, 할 일·모르는 말은 탭 | **세 열 동시**(회의 | 할 일 | 모르는 말) — 라우트 하나 안에서 `ListDetail` 3열, 폭 < 900이면 2열+탭(MI-2) | 없음 |
| A-12 / W-07 회의 상세 | 제목·녹음 상태·해석 목록, 전문은 한 번 더 | 전문 + 할 일 + 용어 동시(2열: 전문 | 할 일·용어) | 회전 시 열 재배치 |
| W-06 새 회의 | 시트 | 시트(모달 520) | 없음 |
| W-01 판교어 해석 (A-11 "판교어 해석" 시트) | **시트**(§6) | **detail 열 화면**으로 push(`.compose(meetingId?)`), 사이드바 유지, ⌘↩ | `PasteButton`·카메라 버튼 노출(MI-3·4) |
| W-02a 동의 | 시트, `interactiveDismissDisabled` | 같음 | 없음 |
| W-02 녹음 중 | push, 파형 전체 폭 | detail 열 안, 파형 + 미리보기 2열 | 회전 |
| W-04 해석 중 | push, `replaceLast`(§8-1) | 같음 | 없음 |
| A-06 / W-03 해석 결과 | 쉬운 말 + 할 일 첫 화면, 숨은 뜻·용어 접힘 | **4블록 전부**(원문 형광펜 | 쉬운 말·할 일 | 숨은 뜻·용어) | 없음 |
| A-03 / A-04 복습 | 카드 전체 폭 | 카드 최대 폭 560 가운데, 키보드 Space/1~4 | 없음 |
| W-05 모르는 말 (`.deck`) | Project 탭 스택 push, 목록 | 목록 + 필터 칩 + 오른쪽 카드 미리보기 2열 | 없음 |
| A-07 / A-08 시험 | 문제 하나 | 같음, 최대 폭 560 | 없음 |
| A-09 MY | 탭 | **Mac: `Settings` 씬(D-20)**, **iPad: 사이드바 항목**(Settings 씬 없음) | iPad에서 "복습 알림은 이 기기로도 옵니다"(iPad는 IOS 토큰 등록, MN-1 참조) |
| A-02 잠금화면, A-05 알림 센터 | 시스템 UI | Mac: 로컬 알림(D-19) 시스템 UI | iPad: iPhone과 동일(APNs) |

**스냅샷 매트릭스** (swift-snapshot-testing, 12번 §11 행을 이것으로 교체). 기기 pt 값은 대표값이며 정확한 논리 해상도는 **확인 필요**(기종별).

| 축 | 값 | 비고 |
|---|---|---|
| iPhone | SE 375×667(최소, REQ-03) / 16 Pro 402×874 세로 / Pro Max 가로 932×430 | Pro Max 가로 = "사이드바 없어야 함" 회귀 |
| iPad 11" | 834×1194 세로 / 1194×834 가로 | |
| iPad 13" | 1024×1366 세로 / 1366×1024 가로 | |
| iPad Split | 11" 가로 1/2 ≈ 592×834(compact) / 13" 가로 1/2 ≈ 678×1024(wide) / 1/3 ≈ 375×834 / Slide Over 320×… | 사이즈 클래스는 트레이트 오버라이드로 주입(`.environment(\.horizontalSizeClass, .compact)`) |
| Mac | 900×600(최소창 — 12번 §8-3 "최소 폭 1000"과 **불일치, 900으로 낮추는 안 제안**) / 1280×800(기본 — 12번 `.defaultSize(1200,800)`과 불일치, 1280 제안) / 6K 3008×1692@1x | 6K는 1x 렌더로 파일 크기 억제, 최대 콘텐츠 폭 1120 가운데 정렬 확인 |
| Dynamic Type | iOS: L, AX3 / Mac: 시스템 기본 | SDK 규칙 6 |
| OS | iOS 17 시뮬레이터 1종 + 최신 / macOS 러너 1종 | MI-5 |
| 상태 | 기본 / 빈 상태 / 에러 | 12번 §11 |
| 사이드바 | 접힘 / 펼침 (wide만) | 12번 §11 |

기기 12 × 흐름 4(홈, 해석 결과, 회의 상세, 복습) = 48 기본 + Dynamic Type·상태 변형은 iPhone 16 Pro와 iPad 13" 가로에만 적용해 총 ~90장으로 제한(CI 시간). 파일명 `{화면ID}_{기기}_{layout}_{dt}_{state}.png`.

---

# 과제 B — REQ-04 워치 대비 알림 설계

## MN-1. APNs payload = `aps`(표시·카테고리) + `mw`(우리 딕셔너리, `deepLink` URL이 유일한 행동 계약)

1. **의도**: iPhone·iPad(v1.0), Mac(v1.1 `MACOS`), 워치(v2)가 **같은 payload**를 받아 같은 규칙으로 이동한다. Apple 문서 지시("컴패니언이 있으면 양쪽에 보내고, payload가 동일하면 하나만 표시")를 만족하려면 payload가 플랫폼 무관해야 한다. 원문·받아쓰기·오디오는 APNs(애플 서버)로도 나가면 안 된다(REQ-14 확장 해석).
2. **비용**: 서버 Day 18(APNs 어댑터) 구현 시 딕셔너리 키 확정 — 추가 시간 0(어차피 만든다). 앱 `DeepLink.parse` 순수 함수 1개(§8-2 계획 그대로). yml에 `PushPayload` 스키마 문서화는 v1.1 백로그(HTTP op가 아니라 43 ops에 영향 없음). 픽스처 JSON 4개. 돈 0(APNs 무료).
3. **대안**:
   - (a) 14번 §5-5의 현재 안 `{type, translationId?, meetingId?, projectId?, quizId?, badge}`를 최상위 키로 — **탈락**: 최상위 커스텀 키는 `aps`와 섞여 네임스페이스 충돌·버전 관리가 어렵고, 워치가 4종 type마다 ID 조합 규칙을 알아야 한다(로직 중복).
   - (b) ID 없이 `deepLink`만 — **탈락**: iOS의 §8-2 "조상 ID 보강" 규칙은 payload에 ID가 있으면 API 호출 0회. 워치는 `deepLink`만 쓰고 iOS는 ID를 활용하는 두 층 구조가 낫다.
   - (c) `mutable-content` + Notification Service Extension으로 앱이 payload를 보강 — **탈락**: 타깃 하나 더, 워치는 익스텐션 미지원 경로.
4. **왜 / 스키마 v1**:

```jsonc
{
  "aps": {
    "alert": { "title": "얼라인, 기억나세요?", "body": "오늘 복습 12장" },   // 문구는 notifications.title/body(dbml 395행). 원문·transcript 절대 금지
    "badge": 12,                    // getMyStats.dueCount (§8-2 배지 규칙과 동일 출처)
    "sound": "default",
    "category": "REVIEW_REMINDER",  // == NotificationType 문자열. iOS·watchOS UNNotificationCategory identifier 동일
    "thread-id": "review",          // review | action | decode | level
    "interruption-level": "active"  // ACTION_DUE는 "time-sensitive" 후보(엔타이틀먼트 필요, 확인 필요)
  },
  "mw": {
    "v": 1,                                   // 스키마 버전. 앱은 v > 자기 버전이면 deepLink만 사용
    "type": "REVIEW_REMINDER",                // NotificationType 4종
    "deepLink": "mwonmal://review/session",   // 유일한 행동 계약. 워치는 이것만 파싱
    "notificationId": 9912,                   // notifications.id — 열림 이벤트 dedupe·notification_opened 속성
    "sentAt": "2026-09-19T18:00:00+09:00",    // v1.1 날짜 규칙(T-B5) 선적용, 앱 KSTDateTranscoder가 오프셋 허용(D-13)
    "review":  { "dueCount": 12 },                                           // type별 섹션은 하나만 존재
    "action":  { "translationId": 0, "actionId": 0, "meetingId": 0, "projectId": 0, "dueAt": "…" },
    "decode":  { "translationId": 0, "recordingId": 0, "meetingId": 0, "projectId": 0 },
    "levelUp": { "quizId": 0, "levelCode": "SETTLER" }
  }
}
```
   - `deepLink` 문법(서버가 생성, 앱은 파싱만): `mwonmal://review/session` · `mwonmal://projects/{p}/meetings/{m}` · `mwonmal://projects/{p}/meetings/{m}/translations/{t}` · `mwonmal://quizzes/{q}/result`. §8-2의 (Tab, [AppRoute]) 매핑과 1:1. 나중에 Universal Link(`https://mwonmal.kr/...`)로 바꿔도 경로 부분은 동일.
   - APNs 헤더: `apns-collapse-id = review-{userId}-{yyyyMMdd}`(REVIEW_REMINDER 하루 1개, 14번 §5-5 SETNX와 이중 안전), `apns-topic`은 플랫폼별(`kr.mwonmal.app`, v2 `kr.mwonmal.app.watchkitapp`), `apns-push-type: alert`. 4KB 한도 내(현재 ~600B).
   - 워치 동작: 컴패니언 미러링(v2 1단계)이면 등록 없이 iPhone 알림이 워치에 뜨고 탭 시 iPhone 앱 열림. 독립 워치 앱(v2 2단계)이면 `WATCHOS` 토큰 등록 후 서버가 IOS·WATCHOS 양쪽에 **동일 payload** 발송 → 시스템이 중복 제거(Apple 문서).
   - 프라이버시 불변식 추가: `aps.alert`에는 사전 용어(`termKo`)·개수·회의 **제목**까지만. `DECODE_DONE` body는 "회의 '스프린트 계획' 해석이 끝났어요" 형식, transcript 발췌 금지. 12번 §10 불변식에 "APNs payload" 열 추가.
   - **계약 v1.1 문안 제안(yml)** — `components/schemas` 추가·수정:
```yaml
    DevicePlatform:
      type: string
      description: |
        IOS(iPhone·iPad APNs) / WEB(예약) / MACOS(v1.1, Mac App Store 앱 APNs) /
        WATCHOS(v1.1 예약, 독립 워치 앱 토큰. 컴패니언 미러링만 쓰는 동안은 등록하지 않음)
      enum: [IOS, WEB, MACOS, WATCHOS]
    NotificationType:
      type: string
      description: REVIEW_REMINDER(퇴근길 복습) / ACTION_DUE(할 일 마감 30분 전) / DECODE_DONE(녹음 해석 완료) / LEVEL_UP(등급 업)
      enum: [REVIEW_REMINDER, ACTION_DUE, DECODE_DONE, LEVEL_UP]
    PushPayload:
      type: object
      description: APNs 커스텀 딕셔너리 `mw`. HTTP 응답이 아니라 문서화 목적. aps.category == type.
      required: [v, type, deepLink, notificationId, sentAt]
      properties:
        v: { type: integer, example: 1 }
        type: { $ref: '#/components/schemas/NotificationType' }
        deepLink: { type: string, format: uri, pattern: '^mwonmal://', example: 'mwonmal://review/session' }
        notificationId: { type: integer, format: int64 }
        sentAt: { type: string, format: date-time, description: '+09:00 오프셋 포함' }
        review:  { type: object, nullable: true, properties: { dueCount: { type: integer } } }
        action:  { type: object, nullable: true, properties: { translationId: {type: integer, format: int64}, actionId: {type: integer, format: int64}, meetingId: {type: integer, format: int64}, projectId: {type: integer, format: int64}, dueAt: {type: string, format: date-time} } }
        decode:  { type: object, nullable: true, properties: { translationId: {type: integer, format: int64}, recordingId: {type: integer, format: int64}, meetingId: {type: integer, format: int64}, projectId: {type: integer, format: int64} } }
        levelUp: { type: object, nullable: true, properties: { quizId: {type: integer, format: int64}, levelCode: { $ref: '#/components/schemas/LevelCode' } } }
```
   `DeviceRequest.pushToken.description`: "IOS일 때 APNs 토큰" → "IOS·MACOS·WATCHOS일 때 APNs 토큰(플랫폼별 topic은 서버가 platform으로 결정)". dbml: `Enum device_platform`에 `MACOS`, `WATCHOS` 추가, `notifications.deep_link varchar(255)` 추가(발송 기록 재현용, `target_id`는 유지).
5. **영향 파일/문서**: 12번 §8-2 "payload 계약은 §13" → 이 스키마로 구체화, §13 표 "알림 payload 스키마" 행 → `mw` + `PushPayload`, `NotificationType` 행 유지. 12번 §10 불변식에 APNs 열. 14번 §5-5 "APNs payload는 … `{type, translationId?…}`" → `mw` 딕셔너리로 교체, §11 표 `PushPayload`·`WATCHOS` 행. 15번 T-D4 "워치 없음" → "워치 v2, payload는 v1부터 공유". 코드: `Domain/Rules/DeepLink.swift`(MN-2), `Navigation/DeepLinkRouter.swift`(DeepLink→(Tab,[AppRoute])), `Platform/PushRegistrar.swift`(카테고리 4개 등록 + 액션 "지금 복습/미루기"), 서버 `infra/apns`. 픽스처 `contracts/push-examples/{4종}.json`을 앱 테스트와 서버 테스트가 같이 읽는다.
6. **검증 방법**: 앱 — `DeepLink.parse(userInfo)` 픽스처 4종 + 미지 `v` + `deepLink` 손상 케이스 단위 테스트, `DeepLink → (Tab,[AppRoute])` 전수(§11). 서버 — 픽스처와 어댑터 출력 diff 테스트, payload 크기 < 4KB, `alert`에 `sourceText/transcript` 필드 문자열이 포함되지 않는지 grep 테스트. 실기기 Day 28.
7. **리스크와 되돌리는 조건**: `interruption-level: time-sensitive`는 엔타이틀먼트·심사 노트가 필요(**확인 필요**) — v1은 `active`로 시작. `deepLink` 문법을 바꾸면 워치까지 깨지므로 `v`를 올리고 구버전 경로를 6개월 유지. 되돌림: Universal Link 도입 시 스킴만 교체(경로 동일).

## MN-2. Domain을 watchOS 데스티네이션에 올린다(의존성 0 확인), `DeepLink`·`StreakStatus`는 Domain으로

1. **의도**: 워치 v2가 `ReviewCard`·`ReviewRating`·`StreakStatus`·`DeepLink`를 **같은 타입**으로 쓰고, 지금부터 Domain에 UIKit/AppKit이 새지 않도록 컴파일러가 막는다.
2. **비용**: `Project.swift` Domain·DomainTests의 `destinations`에 `.appleWatch`, `deploymentTargets`에 `watchOS: "10.0"`(iOS 17 짝) — 2줄. CI: 야간 잡 1개(`xcodebuild build -scheme Domain -destination 'platform=watchOS Simulator'`, Tuist 자동 생성 스킴) 약 1분. Domain 파일 이동 2개. 돈 0.
3. **대안**:
   - (a) 지금은 아무것도 안 하고 v2에서 Domain을 워치용으로 복사/분리 — **탈락**: 그때까지 `import UIKit` 한 줄이 어디선가 들어가면(예: `UIImage` 타입을 `OcrService` 시그니처에) 분리 비용이 폭증. 지금 2줄이 그 보험.
   - (b) 모든 모듈에 `.appleWatch` 추가 — **탈락**: `Platform`(AVAudioEngine·Vision·ASWebAuthenticationSession)·`MwonmalUI`(Pretendard·iOS/macOS 레이아웃)·`Presentation`은 워치에서 컴파일 불가/무의미. 빌드 시간만 늘린다. `MwonmalAPI`(생성 클라이언트)는 `swift-openapi-urlsession`의 watchOS 지원 **확인 필요** 후 v2에 추가.
4. **왜**: 현재 `Project.swift`에서 Domain은 `dependencies: []`이고 12번 §2는 "순수 Swift, Foundation만"이다(확인). `Platform → Domain`이므로 Domain에 `.appleWatch`를 추가해도 그래프 방향은 그대로다(Tuist `enforceExplicitDependencies: true`가 역방향을 막는다). 워치가 공유할 모델:
   - `ReviewCard`(Entity, yml 2726행 그대로: cardId, termId, termKo, originEn, plainKo, meaning, exampleJargon?, examplePlain?, intervalDays, repetitionCount, source?) — 워치 화면은 이 중 `termKo/originEn/plainKo/meaning`만 쓰지만 **Entity를 쪼개지 않는다**(D-21: 표시 모델은 Presentation이 매핑). 워치 표시 모델 `ReviewCardFace`는 v2 워치 Presentation에.
   - `ReviewRating`(AGAIN/HARD/GOOD/EASY), `ReviewSession`, `ReviewAnswer`(nextIntervalDays, remainingCount).
   - **신규 `StreakStatus`**(Domain/Entities): `currentStreak, longestStreak, dueCount, reviewedToday: Bool` — `UserStatsResponse`에서 매핑, `StreakRule`(Rules)이 "오늘 했는지"를 `Clock`으로 계산. A-01·A-09 `StreakBadge`, 워치 컴플리케이션(v2), 홈 위젯(v1.1 T-D4)이 공유.
   - **`DeepLink`를 Navigation → Domain/Rules로 이동**: `DeepLink.parse(url:)`, `DeepLink.parse(userInfo:)`는 Foundation만 필요한 순수 함수. `DeepLink → (Tab, [AppRoute])`는 iOS/macOS 라우팅이라 Navigation에 남는다. 워치는 `DeepLink`만 알고 자기 화면으로 간다.
   - `NotificationCategory`(문자열 상수 4종 + 액션 ID `review.now`, `review.snooze`) — Domain 상수. iOS·워치 `PushRegistrar`가 같은 상수로 등록.
   - Domain 린트: SwiftLint `custom_rules`에 `Domain/`에서 `import (UIKit|AppKit|SwiftUI|AVFoundation|Vision)` 금지(D-4의 폴더 규칙 정규식과 같은 방식).
5. **영향 파일/문서**: `apps/ios-macos/Project.swift` Domain·DomainTests 2타깃(협의 후 수정). 12번 §2 트리에 `Entities/StreakStatus`, `Rules/DeepLink`, `Services/NotificationCategory`; §8-2 "`DeepLink.parse` … 순수 함수" 위치를 Domain으로 명기; §0 그림 Domain 옆 "(iOS·macOS·watchOS)". ADR-0001 "결정"에 "Domain은 watchOS 데스티네이션 포함" 한 줄. 13번 CI에 야간 워치 빌드 잡.
6. **검증 방법**: 야간 CI 워치 빌드 초록. `DomainTests`가 watchOS 시뮬레이터에서도 통과(Swift Testing watchOS 실행 **확인 필요**, 불가 시 빌드만). SwiftLint 규칙 위반 테스트 픽스처 1개.
7. **리스크와 되돌리는 조건**: `Codable` Entity에 `Date`가 있으면 워치도 `KSTDateTranscoder`가 필요 — Transcoder는 MwonmalAPI에 있으므로 v2에 MwonmalAPI를 워치에 올리거나 Domain에 날짜 파서를 두는 결정 필요(v2). 되돌림: 워치 v2를 포기하면 `.appleWatch` 2줄 삭제로 끝, 다른 흔적 없음.

## MN-3. 워치 v2 "복습 카드 넘기기" 한 화면에 필요한 최소 계약

| 필요 | 기존 43 ops 중 | 상태 |
|---|---|---|
| 세션 시작(카드 ≤ 5장) | `startReviewSession` `POST /reviews/sessions {limit: 5}` (1256행, `limit` 1~50) | **있음** |
| 카드 평가 | `submitReviewAnswer` `POST /reviews/sessions/{id}/answers {cardId, rating, elapsedMs}` (1314행) | **있음** — `remainingCount`로 진행 표시 |
| 세션 요약(끝 화면) | `getReviewSession` (1284행) | **있음**, 선택 |
| 컴플리케이션 due 수 | `getMyStats` (233행) | **있으나 과함**: `retentionSeries` 배열까지 내려옴. 워치 백그라운드 갱신 예산에 부담 → v1.1 백로그 후보 `GET /users/me/stats?fields=dueCount,currentStreak` 또는 T-B1 되돌림 조건의 BFF `GET /home`. v2 착수 전까지는 그대로 사용 |
| 인증 토큰 | `oauthLogin` 은 웹 세션 필요 → 워치에서 불가(`ASWebAuthenticationSession` watchOS 지원 **확인 필요**) | **부족**: iPhone이 WatchConnectivity로 토큰을 넘겨야 함 + JWT 24h(T-B6)라 하루 뒤 조용히 만료 → v1.1 refresh 토큰(`POST /auth/refresh`, 14번 §11)이 **워치의 전제 조건**. T-D5 "ThisDeviceOnly" 정책은 워치를 별도 기기로 보고 refresh 토큰을 워치 Keychain에 따로 둔다 |
| 워치 푸시 등록(독립형일 때) | `registerDevice` (1010행) | **부족**: `DevicePlatform.WATCHOS` 없음 → v1.1(MN-1 문안). 컴패니언 미러링만 쓰면 불필요 |
| 딥링크 파싱 | HTTP 아님 | MN-1 `mw.deepLink` |

부족 요약(v1.1 백로그에 올릴 것, 우선순위순): ① refresh 토큰(이미 백로그, 워치 전제), ② `WATCHOS` enum(이미 MN-1), ③ stats 경량화(신규, 낮음). 나머지 40 ops는 워치 v2 범위 밖.

## MN-4. 지금 v1에서 미리 할 것 3개 / 하지 말 것 3개

**할 것**
1. **payload·딥링크·카테고리 문자열을 Domain 상수 + 공유 픽스처로 고정**(MN-1·MN-2): 서버 Day 18과 앱 Day 24·28이 `contracts/push-examples/*.json` 하나를 본다. 워치는 나중에 같은 파일로 테스트. 비용 0.5일.
2. **Domain `.appleWatch` 데스티네이션 + 야간 워치 빌드 + import 린트**(MN-2): 2줄 + CI 1잡. "Domain은 Foundation만"을 사람이 아니라 컴파일러가 지킨다.
3. **`StreakStatus`·`ReviewCard` 흐름을 UI 없이 테스트 가능한 UseCase로**: `StartReviewUseCase(limit:)`·`AnswerCardUseCase`가 이미 §2-1에 있다. 여기에 `limit` 파라미터를 처음부터 노출하고(워치 5장), `ReviewFlow` VM이 `elapsedMs`를 `Clock`으로 재도록 해 워치 VM이 같은 UseCase를 재사용.

**하지 말 것**
1. **워치 타깃·WatchConnectivity·컴플리케이션을 v1에 만들지 않는다**(T-D4 유지). 화면 설계가 없고(REQ-04 "설계만 v1"), 인증 전제(refresh)가 v1.1이다.
2. **payload에 텍스트 본문(원문·받아쓰기·해석 결과 문장)을 넣지 않는다**(REQ-14, MN-1 불변식). "해석 결과 미리보기" 알림은 편해 보여도 APNs를 통해 나가므로 금지. 워치가 필요하면 `deepLink`로 열어서 API로 읽는다.
3. **MwonmalUI·Platform·Presentation에 워치 데스티네이션을 추가하거나 워치 전용 BFF/API를 미리 만들지 않는다.** 계약 v1.0은 제출본이고, 기존 3 ops로 충분하다(MN-3). 미리 만든 API는 쓰이지 않는 채로 계약 drift 검사만 늘린다.

---

## 부록. 이 결정서가 흔든 기존 문구 (문서 수정 목록, 저장소는 협의 후 수정)

| 문서·절 | 현재 | 변경 |
|---|---|---|
| 12번 머리말 | "iOS 26 / macOS 26" | "iOS 17 / macOS 14 최소, 26 기능 `@available`" (MI-5) |
| 12번 D-2 | "macOS(넓은 화면)는 펼치고, iPhone은 접는다" | "넓은 화면(iPad regular×regular, Mac)은 펼치고, 좁은 화면은 접는다" (MI-1) |
| 12번 D-17 두 번째 불릿 | `TabView` + `.sidebarAdaptable` 루트 하나 | compact `TabView` / wide 2열 `NavigationSplitView`, `TabCoordinator`가 switch 위 (MI-2) |
| 12번 §8-3 | "최소 폭 1000", `.defaultSize(1200, 800)` | 900×600 / 1280×800 제안 — **PM·iOS 파트와 합의 필요** (MI-6) |
| 12번 §8-3 | `.onPasteCommand` | `PasteButton` 공통 + Mac `onPasteCommand` 보조 (MI-3) |
| 12번 §9 Layout | `AdaptiveRoot(TabView sidebarAdaptable 래퍼)` | `MwLayout` 환경값 + `ListDetail` 2·3열 (MI-1·2) |
| 12번 §2 트리 | — | `StreakStatus`, `Rules/DeepLink`, `NotificationCategory` (MN-2) |
| 12번 §8-2·§13, 14번 §5-5·§11 | 최상위 키 payload | `mw` 딕셔너리 + `PushPayload`·`WATCHOS` (MN-1) |
| 12번 §10 불변식 | SDK 열만 | APNs payload 열 추가 (MN-1) |
| 12번 §11 스냅샷 | iPhone×DT × Mac 접힘/펼침 | MI-6 매트릭스 |
| 15번 T-C2 | 26 only, 표에 `@Entry` 손실 | 17+/14+, `@Entry` 정정 (MI-5) |
| 15번 T-D4 | 워치 없음 | 워치 v2, payload·Domain은 v1부터 공유 (MN-1·2) |
| 15번 T-E7 | Mac 전용 | Mac·iPad 공유 (MI-3) |
| 05번 126·167행 | 글래스 | 머티리얼(26 글래스는 v1.1) (MI-5) |
| `Project.swift` | 26.0, Domain destinations 3종, 카메라 문구 없음 | 17.0/14.0, Domain `+ .appleWatch`(watchOS 10.0), iOS `NSCameraUsageDescription` (MI-4·5, MN-2) |
| ADR-0001 결정 | 8모듈 | "Domain은 watchOS 포함" 한 줄 (MN-2) |
| REQUIREMENTS E표 | 재결정 대기 3행(D-0/REQ-01, D-19/REQ-04, SDK 규칙 6/REQ-03) | "MI-1·2·6 / MN-1·2 (2026-09-19)"로 상태 갱신 |

**확인 필요 목록(착수 전 문서 MCP로 재확인)**: iPad 13" vs 11" 1/2 Split 사이즈 클래스 표 / `Settings` 씬 macOS 전용 여부 / `dropDestination` 신 API 최소 버전 / `SFSpeechRecognizer` ko-KR 온디바이스 / Swift Testing iOS 17·watchOS 시뮬레이터 실행 / `UIPasteboard.detectPatterns` 최소 버전 / 라이브 액티비티 iPad / `PhotosPicker` 무권한 / hosted `macos-14` 러너 / `time-sensitive` 엔타이틀먼트 / `swift-openapi-urlsession` watchOS / `ASWebAuthenticationSession` watchOS / ⌘R iPadOS 예약 여부 / Continuity Camera(Mac).
