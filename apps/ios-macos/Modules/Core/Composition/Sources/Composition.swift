import AuthFeature
import Domain
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

/// 앱 루트(로그인 뒤). v1.0은 iPhone 탭 구조(Figma 플로팅 탭 바: 홈·프로젝트·복습·MY).
/// wide(iPad·Mac)는 v1.3·v1.4에서 AdaptiveRoot로(ADR-0006).
struct AppRootView: View {
    let session: AppSession
    @State private var router = AppRouter()
    @State private var toast: LocalizedStringKey?
    @State private var toastTask: Task<Void, Never>?
    @State private var aiConsent = false
    /// 방금 해석한 결과는 다시 받지 않고 바로 보여 준다.
    @State private var prefetched: Domain.Translation?
    @Environment(\.mwScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bottomInset: CGFloat = 0

    private var translate: TranslateDependencies {
        TranslateDependencies(repository: session.translations, consent: session.consent)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $router.selectedTab) {
                ForEach(AppTab.allCases, id: \.self) { tab in
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
                    .tag(tab)
                    #if os(iOS)
                        .toolbar(.hidden, for: .tabBar)
                    #endif
                }
            }
            MwTabBar(items: tabItems, selection: $router.selectedTab)
                // Figma: 탭 바 아래 끝 = 화면(기기) 아래 끝에서 26. 안전 영역(홈 인디케이터 34)을 빼고 내린다.
                .offset(y: bottomInset - 26 * scale)
            if let toast, router.sheet == nil {
                MwToast(Text(toast, bundle: .module))
                    .padding(.bottom, 110 * scale)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("toast")
            }
        }
        .ignoresSafeArea(.keyboard)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .environment(router)
        .sheet(item: Binding(get: { router.sheet }, set: { router.sheet = $0 }), onDismiss: { prefetched = nil }, content: { sheet in
            sheetContent(sheet)
                .sheet(item: Binding(get: { router.sheetOverSheet }, set: { router.sheetOverSheet = $0 })) { over in
                    sheetContent(over).presentationDetents([.medium, .large])
                }
        })
        .task { aiConsent = await session.consent.isGranted() }
        .onChange(of: router.sheet) { _, _ in Task { aiConsent = await session.consent.isGranted() } }
        .onChange(of: router.dataVersion) { _, _ in Task { await session.reloadProfile() } }
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
        .presentationCornerRadius(32 * scale)
        .presentationDragIndicator(.hidden)
        .overlay(alignment: .bottom) {
            if let toast {
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

/// 세션 상태에 따라 로그인 화면과 탭 루트를 고른다.
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
                AuthRootView(isSigningIn: session.isSigningIn, errorMessage: session.lastError.flatMap(\.userMessage)) {
                    session.signInWithApple()
                }
            case .signedIn, .unverified:
                AppRootView(session: session)
            }
        }
        .mwScaledToWidth()
        .task { await session.start().value }
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
