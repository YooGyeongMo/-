import SwiftUI

/// 해석 결과를 기다리는 자리(A-06 결과가 오기 전). 결과 카드 두 장과 같은 모양의 빈 칸이 천천히 숨 쉬고(`decodingPulse`),
/// 아래에 안내 글이 있다. 동작 줄이기면 숨 쉬지 않고 진행 표시가 함께 나온다(ADR-0012 §4-2).
/// 문구는 앱이 넘긴다(SDK 규칙 2). VoiceOver는 안내 글 하나로 읽는다.
public struct MwDecodingPlaceholder: View {
    let label: Text
    @Environment(\.mwScale) private var scale
    @Environment(\.mwReduceMotion) private var reduceMotion

    /// 빈 줄 굵기·간격과 카드 모서리(결과 카드 51:2232·51:2263과 같은 모서리 24).
    static let barThickness: CGFloat = 10
    static let cardRadius: CGFloat = 24

    public init(_ label: Text) {
        self.label = label
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            cards.mwDecodingPulse(isActive: true)
            HStack(spacing: 8 * scale) {
                if reduceMotion {
                    ProgressView()
                }
                label
                    .mwFont(.regular, 14, lineHeight: 20)
                    .foregroundStyle(MwColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4 * scale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            VStack(alignment: .leading, spacing: 0) {
                bars([0.22, 0.95, 0.7])
                // swiftlint:disable:next no_fixed_height - 1pt 구분선(결과 카드와 같은 선, 글자 없음)
                Rectangle().fill(MwColor.separator).frame(height: 1).padding(.vertical, 14 * scale)
                bars([0.22, 0.85])
            }
            .padding(.horizontal, 18 * scale)
            .padding(.vertical, 18 * scale)
            .background(RoundedRectangle(cornerRadius: Self.cardRadius * scale, style: .circular).fill(MwColor.surface))
            .mwRaisedShadow(scale)
            bars([0.3, 0.9])
                .padding(16 * scale)
                .background(RoundedRectangle(cornerRadius: Self.cardRadius * scale, style: .circular).fill(MwColor.surfaceMuted))
                .mwRaisedShadow(scale)
        }
    }

    /// 글자 줄 대신 둥근 막대. 비율은 카드 너비 기준.
    private func bars(_ fractions: [CGFloat]) -> some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            ForEach(Array(fractions.enumerated()), id: \.offset) { _, fraction in
                GeometryReader { proxy in
                    Capsule().fill(MwColor.separator).frame(width: proxy.size.width * fraction)
                }
                .frame(height: Self.barThickness * scale)
            }
        }
    }
}

#if DEBUG
    #Preview("해석 대기") {
        MwDecodingPlaceholder(Text(verbatim: "해석하고 있어요"))
            .padding(20)
            .background(MwColor.canvas)
    }

    #Preview("해석 대기 · 동작 줄이기") {
        MwDecodingPlaceholder(Text(verbatim: "해석하고 있어요"))
            .padding(20)
            .background(MwColor.canvas)
            .mwMotionTheme(.reduced)
    }
#endif
