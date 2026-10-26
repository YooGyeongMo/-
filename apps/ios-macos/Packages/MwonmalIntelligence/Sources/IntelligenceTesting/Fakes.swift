public import MwonmalIntelligenceCore

internal import Foundation

/// 정해진 구간을 돌려주는 탐지기.
public struct FakeJargonDetector: JargonDetecting {
    public let engine: EngineTag
    public let result: Result<[JargonSpan], IntelligenceError>
    public let delay: Duration

    public init(engine: EngineTag = .dictionaryOnly, result: Result<[JargonSpan], IntelligenceError>, delay: Duration = .zero) {
        self.engine = engine
        self.result = result
        self.delay = delay
    }

    public func detect(in text: String) async throws(IntelligenceError) -> DetectionResult {
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        return try DetectionResult(spans: result.get(), engine: engine, latency: delay)
    }
}

/// 가용성·결과·지연을 고정한 초안 엔진. ADR-0015 §7 "availability 6종 × 서버 성공·실패·지연" VM 테스트용.
public actor FakeDraftEngine: DraftGenerating {
    public let engine: EngineTag
    public var availabilityValue: EngineAvailability
    public var result: Result<IntelligenceDraft, IntelligenceError>
    public var delay: Duration
    public private(set) var draftCalls = 0
    public private(set) var prewarmCalls = 0

    public init(
        engine: EngineTag = EngineTag("fm/apple-26.4#p1")!,
        availability: EngineAvailability = .available,
        result: Result<IntelligenceDraft, IntelligenceError>,
        delay: Duration = .zero
    ) {
        self.engine = engine
        availabilityValue = availability
        self.result = result
        self.delay = delay
    }

    public func availability(for request: DraftRequest) async -> EngineAvailability {
        availabilityValue
    }

    public func prewarm() async {
        prewarmCalls += 1
    }

    public func draft(for request: DraftRequest) async throws(IntelligenceError) -> IntelligenceDraft {
        draftCalls += 1
        if delay > .zero {
            do { try await Task.sleep(for: delay) } catch { throw .cancelled }
        }
        return try result.get()
    }

    /// 대표 가용성 6종(Domain VM 테스트 매트릭스).
    public static let availabilityMatrix: [EngineAvailability] = [
        .available,
        .unavailable(.osTooOld),
        .unavailable(.deviceNotEligible),
        .unavailable(.appleIntelligenceNotEnabled),
        .unavailable(.modelNotReady),
        .unavailable(.tagDisabled(modelKey: "fm/apple-27-unknown")),
    ]
}

/// 이벤트를 모으는 싱크(텔레메트리 테스트).
public final class RecordingEventSink: IntelligenceEventSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [IntelligenceEvent] = []

    public init() {}

    public func record(_ event: IntelligenceEvent) {
        lock.lock(); defer { lock.unlock() }
        _events.append(event)
    }

    public var events: [IntelligenceEvent] {
        lock.lock(); defer { lock.unlock() }
        return _events
    }
}

/// 원문 유출 검사용 카나리(ADR-0008 §6 `MWCANARY-<uuid>`와 같은 형식).
public enum Canary {
    public static func make() -> String {
        "MWCANARY-\(UUID().uuidString)"
    }
}
