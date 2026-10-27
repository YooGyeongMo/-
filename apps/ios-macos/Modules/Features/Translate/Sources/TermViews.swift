import Domain
import FeatureKit
import MwonmalUI
import Routing
import SwiftUI

/// 용어 칩(Figma 51:2335 담음 = 초록 ✓, 51:2345 안 담음 = 노랑 +): 34 높이, 모서리 20, 14 SemiBold.
struct TermChip: View {
    let term: DetectedTerm
    let action: () -> Void
    @Environment(\.mwScale) private var scale

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6 * scale) {
                if term.inMyCards {
                    MwIconView(.check, color: MwColor.doneText)
                } else if term.isContextGuess {
                    Text(verbatim: "?").font(MwFont.pretendard(.extraBold, size: 14 * scale))
                } else {
                    Text(verbatim: "+").font(MwFont.pretendard(.extraBold, size: 14 * scale))
                }
                Text(verbatim: term.termKo).font(MwFont.pretendard(.semiBold, size: 14 * scale))
                if term.isContextGuess {
                    // 문맥 모델이 찾은 말: 확률을 같이 보여 준다(사전 말과 구분).
                    Text(verbatim: "\(Self.percent(term.confidence))%")
                        .font(MwFont.pretendard(.regular, size: 12 * scale))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(term.inMyCards ? MwColor.doneText : term.isContextGuess ? MwColor.textStrong : MwColor.jargonChipText)
            .padding(.horizontal, 11 * scale)
            .frame(minHeight: 34 * scale)
            .background(RoundedRectangle(cornerRadius: 20 * scale, style: .circular)
                .fill(term.inMyCards ? MwColor.doneFill : term.isContextGuess ? MwColor.chipFill : MwColor.jargonChipFill))
            .overlay {
                if term.isContextGuess {
                    RoundedRectangle(cornerRadius: 20 * scale, style: .circular)
                        .strokeBorder(MwColor.controlBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: term.isContextGuess
                ? fmt("translate.result.guessMeaning", term.termKo, Self.percent(term.confidence))
                : "\(term.termKo), \(term.plainKo)"))
        .accessibilityHint(Text("translate.result.termHint", bundle: .module))
        .accessibilityIdentifier(term.isContextGuess ? "result.guess" : "result.term")
    }

    static func percent(_ value: Double) -> Int {
        Int((min(max(value, 0), 1) * 100).rounded())
    }
}

/// 용어 시트: 이름·원어·쉬운 말·뜻·예문(GET /terms/{id}).
public struct TermSheet: View {
    let termId: Int64
    let repository: any TranslationRepository
    let onNotice: (LocalizedStringKey) -> Void
    @State private var detail: Phase<TermDetail> = .idle
    @Environment(AppRouter.self) private var router
    @Environment(\.mwScale) private var scale

    public init(termId: Int64, repository: any TranslationRepository, onNotice: @escaping (LocalizedStringKey) -> Void = { _ in }) {
        self.termId = termId
        self.repository = repository
        self.onNotice = onNotice
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MwGrabber().frame(maxWidth: .infinity).padding(.top, 10 * scale)
                HStack {
                    Spacer()
                    MwGlassCircleButton(.close, diameter: 32, label: "translate.result.close", bundle: .module) { router.dismissSheet() }
                        .accessibilityIdentifier("term.close")
                }
                .padding(.top, 8 * scale)
                switch detail {
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 160 * scale)
                case .failed:
                    Text("translate.error.generic", bundle: .module).mwFont(.regular, 15, lineHeight: 22)
                        .foregroundStyle(MwColor.textSecondary)
                case let .loaded(term):
                    loaded(term)
                }
            }
            .padding(.horizontal, 20 * scale)
            .padding(.bottom, 24 * scale)
        }
        .background(MwColor.canvas.ignoresSafeArea())
        .task {
            detail = .loading
            if let loaded = try? await repository.term(id: termId) {
                detail = .loaded(loaded)
            } else {
                detail = .failed(code: "UNKNOWN")
            }
        }
    }

    private func loaded(_ term: TermDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                Text(verbatim: term.termKo).mwFont(.bold, 28, lineHeight: 38, tracking: -0.56).foregroundStyle(MwColor.textPrimary)
                if let origin = term.originEn {
                    Text(verbatim: origin).mwFont(.regular, 15).foregroundStyle(MwColor.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text("translate.term.plainLabel", bundle: .module).mwFont(.bold, 12, lineHeight: 16).foregroundStyle(MwColor.accentFill)
                .padding(
                    .top,
                    12 * scale
                )
            Text(verbatim: term.plainKo).mwFont(.semiBold, 17, lineHeight: 25).foregroundStyle(MwColor.textPrimary).padding(.top, 4 * scale)
            Text(verbatim: term.meaning)
                .mwFont(.regular, 15, lineHeight: 22)
                .foregroundStyle(MwColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8 * scale)
            if !term.examples.isEmpty {
                MwSectionHeader(Text("translate.term.examples", bundle: .module)).padding(.top, 20 * scale)
                VStack(alignment: .leading, spacing: 8 * scale) {
                    ForEach(term.examples, id: \.self) { example in
                        VStack(alignment: .leading, spacing: 4 * scale) {
                            Text(verbatim: example.jargon).mwFont(.regular, 15, lineHeight: 22).foregroundStyle(MwColor.textPrimary)
                            Text(verbatim: "→ \(example.plain)").mwFont(.semiBold, 15, lineHeight: 22).foregroundStyle(MwColor.accentText)
                        }
                    }
                }
                .padding(16 * scale)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20 * scale, style: .circular).fill(MwColor.surface))
                .mwCardShadow(scale)
            }
            Button {
                onNotice("translate.result.cardsComingSoon")
            } label: {
                HStack(spacing: 8 * scale) {
                    MwIconView(.cards, color: MwColor.accentOnFill)
                    Text("translate.term.addCard", bundle: .module).font(MwFont.pretendard(.semiBold, size: 17 * scale))
                }
            }
            .buttonStyle(MwPrimaryButtonStyle(height: 52, radius: 18))
            .padding(.top, 20 * scale)
        }
    }
}
