import FeatureKit
import MwonmalUI
import SwiftUI

/// OnboardingFeature 모듈(ADR-0016 v1.1 목록, ADR-0024로 앞당김). 처음 켤 때 한 번만 보이는 O-1~O-3.
/// 본 적이 있는지는 Composition이 저장한다. 이 모듈은 "끝났다"만 알린다.
public enum OnboardingFeatureModule {
    public static let name = "OnboardingFeature"
}

/// 온보딩 쪽 하나(Figma O-1 51:18 · O-2 51:178 · O-3 51:301). 글자는 문구 카탈로그 키다.
struct OnboardingPage: Equatable {
    enum Accent {
        case blue, teal, orange

        var color: Color {
            switch self {
            case .blue: MwColor.eyebrowBlue
            case .teal: MwColor.eyebrowTeal
            case .orange: MwColor.eyebrowOrange
            }
        }

        /// 아래 글 영역 바탕(Figma 쪽마다 다르다).
        var panel: Color {
            switch self {
            case .blue: MwColor.canvas
            case .teal: MwColor.onboardingTeal
            case .orange: MwColor.onboardingOrange
            }
        }
    }

    let index: Int
    let eyebrow: LocalizedStringKey
    /// 제목 줄(Figma에서 줄을 나눈 자리 그대로). 줄마다 차례로 떠오른다.
    let titleLines: [LocalizedStringKey]
    let body: LocalizedStringKey
    let accent: Accent

    static let all: [OnboardingPage] = [
        OnboardingPage(
            index: 0,
            eyebrow: "onboarding.page1.eyebrow",
            titleLines: ["onboarding.page1.title1", "onboarding.page1.title2"],
            body: "onboarding.page1.body",
            accent: .blue
        ),
        OnboardingPage(
            index: 1,
            eyebrow: "onboarding.page2.eyebrow",
            titleLines: ["onboarding.page2.title1", "onboarding.page2.title2"],
            body: "onboarding.page2.body",
            accent: .teal
        ),
        OnboardingPage(
            index: 2,
            eyebrow: "onboarding.page3.eyebrow",
            titleLines: ["onboarding.page3.title1", "onboarding.page3.title2"],
            body: "onboarding.page3.body",
            accent: .orange
        ),
    ]

    var isLast: Bool {
        index == Self.all.count - 1
    }
}

/// O-1~O-3 수치(Figma 393×852). 화면에 쓰는 크기는 여기 값 × 기기 배율이다.
nonisolated enum OnboardingSpec {
    static let heroHeight: CGFloat = 500 // 51:26
    static let sideInset: CGFloat = 20
    static let copyTop: CGFloat = 26 // 51:145 pt-26
    static let titleTop: CGFloat = 6 // 51:149 pt-6
    static let bodyTop: CGFloat = 8 // 51:152 pt-8
    static let skipRow: CGFloat = 52 // 51:138
    static let skipHeight: CGFloat = 40 // 51:141
    static let skipInset: CGFloat = 16
    static let dotsTop: CGFloat = 10 // 51:157 pt-10
    static let dotsToButton: CGFloat = 22 // gap 6 + pt-16
    static let buttonHeight: CGFloat = 56
    static let buttonRadius: CGFloat = 18
    static let bottomInset: CGFloat = 42 // pb-42 (화면 아래 끝 기준)
    static let dot: CGFloat = 7
    static let activeDot: CGFloat = 22
    static let paperGrain: CGFloat = 160 // 51:167
    /// Figma에 없는 값: 낮은 화면(SE)에서 그림이 줄어드는 하한과 글·버튼 사이 최소 간격.
    static let minimumHero: CGFloat = 240
    static let minimumGap: CGFloat = 16

    /// 그림 높이: Figma 500을 기본으로, 글·버튼이 들어갈 자리가 모자라면 줄인다(하한 240).
    static func heroHeight(screenHeight: CGFloat, copyHeight: CGFloat, footerHeight: CGFloat, scale: CGFloat) -> CGFloat {
        let natural = heroHeight * scale
        let room = screenHeight - copyHeight - footerHeight - minimumGap * scale
        return min(natural, max(room, minimumHero * scale))
    }
}
