import MwonmalUI
import SwiftUI

// 그림 위 글자 카드(Figma 51:238 · 51:357 · 51:383). 그림의 일부라 그림과 같은 배율(무대 배율)로 커지고 작아지며,
// 글자 크기 설정을 따르지 않고 VoiceOver에서도 읽지 않는다(뜻은 아래 본문이 말한다).

/// O-2 "붙여넣기 · 캡처 · 회의 녹음" 칩(51:238, 무대 20,420 192×37). 말풍선이 풀린 뒤 떠오른다.
struct PasteSourcesChip: View {
    let geometry: MwStageGeometry
    let isIn: Bool

    static let frame = CGRect(x: 20, y: 420, width: 192, height: 37)
    /// 붙여넣기 아이콘(51:239).
    static let icon = CGSize(width: 15.422, height: 18.766)

    var body: some View {
        let rect = geometry.rect(Self.frame)
        let unit = geometry.scale
        HStack(spacing: 8 * unit) {
            MwIllustration.pasteIcon
                .frame(width: Self.icon.width * unit, height: Self.icon.height * unit)
            Text("onboarding.page2.sources", bundle: .module)
                .font(MwFont.pretendard(.bold, size: 13 * unit))
                .foregroundStyle(MwColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12 * unit)
        .frame(minWidth: rect.width, minHeight: rect.height)
        .fixedSize()
        .background(OnboardingGlass(cornerRadius: 18 * unit))
        .offset(x: rect.minX, y: rect.minY)
        .mwRise(isIn, baseDelay: 1.1)
        .accessibilityHidden(true)
    }
}

/// O-3 알림 두 장(51:357 무대 16,104 361×64 · 51:383 28,176 337×64). 위에서 차례로 내려온다(알림이 오는 것처럼).
struct NoticeCards: View {
    let geometry: MwStageGeometry
    let isIn: Bool

    struct Notice {
        let frame: CGRect
        let title: LocalizedStringKey
        let time: String
        let body: LocalizedStringKey
    }

    /// 앱 아이콘 타일과 그 안 로고(51:358·51:359).
    static let tile: CGFloat = 36
    static let logo: CGFloat = 30

    static let notices = [
        Notice(
            frame: CGRect(x: 16, y: 104, width: 361, height: 64),
            title: "onboarding.page3.noticeDue.title",
            time: "17:00",
            body: "onboarding.page3.noticeDue.body"
        ),
        Notice(
            frame: CGRect(x: 28, y: 176, width: 337, height: 64),
            title: "onboarding.page3.noticeReview.title",
            time: "18:00",
            body: "onboarding.page3.noticeReview.body"
        ),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.notices.enumerated()), id: \.offset) { order, notice in
                card(notice)
                    .mwSlideIn(isIn, from: CGSize(width: 0, height: -36 * geometry.scale), delay: 0.45 + Double(order) * 0.32)
                    .mwFloat(isIn, amplitude: 2 * geometry.scale, period: 4.2 + Double(order) * 0.7, phase: 1.4 + Double(order) * 0.5)
            }
        }
        .accessibilityHidden(true)
    }

    private func card(_ notice: Notice) -> some View {
        let rect = geometry.rect(notice.frame)
        let unit = geometry.scale
        return HStack(spacing: 10 * unit) {
            appTile(unit: unit)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(notice.title, bundle: .module)
                        .font(MwFont.pretendard(.bold, size: 13 * unit))
                        .foregroundStyle(MwColor.textPrimary)
                    Spacer(minLength: 4 * unit)
                    Text(verbatim: notice.time)
                        .font(MwFont.pretendard(.regular, size: 12 * unit))
                        .foregroundStyle(MwColor.textSecondary)
                }
                Text(notice.body, bundle: .module)
                    .font(MwFont.pretendard(.regular, size: 13 * unit))
                    .foregroundStyle(MwColor.textPrimary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14 * unit)
        .frame(width: rect.width, alignment: .leading)
        .frame(minHeight: rect.height)
        .background(OnboardingGlass(cornerRadius: 22 * unit))
        .offset(x: rect.minX, y: rect.minY)
    }

    /// 앱 아이콘 타일(51:358): 36×36, 모서리 8.1, 160° 그라데이션 #FBEBC0 → #F7F3EC, 안쪽 테두리 6%, 로고 30.
    private func appTile(unit: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8.1 * unit, style: .circular)
        return MwIllustration.brandLogo
            .frame(width: Self.logo * unit, height: Self.logo * unit)
            .frame(width: Self.tile * unit, height: Self.tile * unit)
            .background(shape.fill(OnboardingGlass.tileGradient))
            .overlay(shape.strokeBorder(MwColor.textPrimary.opacity(0.06), lineWidth: 1))
            .clipShape(shape)
    }
}

/// 그림 위 유리 카드 면(배경 흐림 22 + 흰 74% + 흰 75% 테두리 + 0 10 30 그림자 14%).
struct OnboardingGlass: View {
    let cornerRadius: CGFloat
    @Environment(\.mwScale) private var scale

    /// 앱 아이콘 타일 그라데이션(Figma 51:358). 앱 아이콘과 같은 색이라 토큰이 아니라 그림 값이다.
    static let tileGradient = LinearGradient(
        colors: [Color(red: 251 / 255, green: 235 / 255, blue: 192 / 255), Color(red: 247 / 255, green: 243 / 255, blue: 236 / 255)],
        startPoint: UnitPoint(x: 0.33, y: 0.03),
        endPoint: UnitPoint(x: 0.67, y: 0.97)
    )

    var body: some View {
        // MwGlassBackground는 모서리를 mwScale로 곱한다 → 무대 배율로 이미 곱한 값을 되돌려 넘긴다.
        MwGlassBackground(cornerRadius: cornerRadius / max(scale, 0.01))
            .mwGlassShadow(scale)
    }
}
