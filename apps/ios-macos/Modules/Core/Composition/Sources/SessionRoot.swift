import AuthFeature
import FeatureKit
import MwonmalUI
import OnboardingFeature
import SwiftUI

/// 세션 상태에 따라 온보딩·로그인 화면과 탭 루트를 고른다. 앱을 켤 때마다 시작 연출(ADR-0024)이 한 번 덮는다.
public struct SessionRootView: View {
    @ViewModelState private var session: AppSession
    /// 온보딩(O-1~O-3)을 끝까지 보거나 건너뛰었는지. 처음 켤 때 한 번만 보인다.
    @AppStorage(OnboardingGate.seenKey) private var onboardingSeen = false
    @Environment(\.mwReduceMotion) private var reduceMotion

    /// `.live()`(Keychain·URLSession·API 조립)는 앱 수명에 한 번만 돈다 — App 의 body 가 다시 불려도.
    public init(session: @autoclosure @escaping () -> AppSession = .live()) {
        _session = ViewModelState(wrappedValue: session())
        _ = OnboardingGate.resetIfRequested
    }

    public var body: some View {
        MwLaunchSplash {
            Group {
                switch session.state {
                case .none:
                    ProgressView()
                case .signedOut:
                    if onboardingSeen {
                        AuthRootView(isSigningIn: session.isSigningIn, errorMessage: session.lastError.flatMap(\.userMessage)) {
                            session.signInWithApple()
                        }
                        .transition(.mwDive(forward: true, reduceMotion: reduceMotion))
                    } else {
                        OnboardingView {
                            withAnimation(MwMotion.page(reduceMotion: reduceMotion)) { onboardingSeen = true }
                        }
                        .transition(.mwDive(forward: true, reduceMotion: reduceMotion))
                    }
                case .signedIn, .unverified:
                    AppRootView(session: session)
                }
            }
        }
        .mwScaledToWidth()
        .task { await session.start().value }
    }
}

/// 온보딩을 봤는지 저장하는 키와 개발용 초기화.
enum OnboardingGate {
    static let seenKey = "MWOnboardingSeen"

    /// Debug + 실행 인자 `-MWResetOnboarding`: 시작할 때 "봤음"을 지운다(E2E·QA가 온보딩부터 보게).
    /// 앱 수명에 한 번만 돈다(루트 뷰가 다시 만들어져도 다 본 온보딩을 또 지우지 않게).
    static let resetIfRequested: Void = {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-MWResetOnboarding") {
                UserDefaults.standard.removeObject(forKey: seenKey)
            }
        #endif
    }()
}
