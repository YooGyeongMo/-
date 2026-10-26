import FeatureKit
import MwonmalUI
import Routing
import SwiftUI

/// AuthFeature 모듈(ADR-0016). 서버·Keychain을 모르고, 버튼이 눌렸다는 사실만 Composition에 넘긴다.
public enum AuthFeatureModule {
    public static let name = "AuthFeature"
}

/// S-01의 Apple 외 로그인. 계약 enum에는 있지만 서버는 v1.0에서 400을 낸다(ADR-0014, #90).
public enum OtherSignInProvider: String, CaseIterable, Sendable {
    case kakao
    case google
}

/// S-01 수치(Figma 51:468, 393×852pt). 화면에 쓰는 모든 크기는 여기 값 × 기기 배율이다.
nonisolated enum S01Spec {
    static let frame = CGSize(width: 393, height: 852)
    static let heroHeight: CGFloat = 470 // 51:469
    static let sideInset: CGFloat = 20 // 51:533·51:541 px-20
    static let contentWidth: CGFloat = 353
    static let titleTop: CGFloat = 22 // 51:533 pt-22
    static let titleSize: CGFloat = 28 // 51:535 Pretendard ExtraBold
    static let titleLineHeight: CGFloat = 38
    static let titleTracking: CGFloat = -0.56
    static let subtitleTop: CGFloat = 4 // 51:537 pt-4
    static let subtitleSize: CGFloat = 17 // 51:538 Pretendard Regular
    static let subtitleLineHeight: CGFloat = 26
    static let buttonsBottom: CGFloat = 42 // 51:541 pb-42 (홈 인디케이터 영역 포함, 화면 아래 끝 기준)
    static let buttonHeight: CGFloat = 56
    static let buttonGap: CGFloat = 10
    static let buttonRadius: CGFloat = 18
    static let buttonIconGap: CGFloat = 8
    static let buttonTextSize: CGFloat = 17 // Pretendard SemiBold
    static let paperGrain: CGFloat = 160 // 51:561
    /// Figma에 없는 값: 화면이 낮을 때(SE 등) 부제와 버튼 사이 최소 간격, 히어로 최소 높이.
    static let minimumGap: CGFloat = 24
    static let minimumHero: CGFloat = 220

    /// 기기 배율. 너비 기준(현재 iPhone 라인업은 화면 비율이 2.16~2.17로 Figma 393×852와 같다).
    static func scale(forWidth width: CGFloat) -> CGFloat {
        width > 0 ? width / frame.width : 1
    }
}

/// S-01 로그인(Figma 51:468).
///
/// Figma 393×852를 기기 너비에 맞춰 같은 비율로 키우거나 줄인다(모든 pt × 너비/393).
/// 세로로 남거나 모자라는 높이는 Figma의 늘어나는 칸(51:533, 제목 아래)이 받는다.
/// 그래도 모자라면(SE처럼 낮은 화면) 히어로가 줄고, 아주 큰 글자에서는 스크롤된다.
public struct AuthRootView: View {
    let isSigningIn: Bool
    let errorMessage: String?
    let onApple: () -> Void

    @State private var pendingProvider: OtherSignInProvider?
    /// 글자 크기 설정 배수. 기본(큰 글씨 끔)에서 1 → Figma와 같은 크기.
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1

    public init(isSigningIn: Bool = false, errorMessage: String? = nil, onApple: @escaping () -> Void = {}) {
        self.isSigningIn = isSigningIn
        self.errorMessage = errorMessage
        self.onApple = onApple
    }

    public var body: some View {
        GeometryReader { proxy in
            let scale = S01Spec.scale(forWidth: proxy.size.width)
            ScrollView {
                S01Layout(screenHeight: proxy.size.height, scale: scale) {
                    MwIllustration.loginHero
                    title(scale: scale)
                    subtitle(scale: scale)
                    buttons(scale: scale)
                }
                .overlay(alignment: .topLeading) {
                    MwIllustration.paperGrain
                        .frame(width: S01Spec.paperGrain * scale, height: S01Spec.paperGrain * scale)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .ignoresSafeArea()
        .background(MwColor.brandPanel)
    }

    // MARK: - 글자

    private func font(_ weight: MwFont.Weight, _ size: CGFloat, _ scale: CGFloat) -> Font {
        MwFont.pretendard(weight, size: size * scale * typeScale)
    }

    /// "뭔말인교?" — 물음표만 Figma 파랑(#2F6FD6). VoiceOver는 한 단어로 읽는다.
    private func title(scale: CGFloat) -> some View {
        (Text("auth.signIn.wordmark", bundle: .module).foregroundStyle(MwColor.textPrimary)
            + Text(verbatim: "?").foregroundStyle(MwColor.accentFill))
            .font(font(.extraBold, S01Spec.titleSize, scale))
            .tracking(S01Spec.titleTracking * scale * typeScale)
            .lineSpacing(Self.extraLeading(lineHeight: S01Spec.titleLineHeight, size: S01Spec.titleSize) * scale * typeScale)
            .frame(minHeight: S01Spec.titleLineHeight * scale * typeScale)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func subtitle(scale: CGFloat) -> some View {
        Text("auth.signIn.subtitle", bundle: .module)
            .font(font(.regular, S01Spec.subtitleSize, scale))
            .foregroundStyle(MwColor.textSecondary)
            .lineSpacing(Self.extraLeading(lineHeight: S01Spec.subtitleLineHeight, size: S01Spec.subtitleSize) * scale * typeScale)
            .frame(minHeight: S01Spec.subtitleLineHeight * scale * typeScale)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// CSS line-height와 글꼴 기본 줄 높이(Pretendard ≈ 1.193em)의 차이. 여러 줄일 때 줄 간격으로 쓴다.
    static func extraLeading(lineHeight: CGFloat, size: CGFloat) -> CGFloat {
        max(lineHeight - size * 1.193, 0)
    }

    // MARK: - 버튼

    private func buttons(scale: CGFloat) -> some View {
        VStack(spacing: S01Spec.buttonGap * scale) {
            SignInButton(kind: .apple, scale: scale, typeScale: typeScale, isBusy: isSigningIn) {
                pendingProvider = nil
                onApple()
            }
            .disabled(isSigningIn)
            SignInButton(kind: .kakao, scale: scale, typeScale: typeScale) { pendingProvider = .kakao }
            SignInButton(kind: .google, scale: scale, typeScale: typeScale) { pendingProvider = .google }
        }
        // 안내·오류 문구는 Figma에 없다 → 배치를 밀지 않도록 버튼 위 빈 칸에 겹쳐 띄운다.
        .overlay(alignment: .top) {
            message(scale: scale)
                .alignmentGuide(.top) { $0[.bottom] + 12 * scale }
        }
    }

    @ViewBuilder private func message(scale: CGFloat) -> some View {
        if let provider = pendingProvider {
            Label(String(localized: String.LocalizationValue(Self.comingSoonKey(provider)), bundle: .module), systemImage: "clock")
                .font(font(.regular, 13, scale))
                .foregroundStyle(MwColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
        } else if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle")
                .font(font(.regular, 13, scale))
                .foregroundStyle(MwColor.urgentText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    static func comingSoonKey(_ provider: OtherSignInProvider) -> String {
        switch provider {
        case .kakao: "auth.signIn.kakao.comingSoon"
        case .google: "auth.signIn.google.comingSoon"
        }
    }
}

/// S-01 배치. Figma 좌표를 배율만 곱해 그대로 놓는다.
/// - 히어로: 위 0, 높이 470
/// - 제목: 히어로 아래 22, 부제: 제목 아래 4
/// - 버튼 묶음: 화면 아래 끝에서 42 위
/// 남는 높이는 부제와 버튼 사이가 받는다(Figma 51:533 flex). 최소 간격 24가 안 나오면 히어로를 220까지 줄이고,
/// 그래도 모자라면 전체 높이가 화면보다 커져 스크롤된다.
struct S01Layout: Layout {
    let screenHeight: CGFloat
    let scale: CGFloat

    struct Frames: Equatable {
        var hero: CGRect
        var title: CGRect
        var subtitle: CGRect
        var buttons: CGRect
        var height: CGFloat
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? S01Spec.frame.width * scale
        return CGSize(width: width, height: frames(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard subviews.count == 4 else { return }
        let frames = frames(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, [frames.hero, frames.title, frames.subtitle, frames.buttons]) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> Frames {
        guard subviews.count == 4 else { return Frames(hero: .zero, title: .zero, subtitle: .zero, buttons: .zero, height: 0) }
        let content = width - S01Spec.sideInset * 2 * scale
        func height(_ index: Int) -> CGFloat {
            subviews[index].sizeThatFits(ProposedViewSize(width: content, height: nil)).height
        }
        let measured = Measured(title: height(1), subtitle: height(2), buttons: height(3))
        return Self.frames(width: width, screenHeight: screenHeight, scale: scale, measured: measured)
    }

    /// 측정값만으로 위치를 계산한다(테스트에서 직접 부른다).
    /// 글자 크기에 따라 달라지는 높이(제목·부제·버튼 묶음).
    struct Measured {
        var title: CGFloat
        var subtitle: CGFloat
        var buttons: CGFloat
    }

    static func frames(width: CGFloat, screenHeight: CGFloat, scale: CGFloat, measured: Measured) -> Frames {
        let (title, subtitle, buttons) = (measured.title, measured.subtitle, measured.buttons)
        let inset = S01Spec.sideInset * scale
        let content = width - inset * 2
        let textBlock = S01Spec.titleTop * scale + title + S01Spec.subtitleTop * scale + subtitle
        let bottomBlock = buttons + S01Spec.buttonsBottom * scale
        let naturalHero = S01Spec.heroHeight * scale
        let room = screenHeight - textBlock - S01Spec.minimumGap * scale - bottomBlock
        let hero = min(naturalHero, max(room, min(S01Spec.minimumHero * scale, naturalHero)))
        let height = max(screenHeight, hero + textBlock + S01Spec.minimumGap * scale + bottomBlock)
        let titleY = hero + S01Spec.titleTop * scale
        let subtitleY = titleY + title + S01Spec.subtitleTop * scale
        return Frames(
            hero: CGRect(x: 0, y: 0, width: width, height: hero),
            title: CGRect(x: inset, y: titleY, width: content, height: title),
            subtitle: CGRect(x: inset, y: subtitleY, width: content, height: subtitle),
            buttons: CGRect(x: inset, y: height - S01Spec.buttonsBottom * scale - buttons, width: content, height: buttons),
            height: height
        )
    }
}

/// 로그인 버튼 3종(Figma 51:542·51:547·51:552). 색·로고는 각 회사 브랜드 가이드 값이라 앱 토큰에 넣지 않는다.
/// - Apple: 검정 바탕·흰 글자(다크 모드는 반대, Apple HIG). Apple은 직접 만든 버튼도 허용한다(HIG "Sign in with Apple").
/// - 카카오: #FEE500, 글자 검정 85%
/// - Google: 흰 바탕·#1F1F1F·옅은 그림자 두 겹. 다크는 #131314·#E3E3E3·#8E918F 테두리, 고대비 설정이면 테두리
struct SignInButton: View {
    enum Kind {
        case apple
        case kakao
        case google
    }

    let kind: Kind
    let scale: CGFloat
    let typeScale: CGFloat
    var isBusy = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            HStack(spacing: S01Spec.buttonIconGap * scale) {
                icon
                    .frame(width: iconSize.width * scale * typeScale, height: iconSize.height * scale * typeScale)
                    .accessibilityHidden(true)
                Text(titleKey, bundle: .module)
                    .font(MwFont.pretendard(.semiBold, size: S01Spec.buttonTextSize * scale * typeScale))
                    .foregroundStyle(foreground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(isBusy ? 0 : 1)
            .overlay {
                if isBusy {
                    ProgressView().tint(foreground)
                }
            }
            .padding(.horizontal, 16 * scale)
            .frame(maxWidth: .infinity, minHeight: S01Spec.buttonHeight * scale)
            .background(background, in: shape)
            .overlay { shape.strokeBorder(border, lineWidth: 1) }
            .shadow(color: liftShadow.opacity(0.04), radius: 0, y: 1 * scale)
            .shadow(color: liftShadow.opacity(0.06), radius: 1.5 * scale, y: 2 * scale)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    private var shape: RoundedRectangle {
        // Figma(CSS border-radius)는 원형 모서리다. iOS 기본인 연속 곡선(.continuous)을 쓰면 모서리 픽셀이 달라진다.
        RoundedRectangle(cornerRadius: S01Spec.buttonRadius * scale, style: .circular)
    }

    /// Figma 아이콘 크기(51:543·51:548·51:553).
    private var iconSize: CGSize {
        switch kind {
        case .apple: CGSize(width: 14.8906, height: 18.2974)
        case .kakao: CGSize(width: 18.2817, height: 17.2188)
        case .google: CGSize(width: 18, height: 18)
        }
    }

    @ViewBuilder private var icon: some View {
        switch kind {
        case .apple: Image("AppleLogo", bundle: .module).resizable().foregroundStyle(foreground)
        case .kakao: Image("KakaoSymbol", bundle: .module).resizable()
        case .google: Image("GoogleG", bundle: .module).resizable()
        }
    }

    private var titleKey: LocalizedStringKey {
        switch kind {
        case .apple: "auth.signIn.apple"
        case .kakao: "auth.signIn.kakao"
        case .google: "auth.signIn.google"
        }
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var background: Color {
        switch kind {
        case .apple: isDark ? .white : .black
        case .kakao: Color(brandHex: 0xFEE500)
        case .google: isDark ? Color(brandHex: 0x131314) : .white
        }
    }

    private var foreground: Color {
        switch kind {
        case .apple: isDark ? .black : .white
        case .kakao: Color.black.opacity(0.85)
        case .google: Color(brandHex: isDark ? 0xE3E3E3 : 0x1F1F1F)
        }
    }

    private var liftShadow: Color {
        kind == .google && !isDark ? Color(brandHex: 0x5A3C1E) : .clear
    }

    private var border: Color {
        guard kind == .google else { return .clear }
        if isDark {
            return Color(brandHex: 0x8E918F)
        }
        return contrast == .increased ? MwColor.controlBorder : .clear
    }
}

private extension Color {
    /// 다른 회사 브랜드 색 전용(Apple·카카오·Google 가이드). 앱 자체 색은 MwColor 토큰만 쓴다.
    init(brandHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

#if DEBUG
    #Preview("S-01") { AuthRootView() }
    #Preview("S-01 오류") { AuthRootView(errorMessage: "로그인에 실패했어요. 다시 시도해 주세요.") }
#endif
