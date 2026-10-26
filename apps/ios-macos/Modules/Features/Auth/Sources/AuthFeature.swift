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

/// S-01 로그인(Figma 51:468). v1.0은 Apple만(ADR-0013·0014) — 카카오·Google 버튼은 #90.
/// 레이아웃: 위는 일러스트(상태 바 아래까지 확장), 아래는 브랜드 패널(제목·부제·공식 Apple 버튼).
public struct AuthRootView: View {
    let isSigningIn: Bool
    let errorMessage: String?
    let onApple: (AppleSignInOutcome) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var localError = false

    public init(isSigningIn: Bool = false, errorMessage: String? = nil, onApple: @escaping (AppleSignInOutcome) -> Void = { _ in }) {
        self.isSigningIn = isSigningIn
        self.errorMessage = errorMessage
        self.onApple = onApple
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Figma 비율(393×470) 그대로 화면 너비에 맞춘다 → 어떤 기기에서도 해·언덕·인물이 잘리지 않는다.
            // 아주 큰 글자에서 공간이 모자라면 일러스트가 먼저 줄어든다(패널 글자가 우선).
            MwIllustration.loginHero
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
            panel
        }
        .background(MwColor.brandPanel.ignoresSafeArea())
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
            Text("auth.signIn.subtitle", bundle: .module)
                .font(.body)
                .foregroundStyle(MwColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 24)
            if let message = errorMessage ?? (localError ? String(localized: "auth.signIn.failed", bundle: .module) : nil) {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(MwColor.urgentText)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            appleButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    /// "뭔말인교?" — 물음표만 강조색. VoiceOver는 한 단어로 읽는다.
    private var title: some View {
        (Text("auth.signIn.wordmark", bundle: .module).foregroundStyle(MwColor.textPrimary)
            + Text(verbatim: "?").foregroundStyle(MwColor.accentText))
            .font(.largeTitle.bold())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = []
            localError = false
        } onCompletion: { result in
            let outcome = Self.outcome(result)
            localError = outcome == .failed
            onApple(outcome)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        // 공식 버튼은 외관이 바뀌어도 스타일을 다시 그리지 않는다 → 모드가 바뀌면 새로 만든다.
        .id(colorScheme)
        .frame(minHeight: 50, maxHeight: 56)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

#if DEBUG
    #Preview("S-01") { AuthRootView() }
    #Preview("S-01 오류") { AuthRootView(errorMessage: "로그인에 실패했어요. 다시 시도해 주세요.") }
#endif
