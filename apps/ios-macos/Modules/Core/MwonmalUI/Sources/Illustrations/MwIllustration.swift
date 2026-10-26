import SwiftUI

/// 일러스트(장식). VoiceOver에서는 읽지 않는다.
public enum MwIllustration {
    /// S-01 히어로(Figma 51:470, 벡터 PDF).
    public static var loginHero: some View {
        Image("LoginHero", bundle: .module)
            .resizable()
            .accessibilityHidden(true)
    }
}
