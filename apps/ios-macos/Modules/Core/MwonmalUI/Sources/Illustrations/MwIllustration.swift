import SwiftUI

/// 일러스트(장식). VoiceOver에서는 읽지 않는다.
public enum MwIllustration {
    /// S-01 히어로(Figma 51:470). 화면 크기에 맞춰 레이어별로 늘고 준다 — `LoginHeroIllustration` 참고.
    public static var loginHero: some View {
        LoginHeroIllustration()
    }

    /// 종이 질감(Figma 51:561). 160×160 노이즈 한 장, 레이어 불투명도 16%. 크기는 호출하는 쪽이 정한다.
    public static var paperGrain: some View {
        Image("PaperGrain", bundle: .module)
            .resizable()
            .opacity(0.16)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
