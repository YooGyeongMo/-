import Domain
import FeatureKit
import MwonmalUI
import Routing
import SwiftUI

/// A-06 해석 결과(Figma 51:2201): 바탕 canvas, 위 모서리 32, 손잡이 40×5.
/// 머리(출처 칩·닫기) → "해석 결과" 22 Bold → 출처·시각 → 원문+쉬운 말 카드 → 숨은 뜻 카드 → 나한테 시킨 일 →
/// 복습 카드로 담은 말 칩 → 아래 고정 버튼 "모르는 말 모두 복습 카드로"(카드는 v1.1 → 안내).
public struct ResultSheet: View {
    @State private var model: ResultViewModel
    let onNotice: (LocalizedStringKey) -> Void
    let onChange: () -> Void
    @Environment(AppRouter.self) private var router
    @Environment(\.mwScale) private var s

    public init(
        translationId: Int64,
        dependencies: TranslateDependencies,
        prefetched: Translation? = nil,
        onChange: @escaping () -> Void = {},
        onNotice: @escaping (LocalizedStringKey) -> Void = { _ in }
    ) {
        _model = State(initialValue: ResultViewModel(translationId: translationId, dependencies: dependencies, prefetched: prefetched))
        self.onChange = onChange
        self.onNotice = onNotice
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MwGrabber().frame(maxWidth: .infinity).padding(.top, 10 * s)
                    content.padding(.top, 14 * s)
                }
                .padding(.horizontal, 20 * s)
                .padding(.bottom, (56 + 42 + 10 + 16) * s)
            }
            .scrollIndicators(.hidden)
            bottomButton
        }
        .background(MwColor.canvas.ignoresSafeArea())
        .task {
            model.onChange = onChange
            await model.load()
        }
        .onChange(of: model.notice) { _, notice in
            if let notice {
                onNotice(notice)
                model.notice = nil
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.translation {
        case .idle, .loading:
            header(nil)
            ProgressView().frame(maxWidth: .infinity, minHeight: 240 * s)
        case let .failed(code):
            header(nil)
            Text(code == "NOT_FOUND" ? "translate.result.notFound" : code == "OFFLINE" ? "translate.error.offline" : "translate.error.generic", bundle: .module)
                .mwFont(.regular, 15, lineHeight: 22)
                .foregroundStyle(MwColor.textSecondary)
                .padding(.top, 24 * s)
        case let .loaded(t):
            header(t)
            VStack(alignment: .leading, spacing: 0) {
                sourceCard(t).padding(.top, 16 * s)
                if let nuance = t.nuance {
                    nuanceCard(nuance, intent: t.intent).padding(.top, 12 * s)
                }
                if !t.actions.isEmpty {
                    MwSectionHeader(Text("translate.result.actions", bundle: .module)).padding(.top, 12 * s)
                    VStack(spacing: 0) {
                        ForEach(Array(t.actions.enumerated()), id: \.element.id) { index, action in
                            if index > 0 {
                                MwRowDivider()
                            }
                            ActionLine(action: action) { Task { await model.toggle(action) } }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 20 * s, style: .circular).fill(MwColor.surface))
                    .clipShape(RoundedRectangle(cornerRadius: 20 * s, style: .circular))
                    .mwCardShadow(s)
                }
                if !t.terms.isEmpty {
                    MwSectionHeader(Text("translate.result.terms", bundle: .module)).padding(.top, 12 * s)
                    MwFlowLayout(spacing: 6 * s) {
                        ForEach(Array(t.terms.enumerated()), id: \.offset) { _, term in
                            TermChip(term: term) { open(term) }
                        }
                    }
                }
            }
        }
    }

    private func header(_ t: Translation?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let t {
                    MwSourceChip(icon: .layers, Text(verbatim: Self.sourceTitle(t)), height: 26, size: 13)
                }
                Spacer()
                MwGlassCircleButton(.close, diameter: 32, label: "translate.result.close", bundle: .module) {
                    router.dismissSheet()
                }
                .accessibilityIdentifier("result.close")
            }
            Text("translate.result.title", bundle: .module)
                .mwFont(.bold, 22, lineHeight: 31, tracking: -0.33)
                .foregroundStyle(MwColor.textPrimary)
                .padding(.top, 12 * s)
                .accessibilityAddTraits(.isHeader)
            if let t {
                HStack(spacing: 6 * s) {
                    Text(verbatim: Self.subtitle(t)).mwFont(.regular, 13, lineHeight: 19).foregroundStyle(MwColor.textSecondary)
                    if t.isSimplified {
                        MwStatusPill(Text("translate.result.simplified", bundle: .module), tone: .neutral, height: 20, size: 11)
                            .accessibilityHint(Text("translate.result.simplifiedHint", bundle: .module))
                            .accessibilityIdentifier("result.simplified")
                    }
                }
            }
        }
    }

    static func sourceTitle(_ t: Translation) -> String {
        let place = t.meetingTitle ?? String(localized: "translate.result.messageSource", bundle: .module)
        return "\(t.projectName) · \(place)"
    }

    static func subtitle(_ t: Translation) -> String {
        let source = String(localized: t.inputSource == .screenshot ? "translate.result.fromScreenshot" : "translate.result.fromPaste", bundle: .module)
        return "\(source) · \(t.createdAt.mwClock)"
    }

    private func sourceCard(_ t: Translation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("translate.result.original", bundle: .module).mwFont(.bold, 12, lineHeight: 16).foregroundStyle(MwColor.textSecondary)
            JargonText(
                t.sourceText,
                highlights: t.terms.map { JargonText.Highlight(start: $0.startIndex, end: $0.endIndex, termId: $0.termId, meaning: "\($0.termKo), \($0.plainKo)") }
            ) { id in router.present(.term(termId: id)) }
                .padding(.top, 4 * s)
                .accessibilityIdentifier("result.original")
            Rectangle().fill(MwColor.separator).frame(height: 1).padding(.top, 12 * s)
            Text("translate.result.plain", bundle: .module).mwFont(.bold, 12, lineHeight: 16).foregroundStyle(MwColor.accentFill).padding(.top, 12 * s)
            Group {
                if t.isClean {
                    Text("translate.result.clean", bundle: .module)
                } else {
                    Text(verbatim: t.resultText)
                }
            }
            .mwFont(.semiBold, 17, lineHeight: 25, tracking: -0.085)
            .foregroundStyle(MwColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4 * s)
            .accessibilityIdentifier("result.plain")
        }
        .padding(.horizontal, 18 * s)
        .padding(.vertical, 16 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24 * s, style: .circular).fill(MwColor.surface))
        .mwRaisedShadow(s)
    }

    private func nuanceCard(_ n: Nuance, intent: IntentType?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 0) {
                    MwIconView(.nuance, color: MwColor.textStrong)
                    Text("translate.result.nuance", bundle: .module).mwFont(.bold, 12, lineHeight: 16).foregroundStyle(MwColor.textStrong)
                }
                Spacer()
                if let intent {
                    let label = String(localized: String.LocalizationValue(IntentLabel.raw(intent)), bundle: .module)
                    MwStatusPill(Text(verbatim: "\(label) · \(Int((n.confidence * 100).rounded()))%"), tone: .neutral, height: 22, size: 11)
                }
            }
            Text(verbatim: n.tip.isEmpty ? n.note : "\(n.note) \(n.tip)")
                .mwFont(.regular, 15, lineHeight: 22)
                .foregroundStyle(MwColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4 * s)
        }
        .padding(.horizontal, 16 * s)
        .padding(.vertical, 12 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24 * s, style: .circular).fill(MwColor.surfaceMuted))
        .mwRaisedShadow(s)
        .accessibilityElement(children: .combine)
    }

    private var bottomButton: some View {
        Button {
            onNotice("translate.result.cardsComingSoon")
        } label: {
            HStack(spacing: 8 * s) {
                MwIconView(.cards, color: MwColor.accentOnFill)
                Text("translate.result.addAll", bundle: .module).font(MwFont.pretendard(.semiBold, size: 17 * s))
            }
        }
        .buttonStyle(MwPrimaryButtonStyle(height: 56, radius: 18))
        .padding(.horizontal, 20 * s)
        .padding(.top, 10 * s)
        .padding(.bottom, 42 * s)
        .background(MwColor.canvas)
        .ignoresSafeArea(edges: .bottom)
        .opacity(model.translation.value?.terms.isEmpty == false ? 1 : 0)
    }

    private func open(_ term: DetectedTerm) {
        if let id = term.termId {
            router.present(.term(termId: id))
        } else {
            onNotice("translate.result.newTerm")
        }
    }
}

extension IntentLabel {
    static func raw(_ intent: IntentType) -> String {
        switch intent {
        case .request: "translate.intent.request"
        case .decision: "translate.intent.decision"
        case .decline: "translate.intent.decline"
        case .share: "translate.intent.share"
        case .question: "translate.intent.question"
        }
    }
}

/// 용어 칩(Figma 51:2335 담음 = 초록 ✓, 51:2345 안 담음 = 노랑 +): 34 높이, 모서리 20, 14 SemiBold.
struct TermChip: View {
    let term: DetectedTerm
    let action: () -> Void
    @Environment(\.mwScale) private var s

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6 * s) {
                if term.inMyCards {
                    MwIconView(.check, color: MwColor.doneText)
                } else {
                    Text(verbatim: "+").font(MwFont.pretendard(.extraBold, size: 14 * s))
                }
                Text(verbatim: term.termKo).font(MwFont.pretendard(.semiBold, size: 14 * s))
            }
            .foregroundStyle(term.inMyCards ? MwColor.doneText : MwColor.jargonChipText)
            .padding(.horizontal, 11 * s)
            .frame(height: 34 * s)
            .background(RoundedRectangle(cornerRadius: 20 * s, style: .circular).fill(term.inMyCards ? MwColor.doneFill : MwColor.jargonChipFill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(term.termKo), \(term.plainKo)"))
        .accessibilityHint(Text("translate.result.termHint", bundle: .module))
    }
}

/// 용어 시트: 이름·원어·쉬운 말·뜻·예문(GET /terms/{id}).
public struct TermSheet: View {
    let termId: Int64
    let repository: any TranslationRepository
    let onNotice: (LocalizedStringKey) -> Void
    @State private var detail: Phase<TermDetail> = .idle
    @Environment(AppRouter.self) private var router
    @Environment(\.mwScale) private var s

    public init(termId: Int64, repository: any TranslationRepository, onNotice: @escaping (LocalizedStringKey) -> Void = { _ in }) {
        self.termId = termId
        self.repository = repository
        self.onNotice = onNotice
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MwGrabber().frame(maxWidth: .infinity).padding(.top, 10 * s)
                HStack {
                    Spacer()
                    MwGlassCircleButton(.close, diameter: 32, label: "translate.result.close", bundle: .module) { router.dismissSheet() }
                        .accessibilityIdentifier("term.close")
                }
                .padding(.top, 8 * s)
                switch detail {
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 160 * s)
                case .failed:
                    Text("translate.error.generic", bundle: .module).mwFont(.regular, 15, lineHeight: 22).foregroundStyle(MwColor.textSecondary)
                case let .loaded(d):
                    loaded(d)
                }
            }
            .padding(.horizontal, 20 * s)
            .padding(.bottom, 24 * s)
        }
        .background(MwColor.canvas.ignoresSafeArea())
        .task {
            detail = .loading
            if let d = try? await repository.term(id: termId) {
                detail = .loaded(d)
            } else {
                detail = .failed(code: "UNKNOWN")
            }
        }
    }

    private func loaded(_ d: TermDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8 * s) {
                Text(verbatim: d.termKo).mwFont(.bold, 28, lineHeight: 38, tracking: -0.56).foregroundStyle(MwColor.textPrimary)
                if let en = d.originEn {
                    Text(verbatim: en).mwFont(.regular, 15).foregroundStyle(MwColor.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text("translate.term.plainLabel", bundle: .module).mwFont(.bold, 12, lineHeight: 16).foregroundStyle(MwColor.accentFill).padding(.top, 12 * s)
            Text(verbatim: d.plainKo).mwFont(.semiBold, 17, lineHeight: 25).foregroundStyle(MwColor.textPrimary).padding(.top, 4 * s)
            Text(verbatim: d.meaning)
                .mwFont(.regular, 15, lineHeight: 22)
                .foregroundStyle(MwColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8 * s)
            if !d.examples.isEmpty {
                MwSectionHeader(Text("translate.term.examples", bundle: .module)).padding(.top, 20 * s)
                VStack(alignment: .leading, spacing: 8 * s) {
                    ForEach(d.examples, id: \.self) { e in
                        VStack(alignment: .leading, spacing: 4 * s) {
                            Text(verbatim: e.jargon).mwFont(.regular, 15, lineHeight: 22).foregroundStyle(MwColor.textPrimary)
                            Text(verbatim: "→ \(e.plain)").mwFont(.semiBold, 15, lineHeight: 22).foregroundStyle(MwColor.accentText)
                        }
                    }
                }
                .padding(16 * s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20 * s, style: .circular).fill(MwColor.surface))
                .mwCardShadow(s)
            }
            Button {
                onNotice("translate.result.cardsComingSoon")
            } label: {
                HStack(spacing: 8 * s) {
                    MwIconView(.cards, color: MwColor.accentOnFill)
                    Text("translate.term.addCard", bundle: .module).font(MwFont.pretendard(.semiBold, size: 17 * s))
                }
            }
            .buttonStyle(MwPrimaryButtonStyle(height: 52, radius: 18))
            .padding(.top, 20 * s)
        }
    }
}
