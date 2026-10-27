import Domain
import Foundation
import MwonmalAPI

/// `TranslationRepository` 서버 구현(계약 v1.0 createTranslation 외 7개).
/// DTO는 여기서 Domain 값으로 바뀌고 밖으로 나가지 않는다. 필수 값이 빠진 응답은 INVALID_RESPONSE.
public struct RemoteTranslationRepository: TranslationRepository {
    private let client: Client

    public init(client: Client) {
        self.client = client
    }

    public func translate(_ text: String, direction: TranslationDirection, projectId: Int64?, aiConsent: Bool) async throws -> Translation {
        do {
            let request = Components.Schemas.TranslationRequest(projectId: projectId, sourceText: text, direction: Self.direction(direction))
            let output = try await AIConsent.$granted.withValue(aiConsent) {
                try await client.createTranslation(body: .json(request))
            }
            return try Self.translation(output.created.body.json)
        } catch {
            throw DomainErrorMapping.map(error)
        }
    }

    public func translations(projectId: Int64?, page: Int, size: Int) async throws -> Page<TranslationSummary> {
        do {
            let body = try await client.getTranslations(query: .init(projectId: projectId, page: page, size: size)).ok.body.json
            let items = try (body.value2.content ?? []).map(Self.summary)
            return Self.page(items, body.value1)
        } catch {
            throw DomainErrorMapping.map(error)
        }
    }

    public func translation(id: Int64) async throws -> Translation {
        do {
            return try await Self.translation(client.getTranslation(path: .init(translationId: id)).ok.body.json)
        } catch {
            throw DomainErrorMapping.map(error)
        }
    }

    public func deleteTranslation(id: Int64) async throws {
        do {
            _ = try await client.deleteTranslation(path: .init(translationId: id)).noContent
        } catch {
            throw DomainErrorMapping.map(error)
        }
    }

    public func setAction(translationId: Int64, actionId: Int64, isChecked: Bool?, alertEnabled: Bool?) async throws -> ActionItem {
        do {
            let output = try await client.updateAction(
                path: .init(translationId: translationId, actionId: actionId),
                body: .json(.init(isChecked: isChecked, alertEnabled: alertEnabled))
            )
            return try Self.action(output.ok.body.json)
        } catch {
            throw DomainErrorMapping.map(error)
        }
    }

    public func actions(checked: Bool, page: Int, size: Int) async throws -> Page<UpcomingAction> {
        do {
            let body = try await client.getActions(query: .init(checked: checked, page: page, size: size)).ok.body.json
            let items = try (body.value2.content ?? []).map(Self.upcoming)
            return Self.page(items, body.value1)
        } catch {
            throw DomainErrorMapping.map(error)
        }
    }

    public func term(id: Int64) async throws -> TermDetail {
        do {
            let body = try await client.getTerm(path: .init(termId: id)).ok.body.json
            guard let termId = body.value1.termId, let ko = body.value1.termKo else { throw Self.invalid }
            return TermDetail(
                id: termId,
                termKo: ko,
                originEn: body.value1.originEn.flatMap { $0.isEmpty ? nil : $0 },
                plainKo: body.value1.plainKo ?? "",
                meaning: body.value2.meaning ?? "",
                examples: (body.value2.examples ?? []).compactMap { e in
                    guard let jargon = e.sentenceJargon, let plain = e.sentencePlain else { return nil }
                    return TermExample(jargon: jargon, plain: plain)
                }
            )
        } catch {
            throw DomainErrorMapping.map(error)
        }
    }

    public func projects() async throws -> [ProjectSummary] {
        do {
            let body = try await client.getProjects(query: .init(page: 1, size: 100)).ok.body.json
            return (body.value2.content ?? []).compactMap { p in
                guard let id = p.projectId, let name = p.name else { return nil }
                return ProjectSummary(
                    id: id, name: name, description: p.description ?? "",
                    translationCount: p.translationCount ?? 0, openActionCount: p.openActionCount ?? 0,
                    meetingCount: p.meetingCount ?? 0, unknownTermCount: p.unknownTermCount ?? 0,
                    isDefault: p.isDefault ?? false
                )
            }
        } catch {
            throw DomainErrorMapping.map(error)
        }
    }

    // MARK: - DTO → Domain

    static let invalid = DomainError.server(code: "INVALID_RESPONSE", message: nil)

    static func direction(_ d: TranslationDirection) -> Components.Schemas.TranslationDirection {
        switch d {
        case .jargonToPlain: .jargonToPlain
        case .plainToJargon: .plainToJargon
        }
    }

    static func inputSource(_ s: Components.Schemas.InputSource?) -> InputSource {
        switch s {
        case .screenshot: .screenshot
        case .recording: .recording
        case ._extension: .extension
        case .typed, nil: .typed
        }
    }

    static func intent(_ i: Components.Schemas.IntentType?) -> IntentType? {
        i.flatMap { IntentType(rawValue: $0.rawValue) }
    }

    static func page<T>(_ items: [T], _ meta: Components.Schemas.PagedResponse) -> Page<T> {
        Page(items: items, page: meta.page, totalElements: meta.totalElements, totalPages: meta.totalPages)
    }

    static func action(_ a: Components.Schemas.ActionItem) throws -> ActionItem {
        guard let id = a.actionId, let text = a.actionText else { throw invalid }
        return ActionItem(
            id: id, sortOrder: a.sortOrder ?? 0, text: text, dueHint: a.dueHint, dueAt: a.dueAt,
            isChecked: a.isChecked ?? false, alertEnabled: a.alertEnabled ?? true
        )
    }

    static func translation(_ t: Components.Schemas.TranslationResponse) throws -> Translation {
        guard let id = t.translationId, let source = t.sourceText, let result = t.resultText else { throw invalid }
        let nuance = t.nuance.flatMap { payload -> Nuance? in
            guard let note = payload.value1.note, !note.isEmpty else { return nil }
            return Nuance(note: note, tip: payload.value1.tip ?? "", confidence: Double(payload.value1.confidence ?? 0))
        }
        let terms: [DetectedTerm] = (t.detectedTerms ?? []).compactMap { d in
            guard let start = d.startIndex, let end = d.endIndex, let matched = d.matchedText else { return nil }
            return DetectedTerm(
                termId: d.termId, termKo: d.termKo ?? matched, plainKo: d.plainKo ?? "", matchedText: matched,
                startIndex: start, endIndex: end, inMyCards: d.inMyCards ?? false
            )
        }
        return try Translation(
            id: id,
            projectId: t.projectId ?? 0,
            projectName: t.projectName ?? "",
            meetingTitle: t.meetingTitle,
            inputSource: inputSource(t.inputSource),
            sourceText: source,
            resultText: result,
            jargonCount: t.jargonCount ?? terms.count,
            intent: intent(t.intentType?.value1),
            nuance: nuance,
            actions: (t.actionItems ?? []).map(action).sorted { $0.sortOrder < $1.sortOrder },
            terms: terms,
            aiModel: t.aiModel ?? "",
            createdAt: t.createdAt ?? Date()
        )
    }

    static func summary(_ s: Components.Schemas.TranslationSummary) throws -> TranslationSummary {
        guard let id = s.translationId else { throw invalid }
        return TranslationSummary(
            id: id,
            title: s.title ?? String((s.sourceText ?? "").prefix(24)),
            inputSource: inputSource(s.inputSource),
            sourceText: s.sourceText ?? "",
            resultText: s.resultText ?? "",
            jargonCount: s.jargonCount ?? 0,
            intent: intent(s.intentType?.value1),
            actionCount: s.actionCount ?? 0,
            openActionCount: s.openActionCount ?? 0,
            createdAt: s.createdAt ?? Date()
        )
    }

    static func upcoming(_ a: Components.Schemas.ActionWithSource) throws -> UpcomingAction {
        guard let translationId = a.value2.translationId else { throw invalid }
        return try UpcomingAction(
            action: action(a.value1),
            translationId: translationId,
            projectName: a.value2.projectName ?? "",
            meetingTitle: a.value2.meetingTitle,
            inputSource: nil,
            createdAt: a.value2.createdAt ?? Date()
        )
    }
}
