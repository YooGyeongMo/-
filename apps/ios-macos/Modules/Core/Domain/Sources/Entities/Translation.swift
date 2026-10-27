import Foundation

/// 해석 방향(계약 TranslationDirection). v1.0 화면은 판교어 → 쉬운 말만 쓴다.
public enum TranslationDirection: String, Sendable, CaseIterable {
    case jargonToPlain = "JARGON_TO_PLAIN"
    case plainToJargon = "PLAIN_TO_JARGON"
}

/// 문장의 실제 의도(계약 IntentType).
public enum IntentType: String, Sendable, CaseIterable {
    case request = "REQUEST"
    case decision = "DECISION"
    case decline = "DECLINE"
    case share = "SHARE"
    case question = "QUESTION"
}

/// 입력 경로(계약 InputSource).
public enum InputSource: String, Sendable, CaseIterable {
    case typed = "TYPED"
    case screenshot = "SCREENSHOT"
    case recording = "RECORDING"
    case `extension` = "EXTENSION"
}

/// 원문에서 찾은 판교어 한 개. 위치는 유니코드 스칼라 기준(서버와 같다, REQ-14).
public struct DetectedTerm: Sendable, Equatable, Hashable {
    /// 사전에 없는 새 말(AI가 찾음)이면 nil → 카드 담기 불가(#15).
    public let termId: Int64?
    public let termKo: String
    public let plainKo: String
    public let matchedText: String
    public let startIndex: Int
    public let endIndex: Int
    public let inMyCards: Bool
    /// 이 말이 판교어일 확률(0~1). 사전에서 찾으면 1에 가깝고, 사전 밖에서 앞뒤 문맥으로 찾은 말(서버 문맥 모델)은
    /// 모델 확률이다(계약 `DetectedTerm.confidence`).
    public let confidence: Double

    public init(
        termId: Int64?,
        termKo: String,
        plainKo: String,
        matchedText: String,
        startIndex: Int,
        endIndex: Int,
        inMyCards: Bool,
        confidence: Double = 1
    ) {
        self.termId = termId
        self.termKo = termKo
        self.plainKo = plainKo
        self.matchedText = matchedText
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.inMyCards = inMyCards
        self.confidence = confidence
    }

    /// 사전에도 없고 뜻도 아직 없는 말(문맥 모델이 찾음). 형광펜은 칠하되 "확률"을 같이 보여 준다.
    public var isContextGuess: Bool {
        termId == nil && plainKo.isEmpty
    }
}

/// 해석으로 뽑힌 할 일.
public struct ActionItem: Sendable, Equatable, Identifiable, Hashable {
    public let id: Int64
    public let sortOrder: Int
    public let text: String
    public let dueHint: String?
    public let dueAt: Date?
    public var isChecked: Bool
    public var alertEnabled: Bool

    public init(id: Int64, sortOrder: Int, text: String, dueHint: String?, dueAt: Date?, isChecked: Bool, alertEnabled: Bool) {
        self.id = id
        self.sortOrder = sortOrder
        self.text = text
        self.dueHint = dueHint
        self.dueAt = dueAt
        self.isChecked = isChecked
        self.alertEnabled = alertEnabled
    }
}

/// 숨은 뜻(💭 블록).
public struct Nuance: Sendable, Equatable, Hashable {
    public let note: String
    public let tip: String
    /// 0~1. 화면 노출 여부는 PO 결정 대기(확신도 % 노출, STATE §2).
    public let confidence: Double

    public init(note: String, tip: String, confidence: Double) {
        self.note = note
        self.tip = tip
        self.confidence = confidence
    }
}

/// 해석 결과 한 건(계약 TranslationResponse의 화면용 모양).
public struct Translation: Sendable, Equatable, Identifiable, Hashable {
    public let id: Int64
    public let projectId: Int64
    public let projectName: String
    public let meetingTitle: String?
    public let inputSource: InputSource
    public let sourceText: String
    public let resultText: String
    public let jargonCount: Int
    public let intent: IntentType?
    public let nuance: Nuance?
    public var actions: [ActionItem]
    public let terms: [DetectedTerm]
    /// `<엔진>/<모델>#p<n>`. `none/`이면 사전만 쓴 간이 해석(#14 배지).
    public let aiModel: String
    public let createdAt: Date

    public init(
        id: Int64, projectId: Int64, projectName: String, meetingTitle: String?, inputSource: InputSource,
        sourceText: String, resultText: String, jargonCount: Int, intent: IntentType?, nuance: Nuance?,
        actions: [ActionItem], terms: [DetectedTerm], aiModel: String, createdAt: Date
    ) {
        self.id = id
        self.projectId = projectId
        self.projectName = projectName
        self.meetingTitle = meetingTitle
        self.inputSource = inputSource
        self.sourceText = sourceText
        self.resultText = resultText
        self.jargonCount = jargonCount
        self.intent = intent
        self.nuance = nuance
        self.actions = actions
        self.terms = terms
        self.aiModel = aiModel
        self.createdAt = createdAt
    }

    /// 사전만으로 한 간이 해석인지(옵트인 안 했거나 AI가 쉬는 중).
    public var isSimplified: Bool {
        aiModel.hasPrefix("none/")
    }

    /// 판교어가 하나도 없다(청정 한국어 빈 상태).
    public var isClean: Bool {
        jargonCount == 0
    }
}

/// 기록 목록 한 줄(계약 TranslationSummary).
public struct TranslationSummary: Sendable, Equatable, Identifiable, Hashable {
    public let id: Int64
    public let title: String
    public let inputSource: InputSource
    public let sourceText: String
    public let resultText: String
    public let jargonCount: Int
    public let intent: IntentType?
    public let actionCount: Int
    public let openActionCount: Int
    public let createdAt: Date

    public init(
        id: Int64, title: String, inputSource: InputSource, sourceText: String, resultText: String,
        jargonCount: Int, intent: IntentType?, actionCount: Int, openActionCount: Int, createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.inputSource = inputSource
        self.sourceText = sourceText
        self.resultText = resultText
        self.jargonCount = jargonCount
        self.intent = intent
        self.actionCount = actionCount
        self.openActionCount = openActionCount
        self.createdAt = createdAt
    }
}

/// 홈 "다가오는 할 일" 한 줄(계약 ActionWithSource).
public struct UpcomingAction: Sendable, Equatable, Identifiable, Hashable {
    public var action: ActionItem
    public let translationId: Int64
    public let projectName: String
    public let meetingTitle: String?
    public let inputSource: InputSource?
    public let createdAt: Date

    public var id: Int64 {
        action.id
    }

    public init(
        action: ActionItem,
        translationId: Int64,
        projectName: String,
        meetingTitle: String?,
        inputSource: InputSource?,
        createdAt: Date
    ) {
        self.action = action
        self.translationId = translationId
        self.projectName = projectName
        self.meetingTitle = meetingTitle
        self.inputSource = inputSource
        self.createdAt = createdAt
    }
}

/// 용어 상세(용어 시트).
public struct TermDetail: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let termKo: String
    public let originEn: String?
    public let plainKo: String
    public let meaning: String
    public let examples: [TermExample]

    public init(id: Int64, termKo: String, originEn: String?, plainKo: String, meaning: String, examples: [TermExample]) {
        self.id = id
        self.termKo = termKo
        self.originEn = originEn
        self.plainKo = plainKo
        self.meaning = meaning
        self.examples = examples
    }
}

public struct TermExample: Sendable, Equatable, Hashable {
    public let jargon: String
    public let plain: String

    public init(jargon: String, plain: String) {
        self.jargon = jargon
        self.plain = plain
    }
}

/// 프로젝트 요약(A-11 머리, MY 행).
public struct ProjectSummary: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let name: String
    public let description: String
    public let translationCount: Int
    public let openActionCount: Int
    public let meetingCount: Int
    public let unknownTermCount: Int
    public let isDefault: Bool

    public init(
        id: Int64,
        name: String,
        description: String,
        translationCount: Int,
        openActionCount: Int,
        meetingCount: Int,
        unknownTermCount: Int,
        isDefault: Bool
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.translationCount = translationCount
        self.openActionCount = openActionCount
        self.meetingCount = meetingCount
        self.unknownTermCount = unknownTermCount
        self.isDefault = isDefault
    }
}

/// 목록 한 페이지.
public struct Page<Item: Sendable>: Sendable {
    public let items: [Item]
    public let page: Int
    public let totalElements: Int
    public let totalPages: Int

    public init(items: [Item], page: Int, totalElements: Int, totalPages: Int) {
        self.items = items
        self.page = page
        self.totalElements = totalElements
        self.totalPages = totalPages
    }

    public var hasMore: Bool {
        page < totalPages
    }
}

extension Page: Equatable where Item: Equatable {}
