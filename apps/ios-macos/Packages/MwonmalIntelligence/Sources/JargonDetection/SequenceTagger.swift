public import Foundation
public import MwonmalIntelligenceCore

internal import CoreML
internal import NaturalLanguage

/// 토큰 → 라벨(+확률) 태거. Core ML 구현과 테스트용 Fake가 같은 자리를 쓴다.
public protocol SequenceTagging: Sendable {
    var engine: EngineTag { get }
    /// 토큰마다 (라벨, 그 라벨의 확률). 확률을 못 주는 구현은 1.0.
    func tag(tokens: [String]) async throws(IntelligenceError) -> [(label: String, probability: Double)]
}

/// Create ML `MLWordTagger`로 학습한 모델을 `NLModel`로 돌린다(iOS 12+ API, 앱 최소 17에서 게이트 불필요).
/// `NLModel`·`MLModel`은 `Sendable`이 아니므로 actor 안에 가둔다.
public actor CoreMLSequenceTagger: SequenceTagging {
    public nonisolated let engine: EngineTag
    private let model: NLModel

    /// - Parameter compiledModelURL: `.mlmodelc` 디렉터리. 암호화 모델(`coremlcompiler compile --encrypt`)도 같은 경로로 로드된다 —
    ///   첫 로드 때 Core ML이 Apple 키 서버에서 복호화 키를 받는다(사용자 원문과 무관한 네트워크, 실패 시 `.modelLoadFailed`).
    public init(compiledModelURL: URL, engine: EngineTag, computeUnits: MLComputeUnitsOption = .cpuOnly) async throws(IntelligenceError) {
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits.mlValue
        do {
            let mlModel = try await MLModel.load(contentsOf: compiledModelURL, configuration: config)
            model = try NLModel(mlModel: mlModel)
        } catch {
            throw .modelLoadFailed
        }
        self.engine = engine
    }

    public func tag(tokens: [String]) async throws(IntelligenceError) -> [(label: String, probability: Double)] {
        guard !tokens.isEmpty else { return [] }
        let hyps = model.predictedLabelHypotheses(forTokens: tokens, maximumCount: 1)
        guard hyps.count == tokens.count else { throw .decodingFailure }
        return hyps.map { hypothesis in
            let best = hypothesis.max { $0.value < $1.value }
            return (best?.key ?? "O", best?.value ?? 0)
        }
    }
}

/// `MLComputeUnits`를 공개 API에 노출하지 않으려는 얇은 래퍼(호스트가 CoreML을 import하지 않아도 되게).
public enum MLComputeUnitsOption: Sendable {
    case cpuOnly, cpuAndNeuralEngine, all

    var mlValue: MLComputeUnits {
        switch self {
        case .cpuOnly: .cpuOnly
        case .cpuAndNeuralEngine: .cpuAndNeuralEngine
        case .all: .all
        }
    }
}
