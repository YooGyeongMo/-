public import Foundation
public import MwonmalIntelligenceCore

// 이 파일은 FoundationModels를 import하지 않는다 → 게이트 로직은 iOS 17 / 어떤 Mac에서도 단위 테스트된다.

/// ADR-0015 다섯 겹 게이트의 **입력 스냅샷**. 실기에서는 `AppleFMDraftEngine`이 채우고, 테스트는 직접 만든다.
public struct FMGateInput: Sendable, Equatable {
    public enum ModelState: Sendable, Equatable {
        case available
        case deviceNotEligible, appleIntelligenceNotEnabled, modelNotReady, other
    }

    /// 겹 1: `#available(iOS 26, macOS 26, *)` && `canImport(FoundationModels)`.
    public var osSupported: Bool
    /// 겹 2: `SystemLanguageModel.availability`.
    public var model: ModelState
    /// 겹 3: `supportsLocale(Locale(identifier: "ko_KR"))`.
    public var supportsKorean: Bool
    /// 겹 4 재료: `SystemLanguageModel.contextSize`(26.0 back-deploy) 와 입력 스칼라 수.
    public var contextSize: Int
    public var inputScalarCount: Int
    /// 겹 5 재료: 이 기기의 모델 태그(`FMModelTag.resolve`).
    public var modelTag: EngineTag

    public init(osSupported: Bool, model: ModelState, supportsKorean: Bool, contextSize: Int, inputScalarCount: Int, modelTag: EngineTag) {
        self.osSupported = osSupported
        self.model = model
        self.supportsKorean = supportsKorean
        self.contextSize = contextSize
        self.inputScalarCount = inputScalarCount
        self.modelTag = modelTag
    }
}

/// 호스트가 원격 설정·야간 평가 결과로 내려 주는 정책. **기본값은 전부 닫힘**(fail-closed).
public struct FMGatePolicy: Sendable, Equatable {
    /// 점수 게이트(≥ 서버 최고 80% & p50 ≤ 3s)를 통과한 모델 키(`fm/apple-26.4` 등). 프롬프트 버전은 보지 않는다.
    public var enabledModelKeys: Set<String>
    /// MESSAGE 상한(ADR-0015: 500자). 한국어 ≈ 1글자 1토큰 가정.
    public var maxInputScalars: Int
    /// instructions ≈300 + 스키마 ≈200~400 + 출력 ≈400 (ADR-0007 §4-6 [예상]) → 실측 전 보수적으로 1,200.
    public var reservedTokens: Int

    public init(enabledModelKeys: Set<String> = [], maxInputScalars: Int = 500, reservedTokens: Int = 1200) {
        self.enabledModelKeys = enabledModelKeys
        self.maxInputScalars = maxInputScalars
        self.reservedTokens = reservedTokens
    }

    public static let closed = FMGatePolicy()
}

public enum FMGate {
    /// 겹 순서대로 처음 실패한 사유를 돌려준다(텔레메트리에서 어느 겹이 막는지 분포를 본다).
    public static func evaluate(_ input: FMGateInput, policy: FMGatePolicy) -> EngineAvailability {
        guard input.osSupported else { return .unavailable(.osTooOld) }
        switch input.model {
        case .available: break
        case .deviceNotEligible: return .unavailable(.deviceNotEligible)
        case .appleIntelligenceNotEnabled: return .unavailable(.appleIntelligenceNotEnabled)
        case .modelNotReady: return .unavailable(.modelNotReady)
        case .other: return .unavailable(.modelUnavailableOther)
        }
        guard input.supportsKorean else { return .unavailable(.localeUnsupported) }
        let limit = max(0, min(policy.maxInputScalars, input.contextSize - policy.reservedTokens))
        guard input.inputScalarCount <= limit else { return .unavailable(.inputTooLong(limit: limit)) }
        guard policy.enabledModelKeys.contains(input.modelTag.modelKey) else {
            return .unavailable(.tagDisabled(modelKey: input.modelTag.modelKey))
        }
        return .available
    }
}

/// 기기에서 도는 시스템 모델의 태그. Apple 문서상 모델 버전은 26.0–26.3 / 26.4 / 27.0 셋이다.
/// iOS 27 의 `variant`(.core3 / .coreAdvanced3)는 **Xcode 27 SDK에만** 있다 → 26.4 SDK로 빌드한 앱이 27 기기에서 돌면
/// 변형을 알 수 없으므로 `fm/apple-27-unknown` 으로 두고 정책에 없으니 자동으로 닫힌다(fail-closed).
public enum FMModelTag {
    public static func resolve(os osVersion: OperatingSystemVersion, variant: String? = nil, promptVersion: Int) -> EngineTag {
        let model = switch (osVersion.majorVersion, osVersion.minorVersion) {
        case (26, ..<4): "apple-26.0"
        case (26, _): "apple-26.4"
        case (27, _):
            switch variant {
            case "core3": "apple-27-core"
            case "coreAdvanced3": "apple-27-adv"
            default: "apple-27-unknown"
            }
        case let (major, _) where major > 27: "apple-\(major)-unknown"
        default: "apple-pre26"
        }
        return EngineTag(track: "fm", model: model, pipelineVersion: promptVersion)!
    }
}
