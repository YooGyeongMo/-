import SwiftUI

/// 일러스트(장식). VoiceOver에서는 읽지 않는다.
public enum MwIllustration {
    /// S-01 히어로(Figma 51:470). 화면 크기에 맞춰 레이어별로 늘고 준다 — `LoginHeroIllustration` 참고.
    public static var loginHero: some View {
        LoginHeroIllustration()
    }
}
