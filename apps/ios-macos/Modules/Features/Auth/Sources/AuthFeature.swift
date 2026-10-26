import FeatureKit
import Routing
import SwiftUI

/// AuthFeature 모듈(ADR-0016). 다른 Feature를 모르고, 로그인 동작은 Composition이 넘긴다.
public enum AuthFeatureModule {
    public static let name = "AuthFeature"
}

/// S-01 자리표시. 디자인(Figma 51:468)대로 만드는 것은 Day 5(#9).
public struct AuthRootView: View {
    let isSigningIn: Bool
    let errorMessage: String?
    let onSignIn: () -> Void

    public init(isSigningIn: Bool = false, errorMessage: String? = nil, onSignIn: @escaping () -> Void = {}) {
        self.isSigningIn = isSigningIn
        self.errorMessage = errorMessage
        self.onSignIn = onSignIn
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("auth.root.placeholder", bundle: .module).font(.title2.bold())
            Button(action: onSignIn) {
                Text("auth.signIn.apple", bundle: .module)
            }
            .disabled(isSigningIn)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
