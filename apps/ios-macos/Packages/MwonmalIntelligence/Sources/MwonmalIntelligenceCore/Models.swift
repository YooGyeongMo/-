internal import Foundation

// MARK: - 탐지

/// 탐지된 판교어 구간 하나. `termKey`는 사전 표제어(사전에서 왔을 때만). 서버 `termId`는 여기 없다(REQ-14: 서버 전용).
public struct JargonSpan: Hashable, Sendable {
    public enum Origin: String, Sendable, Codable { case dictionary, model }

    public let range: ScalarRange
    public let matchedText: String
    public let origin: Origin
    public let termKey: String?
    /// 모델 출처일 때 구간 평균 확률(0~1). 사전 출처는 nil.
    public let confidence: Double?

    public init(range: ScalarRange, matchedText: String, origin: Origin, termKey: String? = nil, confidence: Double? = nil) {
        self.range = range
        self.matchedText = matchedText
        self.origin = origin
        self.termKey = termKey
        self.confidence = confidence
    }
}

public struct DetectionResult: Sendable {
    public let spans: [JargonSpan]
    public let engine: EngineTag
    public let latency: Duration

    public init(spans: [JargonSpan], engine: EngineTag, latency: Duration) {
        self.spans = spans
        self.engine = engine
        self.latency = latency
    }
}

// MARK: - 미리보기 초안

/// 서버 `IntentType` enum과 같은 값(계약 yml 그대로).
public enum DraftIntent: String, Sendable, Codable, CaseIterable {
    case request = "REQUEST", decision = "DECISION", decline = "DECLINE", share = "SHARE", question = "QUESTION"
}

/// 미리보기 초안 = 서버 `TranslationResponse`의 AI 생성 부분집합 중 ADR-0015가 허용한 것만.
/// 형광펜(인덱스)·`termId`·`dueAt`은 **없다**(서버 전용, REQ-14). 저장·전송하지 않는다.
public struct IntelligenceDraft: Hashable, Sendable {
    public let resultText: String
    public let intent: DraftIntent?
    public let actionTexts: [String]
    public let engine: EngineTag

    public init(resultText: String, intent: DraftIntent?, actionTexts: [String], engine: EngineTag) {
        self.resultText = resultText
        self.intent = intent
        self.actionTexts = actionTexts
        self.engine = engine
    }
}

public enum SourceKind: String, Sendable, Codable { case message = "MESSAGE", meetingNote = "MEETING_NOTE" }

public struct DraftRequest: Sendable {
    public let text: String
    public let source: SourceKind

    public init(text: String, source: SourceKind = .message) {
        self.text = text
        self.source = source
    }
}

// MARK: - 가용성·오류

/// 엔진을 지금 쓸 수 있는가. Domain `TranslationEngineAvailability`로 1:1 매핑한다(Platform 어댑터).
public enum EngineAvailability: Hashable, Sendable {
    case available
    case unavailable(UnavailableReason)

    public var isAvailable: Bool {
        self == .available
    }
}

/// ADR-0015 다섯 겹 게이트 순서와 같은 순서로 정의.
public enum UnavailableReason: Hashable, Sendable {
    /// 겹 1: OS < 26 또는 SDK에 FoundationModels 없음.
    case osTooOld
    /// 겹 2: `SystemLanguageModel.availability` 사유.
    case deviceNotEligible, appleIntelligenceNotEnabled, modelNotReady, modelUnavailableOther
    /// 겹 3: `supportsLocale(ko_KR)` 실패.
    case localeUnsupported
    /// 겹 4: 토큰 예산 초과(입력 스칼라 수 > 한도).
    case inputTooLong(limit: Int)
    /// 겹 5: 모델 태그 기능 플래그 OFF(점수 게이트 미통과·야간 2회 미달·미측정 태그).
    case tagDisabled(modelKey: String)
    /// 탐지 모델 파일 없음·로드 실패(애셋 팩 미다운로드 포함).
    case modelAssetMissing
}

public enum IntelligenceError: Error, Hashable, Sendable {
    case unavailable(UnavailableReason)
    case exceededContextWindow
    case guardrailViolation
    case refusal
    case unsupportedLanguageOrLocale
    case decodingFailure
    case rateLimited
    case concurrentRequests
    case assetsUnavailable
    case modelLoadFailed
    case cancelled
    case unknown
}

// MARK: - 프로토콜 (패키지 소유 — Domain 프로토콜은 Platform 어댑터가 구현)

public protocol JargonDetecting: Sendable {
    var engine: EngineTag { get }
    func detect(in text: String) async throws(IntelligenceError) -> DetectionResult
}

public protocol DraftGenerating: Sendable {
    var engine: EngineTag { get async }
    func availability(for request: DraftRequest) async -> EngineAvailability
    func prewarm() async
    func draft(for request: DraftRequest) async throws(IntelligenceError) -> IntelligenceDraft
}
