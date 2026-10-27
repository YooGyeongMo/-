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
            let request = Components.Schemas.TranslationRequest(
                projectId: projectId,
                sourceText: text,
                direction: Self.direction(direction)
            )
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
            guard let termId = body.value1.termId, let termName = body.value1.termKo else { throw Self.invalid }
            return TermDetail(
                id: termId,
                termKo: termName,
                originEn: body.value1.originEn.flatMap { $0.isEmpty ? nil : $0 },
                plainKo: body.value1.plainKo ?? "",
                meaning: body.value2.meaning ?? "",
                examples: (body.value2.examples ?? []).compactMap { example in
                    guard let jargon = example.sentenceJargon, let plain = example.sentencePlain else { return nil }
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
            return (body.value2.content ?? []).compactMap { proj in
                guard let id = proj.projectId, let name = proj.name else { return nil }
                return ProjectSummary(
                    id: id, name: name, description: proj.description ?? "",
                    translationCount: proj.translationCount ?? 0, openActionCount: proj.openActionCount ?? 0,
                    meetingCount: proj.meetingCount ?? 0, unknownTermCount: proj.unknownTermCount ?? 0,
                    isDefault: proj.isDefault ?? false
                )
            }
        } catch {
            throw DomainErrorMapping.map(error)
        }
    }

    // MARK: - DTO → Domain

    static let invalid = DomainError.server(code: "INVALID_RESPONSE", message: nil)

    static func direction(_ dto: TranslationDirection) -> Components.Schemas.TranslationDirection {
        switch dto {
        case .jargonToPlain: .jargonToPlain
        case .plainToJargon: .plainToJargon
        }
    }

    static func inputSource(_ src: Components.Schemas.InputSource?) -> InputSource {
        switch src {
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

    static func action(_ raw: Components.Schemas.ActionItem) throws -> ActionItem {
        guard let id = raw.actionId, let text = raw.actionText else { throw invalid }
        return ActionItem(
            id: id, sortOrder: raw.sortOrder ?? 0, text: text, dueHint: raw.dueHint, dueAt: raw.dueAt,
            isChecked: raw.isChecked ?? false, alertEnabled: raw.alertEnabled ?? true
        )
    }

    static func translation(_ dto: Components.Schemas.TranslationResponse) throws -> Translation {
        guard let id = dto.translationId, let source = dto.sourceText, let result = dto.resultText else { throw invalid }
        let nuance = dto.nuance.flatMap { payload -> Nuance? in
            guard let note = payload.value1.note, !note.isEmpty else { return nil }
            return Nuance(note: note, tip: payload.value1.tip ?? "", confidence: Double(payload.value1.confidence ?? 0))
        }
        let terms: [DetectedTerm] = (dto.detectedTerms ?? []).compactMap { dto in
            guard let start = dto.startIndex, let end = dto.endIndex, let matched = dto.matchedText else { return nil }
            return DetectedTerm(
                termId: dto.termId, termKo: dto.termKo ?? matched, plainKo: dto.plainKo ?? "", matchedText: matched,
                startIndex: start, endIndex: end, inMyCards: dto.inMyCards ?? false,
                confidence: min(max(Double(dto.confidence ?? 1), 0), 1)
            )
        }
        return try Translation(
            id: id,
            projectId: dto.projectId ?? 0,
            projectName: dto.projectName ?? "",
            meetingTitle: dto.meetingTitle,
            inputSource: inputSource(dto.inputSource),
            sourceText: source,
            resultText: result,
            jargonCount: dto.jargonCount ?? terms.count,
            intent: intent(dto.intentType?.value1),
            nuance: nuance,
            actions: (dto.actionItems ?? []).map(action).sorted { $0.sortOrder < $1.sortOrder },
            terms: terms,
            aiModel: dto.aiModel ?? "",
            createdAt: dto.createdAt ?? Date()
        )
    }

    static func summary(_ src: Components.Schemas.TranslationSummary) throws -> TranslationSummary {
        guard let id = src.translationId else { throw invalid }
        return TranslationSummary(
            id: id,
            title: src.title ?? String((src.sourceText ?? "").prefix(24)),
            inputSource: inputSource(src.inputSource),
            sourceText: src.sourceText ?? "",
            resultText: src.resultText ?? "",
            jargonCount: src.jargonCount ?? 0,
            intent: intent(src.intentType?.value1),
            actionCount: src.actionCount ?? 0,
            openActionCount: src.openActionCount ?? 0,
            createdAt: src.createdAt ?? Date()
        )
    }

    static func upcoming(_ raw: Components.Schemas.ActionWithSource) throws -> UpcomingAction {
        guard let translationId = raw.value2.translationId else { throw invalid }
        return try UpcomingAction(
            action: action(raw.value1),
            translationId: translationId,
            projectName: raw.value2.projectName ?? "",
            meetingTitle: raw.value2.meetingTitle,
            inputSource: nil,
            createdAt: raw.value2.createdAt ?? Date()
        )
    }
}
