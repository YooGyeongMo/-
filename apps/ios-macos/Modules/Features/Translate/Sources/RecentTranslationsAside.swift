import Domain
import FeatureKit
import MwonmalUI
import Observation
import Routing
import SwiftUI

/// 넓은 화면 붙여넣기 페이지 오른쪽 열: 최근 해석 5개(웹 W-01 "최근 해석"). 누르면 그 결과를 연다.
@MainActor @Observable
final class RecentTranslationsModel {
    private(set) var items: Phase<[TranslationSummary]> = .idle
    private let repository: any TranslationRepository
    static let count = 5

    init(repository: any TranslationRepository) {
        self.repository = repository
    }

    func load() async {
        if items.value == nil {
            items = .loading
        }
        do {
            items = try await .loaded(repository.translations(projectId: nil, page: 1, size: Self.count).items)
        } catch let error as DomainError {
            if error != .cancelled {
                items = .failed(code: error == .offline ? "OFFLINE" : "UNKNOWN")
            }
        } catch {
            items = .failed(code: "UNKNOWN")
        }
    }
}

struct RecentTranslationsAside: View {
    @ViewModelState private var model: RecentTranslationsModel
    @Environment(AppRouter.self) private var router

    init(dependencies: TranslateDependencies) {
        _model = ViewModelState(wrappedValue: RecentTranslationsModel(repository: dependencies.repository))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MwSectionHeader(Text("translate.compose.recent", bundle: .module))
            switch model.items {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            case .failed:
                Text("translate.error.generic", bundle: .module)
                    .mwFont(.regular, 13, lineHeight: 19)
                    .foregroundStyle(MwColor.textSecondary)
            case let .loaded(items) where items.isEmpty:
                Text("translate.compose.recentEmpty", bundle: .module)
                    .mwFont(.regular, 13, lineHeight: 19)
                    .foregroundStyle(MwColor.textSecondary)
            case let .loaded(items):
                ForEach(items) { item in
                    Button {
                        router.present(.result(translationId: item.id))
                    } label: {
                        TranslationCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("recent.\(item.id)")
                }
            }
        }
        .task { await model.load() }
    }
}
