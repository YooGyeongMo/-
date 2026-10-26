// swift-tools-version: 6.0
// MwonmalAPI: 계약 v1.0(contracts/openapi.yml)에서 생성하는 클라이언트 + 미들웨어 3개 + KST 날짜 변환.
// 생성기는 빌드 플러그인이라 Tuist 타깃 대신 로컬 패키지로 둔다(ADR-0001 개정, PR 본문 참고).
// Tuist 프로젝트는 `packages: [.local(path: "Packages/MwonmalAPI")]`로 참조한다.
import PackageDescription

let package = Package(
    name: "MwonmalAPI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MwonmalAPI", targets: ["MwonmalAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", .upToNextMinor(from: "1.14.2")),
        .package(url: "https://github.com/apple/swift-openapi-runtime", .upToNextMinor(from: "1.13.3")),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", .upToNextMinor(from: "1.4.0")),
        .package(url: "https://github.com/apple/swift-http-types", .upToNextMinor(from: "1.8.0")),
    ],
    targets: [
        .target(
            name: "MwonmalAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ],
            plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),
        .testTarget(
            name: "MwonmalAPITests",
            dependencies: [
                "MwonmalAPI",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
