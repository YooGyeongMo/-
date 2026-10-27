import Foundation

/// 해석: 입력 정리 → 동의 확인 → 서버. 빈 문장·500자 초과는 서버까지 가지 않는다(W-01).
public struct TranslateUseCase: Sendable {
    public static let maxLength = 500

    private let repository: any TranslationRepository
    private let consent: any AIConsentStore

    public init(repository: any TranslationRepository, consent: any AIConsentStore) {
        self.repository = repository
        self.consent = consent
    }

    public func callAsFunction(_ text: String, projectId: Int64? = nil) async throws -> Translation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.invalidInput(message: nil) }
        guard trimmed.unicodeScalars.count <= Self.maxLength else { throw DomainError.invalidInput(message: nil) }
        let granted = await consent.isGranted()
        return try await repository.translate(trimmed, direction: .jargonToPlain, projectId: projectId, aiConsent: granted)
    }

    /// 입력 칸 글자 수 표시(서버와 같은 단위: 유니코드 스칼라).
    public static func length(of text: String) -> Int {
        text.unicodeScalars.count
    }
}

/// 할 일 체크. 화면은 먼저 바꿔 보여 주고(낙관적), 실패하면 되돌린다.
public struct ToggleActionUseCase: Sendable {
    private let repository: any TranslationRepository

    public init(repository: any TranslationRepository) {
        self.repository = repository
    }

    public func callAsFunction(translationId: Int64, action: ActionItem) async throws -> ActionItem {
        try await repository.setAction(translationId: translationId, actionId: action.id, isChecked: !action.isChecked, alertEnabled: nil)
    }
}
