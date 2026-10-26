public import Foundation
public import MwonmalIntelligenceCore
#if canImport(BackgroundAssets)
    internal import BackgroundAssets
    internal import System
#endif

/// 태거 모델(.mlmodelc)이 어디 있는가. 패키지는 **스스로 내려받지 않는다**(네트워크 코드 0, ADR-0008).
/// - `.file`: 호스트가 둔 경로(앱 번들 리소스, 또는 iOS 17~25에서 호스트가 받은 파일).
/// - `.assetPack`: Apple-hosted Background Assets(iOS/macOS 26+). 시스템이 받는다.
public enum TaggerModelSource: Sendable, Hashable {
    case file(URL)
    case assetPack(id: String, path: String)
}

public enum TaggerModelLocator {
    public static func resolve(_ source: TaggerModelSource) async throws(IntelligenceError) -> URL {
        switch source {
        case let .file(url):
            guard FileManager.default.fileExists(atPath: url.path) else { throw .unavailable(.modelAssetMissing) }
            return url
        case let .assetPack(id, path):
            #if canImport(BackgroundAssets)
                if #available(iOS 26.4, macOS 26.4, *) {
                    return try await AssetPackResolver.url(packID: id, path: path)
                }
            #endif
            throw .unavailable(.osTooOld)
        }
    }
}

#if canImport(BackgroundAssets)
    @available(iOS 26.4, macOS 26.4, *)
    enum AssetPackResolver {
        /// 문서: developer.apple.com/documentation/backgroundassets/downloading-apple-hosted-asset-packs
        /// `ensureLocalAvailability(of:requireLatestVersion:)`·`url(for:)`는 SDK 26.4 swiftinterface에서 확인.
        static func url(packID: String, path: String) async throws(IntelligenceError) -> URL {
            do {
                let manager = AssetPackManager.shared
                let pack = try await manager.assetPack(withID: packID)
                try await manager.ensureLocalAvailability(of: pack, requireLatestVersion: false)
                return try manager.url(for: .init(path))
            } catch {
                throw .unavailable(.modelAssetMissing)
            }
        }
    }
#endif
