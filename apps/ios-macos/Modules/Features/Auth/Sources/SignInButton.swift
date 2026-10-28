import MwonmalUI
import SwiftUI

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
        .accessibilityIdentifier("signin.\(kind)")
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
