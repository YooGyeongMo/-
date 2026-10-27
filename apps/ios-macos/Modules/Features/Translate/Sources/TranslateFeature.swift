import Domain
import FeatureKit
import Foundation
import Observation
import SwiftUI

/// TranslateFeature 모듈(ADR-0016). 다른 Feature를 모르고, 이동은 `AppNavigating`으로만 요청한다.
/// 화면: A-11 프로젝트(해석 기록·할 일), 붙여넣기 시트(W-01의 iPhone 판), A-06 해석 결과, 용어 시트.
public enum TranslateFeatureModule {
    public static let name = "TranslateFeature"
}

/// 화면 모델이 같이 쓰는 의존성. Composition이 실제 구현을 넣는다.
public struct TranslateDependencies: Sendable {
    public let repository: any TranslationRepository
    public let consent: any AIConsentStore

    public init(repository: any TranslationRepository, consent: any AIConsentStore) {
        self.repository = repository
        self.consent = consent
    }
}

// MARK: - 붙여넣기

/// 붙여넣기 시트 화면 모델. 해석 중에 닫거나 다시 누르면 앞 요청을 취소한다(#14 inflight 규칙).
@MainActor @Observable
public final class ComposeViewModel {
    public enum State: Equatable {
        case editing
        case translating
        case failed(FailureReason)
    }

    public enum FailureReason: Equatable {
        case empty
        case tooLong
        case offline
        /// 엔진이 쉬는 중(503). 초는 Retry-After.
        case busy(seconds: Int?)
        case server(message: String?)
    }

    public var text = ""
    public private(set) var state: State = .editing
    private let translate: TranslateUseCase
    private var task: Task<Domain.Translation?, Never>?

    public init(dependencies: TranslateDependencies) {
        translate = TranslateUseCase(repository: dependencies.repository, consent: dependencies.consent)
    }

    public var length: Int {
        TranslateUseCase.length(of: text)
    }

    public var canSubmit: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && length <= TranslateUseCase.maxLength && state != .translating
    }

    /// 해석을 보낸다. 성공하면 결과를, 실패·취소면 nil(실패 이유는 `state`).
    public func submit() async -> Domain.Translation? {
        guard state != .translating else { return nil } // 두 번 누름 → 한 번만(QA M4)
        let text = text
        state = .translating
        let task = Task { [translate] () -> Domain.Translation? in
            do {
                return try await translate(text)
            } catch let error as DomainError {
                await self.fail(error)
                return nil
            } catch is CancellationError {
                return nil // 취소는 cancel() 이 상태를 돌려놓았다
            } catch {
                await self.fail(.unknown)
                return nil
            }
        }
        self.task = task
        let result = await task.value
        if result != nil {
            state = .editing
        }
        return result
    }

    public func cancel() {
        task?.cancel()
        task = nil
        if state == .translating {
            state = .editing
        }
    }

    public func clearError() {
        if case .failed = state {
            state = .editing
        }
    }

    private func fail(_ error: DomainError) {
        switch error {
        case .cancelled:
            break // 취소는 cancel() 이 이미 상태를 돌려놓았다
        case .invalidInput:
            state = .failed(length > TranslateUseCase.maxLength ? .tooLong : .empty)
        case .offline:
            state = .failed(.offline)
        case let .aiUnavailable(seconds, _):
            state = .failed(.busy(seconds: seconds))
        case let .server(_, message):
            state = .failed(.server(message: message))
        default:
            state = .failed(.server(message: nil))
        }
    }
}

// MARK: - 결과

@MainActor @Observable
public final class ResultViewModel {
    public private(set) var translation: Phase<Domain.Translation> = .idle
    public var notice: LocalizedStringKey?
    private let repository: any TranslationRepository
    private let toggleUseCase: ToggleActionUseCase
    let translationId: Int64
    /// 체크가 바뀌면 홈·목록이 다시 불러오도록 알린다.
    var onChange: () -> Void = {}

    public init(translationId: Int64, dependencies: TranslateDependencies, prefetched: Domain.Translation? = nil) {
        self.translationId = translationId
        repository = dependencies.repository
        toggleUseCase = ToggleActionUseCase(repository: dependencies.repository)
        if let prefetched {
            translation = .loaded(prefetched)
        }
    }

    public func load() async {
        if translation.value != nil {
            return
        }
        translation = .loading
        do {
            translation = try await .loaded(repository.translation(id: translationId))
        } catch let error as DomainError {
            translation = .failed(code: error == .notFound ? "NOT_FOUND" : error == .offline ? "OFFLINE" : "UNKNOWN")
        } catch {
            translation = .failed(code: "UNKNOWN")
        }
    }

    public func toggle(_ action: ActionItem) async {
        guard var item = translation.value, let i = item.actions.firstIndex(where: { $0.id == action.id }) else { return }
        item.actions[i].isChecked.toggle()
        translation = .loaded(item)
        do {
            let saved = try await toggleUseCase(translationId: item.id, action: action)
            guard var now = translation.value, let j = now.actions.firstIndex(where: { $0.id == action.id }) else { return }
            now.actions[j] = saved
            translation = .loaded(now)
            onChange()
        } catch {
            guard var now = translation.value, let j = now.actions.firstIndex(where: { $0.id == action.id }) else { return }
            now.actions[j] = action
            translation = .loaded(now)
            notice = "translate.result.toggleFailed"
        }
    }

    public func delete() async -> Bool {
        do {
            try await repository.deleteTranslation(id: translationId)
            onChange()
            return true
        } catch {
            notice = "translate.result.deleteFailed"
            return false
        }
    }
}

// MARK: - 프로젝트(A-11)

@MainActor @Observable
public final class ProjectViewModel {
    public enum Segment: Hashable, CaseIterable {
        case translations, actions, terms
    }

    public var segment: Segment = .translations
    public private(set) var project: ProjectSummary?
    public private(set) var translations: Phase<[TranslationSummary]> = .idle
    public private(set) var translationTotal = 0
    public private(set) var openActions: Phase<[UpcomingAction]> = .idle
    public private(set) var openActionTotal = 0
    private var page = 1
    private var hasMore = false
    private var isLoadingMore = false
    private let repository: any TranslationRepository
    private let toggleUseCase: ToggleActionUseCase
    public var notice: LocalizedStringKey?

    public init(dependencies: TranslateDependencies) {
        repository = dependencies.repository
        toggleUseCase = ToggleActionUseCase(repository: dependencies.repository)
    }

    public func load() async {
        if translations.value == nil {
            translations = .loading
        }
        async let projects = repository.projects()
        async let first = repository.translations(projectId: nil, page: 1, size: 20)
        async let actions = repository.actions(checked: false, page: 1, size: 50)
        do {
            let page = try await first
            translations = .loaded(page.items)
            translationTotal = page.totalElements
            self.page = 1
            hasMore = page.hasMore
        } catch let error as DomainError {
            if error != .cancelled {
                translations = .failed(code: error == .offline ? "OFFLINE" : "UNKNOWN")
            }
        } catch {
            translations = .failed(code: "UNKNOWN")
        }
        if let page = try? await actions {
            openActions = .loaded(page.items)
            openActionTotal = page.totalElements
        } else if openActions.value == nil {
            openActions = .failed(code: "UNKNOWN")
        }
        project = await (try? projects)?.first
    }

    public func loadMoreIfNeeded(current item: TranslationSummary) async {
        guard hasMore, !isLoadingMore, let list = translations.value, item.id == list.last?.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = try await repository.translations(projectId: nil, page: page + 1, size: 20)
            translations = .loaded(list + next.items.filter { newItem in !list.contains { $0.id == newItem.id } })
            page = next.page // 응답이 알려 준 페이지(QA M5)
            hasMore = next.hasMore
        } catch {
            hasMore = false
        }
    }

    public func toggle(_ item: UpcomingAction) async {
        guard var list = openActions.value, let i = list.firstIndex(where: { $0.id == item.id }) else { return }
        list[i].action.isChecked.toggle()
        openActions = .loaded(list)
        do {
            _ = try await toggleUseCase(translationId: item.translationId, action: item.action)
            openActionTotal += item.action.isChecked ? 1 : -1
        } catch {
            guard var now = openActions.value, let j = now.firstIndex(where: { $0.id == item.id }) else { return }
            now[j] = item
            openActions = .loaded(now)
            notice = "translate.result.toggleFailed"
        }
    }
}

/// 카탈로그 문구 + 값(키는 점 표기만 쓴다 → 값은 %lld·%@ 자리표시자로 넣는다, check-xcstrings).
func fmt(_ key: String, _ args: CVarArg...) -> String {
    String(format: String(localized: String.LocalizationValue(key), bundle: .module), arguments: args)
}
