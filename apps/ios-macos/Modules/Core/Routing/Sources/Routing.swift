import Observation

/// Routing 모듈(ADR-0016). 화면 간 계약은 값(`AppRoute`)이고, 경로 상태는 `AppRouter` 하나가 가진다.
/// Feature는 서로를 모르고, 이동은 `AppNavigating`을 통해서만 요청한다.
public enum RoutingModule {
    public static let name = "Routing"
}

/// v1.0 탭. iPad·Mac(v1.3·v1.4)도 같은 값을 사이드바 항목으로 쓴다(ADR-0006).
public enum AppTab: String, CaseIterable, Hashable, Sendable {
    case home
    case settings
}

/// 탭 안에서 push하는 목적지. 화면 하나 = 케이스 하나. 연관값은 id 같은 값만(엔티티를 싣지 않는다).
public enum AppRoute: Hashable, Sendable {
    case compose
    case result(translationId: Int64)
}

/// Feature가 보는 유일한 내비게이션 창구. 테스트에서는 Spy로 바꾼다.
@MainActor
public protocol AppNavigating: AnyObject {
    func select(_ tab: AppTab)
    func push(_ route: AppRoute)
    func pop()
    func popToRoot()
}

/// 탭별 경로를 가진 단일 라우터(D-17 유지, Coordinator 없음).
@MainActor @Observable
public final class AppRouter: AppNavigating {
    public var selectedTab: AppTab
    public private(set) var paths: [AppTab: [AppRoute]]

    public init(selectedTab: AppTab = .home) {
        self.selectedTab = selectedTab
        paths = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, []) })
    }

    /// `NavigationStack(path:)` 바인딩용.
    public func path(for tab: AppTab) -> [AppRoute] {
        paths[tab] ?? []
    }

    public func setPath(_ path: [AppRoute], for tab: AppTab) {
        paths[tab] = path
    }

    public func select(_ tab: AppTab) {
        selectedTab = tab
    }

    public func push(_ route: AppRoute) {
        paths[selectedTab, default: []].append(route)
    }

    public func pop() {
        guard paths[selectedTab]?.isEmpty == false else { return }
        paths[selectedTab]?.removeLast()
    }

    public func popToRoot() {
        paths[selectedTab] = []
    }
}
