public import MwonmalIntelligenceCore

/// iOS 17에서도 부를 수 있는 진입점. `#available`은 여기 한 곳(패키지 = Platform 층, ADR-0005 게이트 ①).
/// Composition은 이 함수 결과(`nil` 가능)를 Domain 어댑터에 넣기만 한다.
public enum FMEngineFactory {
    public static func makeIfSupported(policy: FMGatePolicy) -> (any DraftGenerating)? {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                return AppleFMDraftEngine(policy: policy)
            }
        #endif
        return nil
    }
}
