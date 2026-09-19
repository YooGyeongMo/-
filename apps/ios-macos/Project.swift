import ProjectDescription

// 모듈 그래프 (설계 12번 §0). 의존 방향 위반은 생성 단계에서 실패한다.
// Composition → Navigation → Presentation → Domain ; Presentation → MwonmalUI ; Data → Domain, MwonmalAPI, Platform ; Platform → Domain
let project = Project(
    name: "Mwonmal",
    organizationName: "Mwonmal",
    options: .options(defaultKnownRegions: ["ko"], developmentRegion: "ko"),
    settings: .settings(base: ["SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete"]),
    targets: [
    .target(
        name: "Domain",
        destinations: [.iPhone, .iPad, .mac],
        product: .staticFramework,
        bundleId: "kr.mwonmal.domain",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/Domain/Sources/**"],
        resources: nil,
        dependencies: []
    ),
    .target(
        name: "DomainTests",
        destinations: [.iPhone, .iPad, .mac],
        product: .unitTests,
        bundleId: "kr.mwonmal.domain.tests",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/Domain/Tests/**"],
        dependencies: [.target(name: "Domain")]
    ),
    .target(
        name: "MwonmalUI",
        destinations: [.iPhone, .iPad, .mac],
        product: .staticFramework,
        bundleId: "kr.mwonmal.mwonmalui",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/MwonmalUI/Sources/**"],
        resources: ["Modules/MwonmalUI/Resources/**"],
        dependencies: []
    ),
    .target(
        name: "MwonmalUITests",
        destinations: [.iPhone, .iPad, .mac],
        product: .unitTests,
        bundleId: "kr.mwonmal.mwonmalui.tests",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/MwonmalUI/Tests/**"],
        dependencies: [.target(name: "MwonmalUI")]
    ),
    .target(
        name: "MwonmalAPI",
        destinations: [.iPhone, .iPad, .mac],
        product: .staticFramework,
        bundleId: "kr.mwonmal.mwonmalapi",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/MwonmalAPI/Sources/**"],
        resources: nil,
        dependencies: []
    ),
    .target(
        name: "MwonmalAPITests",
        destinations: [.iPhone, .iPad, .mac],
        product: .unitTests,
        bundleId: "kr.mwonmal.mwonmalapi.tests",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/MwonmalAPI/Tests/**"],
        dependencies: [.target(name: "MwonmalAPI")]
    ),
    .target(
        name: "Platform",
        destinations: [.iPhone, .iPad, .mac],
        product: .staticFramework,
        bundleId: "kr.mwonmal.platform",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/Platform/Sources/**"],
        resources: nil,
        dependencies: [.target(name: "Domain")]
    ),
    .target(
        name: "PlatformTests",
        destinations: [.iPhone, .iPad, .mac],
        product: .unitTests,
        bundleId: "kr.mwonmal.platform.tests",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/Platform/Tests/**"],
        dependencies: [.target(name: "Platform")]
    ),
    .target(
        name: "Data",
        destinations: [.iPhone, .iPad, .mac],
        product: .staticFramework,
        bundleId: "kr.mwonmal.data",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/Data/Sources/**"],
        resources: nil,
        dependencies: [.target(name: "Domain"), .target(name: "MwonmalAPI"), .target(name: "Platform")]
    ),
    .target(
        name: "DataTests",
        destinations: [.iPhone, .iPad, .mac],
        product: .unitTests,
        bundleId: "kr.mwonmal.data.tests",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/Data/Tests/**"],
        dependencies: [.target(name: "Data")]
    ),
    .target(
        name: "Presentation",
        destinations: [.iPhone, .iPad, .mac],
        product: .staticFramework,
        bundleId: "kr.mwonmal.presentation",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/Presentation/Sources/**"],
        resources: nil,
        dependencies: [.target(name: "Domain"), .target(name: "MwonmalUI")]
    ),
    .target(
        name: "PresentationTests",
        destinations: [.iPhone, .iPad, .mac],
        product: .unitTests,
        bundleId: "kr.mwonmal.presentation.tests",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/Presentation/Tests/**"],
        dependencies: [.target(name: "Presentation")]
    ),
    .target(
        name: "Navigation",
        destinations: [.iPhone, .iPad, .mac],
        product: .staticFramework,
        bundleId: "kr.mwonmal.navigation",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/Navigation/Sources/**"],
        resources: nil,
        dependencies: [.target(name: "Presentation"), .target(name: "Domain")]
    ),
    .target(
        name: "NavigationTests",
        destinations: [.iPhone, .iPad, .mac],
        product: .unitTests,
        bundleId: "kr.mwonmal.navigation.tests",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/Navigation/Tests/**"],
        dependencies: [.target(name: "Navigation")]
    ),
    .target(
        name: "Composition",
        destinations: [.iPhone, .iPad, .mac],
        product: .staticFramework,
        bundleId: "kr.mwonmal.composition",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/Composition/Sources/**"],
        resources: nil,
        dependencies: [.target(name: "Navigation"), .target(name: "Presentation"), .target(name: "Data"), .target(name: "Platform"), .target(name: "MwonmalUI"), .target(name: "Domain")]
    ),
    .target(
        name: "CompositionTests",
        destinations: [.iPhone, .iPad, .mac],
        product: .unitTests,
        bundleId: "kr.mwonmal.composition.tests",
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        sources: ["Modules/Composition/Tests/**"],
        dependencies: [.target(name: "Composition")]
    ),
    .target(
        name: "MwonmalIOS",
        destinations: [.iPhone, .iPad],
        product: .app,
        bundleId: "kr.mwonmal.app",
        deploymentTargets: .iOS("26.0"),
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
        deploymentTargets: .macOS("26.0"),
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
        deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
        infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
        sources: ["Apps/Catalog/Sources/**"],
        dependencies: [.target(name: "MwonmalUI")]
    ),
    ],
    schemes: [
        .scheme(name: "MwonmalIOS", buildAction: .buildAction(targets: ["MwonmalIOS"]), testAction: .targets(["DomainTests", "MwonmalUITests", "MwonmalAPITests", "PlatformTests", "DataTests", "PresentationTests", "NavigationTests", "CompositionTests"]), runAction: .runAction(executable: "MwonmalIOS")),
        .scheme(name: "MwonmalMac", buildAction: .buildAction(targets: ["MwonmalMac"]), testAction: .targets(["DomainTests", "MwonmalUITests", "MwonmalAPITests", "PlatformTests", "DataTests", "PresentationTests", "NavigationTests", "CompositionTests"]), runAction: .runAction(executable: "MwonmalMac")),
        .scheme(name: "MwonmalUICatalog", buildAction: .buildAction(targets: ["MwonmalUICatalog"]), runAction: .runAction(executable: "MwonmalUICatalog")),
    ]
)
