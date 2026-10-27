import Domain
import MwonmalUI
import Routing
import SwiftUI

// 넓은 화면(Mac·iPad 전체화면) 루트 조각들(ADR-0006). 상태는 좁은 화면과 같은 `AppRouter` 하나를 쓴다 —
// 창 크기가 바뀌어 compact ↔ wide가 바뀌어도 탭·경로·시트가 그대로 남는다.

extension AppSheet {
    /// 넓은 화면에서는 시트가 아니라 상세 영역의 한 페이지로 그린다(웹 W-01 붙여넣기, W-03 결과).
    /// 용어·설정은 그대로 모달(Mac은 시트 창).
    var isInlineOnWide: Bool {
        switch self {
        case .compose, .result: true
        case .term, .settings: false
        }
    }
}

public extension FocusedValues {
    /// 메뉴 명령(⌘N, ⌘1~4)이 지금 창의 라우터를 찾는 통로. 로그인 전이면 nil → 메뉴가 꺼진다.
    @Entry var mwRouter: AppRouter?
}

/// Mac 메뉴 막대 명령(ADR-0006: Mac·iPad 같은 키). ⌘↩ 해석·Esc 닫기는 각 버튼의 `keyboardShortcut`이 맡는다.
public struct MwonmalCommands: Commands {
    @FocusedValue(\.mwRouter) private var router

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button {
                router?.present(.compose)
            } label: {
                Text("menu.newDecode", bundle: .module)
            }
            .keyboardShortcut("n")
            .disabled(router == nil)
        }
        CommandMenu(Text("menu.go", bundle: .module)) {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button {
                    router?.dismissSheet()
                    router?.select(tab)
                } label: {
                    Text(WideSidebar.titleKey(tab), bundle: .module)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                .disabled(router == nil)
            }
        }
    }
}

/// 사이드바(웹 W-00~W-08 왼쪽 열을 macOS 기본 사이드바로): 서비스 이름 → 판교어 해석 → 탭 4개 → 아래 사용자 카드.
/// 모양은 시스템 사이드바(반투명·선택 강조·키보드 이동)를 그대로 쓰고 아이콘·글자만 우리 것.
struct WideSidebar: View {
    @Binding var selection: AppTab
    let user: UserProfile?
    let onCompose: () -> Void

    var body: some View {
        List(selection: Binding<AppTab?>(get: { selection }, set: {
            if let tab = $0 {
                selection = tab
            }
        })) {
            Section {
                Button(action: onCompose) {
                    Label {
                        Text("sidebar.decode", bundle: .module).mwFont(.semiBold, 15)
                    } icon: {
                        MwIconView(.sparkles, color: MwColor.accentFill)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.decode")
            }
            Section {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Label {
                        Text(Self.titleKey(tab), bundle: .module).mwFont(.medium, 15)
                    } icon: {
                        MwIconView(Self.icon(tab), color: selection == tab ? MwColor.accentFill : MwColor.textSecondary)
                    }
                    .tag(tab)
                    .accessibilityIdentifier("sidebar.\(tab.rawValue)")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) { brand }
        .safeAreaInset(edge: .bottom) { userCard }
    }

    private var brand: some View {
        HStack(spacing: 8) {
            Text("sidebar.brand", bundle: .module).mwFont(.bold, 18)
                .foregroundStyle(MwColor.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var userCard: some View {
        if let user {
            HStack(spacing: 10) {
                MwProfileAvatar().environment(\.mwScale, 36 / 64) // 64pt 그림을 36pt로
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: user.nickname).mwFont(.semiBold, 14).foregroundStyle(MwColor.textPrimary).lineLimit(1)
                    Text(verbatim: user.email ?? "").mwFont(.regular, 12).foregroundStyle(MwColor.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .circular).fill(MwColor.surface))
            .padding(12)
            .accessibilityElement(children: .combine)
        }
    }

    static func titleKey(_ tab: AppTab) -> LocalizedStringKey {
        switch tab {
        case .home: "tab.home"
        case .project: "tab.project"
        case .review: "tab.review"
        case .my: "tab.my"
        }
    }

    static func icon(_ tab: AppTab) -> MwIcon {
        switch tab {
        case .home: .tabHome
        case .project: .tabProject
        case .review: .tabReview
        case .my: .tabMy
        }
    }
}
