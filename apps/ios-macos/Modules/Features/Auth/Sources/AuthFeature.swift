import AuthenticationServices
import FeatureKit
import MwonmalUI
import Routing
import SwiftUI

/// AuthFeature 모듈(ADR-0016). 서버·Keychain을 모르고, 받은 Apple code를 Composition에 넘긴다.
public enum AuthFeatureModule {
    public static let name = "AuthFeature"
}

/// Apple 버튼이 돌려준 결과를 화면 밖으로 넘기는 값.
public enum AppleSignInOutcome: Equatable, Sendable {
    case code(String)
    /// 사용자가 닫음 — 에러를 보여 주지 않는다.
    case cancelled
    case failed
}

/// S-01의 Apple 외 로그인. 계약 enum에는 있지만 서버는 v1.0에서 400을 낸다(ADR-0014, #90).
public enum OtherSignInProvider: String, CaseIterable, Sendable {
    case kakao
    case google
}

/// S-01 로그인(Figma 51:468).
///
/// 화면 높이가 기기마다 달라서 고정 배치 대신 이렇게 나눈다.
/// - 아래 패널(제목·부제·버튼 3개)은 글자 크기에 맞는 제 높이를 먼저 갖는다.
/// - 히어로가 남은 높이를 갖되, Figma 비율(너비 × 470/393)보다 커지지 않는다. 남으면 제목과 버튼 사이가 벌어진다.
/// - 아주 큰 글자처럼 다 안 들어가면 히어로는 최소 높이로 줄고 화면이 스크롤된다.
public struct AuthRootView: View {
    let isSigningIn: Bool
    let errorMessage: String?
    let onApple: (AppleSignInOutcome) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var localError = false
    @State private var pendingProvider: OtherSignInProvider?

    public init(isSigningIn: Bool = false, errorMessage: String? = nil, onApple: @escaping (AppleSignInOutcome) -> Void = { _ in }) {
        self.isSigningIn = isSigningIn
        self.errorMessage = errorMessage
        self.onApple = onApple
    }

    public var body: some View {
        GeometryReader { proxy in
            ScrollView {
                // 히어로는 상태 바 밑까지 그린다 → 화면 전체 높이 = 안전 영역 안 높이 + 위 여백.
                HeroPanelLayout(screenHeight: proxy.size.height + proxy.safeAreaInsets.top) {
                    MwIllustration.loginHero
                    panel
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea(edges: .top)
        }
        .background(MwColor.brandPanel.ignoresSafeArea())
    }

    /// 히어로 높이. Figma 비율(너비 × 470/393)보다 크지 않게, 너무 작아지지도 않게.
    static func heroHeight(width: CGFloat, available: CGFloat) -> CGFloat {
        let natural = width * 470 / 393
        let minimum = min(natural, 220)
        return min(natural, max(available, minimum))
    }

    // MARK: - 패널

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                title
                Text("auth.signIn.subtitle", bundle: .module)
                    .font(.body)
                    .foregroundStyle(MwColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 22)
            Spacer(minLength: 24)
            VStack(spacing: 10) {
                message
                appleButton
                OtherSignInButton(provider: .kakao) { pendingProvider = .kakao }
                OtherSignInButton(provider: .google) { pendingProvider = .google }
            }
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
    }

    /// "뭔말인교?" — 물음표만 강조색. VoiceOver는 한 단어로 읽는다.
    private var title: some View {
        (Text("auth.signIn.wordmark", bundle: .module).foregroundStyle(MwColor.textPrimary)
            + Text(verbatim: "?").foregroundStyle(MwColor.accentText))
            .font(.title.weight(.heavy))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var message: some View {
        if let provider = pendingProvider {
            Label(String(localized: String.LocalizationValue(Self.comingSoonKey(provider)), bundle: .module), systemImage: "clock")
                .font(.footnote)
                .foregroundStyle(MwColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
        } else if let text = errorMessage ?? (localError ? String(localized: "auth.signIn.failed", bundle: .module) : nil) {
            Label(text, systemImage: "exclamationmark.circle")
                .font(.footnote)
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

    /// 공식 버튼(HIG). 문구 "Apple로 계속하기"·검은 바탕·로고가 Figma와 같다.
    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = []
            localError = false
            pendingProvider = nil
        } onCompletion: { result in
            let outcome = Self.outcome(result)
            localError = outcome == .failed
            onApple(outcome)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        // 공식 버튼은 외관이 바뀌어도 스타일을 다시 그리지 않는다 → 모드가 바뀌면 새로 만든다.
        .id(colorScheme)
        // 공식 버튼은 글자 크기를 따라 커지지 않는다 → 높이를 Figma 값으로 둔다.
        .frame(height: OtherSignInButton.height)
        .clipShape(RoundedRectangle(cornerRadius: OtherSignInButton.cornerRadius, style: .continuous))
        .disabled(isSigningIn)
        .opacity(isSigningIn ? 0.6 : 1)
        .overlay {
            if isSigningIn {
                ProgressView()
            }
        }
    }

    static func outcome(_ result: Result<ASAuthorization, any Error>) -> AppleSignInOutcome {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.authorizationCode,
                  let code = String(data: data, encoding: .utf8), !code.isEmpty else { return .failed }
            return .code(code)
        case let .failure(error):
            return (error as? ASAuthorizationError)?.code == .canceled ? .cancelled : .failed
        }
    }
}

/// 히어로 + 패널을 한 번에 배치한다(상태로 높이를 재서 다시 그리는 왕복이 없다).
/// 1. 패널에게 글자 크기 기준 제 높이를 묻는다.
/// 2. 남은 높이를 히어로에 준다(`AuthRootView.heroHeight`로 상·하한).
/// 3. 그래도 남으면 패널이 받아 제목과 버튼 사이가 벌어진다. 모자라면 전체가 화면보다 길어져 스크롤된다.
struct HeroPanelLayout: Layout {
    let screenHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let (hero, panel) = heights(width: width, subviews: subviews)
        return CGSize(width: width, height: hero + panel)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard subviews.count == 2 else { return }
        let (hero, panel) = heights(width: bounds.width, subviews: subviews)
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: hero))
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + hero),
            proposal: ProposedViewSize(width: bounds.width, height: panel)
        )
    }

    private func heights(width: CGFloat, subviews: Subviews) -> (hero: CGFloat, panel: CGFloat) {
        guard subviews.count == 2 else { return (0, 0) }
        let panelIdeal = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        let hero = AuthRootView.heroHeight(width: width, available: screenHeight - panelIdeal)
        return (hero, max(panelIdeal, screenHeight - hero))
    }
}

/// 카카오·Google 버튼(Figma 51:547·51:552). 색·로고는 각 회사 브랜드 가이드 값이라 토큰에 넣지 않는다.
/// - 카카오: 바탕 #FEE500, 글자 검정 85% (모드와 무관하게 같다)
/// - Google: 라이트는 흰 바탕·#1F1F1F, 다크는 #131314 바탕·#E3E3E3·#8E918F 테두리
struct OtherSignInButton: View {
    static let height: CGFloat = 56
    static let cornerRadius: CGFloat = 18

    let provider: OtherSignInProvider
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    /// 브랜드 로고(Figma 18pt)도 글자 크기를 따라 커진다.
    @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 18

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(iconName, bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityHidden(true)
                Text(titleKey, bundle: .module)
                    .font(.headline)
                    .foregroundStyle(foreground)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: Self.height)
            .background(background, in: shape)
            .overlay { shape.strokeBorder(border, lineWidth: 1) }
            // Figma 51:552: 밝은 모드 Google 버튼은 테두리 대신 옅은 그림자 두 겹.
            .shadow(color: liftShadow.opacity(0.04), radius: 0, y: 1)
            .shadow(color: liftShadow.opacity(0.06), radius: 1.5, y: 2)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    private var iconName: String {
        switch provider {
        case .kakao: "KakaoSymbol"
        case .google: "GoogleG"
        }
    }

    private var titleKey: LocalizedStringKey {
        switch provider {
        case .kakao: "auth.signIn.kakao"
        case .google: "auth.signIn.google"
        }
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var background: Color {
        switch provider {
        case .kakao: Color(brandHex: 0xFEE500)
        case .google: isDark ? Color(brandHex: 0x131314) : .white
        }
    }

    private var foreground: Color {
        switch provider {
        case .kakao: Color.black.opacity(0.85)
        case .google: Color(brandHex: isDark ? 0xE3E3E3 : 0x1F1F1F)
        }
    }

    private var liftShadow: Color {
        provider == .google && !isDark ? Color(brandHex: 0x5A3C1E) : .clear
    }

    private var border: Color {
        switch provider {
        case .kakao: .clear
        // 밝은 모드는 Figma대로 그림자만, 고대비 설정이면 경계를 선으로 보여 준다.
        case .google: isDark ? Color(brandHex: 0x8E918F) : (contrast == .increased ? MwColor.controlBorder : .clear)
        }
    }
}

private extension Color {
    /// 다른 회사 브랜드 색 전용(카카오·Google 가이드). 앱 자체 색은 MwColor 토큰만 쓴다.
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
