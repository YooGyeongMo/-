// swift-tools-version: 6.0
// 외부 의존성. Tuist가 이 파일로 SPM 패키지를 받아 그래프에 넣는다 (`tuist install`).
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(productTypes: [:])
#endif

let package = Package(
    name: "MwonmalDeps",
    dependencies: [
        // S0 Day 3에서 활성화: swift-openapi-runtime, swift-openapi-urlsession
        // S5 에서 활성화: sentry-cocoa, Amplitude-Swift
        // S6 에서 활성화: swift-snapshot-testing
    ]
)
