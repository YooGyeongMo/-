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

    /// 앱 로고(Figma 51:359, O-3 알림 아이콘의 "?" 말풍선). 시작 연출·알림 타일·앱 아이콘이 같은 그림을 쓴다.
    public static var brandLogo: some View {
        Image("BrandLogo", bundle: .module)
            .resizable()
            .accessibilityHidden(true)
    }

    /// 온보딩 O-2 칩의 "붙여넣기" 아이콘(Figma 51:239, 15.42×18.77).
    public static var pasteIcon: some View {
        Image("OnboardingPasteIcon", bundle: .module)
            .resizable()
            .accessibilityHidden(true)
    }
}
