import AuthFeature
import Domain
import FeatureKit
import HomeFeature
import MwonmalUI
import Routing
import SettingsFeature
import SwiftUI
import TranslateFeature

/// Composition 모듈. 구현체 주입과 목적지 해석을 하는 유일한 곳(ADR-0016).
public enum CompositionModule {
    public static let name = "Composition"
}

/// 앱 루트(로그인 뒤). 좁은 화면 = iPhone 탭 구조(Figma 플로팅 탭 바: 홈·프로젝트·복습·MY),
/// 넓은 화면(Mac·iPad 전체화면) = 사이드바 + 상세(ADR-0006). 상태(라우터·토스트·동의)는 하나다.
struct AppRootView: View {
    let session: AppSession
    /// `@State var router = AppRouter()`는 이 뷰가 다시 만들어질 때마다 라우터를 새로 만들고 버린다 → 한 번만.
    @ViewModelState private var router = AppRouter()
    @State private var toast: LocalizedStringKey?
    @State private var toastTask: Task<Void, Never>?
    @State private var aiConsent = false
    /// 방금 해석한 결과는 다시 받지 않고 바로 보여 준다.
    @State private var prefetched: Domain.Translation?
    @Environment(\.mwScale) private var scale
    @Environment(\.mwLayout) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bottomInset: CGFloat = 0

    private var translate: TranslateDependencies {
        TranslateDependencies(repository: session.translations, consent: session.consent)
    }

    var body: some View {
        Group {
            if layout == .wide {
                wideRoot
            } else {
                compactRoot
            }
        }
        .environment(router)
        .focusedSceneValue(\.mwRouter, router)
        .sheet(item: modalSheet, onDismiss: {
            if layout == .compact {
                prefetched = nil
            }
        }, content: { sheet in
            if layout == .compact {
                sheetContent(sheet)
                    .sheet(item: Binding(get: { router.sheetOverSheet }, set: { router.sheetOverSheet = $0 })) { over in
                        sheetContent(over).presentationDetents([.medium, .large])
                    }
            } else {
                sheetContent(sheet).frame(minWidth: 480, idealWidth: 560, minHeight: 560, idealHeight: 720)
            }
        })
        .task { aiConsent = await session.consent.isGranted() }
        .onChange(of: router.sheet) { _, sheet in
            if sheet == nil, layout == .wide {
                prefetched = nil
            }
            Task { aiConsent = await session.consent.isGranted() }
        }
        // 설정은 붙여넣기 위에 겹쳐 뜬다 → 닫힐 때도 동의를 다시 읽는다(QA 2차 R1).
        .onChange(of: router.sheetOverSheet) { _, _ in Task { aiConsent = await session.consent.isGranted() } }
        .onChange(of: router.dataVersion) { _, _ in Task { await session.reloadProfile() } }
    }

    /// 모달로 띄울 시트. 좁은 화면은 라우터의 시트 그대로, 넓은 화면은 붙여넣기·결과를 상세 영역에 그리므로
    /// 그 위에 겹친 것(용어·설정)이나 처음부터 모달인 것만.
    private var modalSheet: Binding<AppSheet?> {
        Binding(
            get: {
                guard layout == .wide else { return router.sheet }
                if let over = router.sheetOverSheet {
                    return over
                }
                return router.sheet.flatMap { $0.isInlineOnWide ? nil : $0 }
            },
            set: { new in
                guard new == nil else { return }
                if layout == .wide, router.sheetOverSheet != nil {
                    router.sheetOverSheet = nil
                } else {
                    router.sheet = nil
                }
            }
        )
    }

    private var compactRoot: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: Binding(get: { router.selectedTab }, set: { router.selectedTab = $0 })) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    stack(for: tab)
                        .tag(tab)
                    #if os(iOS)
                        .toolbar(.hidden, for: .tabBar)
                    #endif
                }
            }
            MwTabBar(items: tabItems, selection: Binding(get: { router.selectedTab }, set: { router.selectedTab = $0 }))
                // Figma: 탭 바 아래 끝 = 화면(기기) 아래 끝에서 26. 안전 영역(홈 인디케이터 34)을 빼고 내린다.
                .offset(y: bottomInset - 26 * scale)
            if let toast, router.sheet == nil {
                toastView(toast).padding(.bottom, 110 * scale)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { inset in
            // 홈 인디케이터(0~34)만 쓴다. 키보드가 올라와 커진 값은 무시한다(QA 2차 R2: 탭 바가 밀리지 않게).
            if inset <= 60 {
                bottomInset = inset
            }
        }
    }

    /// 넓은 화면: 사이드바(시스템) + 상세. 붙여넣기·결과는 상세 영역의 페이지(웹 W-01·W-03).
    private var wideRoot: some View {
        NavigationSplitView {
            WideSidebar(
                selection: Binding(get: { router.selectedTab }, set: { tab in
                    router.sheet = nil // 다른 탭을 고르면 열려 있던 붙여넣기·결과 페이지를 닫는다
                    router.select(tab)
                }),
                user: session.user,
                onCompose: { router.present(.compose) }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 300)
        } detail: {
            ZStack(alignment: .bottom) {
                if let sheet = router.sheet, sheet.isInlineOnWide {
                    sheetContent(sheet).id(sheet.id)
                } else {
                    stack(for: router.selectedTab).id(router.selectedTab)
                }
                if let toast, router.sheetOverSheet == nil {
                    toastView(toast).padding(.bottom, 32)
                }
            }
            .background(MwColor.canvas.ignoresSafeArea())
        }
    }

    private func stack(for tab: AppTab) -> some View {
        NavigationStack(path: binding(for: tab)) {
            root(for: tab)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case let .result(id):
                        ResultSheet(translationId: id, dependencies: translate, onChange: router.dataChanged, onNotice: show)
                    }
                }
            #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }

    private func toastView(_ key: LocalizedStringKey) -> some View {
        MwToast(Text(key, bundle: .module))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityIdentifier("toast")
    }

    @ViewBuilder private func root(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeRootView(
                model: HomeViewModel(repository: session.translations),
                user: session.user,
                refreshKey: router.dataVersion,
                onNotice: show
            )
        case .project:
            ProjectRootView(dependencies: translate, refreshKey: router.dataVersion, onNotice: show)
        case .review:
            ReviewComingSoonView()
        case .my:
            MyRootView(
                dependencies: SettingsDependencies(repository: session.translations, consent: session.consent),
                user: session.user,
                refreshKey: router.dataVersion,
                onNotice: show
            )
        }
    }

    private func sheetContent(_ sheet: AppSheet) -> some View {
        Group {
            switch sheet {
            case .compose:
                ComposeSheet(dependencies: translate, aiConsent: aiConsent, onResult: { result in
                    prefetched = result
                    router.dataChanged()
                    router.present(.result(translationId: result.id))
                }, onNotice: show)
            case let .result(id):
                ResultSheet(
                    translationId: id,
                    dependencies: translate,
                    prefetched: prefetched?.id == id ? prefetched : nil,
                    onChange: router.dataChanged,
                    onNotice: show
                )
            case let .term(id):
                TermSheet(termId: id, repository: session.translations, onNotice: show)
            case .settings:
                SettingsSheet(consent: session.consent, nickname: session.user?.nickname, email: session.user?.email) {
                    router.reset()
                    session.signOut()
                }
            }
        }
        .environment(router)
        .environment(\.mwScale, scale)
        .environment(\.mwLayout, sheet.isInlineOnWide ? layout : .compact) // 모달 안은 늘 시트 모양
        .presentationCornerRadius(32 * scale)
        .presentationDragIndicator(.hidden)
        .overlay(alignment: .bottom) {
            if let toast, !(layout == .wide && sheet.isInlineOnWide) {
                MwToast(Text(toast, bundle: .module)).padding(.bottom, 24 * scale).allowsHitTesting(false)
            }
        }
    }

    private var tabItems: [MwTabBar<AppTab>.Item] {
        [
            .init(tab: .home, icon: .tabHome, title: Text("tab.home", bundle: .module)),
            .init(tab: .project, icon: .tabProject, title: Text("tab.project", bundle: .module)),
            .init(tab: .review, icon: .tabReview, title: Text("tab.review", bundle: .module)),
            .init(tab: .my, icon: .tabMy, title: Text("tab.my", bundle: .module)),
        ]
    }

    private func binding(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(get: { router.path(for: tab) }, set: { router.setPath($0, for: tab) })
    }

    /// 아래 안내(2.5초). 다음 업데이트 기능·실패 안내에 쓴다. 키는 기능 모듈 카탈로그와 같은 것을
    /// Composition 카탈로그에도 둔다(여기서 그리므로).
    private func show(_ key: LocalizedStringKey) {
        toastTask?.cancel()
        withAnimation(MwMotion.toast(reduceMotion: reduceMotion)) { toast = key }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(MwMotion.toast(reduceMotion: reduceMotion)) { toast = nil }
        }
    }
}

/// 복습 탭(v1.1). Figma 탭은 두고 화면은 안내.
struct ReviewComingSoonView: View {
    @Environment(\.mwScale) private var scale

    var body: some View {
        ZStack {
            MwSceneBackground(.sky)
            VStack(spacing: 12 * scale) {
                MwIconView(.tabReview, color: MwColor.accentFill).scaleEffect(1.6)
                Text("review.comingSoon.title", bundle: .module)
                    .mwFont(.bold, 22, lineHeight: 31, tracking: -0.33)
                    .foregroundStyle(MwColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("review.comingSoon.body", bundle: .module)
                    .mwFont(.regular, 15, lineHeight: 22)
                    .foregroundStyle(MwColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24 * scale)
        }
    }
}

extension DomainError {
    /// 로그인 화면에 보일 문구. 서버 문구가 있으면 그것, 세션 만료면 안내, 나머지는 nil(화면 기본 문구).
    var userMessage: String? {
        switch self {
        case let .signInFailed(message), let .emailAlreadyRegistered(message): message
        case let .server(_, message): message
        case .unauthorized: String(localized: "session.expired", bundle: .module)
        default: nil
        }
    }
}
