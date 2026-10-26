import ProjectDescription

// ADR-0016: 레이어 + 기능(Feature) 모듈. 허용 의존 표를 여기 한 곳에 둔다.
// Tuist는 순환만 막고 레이어 방향은 막지 않으므로, 표 밖의 의존은 생성 단계에서 precondition으로 막고
// CI는 scripts/check-module-deps.py 로 그래프를 한 번 더 검사한다(메시지가 보이게).

public let minimumOS: DeploymentTargets = .multiplatform(iOS: "17.0", macOS: "14.0")
/// FD-10 / ADR-0010: Domain(의존성 0)만 watchOS 10.0을 더한다.
public let domainOS: DeploymentTargets = .multiplatform(iOS: "17.0", macOS: "14.0", watchOS: "10.0")
public let uiDestinations: Destinations = [.iPhone, .iPad, .mac]

/// 개발 = 동적 프레임워크(프리뷰·증분 빌드). 아카이브 = `TUIST_PRODUCT_TYPE=static tuist generate`.
public func frameworkProduct() -> Product {
    Environment.productType.getString(default: "dynamic") == "static" ? .staticFramework : .framework
}

public enum Layer: String, Sendable {
    case core, testing, routing, feature, composition
}

/// 코어·라우팅 모듈의 허용 의존. 키에 없는 모듈은 의존 0.
public let allowedDependencies: [String: Set<String>] = [
    "Domain": [],
    "DomainTesting": ["Domain"],
    "Platform": ["Domain"],
    "Data": ["Domain", "Platform", "MwonmalAPI"],
    "MwonmalUI": [],
    "Routing": ["Domain"],
    "FeatureKit": ["Domain", "MwonmalUI", "Routing"],
]

/// Feature는 서로를, 그리고 Data·Platform·MwonmalAPI를 볼 수 없다.
public let featureAllowed: Set<String> = ["Domain", "DomainTesting", "MwonmalUI", "Routing", "FeatureKit"]

func validate(_ name: String, layer: Layer, deps: [String]) {
    let allowed: Set<String>
    switch layer {
    case .feature: allowed = featureAllowed
    case .composition: return
    default: allowed = allowedDependencies[name] ?? []
    }
    let illegal = Set(deps).subtracting(allowed)
    precondition(illegal.isEmpty, "의존 규칙 위반(ADR-0016): \(name) → \(illegal.sorted())")
}

/// 로컬 SPM 패키지 제품(예: MwonmalAPI)은 `.package`로, 나머지는 `.target`으로.
let packageProducts: Set<String> = ["MwonmalAPI"]

func dependency(_ name: String) -> TargetDependency {
    packageProducts.contains(name) ? .package(product: name, type: .runtime) : .target(name: name)
}

/// UI 계층만 MainActor 기본 격리. Domain/Data/Platform은 nonisolated + strict complete 유지.
func isolationSettings(_ mainActor: Bool) -> Settings? {
    guard mainActor else { return nil }
    return .settings(base: ["SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor", "SWIFT_APPROACHABLE_CONCURRENCY": "YES"])
}

/// 코어·라우팅 모듈 1개 = 프레임워크 + 테스트.
public func coreModule(
    _ name: String,
    layer: Layer = .core,
    deps: [String] = [],
    destinations: Destinations = uiDestinations,
    deploymentTargets: DeploymentTargets = minimumOS,
    hasResources: Bool = false,
    mainActorByDefault: Bool = false,
    testsUseDomainTesting: Bool = true,
    testDeps: [String] = []
) -> [Target] {
    validate(name, layer: layer, deps: deps)
    let root = "Modules/Core/\(name)"
    return [
        .target(
            name: name,
            destinations: destinations,
            product: frameworkProduct(),
            bundleId: "kr.mwonmal.\(name.lowercased())",
            deploymentTargets: deploymentTargets,
            sources: ["\(root)/Sources/**"],
            resources: hasResources ? ["\(root)/Resources/**"] : nil,
            dependencies: deps.map(dependency),
            settings: isolationSettings(mainActorByDefault),
            metadata: .metadata(tags: ["layer:\(layer.rawValue)"])
        ),
        .target(
            name: "\(name)Tests",
            destinations: uiDestinations,
            product: .unitTests,
            bundleId: "kr.mwonmal.\(name.lowercased()).tests",
            deploymentTargets: minimumOS,
            sources: ["\(root)/Tests/**"],
            dependencies: [.target(name: name)] + (testsUseDomainTesting ? [.target(name: "DomainTesting")] : [])
                + testDeps.map(dependency),
            settings: isolationSettings(mainActorByDefault),
            metadata: .metadata(tags: ["layer:\(layer.rawValue)", "kind:tests"])
        ),
    ]
}

/// Feature 모듈 1개 = Feature 프레임워크(문구 카탈로그 포함) + Tests + (선택) Example 앱.
/// Interface 타깃은 만들지 않는다: 화면 간 계약은 Routing(AppRoute)과 Domain(UseCase 프로토콜)이 맡는다.
public func featureModule(
    _ name: String,
    deps: [String] = ["Domain", "MwonmalUI", "Routing", "FeatureKit", "DomainTesting"],
    example: Bool = false
) -> [Target] {
    let target = "\(name)Feature"
    validate(target, layer: .feature, deps: deps)
    let root = "Modules/Features/\(name)"
    let tags = ["layer:feature", "feature:\(name.lowercased())"]
    var targets: [Target] = [
        .target(
            name: target,
            destinations: uiDestinations,
            product: frameworkProduct(),
            bundleId: "kr.mwonmal.feature.\(name.lowercased())",
            deploymentTargets: minimumOS,
            sources: ["\(root)/Sources/**"],
            resources: ["\(root)/Resources/**"],
            dependencies: deps.map(dependency),
            settings: isolationSettings(true),
            metadata: .metadata(tags: tags)
        ),
        .target(
            name: "\(target)Tests",
            destinations: uiDestinations,
            product: .unitTests,
            bundleId: "kr.mwonmal.feature.\(name.lowercased()).tests",
            deploymentTargets: minimumOS,
            sources: ["\(root)/Tests/**"],
            dependencies: [.target(name: target), .target(name: "DomainTesting")],
            settings: isolationSettings(true),
            metadata: .metadata(tags: tags + ["kind:tests"])
        ),
    ]
    if example {
        targets.append(
            .target(
                name: "\(name)Example",
                destinations: [.iPhone, .iPad],
                product: .app,
                bundleId: "kr.mwonmal.example.\(name.lowercased())",
                deploymentTargets: .iOS("17.0"),
                infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
                sources: ["\(root)/Example/**"],
                dependencies: [.target(name: target), .target(name: "DomainTesting")],
                metadata: .metadata(tags: tags + ["kind:example"])
            )
        )
    }
    return targets
}
