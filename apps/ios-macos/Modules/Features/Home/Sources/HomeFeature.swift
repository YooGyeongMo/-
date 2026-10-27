import Domain
import FeatureKit
import MwonmalUI
import Observation
import Routing
import SwiftUI

/// HomeFeature 모듈(ADR-0016). 다른 Feature를 모르고, 이동은 `AppNavigating`으로만 요청한다.
public enum HomeFeatureModule {
    public static let name = "HomeFeature"
}

// MARK: - 화면 모델

/// A-01 홈 화면 모델: 다가오는 할 일(GET /actions, 안 끝낸 것) + 현재 프로젝트 이름.
@MainActor @Observable
public final class HomeViewModel {
    public private(set) var actions: Phase<[UpcomingAction]> = .idle
    public private(set) var totalOpen = 0
    public private(set) var projectName: String?
    /// 체크했다가 실패해 되돌린 경우 등 짧은 안내.
    public var notice: LocalizedStringKey?

    private let repository: any TranslationRepository
    private let toggleUseCase: ToggleActionUseCase
    static let pageSize = 5

    public init(repository: any TranslationRepository) {
        self.repository = repository
        toggleUseCase = ToggleActionUseCase(repository: repository)
    }

    public func load() async {
        if actions.value == nil {
            actions = .loading
        }
        async let page = repository.actions(checked: false, page: 1, size: Self.pageSize)
        async let projects = repository.projects()
        do {
            let result = try await page
            actions = .loaded(result.items)
            totalOpen = result.totalElements
        } catch let error as DomainError {
            if error != .cancelled {
                actions = .failed(code: Self.code(error))
            }
        } catch {
            actions = .failed(code: "UNKNOWN")
        }
        projectName = await (try? projects)?.first?.name
    }

    /// 체크 상자: 바로 바꿔 보여 주고(낙관적), 서버가 거절하면 되돌린다. 끝낸 할 일은 목록에 남겨 줄을 긋는다.
    public func toggle(_ item: UpcomingAction) async {
        guard var list = actions.value, let index = list.firstIndex(where: { $0.id == item.id }) else { return }
        let before = list[index]
        list[index].action.isChecked.toggle()
        actions = .loaded(list)
        totalOpen += list[index].action.isChecked ? -1 : 1
        do {
            let saved = try await toggleUseCase(translationId: before.translationId, action: before.action)
            guard var now = actions.value, let i = now.firstIndex(where: { $0.id == item.id }) else { return }
            now[i].action = saved
            actions = .loaded(now)
        } catch {
            guard var now = actions.value, let i = now.firstIndex(where: { $0.id == item.id }) else { return }
            now[i] = before
            actions = .loaded(now)
            totalOpen += before.action.isChecked ? -1 : 1
            notice = "home.actions.toggleFailed"
        }
    }

    static func code(_ error: DomainError) -> String {
        switch error {
        case .offline: "OFFLINE"
        case .unauthorized: "UNAUTHORIZED"
        default: "UNKNOWN"
        }
    }
}

// MARK: - 화면

/// A-01 홈(Figma 51:1272). 히어로 300 위에 프로젝트 칩·등급 카드, 날짜·"오늘", 퇴근길 복습 카드, 다가오는 할 일.
public struct HomeRootView: View {
    @ViewModelState private var model: HomeViewModel
    let user: UserProfile?
    let onNotice: (LocalizedStringKey) -> Void
    let refreshKey: Int

    @Environment(AppRouter.self) private var router
    @Environment(\.mwScale) private var scale

    public init(
        model: @autoclosure @escaping () -> HomeViewModel,
        user: UserProfile?,
        refreshKey: Int = 0,
        onNotice: @escaping (LocalizedStringKey) -> Void = { _ in
        }
    ) {
        _model = ViewModelState(wrappedValue: model())
        self.user = user
        self.refreshKey = refreshKey
        self.onNotice = onNotice
    }

    public var body: some View {
        ScrollView {
            ZStack(alignment: .top) {
                MwHomeHero()
                VStack(alignment: .leading, spacing: 0) {
                    topBar.frame(minHeight: 52 * scale).padding(.top, 54 * scale)
                    header
                    // 히어로 아래 카드: Figma 51:1328 pt 78(186 + 78 = 264)
                    reviewCard.padding(.top, (264 - 186) * scale)
                    actionsSection.padding(.top, 24 * scale)
                }
            }
            .padding(.bottom, MwTabBar<AppTab>.reservedHeight * scale)
        }
        .scrollIndicators(.hidden)
        .background(MwColor.canvas.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .task(id: refreshKey) { await model.load() }
        .refreshable { await model.load() }
        .onChange(of: model.notice) { _, notice in
            if let notice {
                onNotice(notice)
                model.notice = nil
            }
        }
    }

    // 위: 프로젝트 칩(왼쪽 16) · 등급 카드(오른쪽 16)
    private var topBar: some View {
        HStack(alignment: .center) {
            Button {
                router.select(.project)
            } label: {
                HStack(spacing: 6 * scale) {
                    MwIconView(.layers, color: MwColor.accentFill)
                    Text(verbatim: model.projectName ?? String(localized: "home.project.default", bundle: .module))
                        .mwFont(.bold, 13)
                        .foregroundStyle(MwColor.textPrimary)
                        .lineLimit(1)
                    MwIconView(.chevronDown, color: MwColor.textPrimary.opacity(0.6))
                }
                .padding(.horizontal, 14 * scale)
                .frame(minHeight: 36 * scale)
                .background(MwGlassBackground(cornerRadius: 18, fill: MwColor.glassFillThin.opacity(0.7)))
                .mwGlassShadow(scale)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8 * scale)
            levelCard
        }
        .padding(.horizontal, 16 * scale)
    }

    private var levelCard: some View {
        let score = user?.bestScore ?? 0
        let level = PangyoLevel.of(code: user?.levelCode, score: score)
        let progress = level.progress(score: score)
        return VStack(alignment: .leading, spacing: 4 * scale) {
            HStack {
                Text(verbatim: "Lv\(level.number)")
                    .font(MwFont.pretendard(.bold, size: 11 * scale))
                    .foregroundStyle(MwColor.jargonChipText)
                    .padding(.horizontal, 7 * scale)
                    .frame(minHeight: 20 * scale)
                    .background(RoundedRectangle(cornerRadius: 9 * scale, style: .circular).fill(MwColor.jargonChipFill))
                Spacer(minLength: 6 * scale)
                Text(LocalizedStringKey(level.nameKey), bundle: .module)
                    .mwFont(.bold, 13, lineHeight: 19)
                    .foregroundStyle(MwColor.textPrimary)
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3 * scale).fill(MwColor.separator)
                RoundedRectangle(cornerRadius: 3 * scale).fill(MwColor.accentFill).frame(width: 90 * scale * progress)
            }
            .frame(width: 90 * scale, height: 4 * scale)
            if let next = level.next {
                Text(verbatim: fmt(
                    "home.level.toNext",
                    String(localized: String.LocalizationValue(next.nameKey), bundle: .module),
                    Int(progress * 100)
                ))
                .font(MwFont.pretendard(.regular, size: 10 * scale))
                .foregroundStyle(MwColor.textSecondary)
            }
        }
        .padding(.horizontal, 10 * scale)
        .padding(.top, 6 * scale)
        .padding(.bottom, 7 * scale)
        .frame(minWidth: 112 * scale, alignment: .leading)
        .fixedSize()
        .background(MwGlassBackground(cornerRadius: 16))
        .mwGlassShadow(scale)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: Date().formatted(.dateTime.month(.wide).day().weekday(.wide).locale(Locale(identifier: "ko_KR"))))
                .mwFont(.bold, 14, lineHeight: 20, tracking: -0.07)
                .foregroundStyle(MwColor.onHeroStrong)
            Text("home.today", bundle: .module)
                .mwFont(.bold, 34, lineHeight: 44, tracking: -0.68)
                .foregroundStyle(MwColor.onHeroPrimary)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 20 * scale)
        .padding(.top, 4 * scale)
        .padding(.bottom, 12 * scale)
    }

    /// 퇴근길 복습 카드(Figma 51:1329). 복습은 v1.1 → 장 수 0, 버튼은 안내.
    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 0) {
                    MwIconView(.bike, color: MwColor.accentFill)
                    Text("home.review.title", bundle: .module).mwFont(.bold, 13, lineHeight: 19).foregroundStyle(MwColor.accentFill)
                }
                Spacer()
                Text(verbatim: Self.reminderText(hour: 18)).mwFont(.regular, 12, lineHeight: 16).foregroundStyle(MwColor.textSecondary)
            }
            HStack(alignment: .lastTextBaseline) {
                (Text(verbatim: "0").font(MwFont.pretendard(.bold, size: 34 * scale)).foregroundStyle(MwColor.textPrimary)
                    + Text("home.review.unit", bundle: .module).font(MwFont.pretendard(.semiBold, size: 17 * scale))
                    .foregroundStyle(MwColor.textSecondary))
                    .tracking(-0.68 * scale)
                Spacer()
                HStack(spacing: 0) {
                    MwIconView(.flame).frame(width: 10.891 * scale, height: 14 * scale)
                    Text(verbatim: fmt("home.review.streak", user?.currentStreak ?? 0))
                        .mwFont(.regular, 13, lineHeight: 19)
                        .foregroundStyle(MwColor.textSecondary)
                }
            }
            .frame(minHeight: 52 * scale, alignment: .bottom)
            Button {
                onNotice("home.review.comingSoon")
            } label: {
                Text("home.review.start", bundle: .module).font(MwFont.pretendard(.semiBold, size: 17 * scale))
            }
            .buttonStyle(MwPrimaryButtonStyle(height: 50, radius: 18))
            .padding(.top, 12 * scale)
        }
        .padding(18 * scale)
        .background(MwGlassBackground(cornerRadius: 26))
        .mwGlassShadow(scale)
        .padding(.horizontal, 20 * scale)
    }

    static func reminderText(hour: Int) -> String {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 1
        comps.hour = hour
        comps.minute = 0
        let date = Calendar(identifier: .gregorian).date(from: comps) ?? Date()
        return date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "ko_KR")))
    }

    /// 다가오는 할 일(Figma 51:1353).
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MwSectionHeader(Text("home.actions.title", bundle: .module)) {
                if model.totalOpen > 0 {
                    Button {
                        router.select(.project)
                    } label: {
                        Text(verbatim: fmt("home.actions.all", model.totalOpen))
                            .mwFont(.semiBold, 13, lineHeight: 19)
                            .foregroundStyle(MwColor.accentFill)
                    }
                    .buttonStyle(.plain)
                }
            }
            switch model.actions {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 120 * scale)
            case let .failed(code):
                failure(code)
            case let .loaded(items) where items.isEmpty:
                emptyActions
            case let .loaded(items):
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            MwRowDivider()
                        }
                        ActionRow(item: item) { Task { await model.toggle(item) } }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 20 * scale, style: .circular).fill(MwColor.surface))
                .clipShape(RoundedRectangle(cornerRadius: 20 * scale, style: .circular))
                .mwCardShadow(scale)
            }
        }
        .padding(.horizontal, 20 * scale)
    }

    private var emptyActions: some View {
        VStack(spacing: 12 * scale) {
            Text("home.actions.empty", bundle: .module)
                .mwFont(.regular, 15, lineHeight: 22)
                .foregroundStyle(MwColor.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                router.present(.compose)
            } label: {
                HStack(spacing: 8 * scale) {
                    MwIconView(.sparkles, color: MwColor.accentFill)
                    Text("home.actions.decode", bundle: .module).font(MwFont.pretendard(.semiBold, size: 16 * scale))
                }
            }
            .buttonStyle(MwSecondaryButtonStyle(height: 48))
        }
        .padding(18 * scale)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20 * scale, style: .circular).fill(MwColor.surface))
        .mwCardShadow(scale)
    }

    private func failure(_ code: String) -> some View {
        VStack(spacing: 10 * scale) {
            Text(code == "OFFLINE" ? "home.error.offline" : "home.error.generic", bundle: .module)
                .mwFont(.regular, 15, lineHeight: 22)
                .foregroundStyle(MwColor.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await model.load() }
            } label: {
                Text("home.error.retry", bundle: .module).font(MwFont.pretendard(.semiBold, size: 16 * scale))
            }
            .buttonStyle(MwSecondaryButtonStyle(height: 44))
        }
        .padding(18 * scale)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20 * scale, style: .circular).fill(MwColor.surface))
        .mwCardShadow(scale)
    }
}

#if DEBUG
    import DomainTesting

    #Preview("A-01 홈") {
        HomeRootView(model: HomeViewModel(repository: FakeTranslationRepository()), user: .sample)
            .environment(AppRouter())
            .mwScaledToWidth()
    }
#endif

/// 카탈로그 문구 + 값(키는 점 표기만 쓴다 → 값은 %lld·%@ 자리표시자로 넣는다, check-xcstrings).
func fmt(_ key: String, _ args: CVarArg...) -> String {
    String(format: String(localized: String.LocalizationValue(key), bundle: .module), arguments: args)
}
