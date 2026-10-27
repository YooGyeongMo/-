import Domain
import FeatureKit
import MwonmalUI
import Routing
import SwiftUI

/// A-11 프로젝트(Figma 51:3356). v1.0은 회의(v1.2)가 없어서 첫 칸은 "해석"(회의 밖 메시지 해석 기록)이다.
/// 머리: 파란 아이콘 34 + 이름 22 Bold + 설명 13. 버튼 둘: 판교어 해석(흰) · 새 회의(파랑, v1.2 안내).
/// 세 칸 고르기(44 높이, 흰 60% 바탕, 고른 칸 흰색): 해석 N · 할 일 N · 모르는 말 N.
public struct ProjectRootView: View {
    @State private var model: ProjectViewModel
    let refreshKey: Int
    let onNotice: (LocalizedStringKey) -> Void
    @Environment(AppRouter.self) private var router
    @Environment(\.mwScale) private var s

    public init(dependencies: TranslateDependencies, refreshKey: Int = 0, onNotice: @escaping (LocalizedStringKey) -> Void = { _ in }) {
        _model = State(initialValue: ProjectViewModel(dependencies: dependencies))
        self.refreshKey = refreshKey
        self.onNotice = onNotice
    }

    public var body: some View {
        ZStack(alignment: .top) {
            MwSceneBackground(.sky)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar.frame(height: 52 * s).padding(.top, 54 * s)
                    header.padding(.top, 12 * s)
                    buttons.padding(.top, 16 * s)
                    segments.padding(.top, 16 * s)
                    content.padding(.top, 14 * s)
                }
                .padding(.bottom, MwTabBar<AppTab>.reservedHeight * s)
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

    // 위 막대: v1.0 프로젝트 탭은 뿌리 화면이라 뒤로 버튼 자리는 비우고(Figma 44×44 자리), 오른쪽 ··· 은 새로고침.
    private var topBar: some View {
        HStack {
            Color.clear.frame(width: 44 * s, height: 44 * s)
            Spacer()
            MwGlassCircleButton(.ellipsis, label: "translate.project.more", bundle: .module) {
                Task { await model.load() }
            }
        }
        .padding(.horizontal, 16 * s)
    }

    private var header: some View {
        HStack(spacing: 8 * s) {
            MwIconView(.layersFill, color: MwColor.accentOnFill)
                .frame(width: 34 * s, height: 34 * s)
                .background(RoundedRectangle(cornerRadius: 11 * s, style: .circular).fill(MwColor.accentFill))
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
        .padding(.horizontal, 20 * s)
    }

    private var description: String {
        if let d = model.project?.description, !d.isEmpty {
            return d
        }
        return String(localized: "translate.project.defaultDescription", bundle: .module)
    }

    private var buttons: some View {
        HStack(spacing: 10 * s) {
            Button {
                router.present(.compose)
            } label: {
                HStack(spacing: 8 * s) {
                    MwIconView(.sparkles, color: MwColor.accentFill)
                    Text("translate.project.decode", bundle: .module).font(MwFont.pretendard(.semiBold, size: 16 * s))
                }
            }
            .buttonStyle(MwSecondaryButtonStyle(height: 48))
            .accessibilityIdentifier("project.decode")
            Button {
                onNotice("translate.project.meetingComingSoon")
            } label: {
                HStack(spacing: 8 * s) {
                    MwIconView(.plus, color: MwColor.accentOnFill)
                    Text("translate.project.newMeeting", bundle: .module).font(MwFont.pretendard(.semiBold, size: 16 * s))
                }
            }
            .buttonStyle(MwPrimaryButtonStyle(height: 48, radius: 18))
        }
        .padding(.horizontal, 20 * s)
    }

    private var segments: some View {
        HStack(spacing: 0) {
            segment(.translations, Text(verbatim: L("translate.project.tab.translations", model.translationTotal)))
            segment(.actions, Text(verbatim: L("translate.project.tab.actions", model.openActionTotal)))
            segment(.terms, Text(verbatim: L("translate.project.tab.terms", model.project?.unknownTermCount ?? 0)))
        }
        .padding(3 * s)
        .frame(height: 44 * s)
        .background(RoundedRectangle(cornerRadius: 14 * s, style: .circular).fill(MwColor.glassFillThin))
        .padding(.horizontal, 20 * s)
    }

    private func segment(_ value: ProjectViewModel.Segment, _ title: Text) -> some View {
        let selected = model.segment == value
        return Button {
            model.segment = value
        } label: {
            title
                .font(MwFont.pretendard(selected ? .semiBold : .medium, size: 15 * s))
                .foregroundStyle(selected ? MwColor.textPrimary : MwColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 11 * s, style: .circular)
                            .fill(MwColor.surface)
                            .shadow(color: Color(red: 90 / 255, green: 60 / 255, blue: 30 / 255).opacity(0.06), radius: 1.5 * s, y: 2 * s)
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
            ProgressView().frame(maxWidth: .infinity, minHeight: 160 * s)
        case let .failed(code):
            StateCard(text: Text(code == "OFFLINE" ? "translate.error.offline" : "translate.error.generic", bundle: .module)) {
                Task { await model.load() }
            }
        case let .loaded(items) where items.isEmpty:
            StateCard(text: Text("translate.project.empty", bundle: .module), actionTitle: Text("translate.project.decode", bundle: .module)) {
                router.present(.compose)
            }
        case let .loaded(items):
            LazyVStack(spacing: 12 * s) {
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
            .padding(.horizontal, 20 * s)
        }
    }

    @ViewBuilder private var actionList: some View {
        switch model.openActions {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 160 * s)
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
                }
            }
            .background(RoundedRectangle(cornerRadius: 20 * s, style: .circular).fill(MwColor.surface))
            .clipShape(RoundedRectangle(cornerRadius: 20 * s, style: .circular))
            .mwCardShadow(s)
            .padding(.horizontal, 20 * s)
        }
    }

    private var termsComingSoon: some View {
        StateCard(text: Text("translate.project.termsComingSoon", bundle: .module))
    }
}

/// 해석 기록 카드(Figma 51:3404 회의 카드 모양): 날짜·시각 + 오른쪽 알약, 제목 17 SemiBold, 아래 개수 셋.
struct TranslationCard: View {
    let item: TranslationSummary
    @Environment(\.mwScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: Self.dateText(item.createdAt))
                    .mwFont(.semiBold, 13, lineHeight: 19)
                    .foregroundStyle(MwColor.textSecondary)
                Spacer()
                MwStatusPill(Text(item.inputSource == .screenshot ? "translate.card.screenshot" : "translate.card.pasted", bundle: .module), tone: .neutral, height: 22, size: 11)
            }
            Text(verbatim: item.title)
                .mwFont(.semiBold, 17, lineHeight: 25, tracking: -0.085)
                .foregroundStyle(MwColor.textPrimary)
                .lineLimit(2)
                .padding(.top, 4 * s)
            HStack(spacing: 12 * s) {
                stat(.sparkleSmall, color: MwColor.textSecondary, Text(verbatim: L("translate.card.jargon", item.jargonCount)))
                stat(.checklist, color: MwColor.urgentText, Text(verbatim: L("translate.card.actions", item.openActionCount)))
                if let intent = item.intent {
                    stat(.nuance, color: MwColor.jargonChipText, Text(IntentLabel.key(intent), bundle: .module))
                }
            }
            .padding(.top, 8 * s)
        }
        .padding(.horizontal, 16 * s)
        .padding(.vertical, 14 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24 * s, style: .circular).fill(MwColor.surface))
        .mwRaisedShadow(s)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func stat(_ icon: MwIcon, color: Color, _ text: Text) -> some View {
        HStack(spacing: 2 * s) {
            MwIconView(icon, color: color)
            text.mwFont(.regular, 13, lineHeight: 19).foregroundStyle(color)
        }
    }

    static func dateText(_ date: Date) -> String {
        let day = date.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated).locale(Locale(identifier: "ko_KR")))
        let time = date.mwClock
        return "\(day) · \(time)"
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
    @Environment(\.mwScale) private var s

    init(text: Text, actionTitle: Text? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.actionTitle = actionTitle ?? (action == nil ? nil : Text("translate.error.retry", bundle: .module))
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12 * s) {
            text.mwFont(.regular, 15, lineHeight: 22).foregroundStyle(MwColor.textSecondary).multilineTextAlignment(.center)
            if let action, let actionTitle {
                Button(action: action) { actionTitle.font(MwFont.pretendard(.semiBold, size: 16 * s)) }
                    .buttonStyle(MwSecondaryButtonStyle(height: 44))
            }
        }
        .padding(18 * s)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20 * s, style: .circular).fill(MwColor.surface))
        .mwCardShadow(s)
        .padding(.horizontal, 20 * s)
    }
}

/// 할 일 한 줄(A-06 51:2304): 체크 · 17 Medium · 아래 기한 문구 · 오른쪽 오늘/내일 알약.
struct ActionLine: View {
    let action: ActionItem
    let onToggle: () -> Void
    @Environment(\.mwScale) private var s

    var body: some View {
        HStack(spacing: 14 * s) {
            Button(action: onToggle) { MwCheckbox(isOn: action.isChecked) }
                .buttonStyle(.plain)
                .frame(width: 26 * s, height: 56 * s)
                .contentShape(Rectangle().inset(by: -9 * s))
                .accessibilityLabel(Text(verbatim: action.text))
                .accessibilityValue(Text(action.isChecked ? "translate.action.done" : "translate.action.notDone", bundle: .module))
                .accessibilityAddTraits(.isToggle)
                .accessibilityIdentifier("action.check.\(action.id)")
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: action.text)
                    .mwFont(.medium, 17, lineHeight: 24)
                    .foregroundStyle(action.isChecked ? MwColor.textDisabled : MwColor.textPrimary)
                    .strikethrough(action.isChecked, color: MwColor.textDisabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = DueText.detail(action) {
                    Text(verbatim: detail)
                        .mwFont(.regular, 14, lineHeight: 20)
                        .foregroundStyle(MwColor.textSecondary)
                        .padding(.top, 1 * s)
                }
            }
            .padding(.vertical, 13 * s)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !action.isChecked, let pill = DueText.pill(action.dueAt) {
                MwStatusPill(Text(pill.key, bundle: .module), tone: pill.tone)
            }
        }
        .padding(.horizontal, 18 * s)
        .frame(minHeight: 56 * s)
    }
}

/// 기한 문구: "오늘 17:30 · 17:00 알림"(마감 30분 전 알림), 시각이 없으면 원문 힌트.
enum DueText {
    static let alertLead: TimeInterval = 30 * 60

    static func detail(_ action: ActionItem, calendar: Calendar = .current) -> String? {
        guard let due = action.dueAt else { return action.dueHint }
        let day: String = if calendar.isDateInToday(due) {
            String(localized: "translate.due.today", bundle: .module)
        } else if calendar.isDateInTomorrow(due) {
            String(localized: "translate.due.tomorrow", bundle: .module)
        } else {
            due.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated).locale(Locale(identifier: "ko_KR")))
        }
        let time = due.mwClock
        guard action.alertEnabled else { return "\(day) \(time)" }
        let alert = due.addingTimeInterval(-alertLead).mwClock
        return L("translate.due.withAlert", day, time, alert)
    }

    static func pill(_ due: Date?, now: Date = Date(), calendar: Calendar = .current) -> (key: LocalizedStringKey, tone: MwStatusPill.Tone)? {
        guard let due else { return nil }
        if due < now {
            return ("translate.due.overdue", .urgent)
        }
        if calendar.isDateInToday(due) {
            return ("translate.due.today", .urgent)
        }
        if calendar.isDateInTomorrow(due) {
            return ("translate.due.tomorrow", .soon)
        }
        return nil
    }
}
