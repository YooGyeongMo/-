/// FeatureKit 모듈(ADR-0016, 구 Presentation/Common). 여러 Feature가 같이 쓰는 화면 상태 조각.
public enum FeatureKitModule {
    public static let name = "FeatureKit"
}

/// 화면 모델의 공통 단계(D-15). 실패 문구는 화면이 String Catalog 키로 정한다.
public enum Phase<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(code: String)

    public var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    public var value: Value? {
        if case let .loaded(value) = self {
            return value
        }
        return nil
    }
}

extension Phase: Equatable where Value: Equatable {}
