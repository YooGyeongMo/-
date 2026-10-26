// swift-tools-version: 6.0
// MwonmalIntelligence: 뭔말인교 온디바이스 지능 모듈 (ADR-0019 초안).
//
// 경계 규칙
// - 이 패키지는 Tuist 타깃(Domain 등)에 의존하지 않는다. 자기 값 타입·프로토콜만 정의하고,
//   Platform이 Domain 프로토콜(`TranslationEngine` 등)로 어댑트한다(ADR-0016: 프로토콜은 Domain 소유).
// - 네트워크 코드 0줄. 사용자 원문은 이 패키지 밖(기기 밖)으로 나가지 않는다(ADR-0008). 테스트가 소스를 검사한다.
// - v1.0 앱은 이 패키지를 링크하지 않는다(ADR-0015). Project.swift `packages:`에도 넣지 않는다.
// - iOS 27 전용 API(LanguageModelError, variant, PCC)는 Xcode 27 CI 전환 후 `#if compiler(>=6.4)` 뒤에 추가한다.
import PackageDescription

let strict: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
    name: "MwonmalIntelligence",
    defaultLocalization: "ko",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // 값 타입·프로토콜·태그·평가·텔레메트리. Foundation만.
        .library(name: "MwonmalIntelligenceCore", targets: ["MwonmalIntelligenceCore"]),
        // 판교어 구간 탐지: 사전 trie + Core ML(NLModel) 태거 하이브리드. iOS 17+.
        .library(name: "JargonDetection", targets: ["JargonDetection"]),
        // Apple Foundation Models 미리보기 엔진. 코드 자체는 iOS/macOS 26+ 게이트 뒤.
        .library(name: "FoundationModelsEngine", targets: ["FoundationModelsEngine"]),
        // 테스트 전용 Fake. 앱 타깃에 링크 금지(테스트·Example만).
        .library(name: "IntelligenceTesting", targets: ["IntelligenceTesting"]),
    ],
    targets: [
        .target(name: "MwonmalIntelligenceCore", swiftSettings: strict),
        .target(
            name: "JargonDetection",
            dependencies: ["MwonmalIntelligenceCore"],
            resources: [.process("Resources")],
            swiftSettings: strict
        ),
        .target(
            name: "FoundationModelsEngine",
            dependencies: ["MwonmalIntelligenceCore"],
            // iOS 17~25에는 FoundationModels.framework가 없다. 최소 OS(14/17)가 프레임워크 도입 OS보다 낮으면 링커가
            // 자동으로 LC_LOAD_WEAK_DYLIB로 건다(2026-10-26 `otool -l`로 확인) → unsafeFlags 불필요. 앱 아카이브에서 재확인.
            swiftSettings: strict
        ),
        .target(name: "IntelligenceTesting", dependencies: ["MwonmalIntelligenceCore"], swiftSettings: strict),
        // 개발 Mac 전용 평가 CLI: eval/dataset/*.jsonl → 예측 JSONL (eval/run.py 가 채점). 앱에 안 들어간다.
        .executableTarget(
            name: "mwintel-eval",
            dependencies: ["MwonmalIntelligenceCore", "JargonDetection", "FoundationModelsEngine"],
            swiftSettings: strict
        ),
        .testTarget(
            name: "MwonmalIntelligenceCoreTests",
            dependencies: ["MwonmalIntelligenceCore", "IntelligenceTesting"]
        ),
        .testTarget(
            name: "JargonDetectionTests",
            dependencies: ["JargonDetection", "IntelligenceTesting"],
            // 실험 태거(합성 데이터, 460KB)를 미리 컴파일한 .mlmodelc. SPM `.process`는 .mlmodel 컴파일을 지원하지 않는다(보고서 §1).
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "FoundationModelsEngineTests",
            dependencies: ["FoundationModelsEngine", "IntelligenceTesting"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
