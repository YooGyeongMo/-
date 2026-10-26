import AuthFeature
import HomeFeature
import Routing
import SettingsFeature
import SwiftUI
import TranslateFeature

/// Composition 모듈. 구현체 주입과 목적지 해석을 하는 유일한 곳(ADR-0016).
public enum CompositionModule {
    public static let name = "Composition"
}

/// `AppRoute` → 화면. Feature들이 서로를 모르는 대신 여기서 한 번에 잇는다.
@MainActor
enum RouteDestination {
    @ViewBuilder
    static func view(for route: AppRoute) -> some View {
        switch route {
        case .compose, .result:
            TranslateRootView()
        }
    }

    @ViewBuilder
    static func root(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeRootView()
        case .settings: SettingsRootView()
        }
    }
}

/// 앱 루트. v1.0은 iPhone(compact) 탭 구조만. wide(iPad·Mac)는 v1.3·v1.4에서 AdaptiveRoot로(ADR-0006).
public struct AppRootView: View {
    @State private var router = AppRouter()

    public init() {}

    public var body: some View {
        TabView(selection: $router.selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                NavigationStack(path: binding(for: tab)) {
                    RouteDestination.root(for: tab)
                        .navigationDestination(for: AppRoute.self) { RouteDestination.view(for: $0) }
                }
                .tag(tab)
                .tabItem { Label { Text(tab.titleKey, bundle: .module) } icon: { Image(systemName: tab.symbol) } }
            }
        }
    }

    private func binding(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(get: { router.path(for: tab) }, set: { router.setPath($0, for: tab) })
    }
}

extension AppTab {
    var titleKey: LocalizedStringKey {
        switch self {
        case .home: "tab.home"
        case .settings: "tab.settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .settings: "gearshape"
        }
    }
}

/// 로그인 전 화면 미리보기용.
public struct SignedOutRootView: View {
    public init() {}
    public var body: some View {
        AuthRootView()
    }
}
