#if DEBUG
    import Domain
    import Foundation

    public extension Translation {
        /// 계약 예시 "업무지시해독"과 같은 문장·위치(스칼라 인덱스).
        static let sample = Translation(
            id: 1024,
            projectId: 7,
            projectName: "루나",
            meetingTitle: "스프린트 계획 회의",
            inputSource: .typed,
            sourceText: "이번 스프린트 스코프 아웃하고 넥스트로 밀죠. 그 전에 R&R 정리해서 얼라인 쳐주세요",
            resultText: "이번 작업 범위에서 빼고 다음으로 미루죠. 그 전에 누가 뭘 할지 정리해서 합의해 주세요.",
            jargonCount: 4,
            intent: .decision,
            nuance: Nuance(note: "\"밀죠\"는 제안이 아니라 이미 정해진 일이에요. 일정만 확인하세요.", tip: "되묻기보다 일정만 확인하는 편이 안전해요.", confidence: 0.88),
            actions: [
                ActionItem(id: 5001, sortOrder: 1, text: "역할 정리 문서 만들기", dueHint: "오늘", dueAt: Date(timeIntervalSince1970: 1_793_600_000), isChecked: false, alertEnabled: true),
                ActionItem(id: 5002, sortOrder: 2, text: "관련 팀과 합의하기", dueHint: "내일", dueAt: nil, isChecked: false, alertEnabled: true),
            ],
            terms: [
                DetectedTerm(termId: 21, termKo: "스코프 아웃", plainKo: "작업 범위에서 제외", matchedText: "스코프 아웃", startIndex: 8, endIndex: 14, inMyCards: false),
                DetectedTerm(termId: 25, termKo: "넥스트", plainKo: "다음 차례", matchedText: "넥스트", startIndex: 17, endIndex: 20, inMyCards: false),
                DetectedTerm(termId: 18, termKo: "R&R", plainKo: "역할과 책임", matchedText: "R&R", startIndex: 31, endIndex: 34, inMyCards: true),
                DetectedTerm(termId: 3, termKo: "얼라인", plainKo: "방향 맞추기", matchedText: "얼라인", startIndex: 40, endIndex: 43, inMyCards: true),
            ],
            aiModel: "gemini_free/gemini-2.5-flash#p1",
            createdAt: Date(timeIntervalSince1970: 1_793_580_000)
        )

        static let clean = Translation(
            id: 1025, projectId: 7, projectName: "루나", meetingTitle: nil, inputSource: .typed,
            sourceText: "오늘 점심 뭐 드실래요", resultText: "오늘 점심 뭐 드실래요", jargonCount: 0, intent: .question,
            nuance: nil, actions: [], terms: [], aiModel: "none/dictionary#p1", createdAt: Date(timeIntervalSince1970: 1_793_580_000)
        )
    }

    public extension TranslationSummary {
        static func sample(id: Int64 = 1024, openActions: Int = 2) -> TranslationSummary {
            TranslationSummary(
                id: id, title: "이번 스프린트 스코프 아웃하고…", inputSource: .typed,
                sourceText: Translation.sample.sourceText, resultText: Translation.sample.resultText,
                jargonCount: 4, intent: .decision, actionCount: 2, openActionCount: openActions,
                createdAt: Date(timeIntervalSince1970: 1_793_580_000)
            )
        }
    }

    /// 메모리 동의 저장소.
    public actor InMemoryAIConsentStore: AIConsentStore {
        public private(set) var granted: Bool

        public init(granted: Bool = false) {
            self.granted = granted
        }

        public func isGranted() async -> Bool {
            granted
        }

        public func setGranted(_ granted: Bool) async {
            self.granted = granted
        }
    }

    /// 호출을 기록하고 정해 둔 결과를 돌려주는 해석 리포지토리.
    public actor FakeTranslationRepository: TranslationRepository {
        public var translateResult: Result<Translation, DomainError> = .success(.sample)
        public var listResult: Result<Page<TranslationSummary>, DomainError> = .success(Page(items: [.sample()], page: 1, totalElements: 1, totalPages: 1))
        public var actionsResult: Result<Page<UpcomingAction>, DomainError> = .success(Page(items: [], page: 1, totalElements: 0, totalPages: 0))
        public var setActionResult: Result<ActionItem, DomainError>?
        public var projectsResult: Result<[ProjectSummary], DomainError> = .success([])
        /// 해석이 끝나기 전까지 기다리게 한다(취소 테스트).
        public var translateDelay: Duration?
        public private(set) var translateCalls: [(text: String, consent: Bool)] = []
        public private(set) var setActionCalls: [(translationId: Int64, actionId: Int64, isChecked: Bool?)] = []
        public private(set) var deleted: [Int64] = []

        public init() {}

        public func setTranslateResult(_ r: Result<Translation, DomainError>) {
            translateResult = r
        }

        public func setTranslateDelay(_ d: Duration?) {
            translateDelay = d
        }

        public func setListResult(_ r: Result<Page<TranslationSummary>, DomainError>) {
            listResult = r
        }

        public func setActionsResult(_ r: Result<Page<UpcomingAction>, DomainError>) {
            actionsResult = r
        }

        public func setSetActionResult(_ r: Result<ActionItem, DomainError>?) {
            setActionResult = r
        }

        public func setProjectsResult(_ r: Result<[ProjectSummary], DomainError>) {
            projectsResult = r
        }

        public func translate(_ text: String, direction: TranslationDirection, projectId: Int64?, aiConsent: Bool) async throws -> Translation {
            translateCalls.append((text, aiConsent))
            if let translateDelay {
                try await Task.sleep(for: translateDelay)
            }
            return try translateResult.get()
        }

        public func translations(projectId: Int64?, page: Int, size: Int) async throws -> Page<TranslationSummary> {
            try listResult.get()
        }

        public func translation(id: Int64) async throws -> Translation {
            try translateResult.get()
        }

        public func deleteTranslation(id: Int64) async throws {
            deleted.append(id)
        }

        public func setAction(translationId: Int64, actionId: Int64, isChecked: Bool?, alertEnabled: Bool?) async throws -> ActionItem {
            setActionCalls.append((translationId, actionId, isChecked))
            if let setActionResult {
                return try setActionResult.get()
            }
            let base = try translateResult.get().actions.first { $0.id == actionId }
                ?? ActionItem(id: actionId, sortOrder: 1, text: "", dueHint: nil, dueAt: nil, isChecked: false, alertEnabled: true)
            var updated = base
            if let isChecked {
                updated.isChecked = isChecked
            }
            if let alertEnabled {
                updated.alertEnabled = alertEnabled
            }
            return updated
        }

        public func actions(checked: Bool, page: Int, size: Int) async throws -> Page<UpcomingAction> {
            try actionsResult.get()
        }

        public func term(id: Int64) async throws -> TermDetail {
            TermDetail(id: id, termKo: "얼라인", originEn: "align", plainKo: "방향 맞추기", meaning: "여러 사람의 이해와 목표를 같은 방향으로 맞추는 것.", examples: [TermExample(jargon: "이번 주까지 팀 간 얼라인 부탁드려요.", plain: "이번 주까지 팀끼리 방향을 맞춰 주세요.")])
        }

        public func projects() async throws -> [ProjectSummary] {
            try projectsResult.get()
        }
    }
#endif
