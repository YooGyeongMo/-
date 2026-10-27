import Domain
import FeatureKit
import MwonmalUI
import Routing
import SwiftUI

/// A-11 프로젝트(Figma 51:3356). v1.0은 회의(v1.2)가 없어서 첫 칸은 "해석"(회의 밖 메시지 해석 기록)이다.
/// 머리: 파란 아이콘 34 + 이름 22 Bold + 설명 13. 버튼 둘: 판교어 해석(흰) · 새 회의(파랑, v1.2 안내).
/// 세 칸 고르기(44 높이, 흰 60% 바탕, 고른 칸 흰색): 해석 N · 할 일 N · 모르는 말 N.
public struct ProjectRootView: View {
    @ViewModelState private var model: ProjectViewModel
    let refreshKey: Int
    let onNotice: (LocalizedStringKey) -> Void
    @Environment(AppRouter.self) private var router
    @Environment(\.mwScale) private var scale

    public init(dependencies: TranslateDependencies, refreshKey: Int = 0, onNotice: @escaping (LocalizedStringKey) -> Void = { _ in }) {
        _model = ViewModelState(wrappedValue: ProjectViewModel(dependencies: dependencies))
        self.refreshKey = refreshKey
        self.onNotice = onNotice
    }

    public var body: some View {
        ZStack(alignment: .top) {
            MwSceneBackground(.sky)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar.frame(minHeight: 52 * scale).padding(.top, 54 * scale)
                    header.padding(.top, 12 * scale)
                    buttons.padding(.top, 16 * scale)
                    segments.padding(.top, 16 * scale)
                    content.padding(.top, 14 * scale)
                }
                .padding(.bottom, MwTabBar<AppTab>.reservedHeight * scale)
                .mwReadableWidth() // 넓은 화면: 가운데 680 (배경은 꽉 채운다)
            }
            .scrollIndicators(.hidden)
        }
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

    /// 위 막대: v1.0 프로젝트 탭은 뿌리 화면이라 뒤로 버튼 자리는 비우고(Figma 44×44 자리), 오른쪽 ··· 은 새로고침.
    private var topBar: some View {
        HStack {
            Color.clear.frame(width: 44 * scale, height: 44 * scale)
            Spacer()
            MwGlassCircleButton(.ellipsis, label: "translate.project.more", bundle: .module) {
                Task { await model.load() }
            }
        }
        .padding(.horizontal, 16 * scale)
    }

    private var header: some View {
        HStack(spacing: 8 * scale) {
            MwIconView(.layersFill, color: MwColor.accentOnFill)
                .frame(width: 34 * scale, height: 34 * scale)
                .background(RoundedRectangle(cornerRadius: 11 * scale, style: .circular).fill(MwColor.accentFill))
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: model.project?.name ?? String(localized: "translate.project.defaultName", bundle: .module))
                    .mwFont(.bold, 22, lineHeight: 26, tracking: -0.33)
                    .foregroundStyle(MwColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: description)
                    .mwFont(.regular, 13, lineHeight: 19)
                    .foregroundStyle(MwColor.textSecondary)
            }
        }
        .padding(.horizontal, 20 * scale)
    }

    private var description: String {
        if let desc = model.project?.description, !desc.isEmpty {
            return desc
        }
        return String(localized: "translate.project.defaultDescription", bundle: .module)
    }

    private var buttons: some View {
        HStack(spacing: 10 * scale) {
            Button {
                router.present(.compose)
            } label: {
                HStack(spacing: 8 * scale) {
                    MwIconView(.sparkles, color: MwColor.accentFill)
                    Text("translate.project.decode", bundle: .module).font(MwFont.pretendard(.semiBold, size: 16 * scale))
                }
            }
            .buttonStyle(MwSecondaryButtonStyle(height: 48))
            .accessibilityIdentifier("project.decode")
            Button {
                onNotice("translate.project.meetingComingSoon")
            } label: {
                HStack(spacing: 8 * scale) {
                    MwIconView(.plus, color: MwColor.accentOnFill)
                    Text("translate.project.newMeeting", bundle: .module).font(MwFont.pretendard(.semiBold, size: 16 * scale))
                }
            }
            .buttonStyle(MwPrimaryButtonStyle(height: 48, radius: 18))
        }
        .padding(.horizontal, 20 * scale)
    }

    private var segments: some View {
        HStack(spacing: 0) {
            segment(.translations, Text(verbatim: fmt("translate.project.tab.translations", model.translationTotal)))
            segment(.actions, Text(verbatim: fmt("translate.project.tab.actions", model.openActionTotal)))
            segment(.terms, Text(verbatim: fmt("translate.project.tab.terms", model.project?.unknownTermCount ?? 0)))
        }
        .padding(3 * scale)
        .frame(minHeight: 44 * scale)
        .background(RoundedRectangle(cornerRadius: 14 * scale, style: .circular).fill(MwColor.glassFillThin))
        .padding(.horizontal, 20 * scale)
    }

    private func segment(_ value: ProjectViewModel.Segment, _ title: Text) -> some View {
        let selected = model.segment == value
        return Button {
            model.segment = value
        } label: {
            title
                .font(MwFont.pretendard(selected ? .semiBold : .medium, size: 15 * scale))
                .foregroundStyle(selected ? MwColor.textPrimary : MwColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 11 * scale, style: .circular)
                            .fill(MwColor.surface)
                            .shadow(
                                color: Color(red: 90 / 255, green: 60 / 255, blue: 30 / 255).opacity(0.06),
                                radius: 1.5 * scale,
                                y: 2 * scale
                            )
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var content: some View {
        switch model.segment {
        case .translations: translationList
        case .actions: actionList
        case .terms: termsComingSoon
        }
    }

    @ViewBuilder private var translationList: some View {
        switch model.translations {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 160 * scale)
        case let .failed(code):
            StateCard(text: Text(code == "OFFLINE" ? "translate.error.offline" : "translate.error.generic", bundle: .module)) {
                Task { await model.load() }
            }
        case let .loaded(items) where items.isEmpty:
            StateCard(
                text: Text("translate.project.empty", bundle: .module),
                actionTitle: Text("translate.project.decode", bundle: .module)
            ) {
                router.present(.compose)
            }
        case let .loaded(items):
            LazyVStack(spacing: 12 * scale) {
                ForEach(items) { item in
                    Button {
                        router.present(.result(translationId: item.id))
                    } label: {
                        TranslationCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .task { await model.loadMoreIfNeeded(current: item) }
                }
            }
            .padding(.horizontal, 20 * scale)
        }
    }

    @ViewBuilder private var actionList: some View {
        switch model.openActions {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 160 * scale)
        case .failed:
            StateCard(text: Text("translate.error.generic", bundle: .module)) { Task { await model.load() } }
        case let .loaded(items) where items.isEmpty:
            StateCard(text: Text("translate.project.noActions", bundle: .module))
        case let .loaded(items):
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        MwRowDivider()
                    }
                    ActionLine(action: item.action) { Task { await model.toggle(item) } }
                        .contentShape(Rectangle())
                        .onTapGesture { router.present(.result(translationId: item.translationId)) }
                        .accessibilityAction(named: Text("translate.project.openResult", bundle: .module)) {
                            router.present(.result(translationId: item.translationId))
                        }
                }
            }
            .background(RoundedRectangle(cornerRadius: 20 * scale, style: .circular).fill(MwColor.surface))
            .clipShape(RoundedRectangle(cornerRadius: 20 * scale, style: .circular))
            .mwCardShadow(scale)
            .padding(.horizontal, 20 * scale)
        }
    }

    private var termsComingSoon: some View {
        StateCard(text: Text("translate.project.termsComingSoon", bundle: .module))
    }
}

/// 해석 기록 카드(Figma 51:3404 회의 카드 모양): 날짜·시각 + 오른쪽 알약, 제목 17 SemiBold, 아래 개수 셋.
struct TranslationCard: View {
    let item: TranslationSummary
    @Environment(\.mwScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: Self.dateText(item.createdAt))
                    .mwFont(.semiBold, 13, lineHeight: 19)
                    .foregroundStyle(MwColor.textSecondary)
                Spacer()
                MwStatusPill(
                    Text(item.inputSource == .screenshot ? "translate.card.screenshot" : "translate.card.pasted", bundle: .module),
                    tone: .neutral,
                    height: 22,
                    size: 11
                )
            }
            Text(verbatim: item.title)
                .mwFont(.semiBold, 17, lineHeight: 25, tracking: -0.085)
                .foregroundStyle(MwColor.textPrimary)
                .lineLimit(2)
                .padding(.top, 4 * scale)
            HStack(spacing: 12 * scale) {
                stat(.sparkleSmall, color: MwColor.textSecondary, Text(verbatim: fmt("translate.card.jargon", item.jargonCount)))
                stat(.checklist, color: MwColor.urgentText, Text(verbatim: fmt("translate.card.actions", item.openActionCount)))
                if let intent = item.intent {
                    stat(.nuance, color: MwColor.jargonChipText, Text(IntentLabel.key(intent), bundle: .module))
                }
            }
            .padding(.top, 8 * scale)
        }
        .padding(.horizontal, 16 * scale)
        .padding(.vertical, 14 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24 * scale, style: .circular).fill(MwColor.surface))
        .mwRaisedShadow(scale)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func stat(_ icon: MwIcon, color: Color, _ text: Text) -> some View {
        HStack(spacing: 2 * scale) {
            MwIconView(icon, color: color)
            text.mwFont(.regular, 13, lineHeight: 19).foregroundStyle(color)
        }
    }

    /// Figma "9월 17일 (수) · 10:00".
    static func dateText(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        let weekday = date.formatted(.dateTime.weekday(.abbreviated))
        return fmt("translate.card.date", parts.month ?? 0, parts.day ?? 0, weekday) + " · \(date.mwClock)"
    }
}

/// 의도 → 사람 말("결정 통보" 등).
enum IntentLabel {
    static func key(_ intent: IntentType) -> LocalizedStringKey {
        switch intent {
        case .request: "translate.intent.request"
        case .decision: "translate.intent.decision"
        case .decline: "translate.intent.decline"
        case .share: "translate.intent.share"
        case .question: "translate.intent.question"
        }
    }
}

/// 빈 상태·오류 카드(흰 카드 + 문구 + 선택 버튼).
struct StateCard: View {
    let text: Text
    var actionTitle: Text?
    var action: (() -> Void)?
    @Environment(\.mwScale) private var scale

    init(text: Text, actionTitle: Text? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.actionTitle = actionTitle ?? (action == nil ? nil : Text("translate.error.retry", bundle: .module))
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12 * scale) {
            text.mwFont(.regular, 15, lineHeight: 22).foregroundStyle(MwColor.textSecondary).multilineTextAlignment(.center)
            if let action, let actionTitle {
                Button(action: action) { actionTitle.font(MwFont.pretendard(.semiBold, size: 16 * scale)) }
                    .buttonStyle(MwSecondaryButtonStyle(height: 44))
            }
        }
        .padding(18 * scale)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20 * scale, style: .circular).fill(MwColor.surface))
        .mwCardShadow(scale)
        .padding(.horizontal, 20 * scale)
    }
}
