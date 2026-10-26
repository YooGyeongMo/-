import AuthFeature
import Domain
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

/// 세션 상태에 따라 로그인 화면과 탭 루트를 고른다. 화면 자체는 Day 5(#9)에서 S-01로 교체.
public struct SessionRootView: View {
    @State private var session: AppSession

    public init(session: AppSession = .live()) {
        _session = State(initialValue: session)
    }

    public var body: some View {
        Group {
            switch session.state {
            case .none:
                ProgressView()
            case .signedOut:
                AuthRootView(isSigningIn: session.isSigningIn, errorMessage: session.lastError?.userMessage) { outcome in
                    switch outcome {
                    case let .code(code): session.signIn(withAppleCode: code)
                    case .cancelled: break
                    case .failed: session.appleSignInFailed()
                    }
                }
            case .signedIn, .unverified:
                AppRootView()
            }
        }
        .task { await session.start().value }
    }
}

extension DomainError {
    /// 서버가 준 사용자용 문구. 없으면 nil이고 화면이 기본 문구(String Catalog)를 쓴다.
    var userMessage: String? {
        switch self {
        case let .signInFailed(message), let .emailAlreadyRegistered(message): message
        case let .server(_, message): message
        default: nil
        }
    }
}
