#if canImport(FoundationModels)
    public import MwonmalIntelligenceCore

    internal import Foundation
    internal import FoundationModels

    // 모든 심볼은 SDK 26.4 `FoundationModels.swiftinterface`에서 확인한 것만 쓴다.
    // iOS 27 전용(`LanguageModelError`, `SystemLanguageModel.variant`, PCC)은 CI가 Xcode 27로 올라간 뒤
    // `#if compiler(>=6.4)` 블록으로 추가한다(ADR-0011 개정 조건). 지금 SDK에는 없다.

    @available(iOS 26.0, macOS 26.0, *)
    @Generable(description: "판교어 문장의 쉬운 말 미리보기")
    struct FMDraftSchema {
        @Guide(description: "원문 전체를 쉬운 한국어로 다시 쓴 한두 문장")
        var plainKorean: String

        @Guide(description: "원문의 의도. 애매하면 nil")
        var intent: FMIntent?

        @Guide(description: "원문이 시킨 할 일. 짧은 한국어 명사구", .maximumCount(5))
        var actionItems: [String]
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    enum FMIntent {
        case request, decision, decline, share, question

        var draftIntent: DraftIntent {
            switch self {
            case .request: .request
            case .decision: .decision
            case .decline: .decline
            case .share: .share
            case .question: .question
            }
        }
    }

    /// 온디바이스 Foundation Models 미리보기 엔진(ADR-0015). 상태 없음 — 요청마다 새 세션, greedy.
    /// `SystemLanguageModel`·`LanguageModelSession`은 `Sendable`(SDK 확인)이라 값 타입으로 충분하다.
    @available(iOS 26.0, macOS 26.0, *)
    public struct AppleFMDraftEngine: DraftGenerating {
        public let policy: FMGatePolicy
        private let model: SystemLanguageModel

        public init(policy: FMGatePolicy) {
            self.policy = policy
            // 일반 용도 + 기본 가드레일. `.contentTagging`은 측정 열로만(ADR-0007 §4-6 (b)).
            model = SystemLanguageModel.default
        }

        public var engine: EngineTag {
            let key = FMModelTag.resolve(os: ProcessInfo.processInfo.operatingSystemVersion, promptVersion: 0).modelKey
            return FMModelTag.resolve(
                os: ProcessInfo.processInfo.operatingSystemVersion,
                promptVersion: FMPrompt.forModel(key).version
            )
        }

        public func gateInput(for request: DraftRequest) -> FMGateInput {
            let state: FMGateInput.ModelState = switch model.availability {
            case .available: .available
            case .unavailable(.deviceNotEligible): .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady): .modelNotReady
            case .unavailable: .other
            }
            return FMGateInput(
                osSupported: true,
                model: state,
                supportsKorean: model.supportsLocale(Locale(identifier: "ko_KR")),
                contextSize: model.contextSize,
                inputScalarCount: request.text.unicodeScalars.count,
                modelTag: engine
            )
        }

        public func availability(for request: DraftRequest) async -> EngineAvailability {
            guard request.source == .message else { return .unavailable(.inputTooLong(limit: policy.maxInputScalars)) }
            return FMGate.evaluate(gateInput(for: request), policy: policy)
        }

        public func prewarm() async {
            guard model.availability == .available else { return }
            LanguageModelSession(model: model, instructions: FMPrompt.forModel(engine.modelKey).instructions).prewarm()
        }

        public func draft(for request: DraftRequest) async throws(IntelligenceError) -> IntelligenceDraft {
            let gate = await availability(for: request)
            guard case .available = gate else {
                if case let .unavailable(reason) = gate {
                    throw .unavailable(reason)
                }
                throw .unknown
            }
            let tag = engine
            let session = LanguageModelSession(model: model, instructions: FMPrompt.forModel(tag.modelKey).instructions)
            do {
                // 원문은 prompt에만.
                let response = try await session.respond(
                    to: request.text,
                    generating: FMDraftSchema.self,
                    options: GenerationOptions(sampling: .greedy)
                )
                let content = response.content
                return IntelligenceDraft(
                    resultText: content.plainKorean,
                    intent: content.intent?.draftIntent,
                    actionTexts: content.actionItems,
                    engine: tag
                )
            } catch is CancellationError {
                throw .cancelled
            } catch let generationError as LanguageModelSession.GenerationError {
                throw FMErrorMapping.map(generationError)
            } catch {
                throw .unknown
            }
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    enum FMErrorMapping {
        /// 26 SDK의 `GenerationError`(27에서 deprecated). 27의 `LanguageModelError` 매핑은 Xcode 27 전환 때
        /// `#if compiler(>=6.4)` 로 위에 catch 절을 하나 더 둔다. 새 case는 `@unknown default`로 흡수.
        static func map(_ error: LanguageModelSession.GenerationError) -> IntelligenceError {
            switch error {
            case .exceededContextWindowSize: .exceededContextWindow
            case .assetsUnavailable: .assetsUnavailable
            case .guardrailViolation: .guardrailViolation
            case .unsupportedLanguageOrLocale: .unsupportedLanguageOrLocale
            case .decodingFailure: .decodingFailure
            case .rateLimited: .rateLimited
            case .concurrentRequests: .concurrentRequests
            case .refusal: .refusal
            default: .unknown
            }
        }
    }

    /// 테스트·평가 CLI용: 이 기기에서 FM 실호출이 가능한지(정책과 무관하게 겹 1~3만).
    public enum FMProbe {
        public static var liveModelReason: String? {
            guard #available(iOS 26.0, macOS 26.0, *) else { return "OS < 26" }
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return "SystemLanguageModel.availability = \(model.availability)" }
            guard model.supportsLocale(Locale(identifier: "ko_KR")) else { return "ko_KR 미지원" }
            return nil
        }
    }
#else
    /// FoundationModels가 없는 SDK(예: 다른 플랫폼)에서도 호출부가 컴파일되도록.
    public enum FMProbe {
        public static var liveModelReason: String? {
            "SDK에 FoundationModels 없음"
        }
    }
#endif
