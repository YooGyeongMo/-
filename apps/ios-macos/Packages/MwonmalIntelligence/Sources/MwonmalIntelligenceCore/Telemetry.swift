internal import Foundation

/// 텔레메트리 이벤트. **문자열 필드는 엔진 태그 하나뿐**이고 원문·결과·용어는 담을 수 없다(타입으로 막음, ADR-0008 관측 규칙).
/// 호스트(Platform/Observability)가 Amplitude allowlist 속성으로 옮긴다.
public struct IntelligenceEvent: Hashable, Sendable {
    public enum Kind: String, Sendable { case detect, draft, availability, modelLoad }
    public enum Outcome: Hashable, Sendable {
        case success
        case unavailable(UnavailableReason)
        case failure(IntelligenceError)
        /// 서버 정본이 먼저 와서 미리보기를 버림(ADR-0015 "늦게 온 미리보기는 무시").
        case discardedLate
    }

    public let kind: Kind
    public let engine: EngineTag
    public let outcome: Outcome
    public let latencyMilliseconds: Int
    public let inputLengthBucket: LengthBucket
    public let spanCount: Int?

    public init(kind: Kind, engine: EngineTag, outcome: Outcome, latency: Duration, inputLength: Int, spanCount: Int? = nil) {
        self.kind = kind
        self.engine = engine
        self.outcome = outcome
        let parts = latency.components
        latencyMilliseconds = Int(parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000)
        inputLengthBucket = LengthBucket(inputLength)
        self.spanCount = spanCount
    }
}

/// 입력 길이는 정확한 값 대신 구간만(재식별 방지).
public enum LengthBucket: String, Sendable, Hashable {
    case upTo100 = "0-100", upTo300 = "101-300", upTo500 = "301-500", upTo1000 = "501-1000", over1000 = "1001+"

    public init(_ length: Int) {
        switch length {
        case ...100: self = .upTo100
        case ...300: self = .upTo300
        case ...500: self = .upTo500
        case ...1000: self = .upTo1000
        default: self = .over1000
        }
    }
}

public protocol IntelligenceEventSink: Sendable {
    func record(_ event: IntelligenceEvent)
}

public struct NoopEventSink: IntelligenceEventSink {
    public init() {}
    public func record(_ event: IntelligenceEvent) {}
}

/// 엔진을 감싸 시간과 결과를 기록하는 데코레이터. 엔진 코드에 텔레메트리 호출을 흩뿌리지 않는다.
public struct InstrumentedDetector<Base: JargonDetecting>: JargonDetecting {
    public let base: Base
    public let sink: any IntelligenceEventSink
    public let clock: ContinuousClock

    public init(_ base: Base, sink: any IntelligenceEventSink, clock: ContinuousClock = .init()) {
        self.base = base
        self.sink = sink
        self.clock = clock
    }

    public var engine: EngineTag {
        base.engine
    }

    public func detect(in text: String) async throws(IntelligenceError) -> DetectionResult {
        let start = clock.now
        do {
            let result = try await base.detect(in: text)
            sink.record(.init(
                kind: .detect,
                engine: engine,
                outcome: .success,
                latency: clock.now - start,
                inputLength: text.unicodeScalars.count,
                spanCount: result.spans.count
            ))
            return result
        } catch {
            sink.record(.init(
                kind: .detect,
                engine: engine,
                outcome: .failure(error),
                latency: clock.now - start,
                inputLength: text.unicodeScalars.count
            ))
            throw error
        }
    }
}
