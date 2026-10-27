import Foundation

/// 해석·할 일·용어·프로젝트. 구현은 Data(RemoteTranslationRepository), 테스트는 DomainTesting Fake.
public protocol TranslationRepository: Sendable {
    /// `POST /translations`. `aiConsent`가 참일 때만 서버가 외부 AI를 쓸 수 있다(ADR-0008).
    func translate(_ text: String, direction: TranslationDirection, projectId: Int64?, aiConsent: Bool) async throws -> Translation
    /// `GET /translations` (최신순).
    func translations(projectId: Int64?, page: Int, size: Int) async throws -> Page<TranslationSummary>
    /// `GET /translations/{id}`
    func translation(id: Int64) async throws -> Translation
    /// `DELETE /translations/{id}`
    func deleteTranslation(id: Int64) async throws
    /// `PATCH /translations/{id}/actions/{actionId}`
    func setAction(translationId: Int64, actionId: Int64, isChecked: Bool?, alertEnabled: Bool?) async throws -> ActionItem
    /// `GET /actions`
    func actions(checked: Bool, page: Int, size: Int) async throws -> Page<UpcomingAction>
    /// `GET /terms/{id}`
    func term(id: Int64) async throws -> TermDetail
    /// `GET /projects`
    func projects() async throws -> [ProjectSummary]
}

/// AI 외부 전송 동의(A-09 토글, 기본 꺼짐). v1.0은 기기에만 저장하고 요청 헤더로 보낸다(#25).
/// v1.1에서 `User.aiConsent`로 서버에 올린다.
public protocol AIConsentStore: Sendable {
    func isGranted() async -> Bool
    func setGranted(_ granted: Bool) async
}
