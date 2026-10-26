import ProjectDescription
import ProjectDescriptionHelpers

// 모듈 그래프 (ADR-0016: MVVM-R + 기능 모듈, 설계 12번 v2.2).
//   App → Composition → {Auth, Translate, Home, Settings}Feature → FeatureKit → Routing → Domain
//   Feature → MwonmalUI ; Composition → Data → {Domain, Platform → Domain, MwonmalAPI(로컬 패키지)}
//   Tests·Example·Preview → DomainTesting → Domain
// 금지: Feature→Feature, Feature→{Data, Platform, MwonmalAPI}. 허용 표는 Tuist/ProjectDescriptionHelpers/Module.swift.
// Tuist는 순환만 막는다 → 방향은 헬퍼의 precondition + CI scripts/check-module-deps.py.
// REQ-02 / ADR-0005: 최소 iOS 17.0 · macOS 14.0. 18·26 전용 API 게이트는 Platform · MwonmalUI/Compat · Composition 세 곳만.

/// v1.0 기능 모듈. v1.1: Onboarding, Review(example), Quiz / v1.2: Project, Meeting(example).
let featureNames = ["Auth", "Translate", "Home", "Settings"]
let features: [Target] = featureNames.flatMap { featureModule($0, example: $0 == "Translate") }

let coreTargets: [Target] =
    coreModule("Domain", destinations: [.iPhone, .iPad, .mac, .appleWatch], deploymentTargets: domainOS, testsUseDomainTesting: false)
        + [
            .target(
                name: "DomainTesting",
                destinations: uiDestinations,
                product: frameworkProduct(),
                bundleId: "kr.mwonmal.domaintesting",
                deploymentTargets: minimumOS,
                sources: ["Modules/Core/DomainTesting/Sources/**"],
                dependencies: [.target(name: "Domain")],
                metadata: .metadata(tags: ["layer:testing"])
            ),
            .target(
                name: "DomainTestingTests",
                destinations: uiDestinations,
                product: .unitTests,
                bundleId: "kr.mwonmal.domaintesting.tests",
                deploymentTargets: minimumOS,
                sources: ["Modules/Core/DomainTesting/Tests/**"],
                dependencies: [.target(name: "DomainTesting")],
                metadata: .metadata(tags: ["layer:testing", "kind:tests"])
            ),
        ]
        + coreModule("Platform", deps: ["Domain"])
        + coreModule("Data", deps: ["Domain", "Platform", "MwonmalAPI"])
        + coreModule("MwonmalUI", hasResources: true, mainActorByDefault: true, testsUseDomainTesting: false)
        + coreModule("Routing", layer: .routing, deps: ["Domain"], mainActorByDefault: true)
        + coreModule("FeatureKit", layer: .routing, deps: ["Domain", "MwonmalUI", "Routing"], mainActorByDefault: true)

let composition: [Target] = coreModule(
    "Composition",
    layer: .composition,
    deps: featureNames.map { "\($0)Feature" } + ["Data", "Platform", "Routing", "FeatureKit", "MwonmalUI", "Domain"],
    hasResources: true,
    mainActorByDefault: true
)

let appInfo: [String: Plist.Value] = [
    "CFBundleDisplayName": "뭔말인교?",
    "CFBundleLocalizations": ["ko", "en"],
    "NSMicrophoneUsageDescription": "회의를 녹음해 받아쓰기와 해석에 씁니다.",
    "NSSpeechRecognitionUsageDescription": "녹음 중 실시간 받아쓰기 미리보기에 씁니다.",
]

let apps: [Target] = [
    .target(
        name: "MwonmalIOS",
        destinations: [.iPhone, .iPad],
        product: .app,
        bundleId: "kr.mwonmal.app",
        deploymentTargets: .iOS("17.0"),
        infoPlist: .extendingDefault(with: appInfo.merging(["UILaunchScreen": [:]]) { $1 }),
        sources: ["Apps/IOS/Sources/**"],
        dependencies: [.target(name: "Composition")]
    ),
    .target(
        name: "MwonmalMac",
        destinations: [.mac],
        product: .app,
        bundleId: "kr.mwonmal.mac",
        deploymentTargets: .macOS("14.0"),
        infoPlist: .extendingDefault(with: appInfo),
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
]

let allTargets = coreTargets + features + composition + apps
let unitTests: [TestableTarget] = allTargets
    .filter { $0.product == .unitTests }
    .map { TestableTarget(stringLiteral: $0.name) }

let project = Project(
    name: "Mwonmal",
    organizationName: "Mwonmal",
    options: .options(defaultKnownRegions: ["ko", "en"], developmentRegion: "ko"),
    // MwonmalAPI는 OpenAPI 생성기(빌드 플러그인)를 쓰므로 로컬 Swift 패키지(ADR-0001 개정).
    packages: [
        .local(path: "Packages/MwonmalAPI"),
    ],
    settings: .settings(base: ["SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete"]),
    targets: allTargets,
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
        .scheme(
            name: "TranslateExample",
            buildAction: .buildAction(targets: ["TranslateExample"]),
            runAction: .runAction(executable: "TranslateExample")
        ),
    ]
)
