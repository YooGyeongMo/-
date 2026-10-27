import Domain
import FeatureKit
import MwonmalUI
import Routing
import SwiftUI

/// A-06 해석 결과(Figma 51:2201): 바탕 canvas, 위 모서리 32, 손잡이 40×5.
/// 머리(출처 칩·닫기) → "해석 결과" 22 Bold → 출처·시각 → 원문+쉬운 말 카드 → 숨은 뜻 카드 → 나한테 시킨 일 →
/// 복습 카드로 담은 말 칩 → 아래 고정 버튼 "모르는 말 모두 복습 카드로"(카드는 v1.1 → 안내).
public struct ResultSheet: View {
    @ViewModelState private var model: ResultViewModel
    let onNotice: (LocalizedStringKey) -> Void
    let onChange: () -> Void
    @Environment(AppRouter.self) private var router
    @Environment(\.mwScale) private var scale
    @Environment(\.mwLayout) private var layout

    public init(
        translationId: Int64,
        dependencies: TranslateDependencies,
        prefetched: Domain.Translation? = nil,
        onChange: @escaping () -> Void = {},
        onNotice: @escaping (LocalizedStringKey) -> Void = { _ in }
    ) {
        _model = ViewModelState(wrappedValue: ResultViewModel(
            translationId: translationId,
            dependencies: dependencies,
            prefetched: prefetched
        ))
        self.onChange = onChange
        self.onNotice = onNotice
    }

    public var body: some View {
        Group {
            if layout == .wide {
                wideBody
            } else {
                sheetBody
            }
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

    /// 좁은 화면: 아래에서 올라오는 시트(A-06).
    private var sheetBody: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MwGrabber().frame(maxWidth: .infinity).padding(.top, 10 * scale)
                    VStack(alignment: .leading, spacing: 0) { content }.padding(.top, 14 * scale)
                }
                .padding(.horizontal, 20 * scale)
                .padding(.bottom, (56 + 42 + 10 + 16) * scale)
            }
            .scrollIndicators(.hidden)
            bottomButton
        }
        // Figma 51:2362 pb 42 는 홈 인디케이터를 포함한 화면 아래 끝 기준이다.
        .ignoresSafeArea(edges: .bottom)
    }

    /// 넓은 화면(Mac·iPad): 웹 W-03처럼 두 열. 왼쪽 = 원문·쉬운 말·숨은 뜻, 오른쪽 = 시킨 일·모르는 말·담기 버튼.
    private var wideBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(model.translation.value)
                switch model.translation {
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                case let .failed(code):
                    failure(code).padding(.top, 24)
                case let .loaded(item):
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            sourceCard(item)
                            if let nuance = item.nuance {
                                nuanceCard(nuance, intent: item.intent)
                            }
                        }
                        .frame(maxWidth: MwLayout.readableWidth)
                        VStack(alignment: .leading, spacing: 0) {
                            actionsBlock(item)
                            termsBlock(item)
                            if !item.terms.isEmpty {
                                addAllButton.padding(.top, 16)
                            }
                        }
                        .frame(width: MwLayout.asideWidth + 40)
                    }
                    .padding(.top, 16)
                }
            }
            .padding(32)
            .frame(maxWidth: MwLayout.readableWidth + MwLayout.asideWidth + 40 + 24 + 64, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.translation {
        case .idle, .loading:
            header(nil)
            ProgressView().frame(maxWidth: .infinity, minHeight: 240 * scale)
        case let .failed(code):
            header(nil)
            failure(code).padding(.top, 24 * scale)
        case let .loaded(item):
            header(item)
            VStack(alignment: .leading, spacing: 0) {
                sourceCard(item).padding(.top, 16 * scale)
                if let nuance = item.nuance {
                    nuanceCard(nuance, intent: item.intent).padding(.top, 12 * scale)
                }
                actionsBlock(item).padding(.top, 12 * scale)
                termsBlock(item)
            }
        }
    }
}

// MARK: - 조각(타입 본문 길이 제한 때문에 확장으로 나눔, 같은 파일이라 private 접근 가능)

extension ResultSheet {
    private func failure(_ code: String) -> some View {
        Text(
            code == "NOT_FOUND" ? "translate.result.notFound" : code == "OFFLINE" ? "translate.error.offline" :
                "translate.error.generic",
            bundle: .module
        )
        .mwFont(.regular, 15, lineHeight: 22)
        .foregroundStyle(MwColor.textSecondary)
    }

    @ViewBuilder private func actionsBlock(_ item: Domain.Translation) -> some View {
        if !item.actions.isEmpty {
            MwSectionHeader(Text("translate.result.actions", bundle: .module))
            VStack(spacing: 0) {
                ForEach(Array(item.actions.enumerated()), id: \.element.id) { index, action in
                    if index > 0 {
                        MwRowDivider()
                    }
                    ActionLine(action: action) { Task { await model.toggle(action) } }
                }
            }
            .background(RoundedRectangle(cornerRadius: 20 * scale, style: .circular).fill(MwColor.surface))
            .clipShape(RoundedRectangle(cornerRadius: 20 * scale, style: .circular))
            .mwCardShadow(scale)
        }
    }

    @ViewBuilder private func termsBlock(_ item: Domain.Translation) -> some View {
        if !item.terms.isEmpty {
            MwSectionHeader(Text("translate.result.terms", bundle: .module)).padding(.top, 12 * scale)
            MwFlowLayout(spacing: 6 * scale) {
                ForEach(Array(item.terms.enumerated()), id: \.offset) { _, term in
                    TermChip(term: term) { open(term) }
                }
            }
        }
    }

    private func header(_ item: Domain.Translation?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let item {
                    MwSourceChip(icon: .layers, Text(verbatim: Self.sourceTitle(item)), height: 26, size: 13)
                }
                Spacer()
                MwGlassCircleButton(.close, diameter: 32, label: "translate.result.close", bundle: .module) {
                    router.dismissSheet()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("result.close")
            }
            Text("translate.result.title", bundle: .module)
                .mwFont(.bold, 22, lineHeight: 31, tracking: -0.33)
                .foregroundStyle(MwColor.textPrimary)
                .padding(.top, 12 * scale)
                .accessibilityAddTraits(.isHeader)
            if let item {
                HStack(spacing: 6 * scale) {
                    Text(verbatim: Self.subtitle(item)).mwFont(.regular, 13, lineHeight: 19).foregroundStyle(MwColor.textSecondary)
                    if item.isSimplified {
                        MwStatusPill(Text("translate.result.simplified", bundle: .module), tone: .neutral, height: 20, size: 11)
                            .accessibilityHint(Text("translate.result.simplifiedHint", bundle: .module))
                            .accessibilityIdentifier("result.simplified")
                    }
                }
            }
        }
    }

    static func sourceTitle(_ item: Domain.Translation) -> String {
        let place = item.meetingTitle ?? String(localized: "translate.result.messageSource", bundle: .module)
        return "\(item.projectName) · \(place)"
    }

    static func subtitle(_ item: Domain.Translation) -> String {
        let source = String(
            localized: item.inputSource == .screenshot ? "translate.result.fromScreenshot" : "translate.result.fromPaste",
            bundle: .module
        )
        return "\(source) · \(item.createdAt.mwClock)"
    }

    private func sourceCard(_ item: Domain.Translation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("translate.result.original", bundle: .module).mwFont(.bold, 12, lineHeight: 16).foregroundStyle(MwColor.textSecondary)
            JargonText(
                item.sourceText,
                highlights: item.terms.map { JargonText.Highlight(
                    start: $0.startIndex,
                    end: $0.endIndex,
                    termId: $0.termId,
                    meaning: $0.isContextGuess ? fmt("translate.result.guessMeaning", $0.termKo, Int(($0.confidence * 100).rounded()))
                        : "\($0.termKo), \($0.plainKo)"
                ) }
            ) { id in router.present(.term(termId: id)) }
                .padding(.top, 4 * scale)
                .accessibilityIdentifier("result.original")
            // swiftlint:disable:next no_fixed_height - 1pt 구분선·빛 줄(글자 없음)
            Rectangle().fill(MwColor.separator).frame(height: 1).padding(.top, 12 * scale)
            Text("translate.result.plain", bundle: .module).mwFont(.bold, 12, lineHeight: 16).foregroundStyle(MwColor.accentFill).padding(
                .top,
                12 * scale
            )
            Group {
                if item.isClean {
                    Text("translate.result.clean", bundle: .module)
                } else {
                    Text(verbatim: item.resultText)
                }
            }
            .mwFont(.semiBold, 17, lineHeight: 25, tracking: -0.085)
            .foregroundStyle(MwColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4 * scale)
            .accessibilityIdentifier("result.plain")
        }
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, 16 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24 * scale, style: .circular).fill(MwColor.surface))
        .mwRaisedShadow(scale)
    }

    private func nuanceCard(_ nuance: Nuance, intent: IntentType?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 0) {
                    MwIconView(.nuance, color: MwColor.textStrong)
                    Text("translate.result.nuance", bundle: .module).mwFont(.bold, 12, lineHeight: 16).foregroundStyle(MwColor.textStrong)
                }
                Spacer()
                if let intent {
                    let label = String(localized: String.LocalizationValue(IntentLabel.raw(intent)), bundle: .module)
                    MwStatusPill(
                        Text(verbatim: "\(label) · \(Int((nuance.confidence * 100).rounded()))%"),
                        tone: .neutral,
                        height: 22,
                        size: 11
                    )
                }
            }
            Text(verbatim: nuance.tip.isEmpty ? nuance.note : "\(nuance.note) \(nuance.tip)")
                .mwFont(.regular, 15, lineHeight: 22)
                .foregroundStyle(MwColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4 * scale)
        }
        .padding(.horizontal, 16 * scale)
        .padding(.vertical, 12 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24 * scale, style: .circular).fill(MwColor.surfaceMuted))
        .mwRaisedShadow(scale)
        .accessibilityElement(children: .combine)
    }

    private var addAllButton: some View {
        Button {
            onNotice("translate.result.cardsComingSoon")
        } label: {
            HStack(spacing: 8 * scale) {
                MwIconView(.cards, color: MwColor.accentOnFill)
                Text("translate.result.addAll", bundle: .module).font(MwFont.pretendard(.semiBold, size: 17 * scale))
            }
        }
        .buttonStyle(MwPrimaryButtonStyle(height: 56, radius: 18))
    }

    private var bottomButton: some View {
        addAllButton
            .padding(.horizontal, 20 * scale)
            .padding(.top, 10 * scale)
            .padding(.bottom, 42 * scale)
            .background(MwColor.canvas)
            .opacity(model.translation.value?.terms.isEmpty == false ? 1 : 0)
    }

    private func open(_ term: DetectedTerm) {
        if let id = term.termId {
            router.present(.term(termId: id))
        } else if term.isContextGuess {
            onNotice("translate.result.contextGuess")
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
