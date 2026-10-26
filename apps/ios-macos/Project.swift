import ProjectDescription

/// 모듈 그래프 (설계 12번 §0). Tuist는 순환 의존만 막고 레이어 방향은 막지 않는다(2026-10-26 확인) → 방향 검사는 별도 스크립트로(ADR-0016 예정).
/// Composition → Navigation → Presentation → Domain
/// Presentation → MwonmalUI ; Data → Domain, MwonmalAPI(로컬 패키지), Platform ; Platform → Domain
/// REQ-02 / FD-1 / ADR-0005: 최소 iOS 17.0 · macOS 14.0. 18·26 전용 API 게이트는 Platform · MwonmalUI/Compat · Composition/AppContainer 세 곳만.
let minimumOS: DeploymentTargets = .multiplatform(iOS: "17.0", macOS: "14.0")
/// FD-10 / ADR-0001 개정: Domain(의존성 0)만 watchOS 10.0 데스티네이션을 추가한다. v2 워치 앱이 DeepLink·StreakStatus를 공유하기 위함.
let domainOS: DeploymentTargets = .multiplatform(iOS: "17.0", macOS: "14.0", watchOS: "10.0")

let unitTests: [TestableTarget] = [
    "DomainTests",
    "MwonmalUITests",
    "PlatformTests",
    "DataTests",
    "PresentationTests",
    "NavigationTests",
    "CompositionTests",
]

let project = Project(
    name: "Mwonmal",
    organizationName: "Mwonmal",
    options: .options(defaultKnownRegions: ["ko"], developmentRegion: "ko"),
    // MwonmalAPI는 OpenAPI 생성기(빌드 플러그인)를 쓰므로 로컬 Swift 패키지로 두고 Xcode 기본 SPM 통합으로 넣는다.
    // Tuist 문서: 빌드 플러그인은 이 방식만 지원한다. 단위 테스트는 `swift test --package-path Packages/MwonmalAPI`.
    packages: [
        .local(path: "Packages/MwonmalAPI"),
    ],
    settings: .settings(base: ["SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete"]),
    targets: [
        .target(
            name: "Domain",
            destinations: [.iPhone, .iPad, .mac, .appleWatch],
            product: .staticFramework,
            bundleId: "kr.mwonmal.domain",
            deploymentTargets: domainOS,
            sources: ["Modules/Domain/Sources/**"],
            resources: nil,
            dependencies: []
        ),
        .target(
            name: "DomainTests",
            destinations: [.iPhone, .iPad, .mac],
            product: .unitTests,
            bundleId: "kr.mwonmal.domain.tests",
            deploymentTargets: minimumOS,
            sources: ["Modules/Domain/Tests/**"],
            dependencies: [.target(name: "Domain")]
        ),
        .target(
            name: "MwonmalUI",
            destinations: [.iPhone, .iPad, .mac],
            product: .staticFramework,
            bundleId: "kr.mwonmal.mwonmalui",
            deploymentTargets: minimumOS,
            sources: ["Modules/MwonmalUI/Sources/**"],
            resources: ["Modules/MwonmalUI/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "MwonmalUITests",
            destinations: [.iPhone, .iPad, .mac],
            product: .unitTests,
            bundleId: "kr.mwonmal.mwonmalui.tests",
            deploymentTargets: minimumOS,
            sources: ["Modules/MwonmalUI/Tests/**"],
            dependencies: [.target(name: "MwonmalUI")]
        ),
        .target(
            name: "Platform",
            destinations: [.iPhone, .iPad, .mac],
            product: .staticFramework,
            bundleId: "kr.mwonmal.platform",
            deploymentTargets: minimumOS,
            sources: ["Modules/Platform/Sources/**"],
            resources: nil,
            dependencies: [.target(name: "Domain")]
        ),
        .target(
            name: "PlatformTests",
            destinations: [.iPhone, .iPad, .mac],
            product: .unitTests,
            bundleId: "kr.mwonmal.platform.tests",
            deploymentTargets: minimumOS,
            sources: ["Modules/Platform/Tests/**"],
            dependencies: [.target(name: "Platform")]
        ),
        .target(
            name: "Data",
            destinations: [.iPhone, .iPad, .mac],
            product: .staticFramework,
            bundleId: "kr.mwonmal.data",
            deploymentTargets: minimumOS,
            sources: ["Modules/Data/Sources/**"],
            resources: nil,
            dependencies: [.target(name: "Domain"), .package(product: "MwonmalAPI", type: .runtime), .target(name: "Platform")]
        ),
        .target(
            name: "DataTests",
            destinations: [.iPhone, .iPad, .mac],
            product: .unitTests,
            bundleId: "kr.mwonmal.data.tests",
            deploymentTargets: minimumOS,
            sources: ["Modules/Data/Tests/**"],
            dependencies: [.target(name: "Data")]
        ),
        .target(
            name: "Presentation",
            destinations: [.iPhone, .iPad, .mac],
            product: .staticFramework,
            bundleId: "kr.mwonmal.presentation",
            deploymentTargets: minimumOS,
            sources: ["Modules/Presentation/Sources/**"],
            resources: nil,
            dependencies: [.target(name: "Domain"), .target(name: "MwonmalUI")]
        ),
        .target(
            name: "PresentationTests",
            destinations: [.iPhone, .iPad, .mac],
            product: .unitTests,
            bundleId: "kr.mwonmal.presentation.tests",
            deploymentTargets: minimumOS,
            sources: ["Modules/Presentation/Tests/**"],
            dependencies: [.target(name: "Presentation")]
        ),
        .target(
            name: "Navigation",
            destinations: [.iPhone, .iPad, .mac],
            product: .staticFramework,
            bundleId: "kr.mwonmal.navigation",
            deploymentTargets: minimumOS,
            sources: ["Modules/Navigation/Sources/**"],
            resources: nil,
            dependencies: [.target(name: "Presentation"), .target(name: "Domain")]
        ),
        .target(
            name: "NavigationTests",
            destinations: [.iPhone, .iPad, .mac],
            product: .unitTests,
            bundleId: "kr.mwonmal.navigation.tests",
            deploymentTargets: minimumOS,
            sources: ["Modules/Navigation/Tests/**"],
            dependencies: [.target(name: "Navigation")]
        ),
        .target(
            name: "Composition",
            destinations: [.iPhone, .iPad, .mac],
            product: .staticFramework,
            bundleId: "kr.mwonmal.composition",
            deploymentTargets: minimumOS,
            sources: ["Modules/Composition/Sources/**"],
            resources: nil,
            dependencies: [
                .target(name: "Navigation"),
                .target(name: "Presentation"),
                .target(name: "Data"),
                .target(name: "Platform"),
                .target(name: "MwonmalUI"),
                .target(name: "Domain"),
            ]
        ),
        .target(
            name: "CompositionTests",
            destinations: [.iPhone, .iPad, .mac],
            product: .unitTests,
            bundleId: "kr.mwonmal.composition.tests",
            deploymentTargets: minimumOS,
            sources: ["Modules/Composition/Tests/**"],
            dependencies: [.target(name: "Composition")]
        ),
        .target(
            name: "MwonmalIOS",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: "kr.mwonmal.app",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "CFBundleDisplayName": "뭔말인교?",
                "NSMicrophoneUsageDescription": "회의를 녹음해 받아쓰기와 해석에 씁니다.",
                "NSSpeechRecognitionUsageDescription": "녹음 중 실시간 받아쓰기 미리보기에 씁니다.",
            ]),
            sources: ["Apps/IOS/Sources/**"],
            dependencies: [.target(name: "Composition")]
        ),
        .target(
            name: "MwonmalMac",
            destinations: [.mac],
            product: .app,
            bundleId: "kr.mwonmal.mac",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "뭔말인교?",
                "NSMicrophoneUsageDescription": "회의를 녹음해 받아쓰기와 해석에 씁니다.",
                "NSSpeechRecognitionUsageDescription": "녹음 중 실시간 받아쓰기 미리보기에 씁니다.",
            ]),
            sources: ["Apps/Mac/Sources/**"],
            entitlements: .file(path: "Apps/Mac/Mwonmal.entitlements"),
            dependencies: [.target(name: "Composition")]
        ),
        .target(
            name: "MwonmalUICatalog",
            destinations: [.iPhone, .iPad, .mac],
            product: .app,
            bundleId: "kr.mwonmal.catalog",
            deploymentTargets: minimumOS,
            infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
            sources: ["Apps/Catalog/Sources/**"],
            dependencies: [.target(name: "MwonmalUI")]
        ),
    ],
    schemes: [
        .scheme(
            name: "MwonmalIOS",
            buildAction: .buildAction(targets: ["MwonmalIOS"]),
            testAction: .targets(unitTests),
            runAction: .runAction(executable: "MwonmalIOS")
        ),
        .scheme(
            name: "MwonmalMac",
            buildAction: .buildAction(targets: ["MwonmalMac"]),
            testAction: .targets(unitTests),
            runAction: .runAction(executable: "MwonmalMac")
        ),
        .scheme(
            name: "MwonmalUICatalog",
            buildAction: .buildAction(targets: ["MwonmalUICatalog"]),
            runAction: .runAction(executable: "MwonmalUICatalog")
        ),
    ]
)
