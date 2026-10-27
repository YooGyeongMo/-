import DomainTesting
import MwonmalUI
import Routing
import SwiftUI
import TranslateFeature

/// 로그인·서버 없이 해석 흐름만 띄우는 예제 앱(ADR-0016). Fake는 DomainTesting에서 가져온다.
@main
struct TranslateExampleApp: App {
    @State private var router = AppRouter(selectedTab: .project)
    private let dependencies = TranslateDependencies(repository: FakeTranslationRepository(), consent: InMemoryAIConsentStore())

    var body: some Scene {
        WindowGroup {
            ProjectRootView(dependencies: dependencies)
                .sheet(item: $router.sheet) { sheet in
                    switch sheet {
                    case .compose:
                        ComposeSheet(dependencies: dependencies, aiConsent: false) { router.present(.result(translationId: $0.id)) }
                    case let .result(id):
                        ResultSheet(translationId: id, dependencies: dependencies)
                    default:
                        EmptyView()
                    }
                }
                .environment(router)
                .mwScaledToWidth()
        }
    }
}
