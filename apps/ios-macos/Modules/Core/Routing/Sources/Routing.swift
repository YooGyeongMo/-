import Observation

/// Routing 모듈(ADR-0016). 화면 간 계약은 값(`AppRoute`·`AppSheet`)이고, 상태는 `AppRouter` 하나가 가진다.
/// Feature는 서로를 모르고, 이동은 `AppNavigating`을 통해서만 요청한다.
public enum RoutingModule {
    public static let name = "Routing"
}

/// 아래 탭(Figma A-01 플로팅 탭 바: 홈·프로젝트·복습·MY). iPad·Mac(v1.3·v1.4)도 같은 값을 사이드바 항목으로 쓴다.
public enum AppTab: String, CaseIterable, Hashable, Sendable {
    case home
    case project
    /// 복습은 v1.1. 탭은 Figma대로 두고 화면은 "다음 업데이트" 안내.
    case review
    case my
}

/// 탭 안에서 push하는 목적지. 화면 하나 = 케이스 하나. 연관값은 id 같은 값만(엔티티를 싣지 않는다).
public enum AppRoute: Hashable, Sendable {
    case result(translationId: Int64)
}

/// 아래에서 올라오는 시트(Figma A-06 해석 결과는 시트, 붙여넣기 시트는 모달).
public enum AppSheet: Hashable, Sendable, Identifiable {
    case compose
    case result(translationId: Int64)
    case term(termId: Int64)
    case settings

    public var id: String {
        switch self {
        case .compose: "compose"
        case let .result(id): "result-\(id)"
        case let .term(id): "term-\(id)"
        case .settings: "settings"
        }
    }
}

/// Feature가 보는 유일한 내비게이션 창구. 테스트에서는 Spy로 바꾼다.
@MainActor
public protocol AppNavigating: AnyObject {
    func select(_ tab: AppTab)
    func push(_ route: AppRoute)
    func pop()
    func popToRoot()
    func present(_ sheet: AppSheet)
    func dismissSheet()
}

/// 탭별 경로 + 시트 하나를 가진 단일 라우터(D-17 유지, Coordinator 없음).
@MainActor @Observable
public final class AppRouter: AppNavigating {
    public var selectedTab: AppTab
    public private(set) var paths: [AppTab: [AppRoute]]
    /// 지금 떠 있는 시트. 시트 위 시트(용어)는 `sheetOverSheet`.
    public var sheet: AppSheet?
    public var sheetOverSheet: AppSheet?
    /// 화면들이 "다시 불러와" 신호로 본다(해석·체크·삭제 뒤 홈·목록 갱신).
    public private(set) var dataVersion = 0

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

    /// 시트가 이미 떠 있으면 용어·설정 시트는 그 위에(아래 시트의 입력을 잃지 않게), 나머지는 바꿔 띄운다
    /// (붙여넣기 → 결과).
    public func present(_ sheet: AppSheet) {
        let stacks: Bool = switch sheet {
        case .term, .settings: self.sheet != nil
        default: false
        }
        if stacks {
            sheetOverSheet = sheet
            return
        }
        sheetOverSheet = nil
        self.sheet = sheet
    }

    public func dismissSheet() {
        if sheetOverSheet != nil {
            sheetOverSheet = nil
        } else {
            sheet = nil
        }
    }

    /// 데이터가 바뀌었다고 알린다.
    public func dataChanged() {
        dataVersion &+= 1
    }

    /// 로그아웃 등: 경로·시트를 모두 비운다.
    public func reset() {
        sheet = nil
        sheetOverSheet = nil
        selectedTab = .home
        paths = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, []) })
    }
}
